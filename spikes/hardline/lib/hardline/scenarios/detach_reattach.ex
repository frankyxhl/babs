defmodule Hardline.Scenarios.DetachReattach do
  @moduledoc """
  Validation helpers for the tmux detach and erlexec reattach scenario.
  """

  alias Hardline.{Observer, Runner}

  def run(opts) do
    session = Keyword.fetch!(opts, :session)
    seconds = Keyword.get(opts, :seconds, 30)
    log_path = Keyword.fetch!(opts, :log_path)
    command = Keyword.get(opts, :command, Runner.default_shell_command())

    try do
      with :ok <- Runner.start_session(session, command),
           {:ok, first_attach} <- Runner.attach(session),
           {:ok, before_snapshot} <- snapshot(session, first_attach, 1, log_path),
           :ok <- Runner.detach(first_attach),
           true <- Runner.tmux_session_alive?(session),
           :ok <- Runner.send_keys(session, "printf 'BABS_DETACH_SEQ:2\\n'"),
           :ok <- sleep_gap(seconds),
           {:ok, second_attach} <- Runner.attach(session),
           {:ok, after_snapshot} <- snapshot(session, second_attach, 2, log_path),
           :ok <- Runner.detach(second_attach),
           :ok <- validate_snapshots(before_snapshot, after_snapshot) do
        Observer.append_event(log_path, :detach_reattach_pass, %{
          session: session,
          session_id: after_snapshot.session_id,
          workload_pid: after_snapshot.workload_pid
        })

        :ok
      else
        false -> {:error, {:tmux_session_died, session}}
        {:error, reason} -> {:error, reason}
      end
    after
      Runner.stop_fleet([%{session: session}])
    end
  end

  def validate_snapshots(before_snapshot, after_snapshot)
      when is_map(before_snapshot) and is_map(after_snapshot) do
    cond do
      before_snapshot.session_id != after_snapshot.session_id ->
        {:error, :session_changed}

      before_snapshot.workload_pid != after_snapshot.workload_pid ->
        {:error, :workload_pid_changed}

      after_snapshot.sequence != before_snapshot.sequence + 1 ->
        {:error, :sequence_gap}

      true ->
        :ok
    end
  end

  defp snapshot(session, attach, sequence, log_path) do
    sentinel = "BABS_DETACH_SEQ:#{sequence}"

    with :ok <- maybe_inject_sequence(session, attach, sequence),
         {:ok, _output} <- Runner.collect_until(attach, sentinel, 5_000),
         {:ok, session_id} <- Runner.tmux_session_id(session),
         {:ok, workload_pid} <- Runner.tmux_pane_pid(session) do
      Observer.append_event(log_path, :detach_snapshot, %{
        session: session,
        session_id: session_id,
        workload_pid: workload_pid,
        sequence: sequence
      })

      {:ok, %{session_id: session_id, workload_pid: workload_pid, sequence: sequence}}
    end
  end

  defp maybe_inject_sequence(_session, _attach, 2), do: :ok

  defp maybe_inject_sequence(_session, attach, sequence) do
    Runner.inject(attach, "printf 'BABS_DETACH_SEQ:'; printf '#{sequence}\\n'\n")
  end

  defp sleep_gap(seconds) do
    Process.sleep(max(seconds, 0) * 1_000)
    :ok
  end
end
