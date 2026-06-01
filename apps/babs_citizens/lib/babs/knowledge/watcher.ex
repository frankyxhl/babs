defmodule Babs.Knowledge.Watcher do
  @moduledoc """
  Filesystem watcher for Citizen Knowledge markdown files.

  Broadcasts logical Citizen/file identifiers instead of filesystem paths so UI
  callers can refresh from `Babs.Knowledge` without receiving host-local paths.
  """

  use GenServer

  require Logger

  alias Babs.Citizens.Citizen.Config, as: CitizenConfig
  alias Babs.Citizens.Knowledge.Config, as: KnowledgeConfig

  @topic "knowledge"
  @default_debounce_ms 250
  @default_retry_ms 1_000
  @event_types [:created, :modified, :renamed, :deleted, :removed, :moved_to, :moved_from]

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
      root: Keyword.get(opts, :knowledge_root) || KnowledgeConfig.knowledge_root(opts),
      debounce_ms:
        Keyword.get(opts, :debounce_ms, Keyword.get(config, :debounce_ms, @default_debounce_ms)),
      retry_ms: Keyword.get(opts, :retry_ms, Keyword.get(config, :retry_ms, @default_retry_ms)),
      watcher: nil,
      debounce_ref: nil,
      changed_entries: MapSet.new(),
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
    case changed_entry(path, events, state.root) do
      {:ok, entry} -> {:noreply, debounce_broadcast(state, [entry])}
      :ignore -> {:noreply, state}
    end
  end

  def handle_info({:file_event, watcher, :stop}, %{watcher: watcher} = state) do
    {:noreply, schedule_retry(%{state | watcher: nil})}
  end

  def handle_info(:broadcast_after_debounce, state) do
    state.changed_entries
    |> Enum.to_list()
    |> Enum.sort()
    |> Enum.each(fn {slug, name} ->
      Phoenix.PubSub.broadcast(Babs.Citizens.PubSub, @topic, {:knowledge_changed, slug, name})
    end)

    {:noreply, %{state | debounce_ref: nil, changed_entries: MapSet.new()}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp changed_entry(path, events, root) when is_binary(path) and is_list(events) do
    normalized = normalized_path(path)
    normalized_root = normalized_path(root)

    with true <- relevant_event?(events),
         true <- inside_or_same?(normalized, normalized_root),
         relative when relative != "." <- Path.relative_to(normalized, normalized_root),
         [slug | name_segments] when name_segments != [] <- Path.split(relative),
         true <- CitizenConfig.valid_slug?(slug),
         name <- Path.join(name_segments),
         true <- visible_markdown_name?(name_segments, name) do
      {:ok, {slug, name}}
    else
      _other -> :ignore
    end
  end

  defp changed_entry(_path, _events, _root), do: :ignore

  defp relevant_event?(events), do: Enum.any?(events, &(&1 in @event_types))

  defp visible_markdown_name?(segments, name) do
    String.ends_with?(name, ".md") and not Enum.any?(segments, &artifact_segment?/1)
  end

  defp artifact_segment?(segment) do
    String.starts_with?(segment, ".") or String.starts_with?(segment, "~") or
      String.starts_with?(segment, "#") or String.ends_with?(segment, ".tmp") or
      String.ends_with?(segment, "~") or String.ends_with?(segment, "#")
  end

  defp normalized_path(path) do
    path
    |> Path.expand()
    |> String.replace_prefix("/private/var/", "/var/")
  end

  defp inside_or_same?(path, root) do
    path == root or String.starts_with?(path, child_path_prefix(root))
  end

  defp child_path_prefix("/"), do: "/"
  defp child_path_prefix(root), do: root <> "/"

  defp start_watcher(%{root: root} = state) do
    cond do
      not state.enabled? ->
        {:ok, state}

      File.dir?(root) ->
        case FileSystem.start_link(dirs: [root]) do
          {:ok, watcher} ->
            :ok = FileSystem.subscribe(watcher)
            Logger.info("Babs Knowledge watcher active")
            {:ok, %{state | watcher: watcher}}

          {:error, _reason} ->
            Logger.warning("Babs Knowledge watcher retrying after start failure")
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

  defp debounce_broadcast(state, entries) do
    if state.debounce_ref, do: Process.cancel_timer(state.debounce_ref)

    %{
      state
      | debounce_ref: Process.send_after(self(), :broadcast_after_debounce, state.debounce_ms),
        changed_entries: Enum.reduce(entries, state.changed_entries, &MapSet.put(&2, &1))
    }
  end
end
