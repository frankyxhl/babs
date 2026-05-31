defmodule Babs.TelemetryTest do
  use ExUnit.Case, async: true

  alias Telemetry.Metrics.{LastValue, Summary}

  test "uses the configured Ecto Repo telemetry prefix" do
    assert Babs.Citizens.Repo.config()[:telemetry_prefix] == [:babs_citizens, :repo]
  end

  test "defines Phoenix, Ecto, and VM metrics for LiveDashboard" do
    metrics = Babs.Telemetry.metrics()
    metric_names = Enum.map(metrics, & &1.name)

    assert [:phoenix, :endpoint, :stop, :duration] in metric_names
    assert [:phoenix, :router_dispatch, :stop, :duration] in metric_names

    assert [:babs_citizens, :repo, :query, :total_time] in metric_names
    assert [:babs_citizens, :repo, :query, :query_time] in metric_names

    total_time_metric =
      Enum.find(metrics, &(&1.name == [:babs_citizens, :repo, :query, :total_time]))

    assert %Summary{event_name: [:babs_citizens, :repo, :query]} = total_time_metric

    assert [:vm, :memory, :total] in metric_names
    assert [:vm, :total_run_queue_lengths, :total] in metric_names
    assert [:vm, :total_run_queue_lengths, :cpu] in metric_names
    assert [:vm, :total_run_queue_lengths, :io] in metric_names

    assert Enum.any?(metrics, &match?(%Summary{}, &1))
    assert Enum.any?(metrics, &match?(%LastValue{}, &1))
  end

  test "is started under the Babs application supervisor" do
    child_ids =
      Babs.Supervisor
      |> Supervisor.which_children()
      |> Enum.map(fn {id, _pid, _type, _modules} -> id end)

    assert Babs.Telemetry in child_ids
  end
end
