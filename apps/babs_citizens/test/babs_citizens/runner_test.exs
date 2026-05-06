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
    assert Runner.attach_command("babs-clare") == ~c"tmux attach-session -t babs-clare"
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
      cwd: "/tmp/babs-sentinel",
      env: %{"TERM" => "xterm-256color"}
    }
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
end
