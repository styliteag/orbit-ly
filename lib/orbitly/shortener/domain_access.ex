defmodule Orbitly.Shortener.DomainAccess do
  @moduledoc """
  Which domains a user may put new links on, and which one is preselected.

  - `users.all_domains` (default on): every active, non-alias domain is usable.
    An admin switches it off to limit the user to the domains granted in
    `user_domains`. Admins themselves are never restricted.
  - `users.default_domain_id`: the user's preselected domain. Set by the user
    (settings) or an admin. A default that is no longer usable (revoked,
    deactivated, deleted) silently falls back to the first usable domain.

  Revoking a domain never touches existing links: they keep redirecting and
  stay editable — only new links and duplicates are refused.
  """

  import Ecto.Query

  alias Orbitly.Accounts.User
  alias Orbitly.Repo
  alias Orbitly.Shortener.{Domain, UserDomain}

  @doc "Active, non-alias domains `user` may use, primary first, then by hostname."
  def usable_domains(user), do: user |> usable_query() |> Repo.all()

  @doc "Whether `user` may put new links on `domain_id`."
  def usable?(user, domain_id) do
    case cast_uuid(domain_id) do
      {:ok, uuid} -> user |> usable_query() |> where([d], d.id == ^uuid) |> Repo.exists?()
      :error -> false
    end
  end

  @doc "Domain ids explicitly granted to `user` (relevant when `all_domains` is off)."
  def granted_domain_ids(%{id: user_id}) do
    from(g in UserDomain, where: g.user_id == ^user_id, select: g.domain_id)
    |> Repo.all()
    |> Enum.sort()
  end

  @doc "All grants as `%{user_id => [domain_id]}` (one query, for the admin user list)."
  def grants_by_user do
    from(g in UserDomain, select: {g.user_id, g.domain_id})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc "The user's default among `domains` (as returned by `usable_domains/1`), else the first."
  def default_domain_id(user, domains) do
    ids = Enum.map(domains, & &1.id)

    if user.default_domain_id in ids, do: user.default_domain_id, else: List.first(ids)
  end

  @doc """
  Sets the user's default domain (`nil` clears it). Allowed for the user
  themselves and for admins; the domain must be usable by `user`.
  """
  def set_default_domain(user, domain_id, actor) do
    cond do
      not (admin?(actor) or actor.id == user.id) -> {:error, :unauthorized}
      blank?(domain_id) -> put_default(user, nil)
      usable?(user, domain_id) -> put_default(user, domain_id)
      true -> {:error, :invalid_domain}
    end
  end

  @doc """
  Admin only. Replaces the user's access: `all_domains` flag plus the granted
  `domain_ids` (unknown, non-UUID and alias ids are dropped). With a
  `:default_domain_id` key the default is validated against the new access and
  set in the same transaction.
  """
  def set_domain_access(user, attrs, actor) do
    if admin?(actor) do
      Repo.transact(fn -> replace_access(user, attrs, actor) end)
    else
      {:error, :unauthorized}
    end
  end

  defp replace_access(user, attrs, actor) do
    user =
      user |> Ecto.Changeset.change(all_domains: truthy?(attrs[:all_domains])) |> Repo.update!()

    Repo.delete_all(from(g in UserDomain, where: g.user_id == ^user.id))

    grants = for id <- grantable_ids(attrs[:domain_ids]), do: %{user_id: user.id, domain_id: id}
    Repo.insert_all(UserDomain, grants)

    case Map.fetch(attrs, :default_domain_id) do
      {:ok, default_id} -> set_default_domain(user, default_id, actor)
      :error -> {:ok, user}
    end
  end

  defp grantable_ids(ids) when is_list(ids) do
    uuids = for id <- ids, {:ok, uuid} <- [cast_uuid(id)], do: uuid

    from(d in Domain, where: d.id in ^uuids and is_nil(d.alias_of_id), select: d.id)
    |> Repo.all()
  end

  defp grantable_ids(_ids), do: []

  defp put_default(user, domain_id) do
    user |> Ecto.Changeset.change(default_domain_id: domain_id) |> Repo.update()
  end

  defp usable_query(user) do
    from(d in Domain,
      where: d.active and is_nil(d.alias_of_id),
      order_by: [desc: d.is_primary, asc: d.hostname]
    )
    |> restrict(user)
  end

  # Access is decided on the DB row, not the caller's struct: a LiveView keeps
  # its mount-time `current_user`, so a revocation must apply without reconnect.
  defp restrict(query, %{id: user_id}) when is_binary(user_id) do
    access =
      Repo.one(
        from(u in User, where: u.id == ^user_id, select: map(u, [:id, :admin, :all_domains]))
      )

    restrict_by(query, access)
  end

  defp restrict(query, _user), do: where(query, false)

  defp restrict_by(query, nil), do: where(query, false)
  defp restrict_by(query, %{admin: true}), do: query
  defp restrict_by(query, %{all_domains: true}), do: query

  defp restrict_by(query, %{id: user_id}) do
    granted = from(g in UserDomain, where: g.user_id == ^user_id, select: g.domain_id)
    where(query, [d], d.id in subquery(granted))
  end

  defp admin?(%{admin: true}), do: true
  defp admin?(_actor), do: false

  defp truthy?(value), do: value in [true, "true", "on"]

  defp blank?(value), do: value in [nil, ""]

  defp cast_uuid(id) when is_binary(id), do: Ecto.UUID.cast(id)
  defp cast_uuid(_id), do: :error
end
