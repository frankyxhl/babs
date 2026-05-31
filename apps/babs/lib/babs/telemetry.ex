defmodule Babs.Telemetry do
  @moduledoc false

  use Supervisor

  import Telemetry.Metrics

  @ecto_repo Babs.Citizens.Repo
  @ecto_query_measurements [:total_time, :decode_time, :query_time, :queue_time, :idle_time]

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {:telemetry_poller,
       measurements: [:memory, :total_run_queue_lengths, :system_counts, :persistent_term],
       period: 10_000,
       name: Babs.Telemetry.Poller}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    ecto_metrics = Enum.map(@ecto_query_measurements, &ecto_query_summary/1)

    [
      summary("phoenix.endpoint.stop.duration", unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      )
    ] ++
      ecto_metrics ++
      [
        last_value("vm.memory.total", unit: {:byte, :kilobyte}),
        last_value("vm.total_run_queue_lengths.total"),
        last_value("vm.total_run_queue_lengths.cpu"),
        last_value("vm.total_run_queue_lengths.io")
      ]
  end

  defp ecto_query_summary(measurement) do
    @ecto_repo
    |> ecto_telemetry_prefix()
    |> Kernel.++([:query, measurement])
    |> summary(unit: {:native, :millisecond})
  end

  defp ecto_telemetry_prefix(repo) do
    Keyword.fetch!(repo.config(), :telemetry_prefix)
  end
end
