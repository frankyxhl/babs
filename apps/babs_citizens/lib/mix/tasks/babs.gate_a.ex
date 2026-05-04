defmodule Mix.Tasks.Babs.GateA do
  @moduledoc """
  Runs the Phase 1 scripted sentinel detach/reattach gate.
  """

  use Mix.Task

  alias Babs.Citizens.Citizen.Config
  alias Babs.Citizens.Hardline.Pane
  alias Babs.Citizens.{Lifecycle, Runner}

  @shortdoc "Run Phase 1 Gate A sentinel reload validation"
  @requirements ["app.start"]
  @timeout_ms 5_000

  @impl true
  def run(_args) do
    config = load_sentinel!()
    session = Runner.session_name(config.slug)

    ensure_started!(config)
    {session_id_before, pane_pid_before} = metadata!(session)

    before_marker = marker("BEFORE_RELOAD")
    after_marker = marker("AFTER_RELOAD")

    inject_marker!(config.slug, before_marker)
    wait_for_capture!(session, before_marker)

    restart_citizens_app!()
    wait_for_pane!(config.slug)

    {session_id_after, pane_pid_after} = metadata!(session)

    if session_id_after != session_id_before do
      Mix.raise(
        "Gate A failed: tmux session id changed from #{session_id_before} to #{session_id_after}"
      )
    end

    if pane_pid_after != pane_pid_before do
      Mix.raise(
        "Gate A failed: tmux pane pid changed from #{pane_pid_before} to #{pane_pid_after}"
      )
    end

    inject_marker!(config.slug, after_marker)
    wait_for_capture!(session, before_marker)
    wait_for_capture!(session, after_marker)

    Mix.shell().info("Gate A PASS: sentinel survived :babs_citizens restart")

    Mix.shell().info(
      "session=#{session} session_id=#{session_id_after} pane_pid=#{pane_pid_after}"
    )
  end

  defp load_sentinel! do
    case Config.load_slug("sentinel", root: File.cwd!()) do
      {:ok, config} -> config
      {:error, reason} -> Mix.raise("Gate A failed to load sentinel config: #{inspect(reason)}")
    end
  end

  defp ensure_started!(config) do
    case Lifecycle.lookup(config.slug) do
      {:ok, _pid} ->
        :ok

      {:error, :not_found} ->
        case Lifecycle.start_config(config) do
          {:ok, _pid} -> :ok
          {:error, reason} -> Mix.raise("Gate A failed to start sentinel: #{inspect(reason)}")
        end
    end
  end

  defp metadata!(session) do
    with {:ok, session_id} <- Runner.tmux_session_id(session),
         {:ok, pane_pid} <- Runner.tmux_pane_pid(session) do
      {session_id, pane_pid}
    else
      {:error, reason} -> Mix.raise("Gate A failed to read tmux metadata: #{inspect(reason)}")
    end
  end

  defp inject_marker!(slug, marker) do
    Pane.inject(slug, "printf '#{marker}\\n'\n")
  end

  defp restart_citizens_app! do
    case Application.stop(:babs_citizens) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("Gate A failed to stop :babs_citizens: #{inspect(reason)}")
    end

    case Application.start(:babs_citizens) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("Gate A failed to restart :babs_citizens: #{inspect(reason)}")
    end
  end

  defp wait_for_pane!(slug) do
    wait_until!("pane #{slug} to reattach", fn ->
      case Lifecycle.lookup(slug) do
        {:ok, _pid} -> true
        {:error, :not_found} -> false
      end
    end)
  end

  defp wait_for_capture!(session, marker) do
    wait_until!("tmux capture to contain #{marker}", fn ->
      case Runner.capture_pane(session) do
        {:ok, capture} -> String.contains?(capture, marker)
        {:error, _reason} -> false
      end
    end)
  end

  defp wait_until!(label, fun) do
    deadline = System.monotonic_time(:millisecond) + @timeout_ms
    do_wait_until!(label, fun, deadline)
  end

  defp do_wait_until!(label, fun, deadline) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        Mix.raise("Gate A timed out waiting for #{label}")

      true ->
        Process.sleep(100)
        do_wait_until!(label, fun, deadline)
    end
  end

  defp marker(prefix) do
    "#{prefix}_#{System.system_time(:millisecond)}_#{System.unique_integer([:positive])}"
  end
end
