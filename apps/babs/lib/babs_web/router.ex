defmodule BabsWeb.Router do
  @moduledoc false

  use Phoenix.Router
  import Phoenix.Controller

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:put_root_layout, html: {BabsWeb.Layouts, :root})
  end

  scope "/", BabsWeb do
    pipe_through(:browser)

    get("/", TerminalController, :index)
    get("/dev/kitchen-sink", TerminalController, :kitchen_sink)
    get("/citizens", TerminalController, :citizens)
    head("/citizens", TerminalController, :citizens_head)
    get("/citizens/new", TerminalController, :new)
    get("/citizens/attach", TerminalController, :attach)
    get("/citizens/:slug", TerminalController, :show)
    head("/citizens/:slug", TerminalController, :head)
    get("/tickets", TerminalController, :tickets)
    get("/tickets/new", TerminalController, :new_ticket)
    get("/tickets/:id", TerminalController, :ticket)
  end
end
