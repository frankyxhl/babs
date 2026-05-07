defmodule Babs.Citizens.DirectCli.ExecutorTest do
  use ExUnit.Case, async: false

  alias Babs.Citizens.DirectCli.{Command, Executor}

  @tag :capture_log
  test "runs a resolved command with bounded stdout" do
    command = %Command{
      args: ["/bin/echo", "hello"],
      env: [{"PATH", System.get_env("PATH", "")}],
      output_limit: 1024,
      timeout_ms: 1_000
    }

    assert {:ok, %{stdout: "hello\n", stderr: "", exit_status: 0}} = Executor.run(command)
  end

  test "runs the provider command from command cwd" do
    cwd =
      Path.join(System.tmp_dir!(), "babs-direct-executor-#{System.unique_integer([:positive])}")

    try do
      File.mkdir_p!(cwd)
      basename = Path.basename(cwd)

      command = %Command{
        args: ["/bin/sh", "-c", ~s(basename "$PWD")],
        cwd: cwd,
        env: [{"PATH", System.get_env("PATH", "")}],
        output_limit: 1024,
        timeout_ms: 1_000
      }

      assert {:ok, %{stdout: stdout}} = Executor.run(command)
      assert String.trim(stdout) == basename
    after
      File.rm_rf(cwd)
    end
  end

  test "times out and terminates the spawned process group" do
    cwd =
      Path.join(
        System.tmp_dir!(),
        "babs-direct-executor-timeout-#{System.unique_integer([:positive])}"
      )

    try do
      File.mkdir_p!(cwd)

      command = %Command{
        args: [
          "/bin/sh",
          "-c",
          "echo $$ > parent.pid; sleep 10 & echo $! > child.pid; wait"
        ],
        cwd: cwd,
        env: [{"PATH", System.get_env("PATH", "")}],
        output_limit: 1024,
        timeout_ms: 250
      }

      assert {:error, :timeout} = Executor.run(command)

      parent_pid = cwd |> Path.join("parent.pid") |> read_pid!()
      child_pid = cwd |> Path.join("child.pid") |> read_pid!()

      refute_process_alive_soon(parent_pid)
      refute_process_alive_soon(child_pid)
    after
      File.rm_rf(cwd)
    end
  end

  test "returns executable_not_found without spawning" do
    command = %Command{
      args: ["babs-missing-direct-cli"],
      env: [{"PATH", System.get_env("PATH", "")}],
      output_limit: 1024,
      timeout_ms: 1_000
    }

    assert {:error, {:executable_not_found, "babs-missing-direct-cli"}} = Executor.run(command)
  end

  defp read_pid!(path) do
    path
    |> File.read!()
    |> String.trim()
    |> String.to_integer()
  end

  defp refute_process_alive_soon(pid, deadline \\ System.monotonic_time(:millisecond) + 2_000) do
    if process_alive?(pid) and System.monotonic_time(:millisecond) < deadline do
      Process.sleep(25)
      refute_process_alive_soon(pid, deadline)
    else
      refute process_alive?(pid)
    end
  end

  defp process_alive?(pid) do
    case System.cmd("/bin/kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_output, 0} -> true
      {_output, _status} -> false
    end
  end
end
