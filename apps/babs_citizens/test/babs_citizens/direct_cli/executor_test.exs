defmodule Babs.Citizens.DirectCli.ExecutorTest do
  use ExUnit.Case, async: false

  alias Babs.Citizens.DirectCli.{Command, Executor}

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

  test "returns executable_not_found without spawning" do
    command = %Command{
      args: ["babs-missing-direct-cli"],
      env: [{"PATH", System.get_env("PATH", "")}],
      output_limit: 1024,
      timeout_ms: 1_000
    }

    assert {:error, {:executable_not_found, "babs-missing-direct-cli"}} = Executor.run(command)
  end
end
