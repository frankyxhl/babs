defmodule BabsWeb.Router do
  @moduledoc false

  use Phoenix.Router
  import Phoenix.Controller
  import Phoenix.LiveView.Router
  import Phoenix.LiveDashboard.Router

  @dashboard_auth_required_by_default Mix.env() == :prod

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:put_root_layout, html: {BabsWeb.Layouts, :root})
  end

  pipeline :citizen_terminal_gate do
    plug(BabsWeb.CitizenTerminalGate)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :live_dashboard_auth do
    plug(:require_live_dashboard_auth)
  end

  scope "/", BabsWeb do
    pipe_through(:browser)

    get("/sw.js", PwaController, :service_worker)
    get("/", TerminalController, :index)
    get("/dev/kitchen-sink", TerminalController, :kitchen_sink)
    get("/citizens", TerminalController, :citizens)
    head("/citizens", TerminalController, :citizens_head)
    get("/citizens/new", TerminalController, :new)
    get("/citizens/attach", TerminalController, :attach)

    scope "/" do
      pipe_through(:citizen_terminal_gate)

      live_session :citizen_terminal,
        session: {BabsWeb.TerminalController, :terminal_session, []} do
        live("/citizens/:slug", TerminalLive)
      end
    end

    head("/citizens/:slug", TerminalController, :head)
    get("/tickets", TerminalController, :tickets)
    get("/tickets/new", TerminalController, :new_ticket)
    get("/tickets/:id", TerminalController, :ticket)
    get("/forum", TerminalController, :forum)
    get("/forum/:id", TerminalController, :forum_thread)
  end

  scope "/" do
    pipe_through([:browser, :live_dashboard_auth])

    live_dashboard("/dev/dashboard", metrics: Babs.Telemetry)
  end

  scope "/api/v1", BabsWeb.Api.V1 do
    pipe_through(:api)

    get("/node", ReadController, :node)
    get("/events", EventsController, :index)
    get("/citizens", ReadController, :citizens)
    get("/citizens/:slug/transcript", ReadController, :citizen_transcript)
    get("/citizens/:slug/standing-context", ReadController, :citizen_standing_context)
    post("/citizens/:slug/injections", ControlController, :inject)
    post("/citizens/:slug/lifecycle", ControlController, :lifecycle)
    get("/citizens/:slug", ReadController, :citizen)
    post("/tickets/:id/comments", ControlController, :comment)
    post("/tickets/:id/transitions", ControlController, :transition)
    post("/tickets/:id/assignments", ControlController, :assign)
    delete("/tickets/:id/assignments/:slug", ControlController, :unassign)
    get("/tickets", ReadController, :tickets)
    get("/tickets/:id", ReadController, :ticket)
  end

  defp require_live_dashboard_auth(conn, _opts) do
    if live_dashboard_auth_required?() do
      case live_dashboard_auth_token() do
        nil ->
          conn
          |> put_resp_content_type("text/plain")
          |> send_resp(503, "LiveDashboard auth token is not configured")
          |> halt()

        token ->
          Plug.BasicAuth.basic_auth(conn,
            username: "babs",
            password: token,
            realm: "babs-dashboard"
          )
      end
    else
      conn
    end
  end

  defp live_dashboard_auth_required? do
    :babs
    |> Application.get_env(BabsWeb.LiveDashboardAuth, [])
    |> Keyword.get(:required?, @dashboard_auth_required_by_default)
  end

  defp live_dashboard_auth_token do
    :babs
    |> Application.get_env(BabsWeb.UserSocket, [])
    |> Keyword.get(:auth_token)
    |> normalize_token()
  end

  defp normalize_token(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_token(_value), do: nil
end
