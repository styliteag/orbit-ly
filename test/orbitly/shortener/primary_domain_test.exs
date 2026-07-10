defmodule Orbitly.Shortener.PrimaryDomainTest do
  use Orbitly.DataCase, async: false

  import Orbitly.Fixtures

  alias Orbitly.Shortener.{Domain, Link, PrimaryDomain}

  test "creates the primary domain when none exists" do
    assert %Domain{} = domain = PrimaryDomain.ensure!("go.example.com")
    assert domain.is_primary
    assert domain.active
    assert domain.hostname == "go.example.com"
  end

  test "normalizes the hostname" do
    assert %Domain{hostname: "go.example.com"} = PrimaryDomain.ensure!("  GO.Example.COM ")
  end

  test "renames the existing primary in place and keeps its links" do
    user = user_fixture()
    primary = domain_fixture(%{hostname: "old.example", is_primary: true})
    link = link_fixture(user, primary, %{slug: "keep"})

    domain = PrimaryDomain.ensure!("new.example")

    assert domain.id == primary.id
    assert domain.hostname == "new.example"
    assert domain.is_primary

    reloaded = Repo.get(Link, link.id)
    assert reloaded.domain_id == primary.id
  end

  test "is idempotent when the primary is already synced" do
    primary = domain_fixture(%{hostname: "go.example", is_primary: true})

    domain = PrimaryDomain.ensure!("go.example")

    assert domain.id == primary.id
    assert domain.hostname == "go.example"
  end

  test "raises when the target hostname is taken by a redirect domain" do
    domain_fixture(%{hostname: "taken.example", is_primary: false})
    domain_fixture(%{hostname: "old.example", is_primary: true})

    assert_raise RuntimeError, ~r/taken\.example/, fn ->
      PrimaryDomain.ensure!("taken.example")
    end
  end
end
