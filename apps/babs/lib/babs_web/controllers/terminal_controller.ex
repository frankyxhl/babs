defmodule BabsWeb.TerminalController do
  @moduledoc false

  import Phoenix.Controller, only: [put_root_layout: 2]
  import Plug.Conn
  import Phoenix.LiveView.Controller

  alias Babs.Citizens.Lifecycle

  def init(action), do: action

  def call(conn, action), do: apply(__MODULE__, action, [conn, conn.params])

  def index(conn, _params) do
    conn
    |> put_resp_header("location", "/citizens/sentinel")
    |> send_resp(302, "")
  end

  def show(conn, %{"slug" => slug}) do
    case Lifecycle.lookup(slug) do
      {:ok, _pid} ->
        send_terminal(conn, slug)

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "citizen not found: #{slug}\n")
    end
  end

  def head(conn, %{"slug" => slug}) do
    case Lifecycle.lookup(slug) do
      {:ok, _pid} -> send_resp(conn, 200, "")
      {:error, :not_found} -> send_resp(conn, 404, "")
    end
  end

  defp send_terminal(conn, slug) do
    conn
    |> put_root_layout(html: {BabsWeb.Layouts, :root})
    |> live_render(BabsWeb.TerminalLive, session: %{"slug" => slug})
  end
end
