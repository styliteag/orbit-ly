defmodule OrbitlyWeb.RedirectorAliasTest do
  use OrbitlyWeb.ConnCase, async: false

  import Orbitly.Fixtures

  alias Orbitly.Shortener.RedirectCache

  setup do
    RedirectCache.flush()
    on_exit(fn -> Orbitly.Shortener.ClickBuffer.flush_now() end)

    target = domain_fixture(%{hostname: "stylite.io"})
    alias_domain = domain_fixture(%{hostname: "stylite.de", alias_of_id: target.id})
    user = user_fixture()

    %{target: target, alias_domain: alias_domain, user: user}
  end

  defp on_host(conn, host), do: %{conn | host: host}

  test "a slug of the target resolves on the alias host and the target host", ctx do
    link_fixture(ctx.user, ctx.target, %{slug: "promo", target_url: "https://example.org/sale"})

    for host <- ["stylite.io", "stylite.de"] do
      conn = build_conn() |> on_host(host) |> get("/promo")

      assert conn.status == 302, "expected redirect on #{host}"
      assert get_resp_header(conn, "location") == ["https://example.org/sale"]
    end
  end

  test "root and catch-all links of the target apply to the alias", ctx do
    link_fixture(ctx.user, ctx.target, %{slug: "", target_url: "https://example.org/root"})
    link_fixture(ctx.user, ctx.target, %{slug: "*", target_url: "https://example.org/any"})

    root = build_conn() |> on_host("stylite.de") |> get("/")
    any = build_conn() |> on_host("stylite.de") |> get("/nope/deep")

    assert get_resp_header(root, "location") == ["https://example.org/root"]
    assert get_resp_header(any, "location") == ["https://example.org/any"]
  end

  test "an unknown slug on the alias answers 404", _ctx do
    assert build_conn() |> on_host("stylite.de") |> get("/nope") |> Map.get(:status) == 404
  end

  test "an inactive alias answers 404", ctx do
    link_fixture(ctx.user, ctx.target, %{slug: "promo"})
    ctx.alias_domain |> Ecto.Changeset.change(active: false) |> Orbitly.Repo.update!()

    assert build_conn() |> on_host("stylite.de") |> get("/promo") |> Map.get(:status) == 404
  end

  test "an inactive target answers 404 on the alias too", ctx do
    link_fixture(ctx.user, ctx.target, %{slug: "promo"})
    ctx.target |> Ecto.Changeset.change(active: false) |> Orbitly.Repo.update!()

    assert build_conn() |> on_host("stylite.de") |> get("/promo") |> Map.get(:status) == 404
  end

  test "a stray link on the alias itself wins instead of crashing", ctx do
    link_fixture(ctx.user, ctx.target, %{slug: "promo", target_url: "https://example.org/target"})

    link_fixture(ctx.user, ctx.alias_domain, %{
      slug: "promo",
      target_url: "https://example.org/own"
    })

    conn = build_conn() |> on_host("stylite.de") |> get("/promo")

    assert get_resp_header(conn, "location") == ["https://example.org/own"]
  end
end
