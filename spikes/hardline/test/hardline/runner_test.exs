defmodule Hardline.RunnerTest do
  use ExUnit.Case, async: true

  describe "session naming" do
    test "builds deterministic tmux session names" do
      assert Hardline.Runner.session_name(3) == "babs-test-3"
      assert Hardline.Runner.session_name(3, prefix: "hardline") == "hardline-3"
    end

    test "rejects invalid session indexes" do
      assert_raise ArgumentError, fn -> Hardline.Runner.session_name(0) end
      assert_raise ArgumentError, fn -> Hardline.Runner.session_name(-1) end
    end
  end

  describe "fleet planning" do
    test "builds deterministic fleet specs" do
      assert Hardline.Runner.fleet_specs(3, command: "zsh", prefix: "short") == [
               %{index: 1, session: "short-1", command: "zsh"},
               %{index: 2, session: "short-2", command: "zsh"},
               %{index: 3, session: "short-3", command: "zsh"}
             ]
    end

    test "rejects invalid fleet sizes" do
      assert_raise ArgumentError, fn -> Hardline.Runner.fleet_specs(0) end
    end
  end

  describe "tmux command shapes" do
    test "builds detached new-session argv" do
      assert Hardline.Runner.new_session_args("babs-test-1", "zsh") == [
               "new-session",
               "-d",
               "-s",
               "babs-test-1",
               "zsh"
             ]
    end

    test "omits the command when using tmux's default shell" do
      assert Hardline.Runner.new_session_args("babs-test-1", "") == [
               "new-session",
               "-d",
               "-s",
               "babs-test-1"
             ]
    end

    test "builds erlexec attach command as a charlist" do
      assert Hardline.Runner.attach_command("babs-test-1") ==
               ~c"tmux attach-session -t babs-test-1"
    end
  end

  describe "managed session naming" do
    test "builds managed names and identifies managed sessions by prefix" do
      assert Hardline.Runner.managed_prefix() == "babs-hardline"
      assert Hardline.Runner.managed_session_name("demo") == "babs-hardline-demo"
      assert Hardline.Runner.managed_session?("babs-hardline-demo")
      refute Hardline.Runner.managed_session?("operator-demo")
    end

    test "refuses to kill unmanaged sessions through managed kill helper" do
      assert {:error, :unmanaged_session} =
               Hardline.Runner.kill_managed_session("operator-demo", "babs-hardline-test")
    end
  end

  describe "terminal resize" do
    test "rejects invalid dimensions" do
      assert_raise ArgumentError, fn -> Hardline.Runner.resize(%{os_pid: 1}, 0, 80) end
      assert_raise ArgumentError, fn -> Hardline.Runner.resize(%{os_pid: 1}, 24, 0) end
    end
  end

  describe "output collection" do
    test "preserves unrelated mailbox messages" do
      send(self(), {:DOWN, make_ref(), :process, self(), :synthetic})
      send(self(), {:stdout, 999, "READY\n"})

      assert {:ok, "READY\n"} = Hardline.Runner.collect_until(%{os_pid: 999}, "READY", 100)
      assert_receive {:DOWN, _ref, :process, _pid, :synthetic}
    end

    test "honors timeout even when stdout continues without the pattern" do
      parent = self()
      os_pid = System.unique_integer([:positive])
      producer = spawn(fn -> send_stdout_until_stopped(parent, os_pid) end)

      started_at = System.monotonic_time(:millisecond)

      assert {:error, {:timeout, output}} =
               Hardline.Runner.collect_until(%{os_pid: os_pid}, "NEVER", 25)

      elapsed = System.monotonic_time(:millisecond) - started_at

      Process.exit(producer, :kill)
      flush_stdout(os_pid)

      assert output != ""
      assert elapsed < 500
    end
  end

  defp send_stdout_until_stopped(parent, os_pid) do
    send(parent, {:stdout, os_pid, "tick\n"})
    Process.sleep(1)
    send_stdout_until_stopped(parent, os_pid)
  end

  defp flush_stdout(os_pid) do
    receive do
      {:stdout, ^os_pid, _data} -> flush_stdout(os_pid)
    after
      0 -> :ok
    end
  end
end
