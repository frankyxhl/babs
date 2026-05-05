defmodule Babs.Citizens.ReattachScanner do
  @moduledoc """
  Boot-time scanner that starts or reattaches Phase 1 seed Citizens.
  """

  use GenServer

  require Logger

  alias Babs.Citizens.Citizen.Config
  alias Babs.Citizens.Catalog
  alias Babs.Citizens.Lifecycle
  alias Babs.Citizens.Runner

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    {:ok, %{opts: opts, events: scan(opts)}}
  end

  def events do
    GenServer.call(__MODULE__, :events)
  end

  @impl true
  def handle_call(:events, _from, state), do: {:reply, state.events, state}

  def scan(opts \\ []) do
    config_results = Config.list_configs(opts)

    case Runner.list_sessions_result() do
      {:ok, sessions} ->
        config_results
        |> plan_actions(sessions)
        |> Enum.map(&run_action/1)

      {:error, reason} ->
        [run_action({:tmux_error, reason})]
    end
  end

  def scan_rows(rows) when is_list(rows) do
    case Runner.list_sessions_result() do
      {:ok, sessions} ->
        rows
        |> plan_rows(sessions)
        |> Enum.map(&run_row_action/1)

      {:error, reason} ->
        [run_action({:tmux_error, reason})]
    end
  end

  def plan_actions(config_results, sessions) when is_list(config_results) and is_list(sessions) do
    config_errors =
      config_results
      |> Enum.filter(&match?({:error, _reason}, &1))
      |> Enum.map(fn {:error, reason} -> {:config_error, reason} end)

    configs =
      config_results
      |> Enum.flat_map(fn
        {:ok, config} -> [config]
        {:error, _reason} -> []
      end)

    configs_by_slug = Map.new(configs, &{&1.slug, &1})

    existing_slugs =
      sessions
      |> Enum.sort()
      |> Enum.flat_map(fn session ->
        case Runner.slug_from_session(session) do
          {:ok, slug} -> [slug]
          :error -> []
        end
      end)
      |> Enum.uniq()

    existing_slug_set = MapSet.new(existing_slugs)

    reattach_actions =
      existing_slugs
      |> Enum.flat_map(fn slug ->
        case Map.fetch(configs_by_slug, slug) do
          {:ok, config} -> [{:reattach, config}]
          :error -> []
        end
      end)

    start_actions =
      configs
      |> Enum.reject(&MapSet.member?(existing_slug_set, &1.slug))
      |> Enum.map(&{:start, &1})

    config_errors ++ reattach_actions ++ start_actions
  end

  def plan_rows(rows, sessions) when is_list(rows) and is_list(sessions) do
    existing_slug_set =
      sessions
      |> Enum.flat_map(fn session ->
        case Runner.slug_from_session(session) do
          {:ok, slug} -> [slug]
          :error -> []
        end
      end)
      |> MapSet.new()

    Enum.map(rows, fn row ->
      cond do
        row.status == "stopped" ->
          {:skip, row.slug, :stopped}

        row.status == "failed" ->
          {:skip, row.slug, :failed}

        row.status == "running" and not File.dir?(row.cwd) ->
          {:fail_missing_cwd, row, {:missing_cwd, row.cwd}}

        row.status == "running" and MapSet.member?(existing_slug_set, row.slug) ->
          {:reattach, row}

        row.status == "running" ->
          {:start, row}

        true ->
          {:skip, row.slug, :unknown_status}
      end
    end)
  end

  defp run_action({:config_error, reason}) do
    event = {:error, :config, reason}
    maybe_log_event(event)
    event
  end

  defp run_action({:tmux_error, reason}) do
    event = {:error, :tmux, reason}
    maybe_log_event(event)
    event
  end

  defp run_action({action, config}) when action in [:start, :reattach] do
    session = Runner.session_name(config.slug)

    result =
      case action do
        :reattach ->
          if Runner.tmux_session_alive?(session) do
            Lifecycle.reattach(config)
          else
            Lifecycle.start_config(config)
          end

        :start ->
          Lifecycle.start_config(config)
      end

    event =
      case result do
        {:ok, _pid} -> {:ok, config.slug}
        {:error, reason} -> {:error, config.slug, reason}
      end

    maybe_log_event(event)
    event
  end

  defp run_row_action({:skip, slug, status}) do
    event = {:skip, slug, status}
    maybe_log_event(event)
    event
  end

  defp run_row_action({:fail_missing_cwd, row, reason}) do
    Catalog.mark_failed(row.slug, reason)
    event = {:error, row.slug, reason}
    maybe_log_event(event)
    event
  end

  defp run_row_action({action, row}) when action in [:start, :reattach] do
    config = Catalog.to_config(row)
    session = Runner.session_name(config.slug)

    result =
      case action do
        :reattach ->
          if Runner.tmux_session_alive?(session) do
            Lifecycle.reattach(config)
          else
            Lifecycle.start_config(config)
          end

        :start ->
          Lifecycle.start_config(config)
      end

    event =
      case result do
        {:ok, _pid} -> {:ok, config.slug}
        {:error, reason} -> {:error, config.slug, reason}
      end

    maybe_log_event(event)
    event
  end

  defp maybe_log_event({:ok, slug}), do: Logger.info("Babs citizen ready: #{slug}")

  defp maybe_log_event({:error, :config, reason}),
    do: Logger.warning("Babs citizen config failed: #{inspect(reason)}")

  defp maybe_log_event({:error, :tmux, reason}),
    do: Logger.warning("Babs citizen tmux scan failed: #{inspect(reason)}")

  defp maybe_log_event({:error, slug, reason}),
    do: Logger.warning("Babs citizen #{slug} failed: #{inspect(reason)}")

  defp maybe_log_event({:skip, slug, status}),
    do: Logger.info("Babs citizen #{slug} skipped: #{status}")
end
