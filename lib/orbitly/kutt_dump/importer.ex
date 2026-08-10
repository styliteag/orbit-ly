defmodule Orbitly.KuttDump.Importer do
  @moduledoc """
  Rebuilds links and click history from a parsed Kutt dump
  (`Orbitly.KuttDump`).

  Unlike the API importer, click events keep their real hour, referrer and
  browser: one Kutt `visits` row is a link/hour bucket with a `total`, browser
  counters and a referrer histogram, so the events are placed inside that hour
  and get a representative user agent per counted browser. IPs are not in the
  dump — imported events have `ip: nil`, which is also what tells them apart
  from live traffic afterwards.

  Events older than the click retention window (12 months, ADR-0005) are
  *not* imported: the app would delete them on the next purge anyway, and
  keeping them would contradict the documented obligation.
  """

  import Ecto.Query

  alias Orbitly.Accounts
  alias Orbitly.Accounts.User
  alias Orbitly.KuttDump
  alias Orbitly.Repo
  alias Orbitly.Shortener.{ClickEvent, Domain, Link, RedirectCache, Slug}

  @retention_months 12
  @insert_chunk 500

  @user_agents %{
    "chrome" =>
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
    "edge" =>
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0",
    "firefox" =>
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0",
    "safari" =>
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
    "opera" =>
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 OPR/112.0.0.0",
    "ie" => "Mozilla/5.0 (Windows NT 10.0; Trident/7.0; rv:11.0) like Gecko",
    "other" => "kutt-dump-import"
  }

  @empty_report %{
    links: 0,
    skipped_links: [],
    renamed_links: [],
    domains: [],
    unknown_owners: [],
    events: 0,
    dropped_by_retention: 0,
    deleted_links: 0,
    deleted_events: 0
  }

  @doc """
  Imports `parsed` (see `Orbitly.KuttDump.parse/1`). Options:

    * `:owner` — email of the account the links belong to (default: first admin)
    * `:reset` — delete every existing link and click event first (default: false)
    * `:now` — reference time for the retention cutoff (default: now)

  Returns a report map.
  """
  def run(parsed, opts \\ []) do
    fallback = fetch_owner!(Keyword.get(opts, :owner))
    now = Keyword.get(opts, :now, DateTime.utc_now())
    cutoff = DateTime.shift(now, month: -@retention_months)

    report = if Keyword.get(opts, :reset, false), do: reset(), else: @empty_report

    {owners, report} = owner_map(parsed, fallback, report)
    domains = domain_map(parsed)
    {report, link_ids} = import_links(parsed, owners, domains, report)
    report = import_visits(parsed, link_ids, cutoff, report)

    RedirectCache.flush()

    %{
      report
      | skipped_links: Enum.reverse(report.skipped_links),
        unknown_owners: report.unknown_owners |> Enum.reverse() |> Enum.uniq()
    }
  end

  ## -- reset ---------------------------------------------------------------

  defp reset do
    {events, _} = Repo.delete_all(ClickEvent)
    {links, _} = Repo.delete_all(Link)

    %{@empty_report | deleted_events: events, deleted_links: links}
  end

  ## -- owners --------------------------------------------------------------

  # Kutt's users carry their real email, so a link keeps its owner as long as
  # that account also exists here (matched case-insensitively). Accounts are
  # admin-created (ADR-0006) — an unknown email is reported, never registered,
  # and its links fall back to the acting owner.
  defp owner_map(parsed, fallback, report) do
    parsed
    |> KuttDump.rows("users")
    |> Enum.reduce({%{}, report}, fn row, {owners, report} ->
      case row["email"] && Accounts.get_user_by_email(row["email"]) do
        %{} = user ->
          {Map.put(owners, row["id"], user), report}

        _ ->
          {owners, %{report | unknown_owners: [row["email"] | report.unknown_owners]}}
      end
    end)
    |> then(fn {owners, report} -> {{owners, fallback}, report} end)
  end

  defp owner_for({owners, fallback}, kutt_user_id) do
    Map.get(owners, kutt_user_id, fallback)
  end

  ## -- domains -------------------------------------------------------------

  # Kutt links either sit on its default domain (NULL) or on a custom one; the
  # former land on our primary domain, the latter get their own row.
  defp domain_map(parsed) do
    primary = Repo.one!(from(d in Domain, where: d.is_primary == true))

    hostnames =
      parsed
      |> KuttDump.rows("domains")
      |> Map.new(fn row -> {row["id"], row["address"]} end)

    {primary, hostnames}
  end

  defp resolve_domain({primary, _hostnames}, nil, report), do: {primary, report}

  defp resolve_domain({primary, hostnames}, kutt_domain_id, report) do
    case Map.get(hostnames, kutt_domain_id) do
      nil -> {primary, report}
      hostname -> find_or_create_domain(hostname, report)
    end
  end

  defp find_or_create_domain(hostname, report) do
    case Repo.get_by(Domain, hostname: hostname) do
      %Domain{} = domain ->
        {domain, report}

      nil ->
        domain = Repo.insert!(%Domain{hostname: hostname, active: true, is_primary: false})
        {domain, %{report | domains: [hostname | report.domains]}}
    end
  end

  ## -- links ---------------------------------------------------------------

  defp import_links(parsed, owners, domains, report) do
    parsed
    |> KuttDump.rows("links")
    |> Enum.reject(&(&1["banned"] == "t"))
    |> Enum.reduce({report, %{}}, fn row, {report, link_ids} ->
      {domain, report} = resolve_domain(domains, row["domain_id"], report)

      case resolve_slug(row["address"], domain.id) do
        {:ok, slug, renamed?} ->
          link = insert_link(row, slug, domain, owner_for(owners, row["user_id"]))
          report = count_link(report, row["address"], slug, renamed?)
          {report, Map.put(link_ids, row["id"], link.id)}

        :skip ->
          {%{report | skipped_links: [row["address"] | report.skipped_links]}, link_ids}
      end
    end)
  end

  defp insert_link(row, slug, domain, owner) do
    created = KuttDump.datetime(row["created_at"]) || DateTime.utc_now()
    updated = KuttDump.datetime(row["updated_at"]) || created

    Repo.insert!(%Link{
      slug: slug,
      target_url: row["target"],
      description: row["description"],
      domain_id: domain.id,
      owner_id: owner.id,
      inserted_at: created,
      updated_at: updated
    })
  end

  defp count_link(report, _address, _slug, false), do: %{report | links: report.links + 1}

  defp count_link(report, address, slug, true) do
    %{report | links: report.links + 1, renamed_links: [{address, slug} | report.renamed_links]}
  end

  # Reserved or already-taken slugs get a numeric suffix, same rule as the API
  # importer; anything our format rejects is skipped and reported.
  defp resolve_slug(address, domain_id) when is_binary(address) do
    cond do
      not Slug.valid_format?(address) -> :skip
      free?(address, domain_id) -> {:ok, address, false}
      true -> suffixed(address, domain_id)
    end
  end

  defp resolve_slug(_address, _domain_id), do: :skip

  defp suffixed(address, domain_id) do
    1..99
    |> Enum.find_value(fn n ->
      candidate = "#{address}-#{n}"
      if free?(candidate, domain_id), do: {:ok, candidate, true}
    end)
    |> Kernel.||(:skip)
  end

  defp free?(slug, domain_id) do
    not Slug.reserved?(slug) and
      not Repo.exists?(from(l in Link, where: l.domain_id == ^domain_id and l.slug == ^slug))
  end

  ## -- visits --------------------------------------------------------------

  defp import_visits(parsed, link_ids, cutoff, report) do
    parsed
    |> KuttDump.rows("visits")
    |> Enum.reduce(report, fn row, report ->
      case Map.fetch(link_ids, row["link_id"]) do
        {:ok, link_id} -> import_visit(row, link_id, cutoff, report)
        :error -> report
      end
    end)
    |> flush_events()
  end

  defp import_visit(row, link_id, cutoff, report) do
    from = KuttDump.datetime(row["created_at"])
    total = KuttDump.int(row["total"]) || 0

    cond do
      is_nil(from) or total <= 0 ->
        report

      DateTime.compare(from, cutoff) == :lt ->
        %{report | dropped_by_retention: report.dropped_by_retention + total}

      true ->
        row
        |> events(link_id, from, total)
        |> buffer(report)
    end
  end

  defp events(row, link_id, from, total) do
    until = KuttDump.datetime(row["updated_at"]) || from
    browsers = browser_agents(row, total)
    referrers = referrer_list(row, total)

    [timestamps(from, until, total), browsers, referrers]
    |> Enum.zip()
    |> Enum.map(fn {occurred_at, user_agent, referrer} ->
      %{
        id: Ecto.UUID.generate(),
        link_id: link_id,
        occurred_at: occurred_at,
        ip: nil,
        user_agent: user_agent,
        referrer: referrer
      }
    end)
  end

  # Spread the bucket's clicks over the span Kutt recorded (first to last visit
  # in that hour); a single-instant bucket gets one-second steps.
  defp timestamps(from, _until, 1), do: [from]

  defp timestamps(from, until, total) do
    span = DateTime.diff(until, from, :second)
    step = if span > 0, do: span / (total - 1), else: 1

    for index <- 0..(total - 1) do
      DateTime.add(from, round(index * step), :second)
    end
  end

  defp browser_agents(row, total) do
    @user_agents
    |> Enum.flat_map(fn {browser, user_agent} ->
      List.duplicate(user_agent, KuttDump.int(row["br_#{browser}"]) || 0)
    end)
    |> pad(total, @user_agents["other"])
  end

  defp referrer_list(row, total) do
    row["referrers"]
    |> KuttDump.referrers()
    |> Enum.flat_map(fn {referrer, count} -> List.duplicate(referrer, count) end)
    |> pad(total, nil)
  end

  # The counters do not always add up to `total` (Kutt counts them separately),
  # so pad short lists with a neutral value and cut long ones.
  defp pad(list, total, filler) do
    case total - length(list) do
      missing when missing > 0 -> list ++ List.duplicate(filler, missing)
      _ -> Enum.take(list, total)
    end
  end

  ## -- buffered insert -----------------------------------------------------

  # SQLite has a single writer: collect events and write them in chunks
  # instead of one INSERT per click.
  defp buffer(events, report) do
    pending = Map.get(report, :pending, []) ++ events

    if length(pending) >= @insert_chunk do
      report |> Map.put(:pending, []) |> insert_events(pending)
    else
      Map.put(report, :pending, pending)
    end
  end

  defp flush_events(report) do
    report
    |> Map.put(:pending, [])
    |> insert_events(Map.get(report, :pending, []))
    |> Map.delete(:pending)
  end

  defp insert_events(report, []), do: report

  defp insert_events(report, events) do
    Repo.insert_all(ClickEvent, events)
    %{report | events: report.events + length(events)}
  end

  ## -- owner ---------------------------------------------------------------

  defp fetch_owner!(nil) do
    case Repo.all(from(u in User, where: u.admin == true, limit: 1)) do
      [admin | _] -> admin
      [] -> raise "no admin user found — create one first (see bin/create_admin)"
    end
  end

  defp fetch_owner!(email) when is_binary(email) do
    Accounts.get_user_by_email(email) ||
      raise "no user with email #{email} — accounts are admin-created (no self-signup)"
  end
end
