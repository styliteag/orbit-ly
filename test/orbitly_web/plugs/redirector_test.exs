defmodule OrbitlyWeb.RedirectorTest do
  use OrbitlyWeb.ConnCase, async: false

  import Orbitly.Fixtures

  alias Orbitly.Shortener
  alias Orbitly.Shortener.RedirectCache

  @primary_host "www.example.com"
  @redirect_host "go.example"

  setup do
    RedirectCache.flush()

    # drain tracked clicks inside the sandbox before it rolls back — leftovers
    # would flush later against rolled-back links and log FK errors
    on_exit(fn -> Orbitly.Shortener.ClickBuffer.flush_now() end)

    primary = domain_fixture(%{hostname: @primary_host, is_primary: true})
    redirect_domain = domain_fixture(%{hostname: @redirect_host})
    user = user_fixture()

    %{primary: primary, redirect_domain: redirect_domain, user: user}
  end

  defp on_host(conn, host), do: %{conn | host: host}

  describe "slug resolution" do
    test "redirects a known slug on a redirect host", ctx do
      link_fixture(ctx.user, ctx.redirect_domain, %{
        slug: "promo",
        target_url: "https://example.org/sale"
      })

      conn = build_conn() |> on_host(@redirect_host) |> get("/promo")

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["https://example.org/sale"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "redirects a known slug on the primary domain too (mixed mode, ADR-0004)", ctx do
      link_fixture(ctx.user, ctx.primary, %{slug: "promo", target_url: "https://example.org/p"})

      conn = build_conn() |> on_host(@primary_host) |> get("/promo")

      assert conn.status == 302
    end

    test "unknown slug on a redirect host answers plain 404", _ctx do
      conn = build_conn() |> on_host(@redirect_host) |> get("/nope")

      assert conn.status == 404
    end

    test "multi-segment paths on a redirect host answer 404", _ctx do
      conn = build_conn() |> on_host(@redirect_host) |> get("/a/b")

      assert conn.status == 404
    end

    test "expired links answer 410", ctx do
      link_fixture(ctx.user, ctx.redirect_domain, %{
        slug: "old",
        expires_at: DateTime.add(DateTime.utc_now(), -60)
      })

      conn = build_conn() |> on_host(@redirect_host) |> get("/old")

      assert conn.status == 410
    end

    test "links on an inactive domain are not resolved", ctx do
      inactive = domain_fixture(%{hostname: "off.example", active: false})
      link_fixture(ctx.user, inactive, %{slug: "hidden"})

      conn = build_conn() |> on_host("off.example") |> get("/hidden")

      # inactive host behaves like an unknown one; test config passes to router
      refute conn.status == 302
    end
  end

  describe "UI pass-through" do
    test "the primary domain serves UI routes", _ctx do
      conn = build_conn() |> on_host(@primary_host) |> get("/")

      # anonymous "/" now redirects into the auth flow — the router handled it
      assert redirected_to(conn) == ~p"/sign-in"
    end

    test "reserved slugs pass to the router on the primary domain", ctx do
      # even if a link with a reserved slug existed (seeded around validation),
      # the plug must not resolve it
      link_fixture(ctx.user, ctx.primary, %{slug: "admin"})

      conn = build_conn() |> on_host(@primary_host) |> get("/admin")

      assert conn.status == 404
      assert get_resp_header(conn, "location") == []
    end

    test "unknown hosts pass to the router in test config", _ctx do
      conn = build_conn() |> on_host("unknown.example") |> get("/")

      assert redirected_to(conn) == ~p"/sign-in"
    end
  end

  describe "password-protected links" do
    setup ctx do
      link_fixture(ctx.user, ctx.redirect_domain, %{
        slug: "vault",
        target_url: "https://example.org/secret",
        password_hash: Bcrypt.hash_pwd_salt("letmein")
      })

      :ok
    end

    test "GET renders the unlock form instead of redirecting" do
      conn = build_conn() |> on_host(@redirect_host) |> get("/vault")

      assert conn.status == 200
      assert conn.resp_body =~ "password-protected"
    end

    test "POST with the correct password redirects" do
      conn =
        build_conn()
        |> on_host(@redirect_host)
        |> post("/vault", %{"password" => "letmein"})

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["https://example.org/secret"]
    end

    test "POST with a wrong password answers 401 with the form again" do
      conn =
        build_conn()
        |> on_host(@redirect_host)
        |> post("/vault", %{"password" => "wrong"})

      assert conn.status == 401
      assert conn.resp_body =~ "Wrong password"
    end

    test "repeated wrong attempts from one IP are rate-limited with 429" do
      Orbitly.Shortener.RateLimiter.clear_all()

      post_wrong = fn ->
        build_conn()
        |> on_host(@redirect_host)
        |> Map.put(:remote_ip, {203, 0, 113, 77})
        |> post("/vault", %{"password" => "wrong"})
      end

      for _ <- 1..5, do: assert(post_wrong.().status == 401)
      assert post_wrong.().status == 429

      # even the correct password is refused while the window is hot
      conn =
        build_conn()
        |> on_host(@redirect_host)
        |> Map.put(:remote_ip, {203, 0, 113, 77})
        |> post("/vault", %{"password" => "letmein"})

      assert conn.status == 429

      # other clients are unaffected
      other =
        build_conn()
        |> on_host(@redirect_host)
        |> Map.put(:remote_ip, {203, 0, 113, 78})
        |> post("/vault", %{"password" => "letmein"})

      assert other.status == 302
    end
  end

  describe "click tracking" do
    test "successful redirects record a click event with request metadata", ctx do
      Orbitly.Shortener.ClickBuffer.flush_now()
      link = link_fixture(ctx.user, ctx.redirect_domain, %{slug: "tracked"})
      admin = admin_fixture()

      build_conn()
      |> on_host(@redirect_host)
      |> put_req_header("x-forwarded-for", "198.51.100.9, 10.0.0.1")
      |> put_req_header("user-agent", "TestAgent/1.0")
      |> put_req_header("referer", "https://referrer.example/page")
      |> get("/tracked")

      Orbitly.Shortener.ClickBuffer.flush_now()

      assert {:ok, [event]} = Shortener.list_click_events(actor: admin)
      assert event.link_id == link.id
      assert event.ip == "198.51.100.9"
      assert event.user_agent == "TestAgent/1.0"
      assert event.referrer == "https://referrer.example/page"
    end

    test "404, 410 and unlock-form responses record nothing", ctx do
      Orbitly.Shortener.ClickBuffer.flush_now()
      admin = admin_fixture()

      link_fixture(ctx.user, ctx.redirect_domain, %{
        slug: "dead",
        expires_at: DateTime.add(DateTime.utc_now(), -60)
      })

      link_fixture(ctx.user, ctx.redirect_domain, %{
        slug: "locked",
        password_hash: Bcrypt.hash_pwd_salt("pw")
      })

      build_conn() |> on_host(@redirect_host) |> get("/missing")
      build_conn() |> on_host(@redirect_host) |> get("/dead")
      build_conn() |> on_host(@redirect_host) |> get("/locked")

      Orbitly.Shortener.ClickBuffer.flush_now()
      assert {:ok, []} = Shortener.list_click_events(actor: admin)
    end
  end

  describe "cache invalidation" do
    test "link updates through Ash invalidate the cache", ctx do
      {:ok, link} =
        Shortener.create_link(
          %{slug: "fresh", target_url: "https://old.example/", domain_id: ctx.redirect_domain.id},
          actor: ctx.user
        )

      conn = build_conn() |> on_host(@redirect_host) |> get("/fresh")
      assert get_resp_header(conn, "location") == ["https://old.example/"]

      {:ok, _} =
        Shortener.update_link(link, %{target_url: "https://new.example/"}, actor: ctx.user)

      conn = build_conn() |> on_host(@redirect_host) |> get("/fresh")
      assert get_resp_header(conn, "location") == ["https://new.example/"]
    end

    test "negative lookups are cached but flushed on writes", ctx do
      conn = build_conn() |> on_host(@redirect_host) |> get("/soon")
      assert conn.status == 404

      {:ok, _} =
        Shortener.create_link(
          %{slug: "soon", target_url: "https://example.org/", domain_id: ctx.redirect_domain.id},
          actor: ctx.user
        )

      conn = build_conn() |> on_host(@redirect_host) |> get("/soon")
      assert conn.status == 302
    end
  end
end
