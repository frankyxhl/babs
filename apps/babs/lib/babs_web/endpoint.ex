defmodule BabsWeb.Endpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :babs

  @session_options [
    store: :cookie,
    key: "_babs_key",
    signing_salt: "babs_live"
  ]

  socket("/socket", BabsWeb.UserSocket,
    websocket: true,
    longpoll: false
  )

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

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

  plug(Plug.Session, @session_options)
  plug(BabsWeb.Router)
end
