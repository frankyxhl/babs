defmodule Babs.Citizens.ReattachScanner do
  @moduledoc """
  Boot-time scanner that starts or reattaches Phase 1 seed Citizens.
  """

  use GenServer

  require Logger

  alias Babs.Citizens.Citizen.Config
  alias Babs.Citizens.Catalog
  alias Babs.Citizens.ImportedHardline
  alias Babs.Citizens.Lifecycle
  alias Babs.Citizens.Runner
  alias Babs.Citizens.TmuxInventory

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

  def scan_rows(rows, opts \\ []) when is_list(rows) do
    case Runner.list_sessions_result() do
      {:ok, sessions} ->
        rows
        |> plan_rows(sessions, opts)
        |> Enum.map(&run_row_action(&1, opts))

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

  def plan_rows(rows, sessions, opts \\ []) when is_list(rows) and is_list(sessions) do
    target_exists? = Keyword.get(opts, :target_exists?, &TmuxInventory.target_exists?/1)

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

        row.status == "running" and ImportedHardline.external?(row) ->
          plan_imported_row(row, target_exists?)

        row.status == "running" and MapSet.member?(existing_slug_set, row.slug) ->
          {:reattach, row}

        row.status == "running" and not File.dir?(row.cwd) ->
          {:fail_missing_cwd, row, {:missing_cwd, row.cwd}}

        row.status == "running" ->
          {:start, row}

        true ->
          {:skip, row.slug, :unknown_status}
      end
    end)
  end

  defp plan_imported_row(row, target_exists?) do
    target = ImportedHardline.operational_target(row)

    cond do
      not is_binary(target) or target == "" ->
        {:fail_import_target, row, :missing_import_target}

      target_exists?.(target) ->
        {:reattach_imported, row}

      true ->
        {:fail_import_target, row, {:import_target_missing, target}}
    end
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

  defp run_row_action(action, opts)

  defp run_row_action({:skip, slug, status}, _opts) do
    event = {:skip, slug, status}
    maybe_log_event(event)
    event
  end

  defp run_row_action({:fail_missing_cwd, row, reason}, _opts) do
    Catalog.mark_failed(row.slug, reason)
    event = {:error, row.slug, reason}
    maybe_log_event(event)
    event
  end

  defp run_row_action({:fail_import_target, row, reason}, _opts) do
    Catalog.mark_import_attach_failed(row, reason)
    event = {:error, row.slug, reason}
    maybe_log_event(event)
    event
  end

  defp run_row_action({:reattach_imported, row}, opts) do
    result = Lifecycle.start_registered_citizen(row.slug, opts)

    event =
      case result do
        {:ok, _pid} -> {:ok, row.slug}
        {:error, reason} -> {:error, row.slug, reason}
      end

    maybe_log_event(event)
    event
  end

  defp run_row_action({action, row}, _opts) when action in [:start, :reattach] do
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
