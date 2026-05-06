defmodule Babs.DevReloader do
  @moduledoc """
  Dev-only watcher for the Phase 1 `:babs_citizens` stop/start reloader.

  Keeping this process in `:babs` fixes the supervision boundary: the watcher
  must live outside the application it restarts.
  """

  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    config = Application.get_env(:babs, __MODULE__, [])
    enabled? = Keyword.get(config, :enabled, false)
    root = Keyword.get(config, :root, File.cwd!())
    watch_path = Path.expand(Keyword.get(config, :watch_path, "apps/babs_citizens/lib"), root)
    debounce_ms = Keyword.get(config, :debounce_ms, 300)

    state = %{
      enabled?: enabled?,
      root: root,
      watch_path: watch_path,
      debounce_ms: debounce_ms,
      watcher: nil,
      debounce_ref: nil
    }

    if enabled? do
      start_watcher(state)
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_info({:reload_babs_citizens, reason}, state) do
    Logger.info("Phase 1 DevReloader requested reload: #{inspect(reason)}")
    reload_citizens(state)
    {:noreply, state}
  end

  def handle_info({:file_event, watcher, {path, events}}, %{watcher: watcher} = state) do
    if watched_elixir_file?(path, events, state.watch_path) do
      {:noreply, debounce_reload(state)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:file_event, watcher, :stop}, %{watcher: watcher} = state) do
    {:noreply, %{state | watcher: nil}}
  end

  def handle_info(:reload_after_debounce, state) do
    reload_citizens(state)
    {:noreply, %{state | debounce_ref: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  def watched_elixir_file?(path, events, watch_path) when is_binary(path) and is_list(events) do
    String.starts_with?(Path.expand(path), Path.expand(watch_path)) and
      Path.extname(path) == ".ex" and
      Enum.any?(events, &(&1 in [:created, :modified, :renamed]))
  end

  def watched_elixir_file?(_path, _events, _watch_path), do: false

  defp start_watcher(state) do
    case FileSystem.start_link(dirs: [state.watch_path]) do
      {:ok, watcher} ->
        :ok = FileSystem.subscribe(watcher)
        Logger.info("Babs.DevReloader watching #{state.watch_path}")
        {:ok, %{state | watcher: watcher}}

      {:error, reason} ->
        Logger.warning("Babs.DevReloader disabled: #{inspect(reason)}")
        {:ok, %{state | enabled?: false}}
    end
  end

  defp debounce_reload(%{debounce_ref: nil} = state) do
    ref = Process.send_after(self(), :reload_after_debounce, state.debounce_ms)
    %{state | debounce_ref: ref}
  end

  defp debounce_reload(state) do
    Process.cancel_timer(state.debounce_ref)
    ref = Process.send_after(self(), :reload_after_debounce, state.debounce_ms)
    %{state | debounce_ref: ref}
  end

  defp reload_citizens(state) do
    with :ok <- compile_citizens(state.root),
         :ok <- restart_application(:babs_citizens) do
      Logger.info("Babs.DevReloader restarted :babs_citizens")
    else
      {:error, reason} -> Logger.warning("Babs.DevReloader reload failed: #{inspect(reason)}")
    end
  end

  defp compile_citizens(root) do
    mix = System.find_executable("mix") || "mix"

    case System.cmd(mix, ["do", "--app", "babs_citizens", "compile"],
           cd: root,
           stderr_to_stdout: true,
           env: [{"MIX_ENV", Atom.to_string(Mix.env())}]
         ) do
      {output, 0} ->
        if String.trim(output) != "", do: Logger.debug(output)
        :ok

      {output, status} ->
        {:error, {:compile_failed, status, output}}
    end
  end

  defp restart_application(app) do
    with :ok <- Application.stop(app),
         {:ok, _apps} <- Application.ensure_all_started(app) do
      :ok
    else
      {:error, {:not_started, ^app}} -> ensure_application_started(app)
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_application_started(app) do
    case Application.ensure_all_started(app) do
      {:ok, _apps} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
