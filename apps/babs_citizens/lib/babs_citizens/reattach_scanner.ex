defmodule Babs.Citizens.ReattachScanner do
  @moduledoc """
  Boot-time scanner that starts or reattaches Phase 1 seed Citizens.
  """

  use GenServer

  require Logger

  alias Babs.Citizens.Citizen.Config
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
    opts
    |> Config.list_configs()
    |> plan_actions(Runner.list_sessions())
    |> Enum.map(&run_action/1)
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

  defp run_action({:config_error, reason}) do
    event = {:error, :config, reason}
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

  defp maybe_log_event({:ok, slug}), do: Logger.info("Babs citizen ready: #{slug}")

  defp maybe_log_event({:error, :config, reason}),
    do: Logger.warning("Babs citizen config failed: #{inspect(reason)}")

  defp maybe_log_event({:error, slug, reason}),
    do: Logger.warning("Babs citizen #{slug} failed: #{inspect(reason)}")
end
