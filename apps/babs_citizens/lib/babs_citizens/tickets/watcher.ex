defmodule Babs.Citizens.Tickets.Watcher do
  @moduledoc """
  Filesystem watcher for the configured Ticket root.

  Ticket files are human-editable runtime data. The watcher broadcasts a small
  internal refresh signal; readers re-read the files instead of trusting event
  payload state.
  """

  use GenServer

  require Logger

  alias Babs.Citizens.Tickets.Config

  @topic "tickets"
  @default_debounce_ms 250
  @default_retry_ms 1_000

  def topic, do: @topic

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @impl true
  def init(opts) do
    config = Application.get_env(:babs_citizens, __MODULE__, [])
    enabled? = Keyword.get(opts, :enabled?, Keyword.get(config, :enabled?, true))

    state = %{
      enabled?: enabled?,
      root: Keyword.get(opts, :tickets_root) || Config.tickets_root(opts),
      debounce_ms:
        Keyword.get(opts, :debounce_ms, Keyword.get(config, :debounce_ms, @default_debounce_ms)),
      retry_ms: Keyword.get(opts, :retry_ms, Keyword.get(config, :retry_ms, @default_retry_ms)),
      watcher: nil,
      debounce_ref: nil,
      changed_paths: MapSet.new(),
      retry_ref: nil
    }

    if enabled? do
      start_watcher(state)
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_info(:retry_watcher, state) do
    {:ok, state} = start_watcher(%{state | retry_ref: nil})
    {:noreply, state}
  end

  def handle_info({:file_event, watcher, {path, events}}, %{watcher: watcher} = state) do
    if watched_ticket_file?(path, events, state.root) do
      {:noreply, debounce_broadcast(state, changed_paths(path, state.root))}
    else
      {:noreply, state}
    end
  end

  def handle_info({:file_event, watcher, :stop}, %{watcher: watcher} = state) do
    {:noreply, schedule_retry(%{state | watcher: nil})}
  end

  def handle_info(:broadcast_after_debounce, state) do
    payload = %{root: state.root, paths: state.changed_paths |> MapSet.to_list() |> Enum.sort()}

    Phoenix.PubSub.broadcast(Babs.Citizens.PubSub, @topic, {:tickets_changed, payload})

    {:noreply, %{state | debounce_ref: nil, changed_paths: MapSet.new()}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  def watched_ticket_file?(path, events, root) when is_binary(path) and is_list(events) do
    expanded = normalized_path(path)
    expanded_root = normalized_path(root)

    String.starts_with?(expanded, expanded_root) and
      (expanded == expanded_root or ticket_file?(path)) and
      Enum.any?(events, &(&1 in [:created, :modified, :renamed, :deleted, :removed]))
  end

  def watched_ticket_file?(_path, _events, _root), do: false

  defp normalized_path(path) do
    # macOS reports /tmp events through /private/var while tests and callers
    # often use /var. Normalize the stable public prefix for equality checks.
    path
    |> Path.expand()
    |> String.replace_prefix("/private/var/", "/var/")
  end

  defp ticket_file?(path) do
    basename = Path.basename(path)

    String.starts_with?(basename, "T-") and
      (String.ends_with?(basename, ".md") or String.ends_with?(basename, ".history.jsonl"))
  end

  defp start_watcher(%{root: root} = state) do
    cond do
      not state.enabled? ->
        {:ok, state}

      File.dir?(root) ->
        case FileSystem.start_link(dirs: [root]) do
          {:ok, watcher} ->
            :ok = FileSystem.subscribe(watcher)
            Logger.info("Babs Ticket watcher watching #{root}")
            {:ok, %{state | watcher: watcher}}

          {:error, reason} ->
            Logger.warning("Babs Ticket watcher retrying after start failure: #{inspect(reason)}")
            {:ok, schedule_retry(state)}
        end

      true ->
        {:ok, schedule_retry(state)}
    end
  end

  defp schedule_retry(%{retry_ref: nil} = state) do
    %{state | retry_ref: Process.send_after(self(), :retry_watcher, state.retry_ms)}
  end

  defp schedule_retry(state), do: state

  defp changed_paths(path, root) do
    if ticket_file?(path) do
      [normalized_path(path)]
    else
      root
      |> Path.join("T-*")
      |> Path.wildcard()
      |> Enum.filter(&ticket_file?/1)
      |> Enum.map(&normalized_path/1)
    end
  end

  defp debounce_broadcast(state, paths) do
    if state.debounce_ref, do: Process.cancel_timer(state.debounce_ref)

    %{
      state
      | debounce_ref: Process.send_after(self(), :broadcast_after_debounce, state.debounce_ms),
        changed_paths: Enum.reduce(paths, state.changed_paths, &MapSet.put(&2, &1))
    }
  end
end
