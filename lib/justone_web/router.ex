defmodule JustoneWeb.Router do
  use JustoneWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {JustoneWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :ensure_session_id
  end

  defp ensure_session_id(conn, _opts) do
    case get_session(conn, :session_id) do
      nil ->
        session_id = Ecto.UUID.generate()
        put_session(conn, :session_id, session_id)

      _session_id ->
        conn
    end
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", JustoneWeb do
    pipe_through :browser

    live_session :default, on_mount: JustoneWeb.LiveAuth do
      live "/", LobbyLive, :index
      live "/game/:code", GameLive, :show
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", JustoneWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:justone, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: JustoneWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
