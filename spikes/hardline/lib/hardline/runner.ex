defmodule Hardline.Runner do
  @moduledoc """
  Builds tmux command shapes used by the Phase 0 harness.
  """

  @default_prefix "babs-test"
  @default_shell_command "/bin/zsh -f"
  @managed_prefix "babs-hardline"

  def default_shell_command, do: @default_shell_command
  def managed_prefix, do: @managed_prefix

  def session_name(index, opts \\ [])

  def session_name(index, opts) when is_integer(index) and index > 0 do
    prefix = Keyword.get(opts, :prefix, @default_prefix)
    "#{prefix}-#{index}"
  end

  def session_name(_index, _opts) do
    raise ArgumentError, "session index must be a positive integer"
  end

  def fleet_specs(count, opts \\ [])

  def fleet_specs(count, opts) when is_integer(count) and count > 0 do
    command = Keyword.get(opts, :command, default_shell_command())
    prefix = Keyword.get(opts, :prefix, @default_prefix)

    for index <- 1..count do
      %{index: index, session: session_name(index, prefix: prefix), command: command}
    end
  end

  def fleet_specs(_count, _opts) do
    raise ArgumentError, "fleet count must be a positive integer"
  end

  def new_session_args(session, command) when is_binary(session) and is_binary(command) do
    ["new-session", "-d", "-s", session, command]
  end

  def attach_command(session) when is_binary(session) do
    String.to_charlist("tmux attach-session -t #{session}")
  end

  def send_keys(session, payload) when is_binary(session) and is_binary(payload) do
    with {_output, 0} <-
           System.cmd("tmux", ["send-keys", "-t", session, "-l", payload], stderr_to_stdout: true),
         {_output, 0} <-
           System.cmd("tmux", ["send-keys", "-t", session, "Enter"], stderr_to_stdout: true) do
      :ok
    else
      {output, status} -> {:error, {:tmux_send_keys_failed, status, output}}
    end
  end

  def start_session(session, command) when is_binary(session) and is_binary(command) do
    case System.cmd("tmux", new_session_args(session, command), stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {:tmux_new_session_failed, status, output}}
    end
  end

  def managed_session?(session, prefix \\ @managed_prefix)
      when is_binary(session) and is_binary(prefix) do
    String.starts_with?(session, "#{prefix}-")
  end

  def managed_session_name(slug, prefix \\ @managed_prefix)
      when is_binary(slug) and is_binary(prefix) do
    "#{prefix}-#{slug}"
  end

  def list_sessions(prefix \\ @managed_prefix) when is_binary(prefix) do
    case System.cmd("tmux", ["list-sessions", "-F", "\#{session_name}"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.filter(&managed_session?(&1, prefix))

      {output, _status} ->
        if String.contains?(output, "no server running") do
          []
        else
          []
        end
    end
  end

  def kill_session(session) when is_binary(session) do
    case System.cmd("tmux", ["kill-session", "-t", session], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {:tmux_kill_session_failed, status, output}}
    end
  end

  def kill_managed_session(session, prefix \\ @managed_prefix)
      when is_binary(session) and is_binary(prefix) do
    if managed_session?(session, prefix) do
      kill_session(session)
    else
      {:error, :unmanaged_session}
    end
  end

  def start_fleet(count, opts \\ []) do
    specs = fleet_specs(count, opts)

    case Enum.reduce_while(specs, [], &start_fleet_member/2) do
      {:error, reason, started} ->
        stop_fleet(started)
        {:error, reason}

      started ->
        {:ok, Enum.reverse(started)}
    end
  end

  def attach_fleet(fleet) when is_list(fleet) do
    case Enum.reduce_while(fleet, [], &attach_fleet_member/2) do
      {:error, reason, attached} ->
        detach_fleet(attached)
        {:error, reason}

      attached ->
        {:ok, Enum.reverse(attached)}
    end
  end

  def detach_fleet(attachments) when is_list(attachments) do
    Enum.each(attachments, &detach/1)
    :ok
  end

  def stop_fleet(fleet) when is_list(fleet) do
    Enum.each(fleet, fn %{session: session} ->
      System.cmd("tmux", ["kill-session", "-t", session], stderr_to_stdout: true)
    end)

    :ok
  end

  def tmux_session_alive?(session) when is_binary(session) do
    case System.cmd("tmux", ["has-session", "-t", session], stderr_to_stdout: true) do
      {_output, 0} -> true
      {_output, _status} -> false
    end
  end

  def tmux_session_id(session) when is_binary(session) do
    tmux_format(session, "\#{session_id}")
  end

  def tmux_pane_pid(session) when is_binary(session) do
    with {:ok, value} <- tmux_format(session, "\#{pane_pid}"),
         {pid, ""} <- Integer.parse(value) do
      {:ok, pid}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_pane_pid}
    end
  end

  def tmux_session_metadata(session) when is_binary(session) do
    format =
      "\#{session_name}\t\#{session_id}\t\#{pane_pid}\t\#{pane_current_command}\t\#{pane_current_path}"

    with {:ok, value} <- tmux_format(session, format),
         [session_name, session_id, pane_pid, pane_command, pane_path] <-
           String.split(value, "\t"),
         {pane_pid, ""} <- Integer.parse(pane_pid) do
      {:ok,
       %{
         session: session_name,
         session_id: session_id,
         pane_pid: pane_pid,
         pane_command: pane_command,
         pane_path: pane_path
       }}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_tmux_metadata}
    end
  end

  def capture_pane(session, lines \\ 200)
      when is_binary(session) and is_integer(lines) and lines > 0 do
    start = "-#{lines}"

    case System.cmd("tmux", ["capture-pane", "-p", "-e", "-t", session, "-S", start],
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, output}
      {output, status} -> {:error, {:tmux_capture_pane_failed, status, output}}
    end
  end

  def attach(session, opts \\ []) when is_binary(session) do
    rows = Keyword.get(opts, :rows, 32)
    cols = Keyword.get(opts, :cols, 100)

    with {:ok, _apps} <- Application.ensure_all_started(:erlexec),
         {:ok, pid, os_pid} <-
           :exec.run(attach_command(session), [
             :stdin,
             :stdout,
             {:stderr, :stdout},
             {:pty, [{:echo, 0}]},
             {:winsz, {rows, cols}},
             :monitor,
             {:env, [{"TERM", "xterm-256color"}]}
           ]) do
      {:ok, %{pid: pid, os_pid: os_pid, session: session}}
    end
  end

  def inject(%{os_pid: os_pid}, data) when is_binary(data) do
    :exec.send(os_pid, data)
  end

  def resize(%{os_pid: os_pid}, rows, cols)
      when is_integer(rows) and rows > 0 and is_integer(cols) and cols > 0 do
    :exec.winsz(os_pid, rows, cols)
  end

  def resize(_attach, _rows, _cols) do
    raise ArgumentError, "terminal resize requires positive integer rows and cols"
  end

  def collect_until(%{os_pid: os_pid}, pattern, timeout_ms)
      when is_binary(pattern) and is_integer(timeout_ms) and timeout_ms > 0 do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_collect_until(os_pid, pattern, "", deadline, [])
  end

  def detach(%{os_pid: os_pid}) do
    :exec.stop(os_pid)
  end

  defp start_fleet_member(%{session: session, command: command} = spec, started) do
    case start_session(session, command) do
      :ok -> {:cont, [spec | started]}
      {:error, reason} -> {:halt, {:error, reason, started}}
    end
  end

  defp attach_fleet_member(%{session: session}, attached) do
    case attach(session) do
      {:ok, attach} -> {:cont, [attach | attached]}
      {:error, reason} -> {:halt, {:error, reason, attached}}
    end
  end

  defp tmux_format(session, format) do
    case System.cmd("tmux", ["display-message", "-p", "-t", session, format],
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, status} -> {:error, {:tmux_format_failed, status, output}}
    end
  end

  defp do_collect_until(os_pid, pattern, acc, deadline, stashed) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      restore_messages(stashed)
      {:error, {:timeout, acc}}
    else
      receive do
        {:stdout, ^os_pid, data} ->
          next = acc <> data

          if String.contains?(next, pattern) do
            restore_messages(stashed)
            {:ok, next}
          else
            do_collect_until(os_pid, pattern, next, deadline, stashed)
          end

        message ->
          do_collect_until(os_pid, pattern, acc, deadline, [message | stashed])
      after
        deadline - now ->
          restore_messages(stashed)
          {:error, {:timeout, acc}}
      end
    end
  end

  defp restore_messages(stashed) do
    stashed
    |> Enum.reverse()
    |> Enum.each(&send(self(), &1))
  end
end
