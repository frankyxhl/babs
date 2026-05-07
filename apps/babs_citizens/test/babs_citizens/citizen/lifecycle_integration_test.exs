defmodule Babs.Citizens.Citizen.LifecycleIntegrationTest do
  use Babs.Citizens.RepoCase, async: false

  alias Babs.Citizens.{CitizenConfig, Lifecycle, Runner}
  alias Babs.Citizens.Hardline.Pane

  test "detaches and reattaches without killing the tmux session" do
    config = sentinel_config()
    session = Runner.session_name(config.slug)

    on_exit(fn -> Runner.kill_session(session) end)

    assert {:ok, pid} = Lifecycle.start_config(config)
    assert Runner.tmux_session_alive?(session)
    assert {:ok, ^pid} = Lifecycle.lookup(config.slug)
    assert {:ok, ^pid} = Lifecycle.start_config(config)

    marker = "BABS_LIFECYCLE_INJECT_#{System.unique_integer([:positive])}"
    Pane.inject(config.slug, "printf '#{marker}\\n'\n")
    wait_for_capture!(session, marker)
    Pane.resize(config.slug, 33, 101)

    assert :ok = DynamicSupervisor.terminate_child(Babs.Citizens.DynamicSupervisor, pid)
    assert Runner.tmux_session_alive?(session)
    assert {:error, :not_found} = Lifecycle.lookup(config.slug)
    assert wait_for_attach_client?(session, false, 5_000)

    assert {:ok, reattached_pid} = Lifecycle.reattach(config)
    assert is_pid(reattached_pid)
    assert Runner.tmux_session_alive?(session)

    assert :ok = Lifecycle.stop_citizen(config.slug)
    refute Runner.tmux_session_alive?(session)
  end

  test "detaching a pane stops its tmux attach client" do
    config = sentinel_config()
    session = Runner.session_name(config.slug)

    on_exit(fn -> Runner.kill_session(session) end)

    assert :ok = Runner.start_session(config)
    assert {:ok, attach} = Runner.attach(session)
    assert wait_for_attach_client?(session, true, 2_000)

    assert :ok = Runner.detach(attach)
    assert wait_for_attach_client?(session, false, 5_000)
    assert Runner.tmux_session_alive?(session)
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

  defp wait_for_capture!(session, marker) do
    deadline = System.monotonic_time(:millisecond) + 5_000
    do_wait_for_capture!(session, marker, deadline)
  end

  defp do_wait_for_capture!(session, marker, deadline) do
    cond do
      capture_contains?(session, marker) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("timed out waiting for #{marker} in #{session}")

      true ->
        Process.sleep(100)
        do_wait_for_capture!(session, marker, deadline)
    end
  end

  defp capture_contains?(session, marker) do
    case Runner.capture_pane(session) do
      {:ok, capture} -> String.contains?(capture, marker)
      {:error, _reason} -> false
    end
  end

  defp wait_for_attach_client?(session, expected, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_attach_client?(session, expected, deadline)
  end

  defp do_wait_for_attach_client?(session, expected, deadline) do
    cond do
      attach_client_alive?(session) == expected ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(100)
        do_wait_for_attach_client?(session, expected, deadline)
    end
  end

  defp attach_client_alive?(session) do
    case System.cmd("tmux", ["list-clients"], stderr_to_stdout: true) do
      {output, 0} -> String.contains?(output, session)
      {_output, _status} -> false
    end
  end
end
