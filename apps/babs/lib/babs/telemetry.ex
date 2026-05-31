defmodule Babs.Telemetry do
  @moduledoc false

  use Supervisor

  import Telemetry.Metrics

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
    [
      summary("phoenix.endpoint.stop.duration", unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("babs_citizens.repo.query.total_time", unit: {:native, :millisecond}),
      summary("babs_citizens.repo.query.decode_time", unit: {:native, :millisecond}),
      summary("babs_citizens.repo.query.query_time", unit: {:native, :millisecond}),
      summary("babs_citizens.repo.query.queue_time", unit: {:native, :millisecond}),
      summary("babs_citizens.repo.query.idle_time", unit: {:native, :millisecond}),
      last_value("vm.memory.total", unit: {:byte, :kilobyte}),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io")
    ]
  end
end
