defmodule Babs.Citizens.Bootstrap do
  @moduledoc """
  One-shot boot sequencer for importing and reattaching durable Citizens.
  """

  use GenServer

  require Logger

  alias Babs.Citizens.{Catalog, ReattachScanner, Repo}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def events do
    GenServer.call(__MODULE__, :events)
  end

  def run_once(opts \\ []) do
    with :ok <- maybe_migrate(opts) do
      import_result = Catalog.import_configs(opts)
      scan_events = ReattachScanner.scan_rows(Catalog.list_citizens())

      {:ok, %{import: import_result, scan: scan_events}}
    end
  end

  @impl true
  def init(opts) do
    {:ok, %{opts: opts, events: []}, {:continue, :run}}
  end

  @impl true
  def handle_continue(:run, %{opts: opts} = state) do
    events =
      case run_once(opts) do
        {:ok, result} ->
          result

        {:error, reason} ->
          Logger.warning("Babs citizen bootstrap failed: #{inspect(reason)}")
          %{import: %{records: [], warnings: [], errors: [reason]}, scan: []}
      end

    {:noreply, %{state | events: events}}
  end

  @impl true
  def handle_call(:events, _from, state), do: {:reply, state.events, state}

  defp maybe_migrate(opts) do
    if Keyword.get(opts, :migrate, Application.get_env(:babs_citizens, :auto_migrate, true)) do
      migrate()
    else
      :ok
    end
  end

  def migrate(with_repo \\ &Ecto.Migrator.with_repo/2) do
    case with_repo.(Repo, fn repo ->
           Ecto.Migrator.run(repo, migrations_path(), :up, all: true)
         end) do
      {:ok, _result, _started_apps} -> :ok
      {:error, reason} -> {:error, {:migration_failed, reason}}
    end
  rescue
    error -> {:error, {:migration_failed, Exception.message(error)}}
  end

  defp migrations_path do
    Application.app_dir(:babs_citizens, "priv/repo/migrations")
  end
end
