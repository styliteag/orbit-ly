defmodule OrbitlyWeb.Router do
  use OrbitlyWeb, :router

  import OrbitlyWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {OrbitlyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug OrbitlyWeb.Plugs.ContentSecurityPolicy
    plug :fetch_current_user
    plug :fetch_design
  end

  # Reads the design/mode cookies into assigns (root layout renders the
  # combined theme as data-theme) and mirrors the design into the session
  # (LiveViews pick their layout on mount).
  defp fetch_design(conn, _opts) do
    design = OrbitlyWeb.Design.validate(conn.cookies["orbitly_design"])
    mode = OrbitlyWeb.Design.validate_mode(conn.cookies["orbitly_mode"])

    conn =
      conn
      |> Plug.Conn.assign(:design, design)
      |> Plug.Conn.assign(:theme, OrbitlyWeb.Design.theme(design, mode))

    if Plug.Conn.get_session(conn, :design) == design do
      conn
    else
      Plug.Conn.put_session(conn, :design, design)
    end
  end

  # Per-IP throttle for credential submissions (sign-in, reset request).
  pipeline :auth_rate_limit do
    plug OrbitlyWeb.Plugs.AuthRateLimit
  end

  scope "/", OrbitlyWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/qr/:id", QrController, :show
    delete "/sign-out", UserSessionController, :delete
    put "/design/:design", DesignController, :update
    put "/design-mode/:mode", DesignController, :update_mode

    live_session :authenticated,
      on_mount: [{OrbitlyWeb.UserAuth, :mount_current_user}] do
      # Each LiveView declares its own requirement via on_mount, e.g.
      # {OrbitlyWeb.UserAuth, :live_user_required | :live_admin_required}.
      live "/links", LinksLive, :index
      live "/links/:id/stats", LinkStatsLive, :show
      live "/settings", UserSettingsLive, :edit
      live "/admin/domains", AdminDomainsLive, :index
      live "/admin/users", AdminUsersLive, :index
    end
  end

  # Credential-handling routes sit behind the per-IP rate limiter.
  scope "/", OrbitlyWeb do
    pipe_through [:browser, :auth_rate_limit]

    post "/session", UserSessionController, :create

    live_session :auth,
      on_mount: [{OrbitlyWeb.UserAuth, :mount_current_user}] do
      # No open registration (ADR-0006): accounts are admin-created.
      live "/sign-in", UserLoginLive, :new
      live "/reset", UserForgotPasswordLive, :new
      live "/password-reset/:token", UserResetPasswordLive, :edit
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:orbitly, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: OrbitlyWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
