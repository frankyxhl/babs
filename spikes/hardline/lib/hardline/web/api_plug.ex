defmodule Hardline.Web.ApiPlug do
  @moduledoc false

  import Plug.Conn

  alias Hardline.Web.Manager

  def init(opts), do: opts

  def call(%Plug.Conn{method: "GET", request_path: "/api/sessions"} = conn, _opts) do
    case call_manager(&Manager.list_sessions/0) do
      {:ok, sessions} -> send_json(conn, 200, %{sessions: sessions})
      {:error, reason} -> send_error(conn, reason)
    end
  end

  def call(%Plug.Conn{method: "POST", request_path: "/api/sessions"} = conn, _opts) do
    with {:ok, body, conn} <- read_json(conn),
         slug when is_binary(slug) <- Map.get(body, "slug"),
         command <- Map.get(body, "command") do
      case call_manager(fn -> Manager.create_session(slug, command) end) do
        {:ok, session} -> send_json(conn, 201, %{session: session})
        {:error, reason} -> send_error(conn, reason)
      end
    else
      _ -> send_error(conn, :bad_request)
    end
  end

  def call(%Plug.Conn{method: "DELETE", path_info: ["api", "sessions", slug]} = conn, _opts) do
    case call_manager(fn -> Manager.stop_session(slug) end) do
      :ok -> send_json(conn, 200, %{ok: true})
      {:error, reason} -> send_error(conn, reason)
    end
  end

  def call(
        %Plug.Conn{method: "GET", path_info: ["api", "sessions", slug, "screen"]} = conn,
        _opts
      ) do
    case call_manager(fn -> Manager.capture_session(slug) end) do
      {:ok, screen} -> send_json(conn, 200, %{screen: screen})
      {:error, reason} -> send_error(conn, reason)
    end
  end

  def call(conn, _opts), do: conn

  defp call_manager(fun) do
    if Process.whereis(Manager) do
      fun.()
    else
      {:error, :manager_not_started}
    end
  catch
    :exit, {:noproc, _call} -> {:error, :manager_not_started}
  end

  defp read_json(conn) do
    with {:ok, body, conn} <- read_body(conn),
         {:ok, decoded} <- Jason.decode(body) do
      {:ok, decoded, conn}
    else
      _ -> :error
    end
  end

  defp send_json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
    |> halt()
  end

  defp send_error(conn, :invalid_slug), do: send_json(conn, 422, %{error: "invalid_slug"})
  defp send_error(conn, :already_exists), do: send_json(conn, 409, %{error: "already_exists"})
  defp send_error(conn, :not_found), do: send_json(conn, 404, %{error: "not_found"})

  defp send_error(conn, :unmanaged_session),
    do: send_json(conn, 403, %{error: "unmanaged_session"})

  defp send_error(conn, :bad_request), do: send_json(conn, 400, %{error: "bad_request"})

  defp send_error(conn, :manager_not_started),
    do: send_json(conn, 503, %{error: "manager_not_started"})

  defp send_error(conn, reason), do: send_json(conn, 500, %{error: inspect(reason)})
end
