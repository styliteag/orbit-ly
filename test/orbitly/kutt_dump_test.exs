defmodule Orbitly.KuttDumpTest do
  use Orbitly.DataCase, async: false

  import Ecto.Query
  import Orbitly.Fixtures

  alias Orbitly.KuttDump
  alias Orbitly.Shortener.{ClickEvent, Domain, Link}

  # A miniature pg_dump: two links (one on a custom domain), three visit
  # buckets, plus noise the parser has to ignore.
  @dump """
  --
  -- PostgreSQL database dump
  --

  SET statement_timeout = 0;

  COPY public.domains (id, banned, banned_by_id, address, homepage, user_id, uuid, created_at, updated_at) FROM stdin;
  4\tf\t\\N\tstylite.tv\t\\N\t5\tuuid-1\t2023-06-27 17:26:24.126015+00\t2023-06-27 17:26:24.126015+00
  \\.


  COPY public.users (id, apikey, banned, banned_by_id, email, password, reset_password_expires, reset_password_token, change_email_expires, change_email_token, change_email_address, verification_expires, verification_token, verified, created_at, updated_at, role) FROM stdin;
  5\tsecret-api-key\tf\t\\N\tOffice@Example.com\thash\t\\N\t\\N\t\\N\t\\N\t\\N\t\\N\t\\N\tt\t2023-06-27 17:26:24+00\t2023-06-27 17:26:24+00\tuser
  6\tother-api-key\tf\t\\N\tgone@example.com\thash\t\\N\t\\N\t\\N\t\\N\t\\N\t\\N\t\\N\tt\t2023-06-27 17:26:24+00\t2023-06-27 17:26:24+00\tuser
  \\.


  COPY public.links (id, address, description, banned, banned_by_id, domain_id, password, expire_in, target, user_id, visit_count, created_at, updated_at, uuid) FROM stdin;
  10\tnews\tCompany news\tf\t\\N\t\\N\t\\N\t\\N\thttps://example.com/news\t5\t3\t2026-01-02 10:00:00+00\t2026-01-02 10:00:00+00\tuuid-a
  11\ttv1\t\\N\tf\t\\N\t4\t\\N\t\\N\thttps://example.com/tv\t6\t1\t2026-02-02 10:00:00+00\t2026-02-02 10:00:00+00\tuuid-b
  12\tstats\t\\N\tf\t\\N\t\\N\t\\N\t\\N\thttps://example.com/stats\t5\t0\t2026-02-03 10:00:00+00\t2026-02-03 10:00:00+00\tuuid-c
  13\tbad slug\t\\N\tf\t\\N\t\\N\t\\N\t\\N\thttps://example.com/bad\t5\t0\t2026-02-04 10:00:00+00\t2026-02-04 10:00:00+00\tuuid-d
  14\tbanned-one\t\\N\tt\t\\N\t\\N\t\\N\t\\N\thttps://example.com/banned\t5\t0\t2026-02-05 10:00:00+00\t2026-02-05 10:00:00+00\tuuid-e
  \\.


  COPY public.visits (id, countries, created_at, updated_at, link_id, referrers, total, br_chrome, br_edge, br_firefox, br_ie, br_opera, br_other, br_safari, os_android, os_ios, os_linux, os_macos, os_other, os_windows, user_id) FROM stdin;
  1\t{"de": 2}\tRECENT_FROM\tRECENT_UNTIL\t10\t{"direct": 1, "team[dot]stylite[dot]de": 1}\t2\t1\t0\t1\t0\t0\t0\t0\t0\t0\t1\t1\t0\t0\t5
  2\t{"de": 1}\tRECENT_FROM\tRECENT_FROM\t11\t{"google[dot]com": 1}\t1\t0\t0\t0\t0\t0\t0\t1\t0\t0\t0\t0\t0\t1\t5
  3\t{"de": 5}\tANCIENT\tANCIENT\t10\t{"direct": 5}\t5\t5\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\t5\t5
  \\.
  """

  setup do
    admin = admin_fixture()
    # Kutt user 5 in the fixture dump, spelled with different case there.
    office = user_fixture(%{email: "office@example.com"})
    domain = domain_fixture(%{hostname: "go.example", is_primary: true})

    recent = DateTime.shift(DateTime.utc_now(), month: -1)
    ancient = DateTime.shift(DateTime.utc_now(), month: -18)

    dump =
      @dump
      |> String.replace("RECENT_FROM", pg(recent))
      |> String.replace("RECENT_UNTIL", pg(DateTime.add(recent, 600, :second)))
      |> String.replace("ANCIENT", pg(ancient))

    path = Path.join(System.tmp_dir!(), "kutt-dump-#{System.unique_integer([:positive])}.sql")
    File.write!(path, dump)
    on_exit(fn -> File.rm(path) end)

    %{admin: admin, office: office, domain: domain, path: path, recent: recent}
  end

  defp pg(datetime) do
    datetime |> DateTime.to_iso8601() |> String.replace("T", " ") |> String.replace("Z", "+00")
  end

  describe "parse/1" do
    test "reads the COPY blocks it cares about", %{path: path} do
      parsed = KuttDump.parse(path)

      assert length(KuttDump.rows(parsed, "links")) == 5
      assert length(KuttDump.rows(parsed, "visits")) == 3
      assert [%{"address" => "stylite.tv"}] = KuttDump.rows(parsed, "domains")

      assert [%{"address" => "news", "description" => "Company news"} | _] =
               KuttDump.rows(parsed, "links")
    end

    test "decodes NULLs and referrer host names", %{path: path} do
      [first | _] = KuttDump.parse(path) |> KuttDump.rows("visits")

      assert KuttDump.referrers(first["referrers"]) == %{nil => 1, "team.stylite.de" => 1}

      assert [%{"description" => nil} | _] =
               KuttDump.parse(path) |> KuttDump.rows("links") |> tl()
    end

    test "reads a dump with CRLF line endings", %{path: path} do
      crlf_path = path <> ".crlf"
      File.write!(crlf_path, path |> File.read!() |> String.replace("\n", "\r\n"))
      on_exit(fn -> File.rm(crlf_path) end)

      parsed = KuttDump.parse(crlf_path)

      assert length(KuttDump.rows(parsed, "links")) == 5
      assert [%{"uuid" => "uuid-a"} | _] = KuttDump.rows(parsed, "links")
    end

    test "reads a gzipped dump too", %{path: path} do
      gz_path = path <> ".gz"
      File.write!(gz_path, :zlib.gzip(File.read!(path)))
      on_exit(fn -> File.rm(gz_path) end)

      assert length(KuttDump.parse(gz_path) |> KuttDump.rows("links")) == 5
    end
  end

  describe "Importer.run/2" do
    test "imports links onto the primary and custom domains", ctx do
      report = import_dump(ctx.path)

      assert report.links == 3
      assert report.domains == ["stylite.tv"]

      news = Repo.one!(from(l in Link, where: l.slug == "news"))
      assert news.target_url == "https://example.com/news"
      assert news.description == "Company news"
      assert news.domain_id == ctx.domain.id
      assert DateTime.to_date(news.inserted_at) == ~D[2026-01-02]

      tv = Repo.one!(from(l in Link, where: l.slug == "tv1"))
      assert Repo.get!(Domain, tv.domain_id).hostname == "stylite.tv"
    end

    test "keeps each link with its own owner, matched by email", ctx do
      report = import_dump(ctx.path)

      news = Repo.one!(from(l in Link, where: l.slug == "news"))
      assert news.owner_id == ctx.office.id

      # kutt user 6 (gone@example.com) has no account here
      tv = Repo.one!(from(l in Link, where: l.slug == "tv1"))
      assert tv.owner_id == ctx.admin.id
      assert report.unknown_owners == ["gone@example.com"]
    end

    test "an explicit owner is the fallback for unmatched users only", ctx do
      other = user_fixture(%{email: "fallback@example.com"})

      ctx.path |> KuttDump.parse() |> KuttDump.Importer.run(owner: "fallback@example.com")

      assert Repo.one!(from(l in Link, where: l.slug == "tv1")).owner_id == other.id
      assert Repo.one!(from(l in Link, where: l.slug == "news")).owner_id == ctx.office.id
    end

    test "renames reserved slugs and skips invalid ones", %{path: path} do
      report = import_dump(path)

      assert report.renamed_links == [{"stats", "stats-1"}]
      assert report.skipped_links == ["bad slug"]
      assert Repo.exists?(from(l in Link, where: l.slug == "stats-1"))
    end

    test "skips banned links", %{path: path} do
      import_dump(path)

      refute Repo.exists?(from(l in Link, where: l.slug == "banned-one"))
    end

    test "places clicks in their real hour with referrer and browser", ctx do
      report = import_dump(ctx.path)

      assert report.events == 3

      news = Repo.one!(from(l in Link, where: l.slug == "news"))
      events = Repo.all(from(c in ClickEvent, where: c.link_id == ^news.id))

      assert length(events) == 2
      assert Enum.all?(events, &(DateTime.diff(&1.occurred_at, ctx.recent, :second) in 0..600))
      assert Enum.all?(events, &is_nil(&1.ip))

      assert Enum.sort(Enum.map(events, & &1.referrer)) == [nil, "team.stylite.de"]

      families = events |> Enum.map(& &1.user_agent) |> Enum.map(&browser_family/1) |> Enum.sort()
      assert families == ["Chrome", "Firefox"]
    end

    test "drops clicks older than the retention window", %{path: path} do
      report = import_dump(path)

      assert report.dropped_by_retention == 5
      assert Repo.aggregate(ClickEvent, :count) == 3
    end

    test "reset clears the previous links and events first", ctx do
      old = link_fixture(ctx.admin, ctx.domain, %{slug: "leftover"})

      Repo.insert!(
        struct(ClickEvent, %{link_id: old.id, occurred_at: DateTime.utc_now(), ip: "203.0.113.1"})
      )

      report = ctx.path |> KuttDump.parse() |> KuttDump.Importer.run(reset: true)

      assert report.deleted_links == 1
      assert report.deleted_events == 1
      refute Repo.exists?(from(l in Link, where: l.slug == "leftover"))
    end

    test "an unknown owner email aborts before anything is written", %{path: path} do
      assert_raise RuntimeError, ~r/nobody@example.com/, fn ->
        path |> KuttDump.parse() |> KuttDump.Importer.run(owner: "nobody@example.com")
      end

      assert Repo.aggregate(Link, :count) == 0
    end
  end

  defp import_dump(path), do: path |> KuttDump.parse() |> KuttDump.Importer.run()

  defp browser_family(user_agent) do
    cond do
      String.contains?(user_agent, "Firefox/") -> "Firefox"
      String.contains?(user_agent, "Chrome/") -> "Chrome"
      String.contains?(user_agent, "Safari/") -> "Safari"
      true -> "Other"
    end
  end
end
