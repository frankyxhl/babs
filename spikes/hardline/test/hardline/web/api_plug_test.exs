defmodule Hardline.Web.ApiPlugTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import Plug.Test

  alias Hardline.Web.{ApiPlug, Manager}

  defmodule CrashManager do
    use GenServer

    def child_spec(reason) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [reason]},
        restart: :temporary
      }
    end

    def start_link(reason) do
      GenServer.start_link(__MODULE__, reason, name: Manager)
    end

    @impl true
    def init(reason), do: {:ok, reason}

    @impl true
    def handle_call(_request, _from, reason), do: exit(reason)
  end

  setup do
    if pid = Process.whereis(Manager) do
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
    end

    :ok
  end

  test "returns JSON when the manager is not started" do
    conn = conn(:get, "/api/sessions") |> ApiPlug.call([])

    assert conn.status == 503
    assert Jason.decode!(conn.resp_body) == %{"error" => "manager_not_started"}
  end

  test "normalizes manager call timeout exits" do
    assert ApiPlug.normalize_manager_exit(
             {:timeout, {GenServer, :call, [Manager, :list_sessions]}}
           ) ==
             :manager_timeout
  end

  test "returns JSON when the manager call exits unexpectedly" do
    start_supervised!({CrashManager, :synthetic_manager_failure})

    {conn, _log} =
      with_log(fn ->
        conn(:get, "/api/sessions") |> ApiPlug.call([])
      end)

    assert conn.status == 500
    assert %{"error" => "manager_exit", "reason" => reason} = Jason.decode!(conn.resp_body)
    assert reason =~ "synthetic_manager_failure"
  end
end
