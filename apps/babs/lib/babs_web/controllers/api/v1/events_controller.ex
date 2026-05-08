defmodule BabsWeb.Api.V1.EventsController do
  @moduledoc false

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn

  alias BabsWeb.Api.V1.EventFeed

  def init(action), do: action

  def call(conn, action), do: apply(__MODULE__, action, [conn, conn.params])

  def index(conn, _params) do
    conn = fetch_query_params(conn)

    case EventFeed.build(cursor: Map.get(conn.query_params, "cursor")) do
      {:ok, response} ->
        json(conn, response)

      {:error, :invalid_cursor} ->
        error(conn, 400, "invalid_cursor", "Event cursor is invalid")

      {:error, {:config_error, _reason}} ->
        error(conn, 503, "config_error", "Federation config is invalid")

      {:error, _reason} ->
        error(conn, 500, "read_failed", "Events could not be read")
    end
  end

  defp error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{"error" => %{"code" => code, "message" => message}})
  end
end
