defmodule Orbitly.KuttImport do
  @moduledoc """
  Imports links from a Kutt instance (via its HTTP API) into orbit-ly.

  Every imported link is assigned to the current instance admin and placed on
  the primary domain (or the one passed as `:domain`). Slug handling:

    * invalid characters for an orbit-ly slug → skipped,
    * a reserved slug (`admin`, `stats`, …) → numeric suffix (`stats-1`),
    * a slug already present on the domain → skipped (re-runs stay idempotent).

  Kutt exposes only aggregated visit counts and no password hashes, so:

    * click history is *synthesised* — one `ClickEvent` per counted visit,
      spread evenly across the link's lifetime, with a placeholder user agent
      and no IP (`nil`),
    * password-protected links are imported without their password and listed
      in the report so they can be reset.
  """

  import Ecto.Query

  alias Orbitly.Accounts.User
  alias Orbitly.Repo
  alias Orbitly.Shortener.{ClickEvent, Domain, Link, Slug}

  @synth_user_agent "kutt-import"
  @insert_chunk 1_000

  @empty_report %{
    imported: [],
    renamed: [],
    skipped_invalid: [],
    skipped_exists: [],
    protected: [],
    clicks: 0
  }

  @doc """
  Runs the import. Options:

    * `:client` — module implementing `Orbitly.KuttImport.Client` (required)
    * `:config` — map passed to the client (required)
    * `:domain` — target domain hostname; `nil` = the primary domain
    * `:now` — reference time for synthesising clicks (defaults to now)

  Returns a report map with lists of `{kutt_slug, orbitly_slug}` tuples per
  outcome and the total number of synthesised clicks.
  """
  def run(opts) do
    client = Keyword.fetch!(opts, :client)
    config = Keyword.fetch!(opts, :config)
    now = Keyword.get(opts, :now, DateTime.utc_now())

    admin = fetch_admin!()
    domain = fetch_domain!(Keyword.get(opts, :domain))

    {:ok, kutt_links} = client.list_links(config)

    {report, _taken} =
      kutt_links
      |> Enum.sort_by(&(&1["created_at"] || ""))
      |> Enum.reduce({@empty_report, existing_slugs(domain.id)}, fn kutt_link, acc ->
        import_link(kutt_link, admin, domain, now, acc)
      end)

    finalize(report)
  end

  defp import_link(kutt_link, admin, domain, now, {report, taken}) do
    case classify(kutt_link["address"], taken) do
      :skip_invalid -> {prepend(report, :skipped_invalid, kutt_link["address"]), taken}
      :skip_exists -> {prepend(report, :skipped_exists, kutt_link["address"]), taken}
      {:import, slug} -> insert(kutt_link, slug, admin, domain, now, report, taken, :imported)
      {:rename, slug} -> insert(kutt_link, slug, admin, domain, now, report, taken, :renamed)
    end
  end

  defp insert(kutt_link, slug, admin, domain, now, report, taken, kind) do
    created = parse_dt(kutt_link["created_at"]) || now
    link = seed_link(kutt_link, slug, admin.id, domain.id, created)
    clicks = synth_clicks(link.id, kutt_link["visit_count"] || 0, created, now)

    report =
      report
      |> prepend(kind, {kutt_link["address"], slug})
      |> Map.update!(:clicks, &(&1 + clicks))
      |> flag_protected(kutt_link, slug)

    {report, MapSet.put(taken, slug)}
  end

  defp seed_link(kutt_link, slug, owner_id, domain_id, created) do
    updated = parse_dt(kutt_link["updated_at"]) || created

    Repo.insert!(%Link{
      slug: slug,
      target_url: kutt_link["target"],
      description: kutt_link["description"],
      expires_at: kutt_link["expire_in"] |> parse_dt() |> truncate_second(),
      domain_id: domain_id,
      owner_id: owner_id,
      inserted_at: to_usec(created),
      updated_at: to_usec(updated)
    })
  end

  # inserted_at/updated_at are :utc_datetime_usec; a struct insert dumps them
  # directly and Ecto demands full microsecond precision, so normalize.
  defp to_usec(%DateTime{microsecond: {us, _}} = dt), do: %{dt | microsecond: {us, 6}}

  defp synth_clicks(_link_id, count, _from, _to) when count <= 0, do: 0

  defp synth_clicks(link_id, count, from, to) do
    span = max(DateTime.diff(to, from, :microsecond), 0)

    for i <- 0..(count - 1) do
      offset = if count > 1, do: div(span * i, count - 1), else: 0

      %{
        id: Ecto.UUID.generate(),
        link_id: link_id,
        occurred_at: DateTime.add(from, offset, :microsecond),
        ip: nil,
        user_agent: @synth_user_agent,
        referrer: nil
      }
    end
    |> Enum.chunk_every(@insert_chunk)
    |> Enum.each(&Repo.insert_all(ClickEvent, &1))

    count
  end

  defp classify(addr, taken) do
    cond do
      not Slug.valid_format?(addr) -> :skip_invalid
      MapSet.member?(taken, addr) -> :skip_exists
      Slug.reserved?(addr) -> {:rename, free_suffix(addr, taken)}
      true -> {:import, addr}
    end
  end

  defp free_suffix(base, taken) do
    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(&"#{base}-#{&1}")
    |> Enum.find(&free?(&1, taken))
  end

  defp free?(slug, taken) do
    Slug.valid_format?(slug) and not Slug.reserved?(slug) and not MapSet.member?(taken, slug)
  end

  defp existing_slugs(domain_id) do
    from(l in Link, where: l.domain_id == ^domain_id, select: l.slug)
    |> Repo.all()
    |> MapSet.new()
  end

  defp fetch_admin! do
    case Repo.all(from(u in User, where: u.admin == true, limit: 1)) do
      [admin | _] -> admin
      [] -> raise "no admin user found — create one first (see bin/create_admin)"
    end
  end

  defp fetch_domain!(nil) do
    Repo.one(from(d in Domain, where: d.is_primary == true)) ||
      raise "no primary domain configured"
  end

  defp fetch_domain!(host) do
    Repo.get_by(Domain, hostname: host) || raise "domain #{host} not found"
  end

  defp flag_protected(report, %{"password" => true}, slug), do: prepend(report, :protected, slug)
  defp flag_protected(report, _kutt_link, _slug), do: report

  defp prepend(report, key, value), do: Map.update!(report, key, &[value | &1])

  defp finalize(report) do
    Map.new(report, fn
      {:clicks, count} -> {:clicks, count}
      {key, list} -> {key, Enum.reverse(list)}
    end)
  end

  defp parse_dt(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_dt(_), do: nil

  defp truncate_second(nil), do: nil
  defp truncate_second(dt), do: DateTime.truncate(dt, :second)
end
