defmodule Orbitly.KuttImportTest do
  use Orbitly.DataCase, async: false

  import Orbitly.Fixtures

  alias Orbitly.KuttImport
  alias Orbitly.Shortener.{ClickEvent, Link}

  defmodule StubClient do
    @behaviour Orbitly.KuttImport.Client
    @impl true
    def list_links(%{links: links}), do: {:ok, links}
  end

  defp run(links, opts \\ []) do
    KuttImport.run([client: StubClient, config: %{links: links}] ++ opts)
  end

  defp kutt_link(attrs) do
    Map.merge(
      %{
        "address" => "abc123",
        "target" => "https://example.com/page",
        "description" => nil,
        "expire_in" => nil,
        "visit_count" => 0,
        "password" => false,
        "created_at" => "2024-01-02T03:04:05.000Z",
        "updated_at" => "2024-01-02T03:04:05.000Z"
      },
      attrs
    )
  end

  defp links_by_slug(slug) do
    Repo.all(from l in Link, where: l.slug == ^slug)
  end

  setup do
    admin = admin_fixture()
    domain = domain_fixture(%{is_primary: true})
    %{admin: admin, domain: domain}
  end

  test "imports a link onto the admin and primary domain, preserving created_at", %{
    admin: admin,
    domain: domain
  } do
    report = run([kutt_link(%{"address" => "abc123", "target" => "https://dest.example"})])

    assert [{"abc123", "abc123"}] = report.imported
    assert [link] = links_by_slug("abc123")
    assert link.owner_id == admin.id
    assert link.domain_id == domain.id
    assert link.target_url == "https://dest.example"
    assert DateTime.to_date(link.inserted_at) == ~D[2024-01-02]
  end

  test "--owner assigns the links to that user instead of the admin", %{domain: domain} do
    owner = user_fixture(%{email: "marketing@example.com"})

    report = run([kutt_link(%{"address" => "owned"})], owner: "marketing@example.com")

    assert [{"owned", "owned"}] = report.imported
    assert [link] = links_by_slug("owned")
    assert link.owner_id == owner.id
    assert link.domain_id == domain.id
  end

  test "--owner matches the email case-insensitively" do
    owner = user_fixture(%{email: "Mixed@Example.com"})

    run([kutt_link(%{"address" => "case"})], owner: "mixed@example.com")

    assert [link] = links_by_slug("case")
    assert link.owner_id == owner.id
  end

  test "an unknown owner email aborts the import" do
    assert_raise RuntimeError, ~r/nobody@example.com/, fn ->
      run([kutt_link(%{"address" => "nope"})], owner: "nobody@example.com")
    end

    assert links_by_slug("nope") == []
  end

  test "a reserved slug gets a numeric suffix" do
    report = run([kutt_link(%{"address" => "stats"})])

    assert [{"stats", "stats-1"}] = report.renamed
    assert [_link] = links_by_slug("stats-1")
    assert links_by_slug("stats") == []
  end

  test "a slug already present on the domain is skipped", %{admin: admin, domain: domain} do
    link_fixture(admin, domain, %{slug: "taken"})

    report = run([kutt_link(%{"address" => "taken"})])

    assert report.skipped_exists == ["taken"]
    assert report.imported == []
    assert [_only_one] = links_by_slug("taken")
  end

  test "an invalid slug is skipped" do
    report = run([kutt_link(%{"address" => "no/slashes"})])

    assert report.skipped_invalid == ["no/slashes"]
    assert report.imported == []
  end

  test "synthesises one click per visit_count spread across the lifetime" do
    now = ~U[2024-06-01 00:00:00.000000Z]

    report =
      run(
        [kutt_link(%{"address" => "hot", "visit_count" => 3})],
        now: now
      )

    assert report.clicks == 3
    assert [link] = links_by_slug("hot")

    events = Repo.all(from c in ClickEvent, where: c.link_id == ^link.id)

    assert length(events) == 3
    assert Enum.all?(events, &(&1.user_agent == "kutt-import"))
    assert Enum.all?(events, &is_nil(&1.ip))
  end

  test "password-protected links import without a password and are reported" do
    report = run([kutt_link(%{"address" => "secret", "password" => true})])

    assert report.protected == ["secret"]
    assert [link] = links_by_slug("secret")
    assert is_nil(link.password_hash)
  end
end
