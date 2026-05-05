defmodule Babs.Citizens.GateA.Validator do
  @moduledoc """
  Testable implementation of the Phase 1 Gate A sentinel reload validation.
  """

  alias Babs.Citizens.Citizen.Config
  alias Babs.Citizens.Hardline.Pane
  alias Babs.Citizens.{Lifecycle, Runner}

  @timeout_ms 5_000

  def run(opts \\ []) do
    root = Keyword.get(opts, :root, File.cwd!())

    with {:ok, config} <- load_sentinel(root),
         session <- Runner.session_name(config.slug),
         :ok <- ensure_started(config),
         {:ok, metadata_before} <- metadata(session),
         before_marker <- marker("BEFORE_RELOAD"),
         after_marker <- marker("AFTER_RELOAD"),
         :ok <- inject_marker(config.slug, before_marker),
         :ok <- wait_for_capture(session, before_marker),
         :ok <- restart_citizens_app(),
         :ok <- ensure_started(config),
         :ok <- wait_for_pane(config.slug),
         {:ok, metadata_after} <- metadata(session),
         :ok <- verify_stable_metadata(metadata_before, metadata_after),
         :ok <- inject_marker(config.slug, after_marker),
         :ok <- wait_for_capture(session, before_marker),
         :ok <- wait_for_capture(session, after_marker) do
      {session_id, pane_pid} = metadata_after
      {:ok, %{session: session, session_id: session_id, pane_pid: pane_pid}}
    end
  end

  def verify_stable_metadata({session_id, pane_pid}, {session_id, pane_pid}), do: :ok

  def verify_stable_metadata(
        {session_id_before, _pane_pid_before},
        {session_id_after, _pane_pid_after}
      )
      when session_id_before != session_id_after do
    {:error, {:session_id_changed, session_id_before, session_id_after}}
  end

  def verify_stable_metadata(
        {_session_id_before, pane_pid_before},
        {_session_id_after, pane_pid_after}
      ) do
    {:error, {:pane_pid_changed, pane_pid_before, pane_pid_after}}
  end

  def capture_contains?(capture, marker) when is_binary(capture) and is_binary(marker) do
    String.contains?(capture, marker)
  end

  def marker(prefix) do
    "#{prefix}_#{System.system_time(:millisecond)}_#{System.unique_integer([:positive])}"
  end

  defp load_sentinel(root) do
    case Config.load_slug("sentinel", root: root) do
      {:ok, config} -> {:ok, config}
      {:error, reason} -> {:error, {:load_sentinel_failed, reason}}
    end
  end

  defp ensure_started(config) do
    case Lifecycle.lookup(config.slug) do
      {:ok, _pid} ->
        :ok

      {:error, :not_found} ->
        case Lifecycle.start_config(config) do
          {:ok, _pid} -> :ok
          {:error, reason} -> {:error, {:start_sentinel_failed, reason}}
        end
    end
  end

  defp metadata(session) do
    with {:ok, session_id} <- Runner.tmux_session_id(session),
         {:ok, pane_pid} <- Runner.tmux_pane_pid(session) do
      {:ok, {session_id, pane_pid}}
    else
      {:error, reason} -> {:error, {:metadata_failed, reason}}
    end
  end

  defp inject_marker(slug, marker) do
    Pane.inject(slug, "printf '#{marker}\\n'\n")
    :ok
  end

  defp restart_citizens_app do
    with :ok <- stop_citizens_app(),
         :ok <- Application.start(:babs_citizens) do
      :ok
    else
      {:error, reason} -> {:error, {:restart_citizens_failed, reason}}
    end
  end

  defp stop_citizens_app do
    case Application.stop(:babs_citizens) do
      :ok -> :ok
      {:error, {:not_started, :babs_citizens}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp wait_for_pane(slug) do
    wait_until("pane #{slug} to reattach", fn ->
      case Lifecycle.lookup(slug) do
        {:ok, _pid} -> true
        {:error, :not_found} -> false
      end
    end)
  end

  defp wait_for_capture(session, marker) do
    wait_until("tmux capture to contain #{marker}", fn ->
      case Runner.capture_pane(session) do
        {:ok, capture} -> capture_contains?(capture, marker)
        {:error, _reason} -> false
      end
    end)
  end

  defp wait_until(label, fun) do
    deadline = System.monotonic_time(:millisecond) + @timeout_ms
    do_wait_until(label, fun, deadline)
  end

  defp do_wait_until(label, fun, deadline) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, {:timeout, label}}

      true ->
        Process.sleep(100)
        do_wait_until(label, fun, deadline)
    end
  end
end
