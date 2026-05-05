defmodule BabsWeb.Router do
  @moduledoc false

  use Phoenix.Router

  pipeline :browser do
    plug(:accepts, ["html"])
  end

  scope "/", BabsWeb do
    pipe_through(:browser)

    get("/", TerminalController, :index)
    get("/citizens/:slug", TerminalController, :show)
    head("/citizens/:slug", TerminalController, :head)
  end
end
