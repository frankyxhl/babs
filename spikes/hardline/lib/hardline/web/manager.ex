defmodule Hardline.Web.Manager do
  @moduledoc """
  Browser-facing manager for Phase 0a hardline sessions.

  Only sessions with the configured prefix are listed or stopped. The default
  prefix is `babs-hardline-`, so operator-owned tmux sessions stay out of scope.
  """

  use GenServer

  alias Hardline.{Runner}
  alias Hardline.Web.PaneServer

  @name __MODULE__
  @slug_regex ~r/^[a-z][a-z0-9-]{0,47}$/

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  def list_sessions do
    GenServer.call(@name, :list_sessions)
  end

  def create_session(slug, command \\ Runner.default_shell_command()) do
    GenServer.call(@name, {:create_session, slug, command}, 15_000)
  end

  def stop_session(slug) do
    GenServer.call(@name, {:stop_session, slug}, 15_000)
  end

  def capture_session(slug) do
    GenServer.call(@name, {:capture_session, slug})
  end

  def session_name(slug, prefix \\ Runner.managed_prefix()) do
    Runner.managed_session_name(slug, prefix)
  end

  def valid_slug?(slug) when is_binary(slug), do: Regex.match?(@slug_regex, slug)
  def valid_slug?(_slug), do: false

  @impl true
  def init(opts) do
    state = %{
      prefix: Keyword.get(opts, :prefix, Runner.managed_prefix()),
      default_command: Keyword.get(opts, :command, Runner.default_shell_command()),
      sessions: %{}
    }

    {:ok, sync_existing(state)}
  end

  @impl true
  def handle_call(:list_sessions, _from, state) do
    state = sync_existing(state)
    {:reply, {:ok, session_entries(state)}, state}
  end

  def handle_call({:create_session, slug, command}, _from, state) do
    state = sync_existing(state)

    with :ok <- validate_slug(slug),
         {:ok, command} <- normalize_command(command, state.default_command),
         {:ok, state} <- create_or_attach(slug, command, state) do
      {:reply, {:ok, session_entry(slug, state)}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:stop_session, slug}, _from, state) do
    case validate_slug(slug) do
      :ok ->
        do_stop_session(slug, state)

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:capture_session, slug}, _from, state) do
    state = sync_existing(state)

    with :ok <- validate_slug(slug),
         {:ok, info} <- fetch_session(slug, state),
         {:ok, capture} <- Runner.capture_pane(info.session) do
      {:reply, {:ok, capture}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp sync_existing(state) do
    state = prune_dead_sessions(state)

    Runner.list_sessions(state.prefix)
    |> Enum.reduce(state, fn session, acc ->
      slug = slug_from_session(session, acc.prefix)

      if Map.has_key?(acc.sessions, slug) do
        acc
      else
        case attach_existing(slug, session, acc) do
          {:ok, next} -> next
          {:error, _reason} -> acc
        end
      end
    end)
  end

  defp prune_dead_sessions(state) do
    {alive_sessions, dead_sessions} =
      Enum.split_with(state.sessions, fn {_slug, info} ->
        Runner.tmux_session_alive?(info.session) and pane_alive?(info.pid)
      end)

    Enum.each(dead_sessions, fn {slug, _info} -> stop_pane(slug) end)

    %{state | sessions: Map.new(alive_sessions)}
  end

  defp create_or_attach(slug, command, state) do
    session = session_name(slug, state.prefix)

    cond do
      Map.has_key?(state.sessions, slug) ->
        {:error, :already_exists}

      Runner.tmux_session_alive?(session) ->
        attach_existing(slug, session, state, command)

      true ->
        start_pane(slug, session, command, true, state)
    end
  end

  defp attach_existing(slug, session, state, command \\ "(reattached)") do
    start_pane(slug, session, command, false, state)
  end

  defp start_pane(slug, session, command, start_session?, state) do
    child = %{
      id: {:pane, slug},
      start:
        {PaneServer, :start_link,
         [[name: slug, session: session, command: command, start_session?: start_session?]]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(Hardline.Web.PaneSupervisor, child) do
      {:ok, pid} ->
        info = %{slug: slug, session: session, command: command, pid: pid}
        {:ok, %{state | sessions: Map.put(state.sessions, slug, info)}}

      {:error, {:already_started, pid}} ->
        info = %{slug: slug, session: session, command: command, pid: pid}
        {:ok, %{state | sessions: Map.put(state.sessions, slug, info)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stop_pane(slug) do
    case Registry.lookup(Hardline.Web.PaneRegistry, slug) do
      [{pid, _value}] ->
        case DynamicSupervisor.terminate_child(Hardline.Web.PaneSupervisor, pid) do
          :ok -> :ok
          {:error, :not_found} -> :ok
          {:error, reason} -> {:error, reason}
        end

      [] ->
        :ok
    end
  end

  defp pane_alive?(pid) when is_pid(pid), do: Process.alive?(pid)
  defp pane_alive?(_pid), do: false

  defp do_stop_session(slug, state) do
    case fetch_session(slug, state) do
      {:ok, info} ->
        pane_result = stop_pane(slug)
        state = %{state | sessions: Map.delete(state.sessions, slug)}

        case pane_result do
          :ok ->
            case kill_live_session(info.session, state.prefix) do
              :ok -> {:reply, :ok, state}
              {:error, reason} -> {:reply, {:error, reason}, state}
            end

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp kill_live_session(session, prefix) do
    cond do
      not Runner.managed_session?(session, prefix) ->
        {:error, :unmanaged_session}

      Runner.tmux_session_alive?(session) ->
        Runner.kill_managed_session(session, prefix)

      true ->
        :ok
    end
  end

  defp session_entries(state) do
    state.sessions
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map(&session_entry(&1, state))
  end

  defp session_entry(slug, state) do
    {:ok, info} = fetch_session(slug, state)

    metadata =
      case Runner.tmux_session_metadata(info.session) do
        {:ok, metadata} -> metadata
        {:error, _reason} -> %{}
      end

    %{
      slug: slug,
      session: info.session,
      command: info.command,
      alive: Runner.tmux_session_alive?(info.session),
      session_id: Map.get(metadata, :session_id),
      pane_pid: Map.get(metadata, :pane_pid),
      pane_command: Map.get(metadata, :pane_command),
      pane_path: Map.get(metadata, :pane_path)
    }
  end

  defp fetch_session(slug, state) do
    case Map.fetch(state.sessions, slug) do
      {:ok, info} -> {:ok, info}
      :error -> {:error, :not_found}
    end
  end

  defp validate_slug(slug) do
    if valid_slug?(slug), do: :ok, else: {:error, :invalid_slug}
  end

  defp normalize_command(command, default_command) when is_binary(command) do
    command = String.trim(command)
    {:ok, if(command == "", do: default_command, else: command)}
  end

  defp normalize_command(_command, default_command), do: {:ok, default_command}

  defp slug_from_session(session, prefix) do
    String.replace_prefix(session, "#{prefix}-", "")
  end
end
