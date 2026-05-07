defmodule Babs.Citizens.RunnerTest do
  use ExUnit.Case, async: false

  alias Babs.Citizens.{CitizenConfig, Runner}

  test "builds a detached Babs-owned tmux session command with cwd and env" do
    original_root = Application.get_env(:babs_citizens, :root)
    original_tickets_root = Application.get_env(:babs_citizens, :tickets_root)
    Application.put_env(:babs_citizens, :root, "/tmp/babs-root")
    Application.put_env(:babs_citizens, :tickets_root, "/tmp/babs-root/var/tickets")

    on_exit(fn ->
      restore_env(:root, original_root)
      restore_env(:tickets_root, original_tickets_root)
    end)

    config = %CitizenConfig{
      id: "BAB-CIT-0000",
      slug: "sentinel",
      display_name: "Sentinel",
      cli: "/bin/zsh",
      cli_args: ["-f"],
      launch_profile: "safe_interactive",
      cwd: "/tmp/babs-sentinel",
      env: %{"BABS_ROOT" => "/wrong-root", "PATH" => "/custom/bin", "TERM" => "xterm-256color"}
    }

    assert Runner.new_session_args(config) == [
             "new-session",
             "-d",
             "-s",
             "babs-sentinel",
             "-c",
             "/tmp/babs-sentinel",
             "-e",
             "BABS_ROOT=/wrong-root",
             "-e",
             "PATH=/custom/bin",
             "-e",
             "TERM=xterm-256color",
             "-e",
             "BABS_CITIZEN_SLUG=sentinel",
             "-e",
             "BABS_ROOT=/tmp/babs-root",
             "-e",
             "BABS_TICKETS_ROOT=/tmp/babs-root/var/tickets",
             "-e",
             "PATH=/tmp/babs-root/bin:/custom/bin",
             "/bin/zsh",
             "-f"
           ]
  end

  test "identifies only babs-prefixed sessions as managed" do
    assert Runner.managed_session?("babs-clare")
    refute Runner.managed_session?("personal-clare")
  end

  test "maps between citizen slugs and managed tmux session names" do
    assert Runner.session_name("clare") == "babs-clare"
    assert Runner.slug_from_session("babs-clare") == {:ok, "clare"}
    assert Runner.slug_from_session("personal-clare") == :error

    assert Runner.attach_command("babs-clare") ==
             ~c"tmux select-pane -t 'babs-clare' \\; attach-session -t 'babs-clare'"

    assert Runner.attach_command("%42", "external-work") ==
             ~c"tmux select-pane -t '%42' \\; attach-session -t 'external-work'"
  end

  test "detects AI CLI configs that should receive submit after Babs prompt injection" do
    assert Runner.ai_cli?(%{cli: "claude", cli_args: []})
    assert Runner.ai_cli?(%{cli: "codex", cli_args: []})
    assert Runner.ai_cli?(%{cli: "gh", cli_args: ["copilot"]})
    assert Runner.ai_cli?(%{cli: "copilot", cli_args: []})
    refute Runner.ai_cli?(%{cli: "gh", cli_args: ["repo", "view"]})
    refute Runner.ai_cli?(%{cli: "/bin/zsh", cli_args: ["-f"]})
  end

  test "trusted autonomous profile appends non-blocking AI CLI args" do
    assert trailing_command(%{
             config()
             | cli: "claude",
               cli_args: [],
               launch_profile: "trusted_autonomous"
           }) ==
             ["claude", "--permission-mode", "dontAsk"]

    assert trailing_command(%{
             config()
             | cli: "codex",
               cli_args: [],
               launch_profile: "trusted_autonomous"
           }) ==
             ["codex", "--ask-for-approval", "never", "--sandbox", "danger-full-access"]

    assert trailing_command(%{
             config()
             | cli: "copilot",
               cli_args: [],
               launch_profile: "trusted_autonomous"
           }) ==
             ["copilot", "--allow-all", "--no-ask-user"]
  end

  test "safe interactive profile preserves explicitly configured args" do
    assert trailing_command(%{config() | cli: "copilot", cli_args: ["--model", "gpt-5.2"]}) ==
             ["copilot", "--model", "gpt-5.2"]
  end

  test "prepare_launch trusts Babs-owned Copilot workspaces before launch" do
    home = tmp_dir("runner-copilot-home")
    cwd = tmp_dir("runner-copilot-workspace")

    config = %{
      config()
      | cli: "copilot",
        cli_args: [],
        launch_profile: "trusted_autonomous",
        cwd: cwd,
        env: %{"COPILOT_HOME" => home}
    }

    assert :ok = Runner.prepare_launch(config)

    settings =
      home
      |> Path.join("config.json")
      |> decode_jsonc_file()

    assert settings["trustedFolders"] == [Path.expand(cwd)]
  end

  test "prepare_launch does not trust folders for safe interactive Copilot sessions" do
    home = tmp_dir("runner-safe-copilot-home")

    config = %{
      config()
      | cli: "copilot",
        cli_args: [],
        launch_profile: "safe_interactive",
        env: %{"COPILOT_HOME" => home}
    }

    assert :ok = Runner.prepare_launch(config)
    refute File.exists?(Path.join(home, "config.json"))
  end

  test "refuses to kill unmanaged sessions" do
    assert Runner.kill_session("personal-clare") == {:error, :unmanaged_session}
  end

  test "returns recoverable errors when the tmux executable is missing" do
    with_tmux_binary("/definitely/missing/babs-tmux", fn ->
      config = config()

      assert {:error, {:tmux_executable_not_found, "/definitely/missing/babs-tmux"}} =
               Runner.list_sessions_result()

      assert Runner.list_sessions() == []

      assert {:error, {:tmux_executable_not_found, "/definitely/missing/babs-tmux"}} =
               Runner.start_session(config)

      refute Runner.tmux_session_alive?(Runner.session_name(config.slug))
    end)
  end

  test "reports tmux metadata and capture failures for missing sessions" do
    missing = "babs-missing-#{System.unique_integer([:positive])}"

    refute Runner.tmux_session_alive?(missing)
    assert {:error, :invalid_pane_pid} = Runner.tmux_pane_pid(missing)
    assert {:error, {:tmux_capture_pane_failed, _status, _output}} = Runner.capture_pane(missing)
  end

  defp config do
    %CitizenConfig{
      id: "BAB-CIT-0000",
      slug: "sentinel",
      display_name: "Sentinel",
      cli: "/bin/zsh",
      cli_args: ["-f"],
      launch_profile: "safe_interactive",
      cwd: "/tmp/babs-sentinel",
      env: %{"TERM" => "xterm-256color"}
    }
  end

  defp trailing_command(config) do
    args = Runner.new_session_args(config)
    Enum.drop(args, length(args) - 1 - length(Runner.effective_cli_args(config)))
  end

  defp with_tmux_binary(binary, fun) do
    original = Application.get_env(:babs_citizens, Runner)
    Application.put_env(:babs_citizens, Runner, tmux_binary: binary)

    try do
      fun.()
    after
      if original do
        Application.put_env(:babs_citizens, Runner, original)
      else
        Application.delete_env(:babs_citizens, Runner)
      end
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:babs_citizens, key)
  defp restore_env(key, value), do: Application.put_env(:babs_citizens, key, value)

  defp tmp_dir(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
  end

  defp decode_jsonc_file(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: false)
    |> Enum.reject(fn line -> line |> String.trim_leading() |> String.starts_with?("//") end)
    |> Enum.join("\n")
    |> Jason.decode!()
  end
end
