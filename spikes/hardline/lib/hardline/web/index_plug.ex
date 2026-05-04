defmodule Hardline.Web.IndexPlug do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{method: "GET", request_path: "/"} = conn, _opts) do
    path = :code.priv_dir(:hardline) |> Path.join("static/index.html")

    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, path)
    |> halt()
  end

  def call(conn, _opts) do
    conn
    |> send_resp(404, "not found")
    |> halt()
  end
end
