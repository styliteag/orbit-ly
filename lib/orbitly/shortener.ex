defmodule Orbitly.Shortener do
  @moduledoc """
  Context for domains, links and their click events.

  Ownership is enforced here (previously Ash policies): a normal user only ever
  sees and mutates their own links; an admin sees and mutates everything.
  Domains are admin-managed and readable by any authenticated user. Every
  mutation flushes the redirect cache (previously the CacheInvalidator
  notifier). The redirect hot path deliberately does NOT go through this module
  — see `Orbitly.Shortener.RedirectCache`.
  """

  import Ecto.Query

  alias Orbitly.Repo
  alias Orbitly.Shortener.{ClickEvent, Domain, Link, RedirectCache, Slug}

  @slug_attempts 5

  ## -- Domains ------------------------------------------------------------

  @doc "All domains. Readable by any authenticated caller; sorting is the caller's."
  def list_domains, do: Repo.all(Domain)

  def get_domain!(id), do: Repo.get!(Domain, id)

  @doc "Blank changeset for the admin create form."
  def change_domain(%Domain{} = domain \\ %Domain{}, attrs \\ %{}),
    do: Domain.create_changeset(domain, attrs)

  def create_domain(attrs, actor) do
    if admin?(actor) do
      %Domain{}
      |> Domain.create_changeset(attrs)
      |> Repo.insert()
      |> flush_on_ok()
    else
      {:error, :unauthorized}
    end
  end

  def update_domain(%Domain{} = domain, attrs, actor) do
    if admin?(actor) do
      domain
      |> Domain.update_changeset(attrs)
      |> Repo.update()
      |> flush_on_ok()
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Deletes a redirect domain (cascades to its links and their click events via
  the DB foreign keys). The primary domain is protected — it follows
  MAIN_DOMAIN and hosts the dashboard.
  """
  def delete_domain(%Domain{} = domain, actor) do
    cond do
      not admin?(actor) -> {:error, :unauthorized}
      domain.is_primary -> {:error, :primary_protected}
      true -> domain |> Repo.delete() |> flush_and_ok()
    end
  end

  ## -- Links --------------------------------------------------------------

  @doc "Links visible to `actor`: own links, or all for an admin. Domain + owner attached."
  def list_links(actor) do
    scope_links(actor)
    |> Repo.all()
    |> Repo.preload(:domain)
    |> attach_owners(actor)
  end

  @doc "Fetches one link if `actor` may see it (owner or admin), domain preloaded."
  def get_link(id, actor) do
    with {:ok, _uuid} <- Ecto.UUID.cast(id),
         %Link{} = link <- Repo.get(Link, id) do
      if can_access_link?(link, actor) do
        {:ok, Repo.preload(link, :domain)}
      else
        {:error, :not_found}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Create-form changeset (validation only, no slug generation or persistence)."
  def change_link(%Link{} = link, attrs, actor) do
    params =
      attrs
      |> take_present([:target_url, :expires_at, :domain_id, :description])
      |> Map.put(:owner_id, actor && actor.id)
      |> maybe_put_slug(preview_slug(field(attrs, :slug)))

    Link.create_changeset(link, params)
  end

  def create_link(attrs, actor) do
    cond do
      is_nil(actor) ->
        {:error, :unauthorized}

      true ->
        domain_id = field(attrs, :domain_id)

        case resolve_slug(field(attrs, :slug), domain_id) do
          {:ok, slug} ->
            params =
              attrs
              |> take_present([:target_url, :expires_at, :domain_id, :description])
              |> Map.put(:slug, slug)
              |> Map.put(:owner_id, actor.id)
              |> Map.put(:password_hash, hash_password(field(attrs, :password)))

            %Link{}
            |> Link.create_changeset(params)
            |> Repo.insert()
            |> flush_on_ok()

          :no_slug ->
            changeset =
              %Link{}
              |> Link.create_changeset(take_present(attrs, [:target_url, :domain_id]))
              |> Ecto.Changeset.add_error(
                :slug,
                "could not generate a free slug, please provide one"
              )
              |> Map.put(:action, :insert)

            {:error, changeset}
        end
    end
  end

  @doc "Edit-form changeset (target, expiry, description; password handled on submit)."
  def change_link_update(%Link{} = link, attrs \\ %{}), do: Link.update_changeset(link, attrs)

  def update_link(%Link{} = link, attrs, actor) do
    if can_access_link?(link, actor) do
      params =
        attrs
        |> take_present([:target_url, :expires_at, :description])
        |> put_password_hash(field(attrs, :password))

      link
      |> Link.update_changeset(params)
      |> Repo.update()
      |> flush_on_ok()
    else
      {:error, :unauthorized}
    end
  end

  def delete_link(%Link{} = link, actor) do
    if can_access_link?(link, actor) do
      link |> Repo.delete() |> flush_and_ok()
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Bulk delete of the links with the given ids, in one statement (SQLite has a
  single writer — never loop deletes here). The ids run through the actor's
  scope, so a tampered id list can only ever hit links the actor may access;
  unknown or malformed ids are ignored. Click events follow via the DB foreign
  key (`on_delete: :delete_all`). Returns `{:ok, deleted_count}`.
  """
  def delete_links(ids, actor) when is_list(ids) do
    if is_nil(actor) do
      {:error, :unauthorized}
    else
      uuids = valid_uuids(ids)

      {count, _} =
        actor
        |> scope_links()
        |> where([l], l.id in ^uuids)
        |> Repo.delete_all()

      flush_and_count(count)
    end
  end

  @doc """
  Moves the given links to another owner. Admin-only: a normal user must not
  even learn that other accounts exist (no open registration, ADR-0006).
  `owner_id` stays out of the create/update changesets — this is the only way
  it ever changes, mirroring `Domain.primary_changeset`. Returns
  `{:ok, moved_count}`, `{:error, :unauthorized}` or `{:error, :invalid_owner}`.
  """
  def reassign_links(ids, new_owner_id, actor) when is_list(ids) do
    with true <- admin?(actor),
         {:ok, owner_id} <- existing_user_id(new_owner_id) do
      uuids = valid_uuids(ids)

      {count, _} =
        from(l in Link, where: l.id in ^uuids)
        |> Repo.update_all(set: [owner_id: owner_id, updated_at: DateTime.utc_now()])

      flush_and_count(count)
    else
      false -> {:error, :unauthorized}
      :error -> {:error, :invalid_owner}
    end
  end

  ## -- Click events -------------------------------------------------------

  @doc "Click events visible to `actor`: for own links, or all for an admin."
  def list_click_events(actor) do
    query =
      if admin?(actor) do
        from(c in ClickEvent)
      else
        from(c in ClickEvent,
          join: l in Link,
          on: l.id == c.link_id,
          where: l.owner_id == ^actor.id
        )
      end

    Repo.all(query)
  end

  @doc """
  Click totals as %{link_id => count} in one grouped query. The caller passes
  already-authorized link ids.
  """
  def click_counts(link_ids) when is_list(link_ids) do
    from(c in ClickEvent,
      where: c.link_id in ^link_ids,
      group_by: c.link_id,
      select: {c.link_id, count(c.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  ## -- Authorization ------------------------------------------------------

  defp admin?(%{admin: true}), do: true
  defp admin?(_), do: false

  defp can_access_link?(_link, nil), do: false
  defp can_access_link?(_link, %{admin: true}), do: true
  defp can_access_link?(%Link{owner_id: owner_id}, %{id: actor_id}), do: owner_id == actor_id
  defp can_access_link?(_link, _actor), do: false

  defp scope_links(%{admin: true}), do: from(l in Link)
  defp scope_links(%{id: actor_id}), do: from(l in Link, where: l.owner_id == ^actor_id)

  # Bulk ids arrive from the client — drop everything that is not a UUID before
  # it reaches a query (a non-UUID would raise on the Ecto.UUID field type).
  defp valid_uuids(ids) do
    for id <- ids, is_binary(id), {:ok, uuid} <- [Ecto.UUID.cast(id)], do: uuid
  end

  # Accounts is a separate context; the users table is read directly here, same
  # as in `owner_map/1`.
  defp existing_user_id(id) when is_binary(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         true <- Repo.exists?(from(u in "users", where: u.id == ^uuid, select: 1)) do
      {:ok, uuid}
    else
      _ -> :error
    end
  end

  defp existing_user_id(_id), do: :error

  ## -- Owner attachment (Accounts is still Ash) ---------------------------

  defp attach_owners(links, %{admin: true}) do
    owners = owner_map(links)
    Enum.map(links, fn link -> %{link | owner: Map.get(owners, link.owner_id)} end)
  end

  defp attach_owners(links, actor) do
    # A non-admin only ever gets their own links, so the actor is the owner.
    Enum.map(links, fn link -> %{link | owner: actor} end)
  end

  defp owner_map(links) do
    ids = links |> Enum.map(& &1.owner_id) |> Enum.uniq()

    from(u in "users", where: u.id in ^ids, select: {u.id, u.email})
    |> Repo.all()
    |> Map.new(fn {id, email} -> {id, %{id: id, email: email}} end)
  end

  ## -- Slug resolution ----------------------------------------------------

  # For the create form: reflect an entered custom/special slug, but never
  # generate — generation happens only on actual submit.
  defp preview_slug(input) do
    cond do
      is_binary(input) and Slug.special_slug(input) != nil -> Slug.special_slug(input)
      is_binary(input) and input != "" -> input
      true -> nil
    end
  end

  defp resolve_slug(input, domain_id) do
    cond do
      is_binary(input) and Slug.special_slug(input) != nil ->
        {:ok, Slug.special_slug(input)}

      is_binary(input) and input != "" ->
        {:ok, input}

      is_nil(domain_id) ->
        # a missing domain fails its own required check in the changeset
        {:ok, nil}

      true ->
        case generate_free_slug(domain_id) do
          nil -> :no_slug
          slug -> {:ok, slug}
        end
    end
  end

  defp generate_free_slug(domain_id) do
    Enum.find_value(1..@slug_attempts, fn _ ->
      candidate = Slug.generate()
      if slug_free?(domain_id, candidate), do: candidate
    end)
  end

  defp slug_free?(domain_id, slug) do
    not Repo.exists?(from(l in Link, where: l.domain_id == ^domain_id and l.slug == ^slug))
  end

  ## -- Password hashing ---------------------------------------------------

  # Create: nil/"" mean no protection.
  defp hash_password(nil), do: nil
  defp hash_password(""), do: nil
  defp hash_password(password) when is_binary(password), do: Bcrypt.hash_pwd_salt(password)

  # Update: absent (nil) leaves the hash untouched, "" clears it.
  defp put_password_hash(params, nil), do: params
  defp put_password_hash(params, ""), do: Map.put(params, :password_hash, nil)

  defp put_password_hash(params, password) when is_binary(password),
    do: Map.put(params, :password_hash, Bcrypt.hash_pwd_salt(password))

  ## -- Param helpers ------------------------------------------------------

  # Params arrive with string keys (forms) or atom keys (tests/internal); take
  # only the keys actually present so partial updates keep existing values.
  defp take_present(attrs, keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case fetch_field(attrs, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  defp field(attrs, key) do
    case fetch_field(attrs, key) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp fetch_field(attrs, key) do
    cond do
      Map.has_key?(attrs, key) -> {:ok, Map.get(attrs, key)}
      Map.has_key?(attrs, to_string(key)) -> {:ok, Map.get(attrs, to_string(key))}
      true -> :error
    end
  end

  defp maybe_put_slug(params, nil), do: params
  defp maybe_put_slug(params, slug), do: Map.put(params, :slug, slug)

  ## -- Cache flush --------------------------------------------------------

  defp flush_on_ok({:ok, _} = result) do
    RedirectCache.flush()
    result
  end

  defp flush_on_ok(other), do: other

  # For deletes, which succeed with {:ok, struct} but whose callers only care
  # that it worked.
  defp flush_and_ok({:ok, _}) do
    RedirectCache.flush()
    :ok
  end

  defp flush_and_ok({:error, _} = error), do: error

  # Bulk operations flush once, not once per row.
  defp flush_and_count(count) do
    RedirectCache.flush()
    {:ok, count}
  end
end
