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
    env_args = env_args(config.env || %{}) ++ env_args(babs_env(config))

    ["new-session", "-d", "-s", session_name(config.slug), "-c", config.cwd] ++
      env_args ++ [config.cli | config.cli_args]
  end

  def start_session(config) do
    case tmux_cmd(new_session_args(config)) do
      {:ok, {_output, 0}} -> :ok
      {:ok, {output, status}} -> {:error, {:tmux_new_session_failed, status, output}}
      {:error, reason} -> {:error, reason}
    end
  end

  def list_sessions do
    case list_sessions_result() do
      {:ok, sessions} -> sessions
      {:error, _reason} -> []
    end
  end

  def list_sessions_result do
    case tmux_cmd(["list-sessions", "-F", "\#{session_name}"]) do
      {:ok, {output, 0}} ->
        sessions =
          output
          |> String.split("\n", trim: true)
          |> Enum.filter(&managed_session?/1)

        {:ok, sessions}

      {:ok, {output, status}} ->
        if String.contains?(output, "no server running") do
          {:ok, []}
        else
          {:error, {:tmux_list_sessions_failed, status, output}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def tmux_session_alive?(session) when is_binary(session) do
    case tmux_cmd(["has-session", "-t", session]) do
      {:ok, {_output, 0}} -> true
      {:ok, {_output, _status}} -> false
      {:error, _reason} -> false
    end
  end

  def kill_session(session) when is_binary(session) do
    if managed_session?(session) do
      case tmux_cmd(["kill-session", "-t", session]) do
        {:ok, {_output, 0}} -> :ok
        {:ok, {output, status}} -> {:error, {:tmux_kill_session_failed, status, output}}
        {:error, reason} -> {:error, reason}
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
    case :exec.kill(os_pid, :sigterm) do
      :ok -> :ok
      {:error, :not_found} -> :ok
      {:error, {:not_found, _pid}} -> :ok
      {:error, _reason} = error -> error
    end
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
    case tmux_cmd(["capture-pane", "-p", "-e", "-t", session, "-S", "-#{lines}"]) do
      {:ok, {output, 0}} -> {:ok, output}
      {:ok, {output, status}} -> {:error, {:tmux_capture_pane_failed, status, output}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp tmux_format(session, format) do
    case tmux_cmd(["display-message", "-p", "-t", session, format]) do
      {:ok, {output, 0}} -> {:ok, String.trim(output)}
      {:ok, {output, status}} -> {:error, {:tmux_format_failed, status, output}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp tmux_cmd(args) do
    tmux = tmux_binary()
    {:ok, System.cmd(tmux, args, stderr_to_stdout: true)}
  rescue
    error in ErlangError ->
      if error.original == :enoent do
        {:error, {:tmux_executable_not_found, tmux_binary()}}
      else
        reraise(error, __STACKTRACE__)
      end
  end

  defp tmux_binary do
    :babs_citizens
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:tmux_binary, "tmux")
  end

  defp env_args(env) do
    env
    |> Enum.sort()
    |> Enum.flat_map(fn {key, value} -> ["-e", "#{key}=#{value}"] end)
  end

  defp babs_env(config) do
    root =
      :babs_citizens
      |> Application.get_env(:root, File.cwd!())
      |> Path.expand()

    env = %{
      "BABS_CITIZEN_SLUG" => config.slug,
      "BABS_ROOT" => root,
      "PATH" => babs_path(root, config.env || %{})
    }

    case Application.get_env(:babs_citizens, :tickets_root) do
      value when is_binary(value) and value != "" ->
        Map.put(env, "BABS_TICKETS_ROOT", Path.expand(value, root))

      _value ->
        env
    end
  end

  defp babs_path(root, citizen_env) do
    base = Map.get(citizen_env || %{}, "PATH") || System.get_env("PATH") || ""
    bin = Path.join(root, "bin")

    if base == "", do: bin, else: bin <> ":" <> base
  end
end
