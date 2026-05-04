defmodule Hardline.Web.PaneServerTest do
  use ExUnit.Case, async: true

  alias Hardline.Web.PaneServer

  test "broadcasts stdout chunks with stream sequence metadata" do
    topic = "pane:pane-server-test-#{System.unique_integer([:positive])}"
    name = String.replace_prefix(topic, "pane:", "")
    state = %{name: name, attach: %{os_pid: 1234}, stream_id: 42, seq: 0}

    Phoenix.PubSub.subscribe(Hardline.PubSub, topic)

    assert {:noreply, %{seq: 1}} = PaneServer.handle_info({:stdout, 1234, "READY\n"}, state)
    assert_receive {:pane_bytes, 42, 1, "READY\n"}
  end

  test "treats clean erlexec exits as normal stops" do
    topic = "pane:pane-server-test-#{System.unique_integer([:positive])}"
    name = String.replace_prefix(topic, "pane:", "")
    state = %{name: name, attach: %{os_pid: 1234}, stream_id: 43, seq: 0}

    Phoenix.PubSub.subscribe(Hardline.PubSub, topic)

    assert {:stop, :normal, ^state} =
             PaneServer.handle_info(
               {:DOWN, make_ref(), :process, self(), {:exit_status, 0}},
               state
             )

    assert_receive {:pane_bytes, 43, 1, message}
    assert message =~ "hardline pane exited"
  end
end
