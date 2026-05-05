defmodule BabsWeb.TerminalController do
  @moduledoc false

  import Plug.Conn
  import Phoenix.LiveView.Controller

  alias Babs.Citizens.Lifecycle
  alias BabsWeb.CitizenPath

  def init(action), do: action

  def call(conn, action), do: apply(__MODULE__, action, [conn, conn.params])

  def index(conn, params) do
    conn = fetch_query_params(conn)

    conn
    |> put_resp_header("location", CitizenPath.index(socket_token(conn, params)))
    |> send_resp(302, "")
  end

  def citizens(conn, params) do
    conn = fetch_query_params(conn)

    live_render(conn, BabsWeb.CitizensLive,
      session: %{"socket_token" => socket_token(conn, params)}
    )
  end

  def show(conn, %{"slug" => slug} = params) do
    conn = fetch_query_params(conn)

    case Lifecycle.lookup(slug) do
      {:ok, _pid} ->
        send_terminal(conn, slug, socket_token(conn, params), full?(conn, params))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "citizen not found: #{slug}\n")
    end
  end

  def new(conn, params) do
    conn = fetch_query_params(conn)

    case Lifecycle.lookup("new") do
      {:ok, _pid} ->
        send_terminal(conn, "new", socket_token(conn, params), full?(conn, params))

      {:error, :not_found} ->
        live_render(conn, BabsWeb.NewCitizenLive,
          session: %{"socket_token" => socket_token(conn, params)}
        )
    end
  end

  def head(conn, %{"slug" => slug}) do
    case Lifecycle.lookup(slug) do
      {:ok, _pid} -> send_resp(conn, 200, "")
      {:error, :not_found} -> send_resp(conn, 404, "")
    end
  end

  def citizens_head(conn, _params), do: send_resp(conn, 200, "")

  defp send_terminal(conn, slug, socket_token, full?) do
    live_render(conn, BabsWeb.TerminalLive,
      session: %{"slug" => slug, "socket_token" => socket_token || "", "full?" => full?}
    )
  end

  defp socket_token(conn, params) do
    case Map.get(conn.query_params, "socket_token") || Map.get(params, "socket_token", "") do
      token when is_binary(token) -> token
      _token -> ""
    end
  end

  defp full?(conn, params) do
    full?(conn.query_params) || full?(params)
  end

  defp full?(%{"full" => value}) when value in ["1", "true"], do: true
  defp full?(_params), do: false
end
