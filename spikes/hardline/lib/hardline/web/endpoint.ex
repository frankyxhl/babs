defmodule Hardline.Web.Endpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :hardline

  socket("/socket", Hardline.Web.UserSocket,
    websocket: true,
    longpoll: false
  )

  plug(Plug.Static,
    at: "/",
    from: :hardline,
    only: ~w(index.html js)
  )

  plug(Hardline.Web.ApiPlug)
  plug(Hardline.Web.IndexPlug)
end
