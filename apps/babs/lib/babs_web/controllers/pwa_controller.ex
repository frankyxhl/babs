defmodule BabsWeb.PwaController do
  @moduledoc false

  import Plug.Conn

  def init(action), do: action

  def call(conn, action), do: apply(__MODULE__, action, [conn, conn.params])

  def service_worker(conn, _params) do
    conn
    |> put_resp_content_type("application/javascript")
    |> put_resp_header("cache-control", "no-cache")
    |> send_file(200, service_worker_path())
  end

  defp service_worker_path do
    :babs
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("pwa/sw.js")
  end
end
