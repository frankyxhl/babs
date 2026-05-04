defmodule Hardline.ObserverTest do
  use ExUnit.Case, async: true

  test "formats events as timestamped log lines" do
    line =
      Hardline.Observer.format_event(:port_down, %{
        session: "babs-test-1",
        os_pid: 12_345,
        reason: :killed
      })

    assert line =~ "event=port_down"
    assert line =~ "session=babs-test-1"
    assert line =~ "os_pid=12345"
    assert line =~ "reason=killed"
    assert line =~ "ts="
    assert String.ends_with?(line, "\n")
  end

  test "sorts metadata keys for stable logs" do
    line = Hardline.Observer.format_event(:tmux_alive, %{z: 1, a: 2})

    assert line =~ "event=tmux_alive a=2 z=1"
  end
end
