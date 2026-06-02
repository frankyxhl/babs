defmodule BabsWeb.CitizenTerminalGate do
  @moduledoc false

  import Plug.Conn

  alias Babs.Citizens.Lifecycle

  def init(opts), do: opts

  def call(%Plug.Conn{path_params: %{"slug" => slug}} = conn, _opts) do
    case Lifecycle.lookup(slug) do
      {:ok, _pid} ->
        conn

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "citizen not found: #{slug}\n")
        |> halt()
    end
  end

  def call(conn, _opts), do: conn
end
