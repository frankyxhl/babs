defmodule BabsWeb.Endpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :babs

  socket("/socket", BabsWeb.UserSocket,
    websocket: true,
    longpoll: false
  )

  if code_reloading? do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.Static,
    at: "/",
    from: :babs,
    only: ~w(css js)
  )

  plug(BabsWeb.Router)
end
