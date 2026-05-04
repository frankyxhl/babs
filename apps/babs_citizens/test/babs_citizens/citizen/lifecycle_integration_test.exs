defmodule Babs.Citizens.Citizen.LifecycleIntegrationTest do
  use ExUnit.Case, async: false

  alias Babs.Citizens.{CitizenConfig, Lifecycle, Runner}

  test "detaches and reattaches without killing the tmux session" do
    config = sentinel_config()
    session = Runner.session_name(config.slug)

    on_exit(fn -> Runner.kill_session(session) end)

    assert {:ok, pid} = Lifecycle.start_config(config)
    assert Runner.tmux_session_alive?(session)
    assert {:ok, ^pid} = Lifecycle.lookup(config.slug)

    assert :ok = DynamicSupervisor.terminate_child(Babs.Citizens.DynamicSupervisor, pid)
    assert Runner.tmux_session_alive?(session)
    assert {:error, :not_found} = Lifecycle.lookup(config.slug)

    assert {:ok, reattached_pid} = Lifecycle.reattach(config)
    assert is_pid(reattached_pid)
    assert Runner.tmux_session_alive?(session)

    assert :ok = Lifecycle.stop_citizen(config.slug)
    refute Runner.tmux_session_alive?(session)
  end

  defp sentinel_config do
    slug = "test-sentinel-#{System.unique_integer([:positive])}"
    cwd = Path.join(System.tmp_dir!(), slug)
    File.mkdir_p!(cwd)

    %CitizenConfig{
      id: "BAB-CIT-TEST",
      slug: slug,
      display_name: "Test Sentinel",
      cli: "/bin/zsh",
      cli_args: ["-f"],
      cwd: cwd,
      env: %{}
    }
  end
end
