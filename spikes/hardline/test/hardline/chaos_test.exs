defmodule Hardline.ChaosTest do
  use ExUnit.Case, async: true

  test "selects a kill target deterministically when seeded" do
    ports = [
      %{session: "babs-test-1", os_pid: 101},
      %{session: "babs-test-2", os_pid: 102},
      %{session: "babs-test-3", os_pid: 103}
    ]

    assert %{session: session, os_pid: os_pid, signal: signal} =
             Hardline.Chaos.choose_target(ports, seed: 7, signal: :sigkill)

    assert session in ["babs-test-1", "babs-test-2", "babs-test-3"]
    assert os_pid in [101, 102, 103]
    assert signal == :sigkill
  end

  test "rejects empty target lists" do
    assert_raise ArgumentError, fn -> Hardline.Chaos.choose_target([]) end
  end
end
