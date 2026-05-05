defmodule BabsWeb.TerminalController do
  @moduledoc false

  import Phoenix.Controller, only: [put_root_layout: 2]
  import Plug.Conn
  import Phoenix.LiveView.Controller

  alias Babs.Citizens.Lifecycle

  def init(action), do: action

  def call(conn, action), do: apply(__MODULE__, action, [conn, conn.params])

  def index(conn, params) do
    conn = fetch_query_params(conn)

    location =
      case socket_token(conn, params) do
        token when is_binary(token) and token != "" ->
          "/citizens/sentinel?socket_token=#{URI.encode(token)}"

        _ ->
          "/citizens/sentinel"
      end

    conn
    |> put_resp_header("location", location)
    |> send_resp(302, "")
  end

  def show(conn, %{"slug" => slug} = params) do
    conn = fetch_query_params(conn)

    case Lifecycle.lookup(slug) do
      {:ok, _pid} ->
        send_terminal(conn, slug, socket_token(conn, params))

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

  defp send_terminal(conn, slug, socket_token) do
    conn
    |> put_root_layout(html: {BabsWeb.Layouts, :root})
    |> live_render(BabsWeb.TerminalLive,
      session: %{"slug" => slug, "socket_token" => socket_token || ""}
    )
  end

  defp socket_token(conn, params) do
    Map.get(conn.query_params, "socket_token") || Map.get(params, "socket_token", "")
  end
end
