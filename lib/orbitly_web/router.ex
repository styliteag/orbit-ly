defmodule OrbitlyWeb.Router do
  use OrbitlyWeb, :router

  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {OrbitlyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug OrbitlyWeb.Plugs.ContentSecurityPolicy
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  # Per-IP throttle for credential submissions (sign-in, reset request).
  pipeline :auth_rate_limit do
    plug OrbitlyWeb.Plugs.AuthRateLimit
  end

  scope "/", OrbitlyWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes do
      # each liveview declares its requirement via on_mount:
      # {OrbitlyWeb.LiveUserAuth, :live_user_required | :live_admin_required | ...}
      live "/links", LinksLive, :index
      live "/links/:id/stats", LinkStatsLive, :show
      live "/admin/domains", AdminDomainsLive, :index
      live "/admin/users", AdminUsersLive, :index
    end
  end

  scope "/", OrbitlyWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/qr/:id", QrController, :show
    sign_out_route AuthController
  end

  # Credential-handling routes sit behind the per-IP rate limiter.
  scope "/", OrbitlyWeb do
    pipe_through [:browser, :auth_rate_limit]

    auth_routes AuthController, Orbitly.Accounts.User, path: "/auth"

    # Keine offene Registrierung (ADR-0006): kein register_path.
    # Konten legt der Instanz-Admin an.
    sign_in_route reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{OrbitlyWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    OrbitlyWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.Default
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  OrbitlyWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.Default
                ]

    # Remove this if you do not use the confirmation strategy
    confirm_route Orbitly.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [OrbitlyWeb.AuthOverrides, Elixir.AshAuthentication.Phoenix.Overrides.Default]
  end

  # Other scopes may use custom stacks.
  # scope "/api", OrbitlyWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:orbitly, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: OrbitlyWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
