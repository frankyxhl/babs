defmodule Babs.Citizens.Runner do
  @moduledoc """
  tmux + erlexec primitives for Babs-owned Citizen sessions.
  """

  @session_prefix "babs"

  def session_name(slug) when is_binary(slug), do: "#{@session_prefix}-#{slug}"

  def managed_session?(session) when is_binary(session) do
    String.starts_with?(session, "#{@session_prefix}-")
  end

  def slug_from_session(<<@session_prefix, "-", slug::binary>>), do: {:ok, slug}
  def slug_from_session(_session), do: :error

  def new_session_args(config) do
    env_args =
      config.env
      |> Enum.sort()
      |> Enum.flat_map(fn {key, value} -> ["-e", "#{key}=#{value}"] end)

    ["new-session", "-d", "-s", session_name(config.slug), "-c", config.cwd] ++
      env_args ++ [config.cli | config.cli_args]
  end

  def start_session(config) do
    case System.cmd("tmux", new_session_args(config), stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {:tmux_new_session_failed, status, output}}
    end
  end

  def list_sessions do
    case System.cmd("tmux", ["list-sessions", "-F", "\#{session_name}"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.filter(&managed_session?/1)

      {output, _status} ->
        if String.contains?(output, "no server running"), do: [], else: []
    end
  end

  def tmux_session_alive?(session) when is_binary(session) do
    case System.cmd("tmux", ["has-session", "-t", session], stderr_to_stdout: true) do
      {_output, 0} -> true
      {_output, _status} -> false
    end
  end

  def kill_session(session) when is_binary(session) do
    if managed_session?(session) do
      case System.cmd("tmux", ["kill-session", "-t", session], stderr_to_stdout: true) do
        {_output, 0} -> :ok
        {output, status} -> {:error, {:tmux_kill_session_failed, status, output}}
      end
    else
      {:error, :unmanaged_session}
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

  def detach(%{os_pid: os_pid}) do
    :exec.stop(os_pid)
  end

  def attach_command(session), do: String.to_charlist("tmux attach-session -t #{session}")

  def tmux_session_id(session), do: tmux_format(session, "\#{session_id}")

  def tmux_pane_pid(session) do
    with {:ok, value} <- tmux_format(session, "\#{pane_pid}"),
         {pid, ""} <- Integer.parse(value) do
      {:ok, pid}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_pane_pid}
    end
  end

  def capture_pane(session, lines \\ 200)
      when is_binary(session) and is_integer(lines) and lines > 0 do
    case System.cmd("tmux", ["capture-pane", "-p", "-e", "-t", session, "-S", "-#{lines}"],
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, output}
      {output, status} -> {:error, {:tmux_capture_pane_failed, status, output}}
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
end
