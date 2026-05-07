defmodule Babs.Citizens.Runner do
  @moduledoc """
  tmux + erlexec primitives for Babs-owned Citizen sessions.
  """

  alias Babs.Citizens.CopilotSettings

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
      env_args ++ [config.cli | effective_cli_args(config)]
  end

  def effective_cli_args(config) do
    cli_args = Map.get(config, :cli_args, []) || []

    case Map.get(config, :launch_profile, "safe_interactive") do
      "trusted_autonomous" -> trusted_autonomous_args(config, cli_args)
      _profile -> cli_args
    end
  end

  def start_session(config) do
    with :ok <- prepare_launch(config),
         {:ok, result} <- tmux_cmd(new_session_args(config)) do
      case result do
        {_output, 0} -> :ok
        {output, status} -> {:error, {:tmux_new_session_failed, status, output}}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def prepare_launch(config) do
    if trusted_autonomous?(config) and copilot_cli?(config) do
      CopilotSettings.trust_folder(config.cwd, home: copilot_home(config))
    else
      :ok
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
    attach_session = Keyword.get(opts, :attach_session, session)

    with {:ok, _apps} <- Application.ensure_all_started(:erlexec),
         {:ok, pid, os_pid} <-
           :exec.run(attach_command(session, attach_session), [
             :stdin,
             :stdout,
             {:stderr, :stdout},
             {:pty, [{:echo, 0}]},
             {:winsz, {rows, cols}},
             {:group, 0},
             :kill_group,
             :monitor,
             {:env, [{"TERM", "xterm-256color"}]}
           ]) do
      {:ok, %{pid: pid, os_pid: os_pid, session: session, attach_session: attach_session}}
    end
  end

  def inject(%{os_pid: os_pid}, data) when is_binary(data) do
    :exec.send(os_pid, data)
  end

  def paste_text(%{session: session}, data) when is_binary(data), do: paste_text(session, data)

  def paste_text(session, data) when is_binary(session) and is_binary(data) do
    buffer = "babs-#{System.unique_integer([:positive, :monotonic])}"

    with :ok <- tmux_ok(["set-buffer", "-b", buffer, data]),
         :ok <- tmux_ok(["paste-buffer", "-d", "-b", buffer, "-t", session]) do
      :ok
    end
  end

  def send_enter(%{session: session}), do: send_enter(session)

  def send_enter(session) when is_binary(session) do
    tmux_ok(["send-keys", "-t", session, "Enter"])
  end

  def ai_cli?(%{cli: cli, cli_args: cli_args}) when is_binary(cli) and is_list(cli_args) do
    cli_name = cli |> Path.basename() |> String.downcase()

    case {cli_name, cli_args} do
      {"claude", _args} -> true
      {"codex", _args} -> true
      {"gh", ["copilot" | _rest]} -> true
      {"copilot", _args} -> true
      _other -> false
    end
  end

  def ai_cli?(_config), do: false

  defp trusted_autonomous?(config) do
    Map.get(config, :launch_profile, "safe_interactive") == "trusted_autonomous"
  end

  defp copilot_cli?(%{cli: cli} = config) when is_binary(cli) do
    cli_name = cli |> Path.basename() |> String.downcase()
    cli_args = Map.get(config, :cli_args, []) || []

    case {cli_name, cli_args} do
      {"copilot", _args} -> true
      {"gh", ["copilot" | _rest]} -> true
      _other -> false
    end
  end

  defp copilot_cli?(_config), do: false

  defp copilot_home(config) do
    env = Map.get(config, :env, %{}) || %{}

    Map.get(env, "COPILOT_HOME") ||
      System.get_env("COPILOT_HOME") ||
      Path.join(System.user_home!(), ".copilot")
  end

  defp trusted_autonomous_args(%{cli: cli}, cli_args) when is_binary(cli) do
    cli_name = cli |> Path.basename() |> String.downcase()

    case {cli_name, cli_args} do
      {"claude", args} ->
        ensure_default_options(args, [
          {["--permission-mode", "--dangerously-skip-permissions"],
           ["--permission-mode", "dontAsk"]}
        ])

      {"codex", args} ->
        ensure_default_options(args, [
          {["--ask-for-approval", "-a"], ["--ask-for-approval", "never"]},
          {["--sandbox", "-s", "--dangerously-bypass-approvals-and-sandbox"],
           ["--sandbox", "danger-full-access"]}
        ])

      {"copilot", args} ->
        copilot_autonomous_args(args)

      {"gh", ["copilot" | rest]} ->
        ["copilot", "--"] ++ copilot_autonomous_args(strip_gh_separator(rest))

      _other ->
        cli_args
    end
  end

  defp trusted_autonomous_args(_config, cli_args), do: cli_args

  defp copilot_autonomous_args(args) do
    ensure_default_options(args, [
      {["--allow-all", "--yolo"], ["--allow-all"]},
      {["--no-ask-user"], ["--no-ask-user"]}
    ])
  end

  defp strip_gh_separator(["--" | rest]), do: rest
  defp strip_gh_separator(rest), do: rest

  defp ensure_default_options(args, defaults) do
    defaults
    |> Enum.flat_map(fn {flags, default_args} ->
      if option_present?(args, flags), do: [], else: default_args
    end)
    |> Kernel.++(args)
  end

  defp option_present?(args, flags) do
    Enum.any?(args, fn arg ->
      Enum.any?(flags, &(arg == &1 or String.starts_with?(arg, &1 <> "=")))
    end)
  end

  def resize(%{os_pid: os_pid}, rows, cols)
      when is_integer(rows) and rows > 0 and is_integer(cols) and cols > 0 do
    :exec.winsz(os_pid, rows, cols)
  end

  def detach(%{pid: pid, os_pid: os_pid}) when is_pid(pid) do
    _ignored = detach_tmux_client(os_pid)

    case stop_managed_process(pid) do
      :ok -> :ok
      {:error, :not_found} -> stop_os_process(os_pid)
      {:error, {:not_found, _pid}} -> stop_os_process(os_pid)
      {:error, _reason} = error -> error
    end
  end

  def detach(%{os_pid: os_pid}), do: stop_os_process(os_pid)

  defp detach_tmux_client(os_pid) when is_integer(os_pid) do
    case tmux_cmd(["detach-client", "-t", to_string(os_pid)]) do
      {:ok, {_output, 0}} -> :ok
      _other -> :ok
    end
  end

  defp stop_managed_process(pid) do
    case :exec.stop_and_wait(pid, 10_000) do
      {:error, _reason} = error -> error
      _exit_status -> :ok
    end
  end

  defp stop_os_process(os_pid) do
    case :exec.stop_and_wait(os_pid, 10_000) do
      {:error, :not_found} -> :ok
      {:error, {:not_found, _pid}} -> :ok
      {:error, _reason} = error -> error
      _exit_status -> :ok
    end
  end

  def attach_command(target, attach_session \\ nil) do
    quoted = shell_quote(target)
    quoted_session = shell_quote(attach_session || target)
    String.to_charlist("tmux select-pane -t #{quoted} \\; attach-session -t #{quoted_session}")
  end

  def tmux_session_id(session), do: tmux_format(session, "\#{session_id}")

  def tmux_pane_pid(session) do
    with {:ok, value} <- tmux_format(session, "\#{pane_pid}"),
         {pid, ""} <- Integer.parse(value) do
      {:ok, pid}
    else
      {:error, {:tmux_format_failed, _status, output}} = error when is_binary(output) ->
        if tmux_missing_target_output?(output) do
          {:error, :invalid_pane_pid}
        else
          error
        end

      {:error, _reason} = error ->
        error

      _ ->
        {:error, :invalid_pane_pid}
    end
  end

  def capture_pane(%{session: session}), do: capture_pane(session)

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

  defp tmux_missing_target_output?(output) do
    output = String.downcase(output)

    String.contains?(output, [
      "can't find",
      "error connecting",
      "no server running"
    ])
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

  defp tmux_ok(args) do
    case tmux_cmd(args) do
      {:ok, {_output, 0}} -> :ok
      {:ok, {output, status}} -> {:error, {:tmux_command_failed, status, output}}
      {:error, reason} -> {:error, reason}
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

  defp shell_quote(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\\''") <> "'"
  end
end
