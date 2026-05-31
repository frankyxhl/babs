defmodule Babs.Telemetry.MeasurementsTest do
  use Babs.Citizens.RepoCase, async: false

  alias Babs.Citizens.Tickets.Api
  alias Babs.Telemetry.Measurements

  test "builds Babs gauges from known Citizen, Hardline, and Ticket fixture state" do
    root = tmp_root!()
    registry = unique_registry!()

    write_citizen_toml!(root, "running-one")
    write_citizen_toml!(root, "running-two")
    write_citizen_toml!(root, "stopped-one")
    write_citizen_toml!(root, "failed-one")

    insert_citizen!(%{slug: "running-one", status: "running"})
    insert_citizen!(%{slug: "running-two", status: "running"})
    insert_citizen!(%{slug: "stopped-one", status: "stopped"})
    insert_citizen!(%{slug: "failed-one", status: "failed"})

    {:ok, _} = Registry.register(registry, "running-one", nil)
    {:ok, _} = Registry.register(registry, "running-two", nil)

    create_ticket!(root, "Open ticket", "open")
    create_ticket!(root, "Pending ticket 1", "pending_approval")
    create_ticket!(root, "Pending ticket 2", "pending_approval")
    create_ticket!(root, "Closed ticket", "closed")

    events =
      Measurements.measurements(
        citizen_opts: [root: root, config_dir: "citizens"],
        pane_registry: registry,
        ticket_opts: [root: root]
      )

    assert gauge(events, [:babs, :citizens], %{status: "running"}) == %{count: 2}
    assert gauge(events, [:babs, :citizens], %{status: "stopped"}) == %{count: 1}
    assert gauge(events, [:babs, :citizens], %{status: "failed"}) == %{count: 1}

    assert gauge(events, [:babs, :hardlines], %{}) == %{live: 2}

    assert gauge(events, [:babs, :tickets], %{state: "open"}) == %{count: 1}
    assert gauge(events, [:babs, :tickets], %{state: "in_progress"}) == %{count: 0}
    assert gauge(events, [:babs, :tickets], %{state: "pending_approval"}) == %{count: 2}
    assert gauge(events, [:babs, :tickets], %{state: "closed"}) == %{count: 1}
    assert gauge(events, [:babs, :tickets], %{state: "cancelled"}) == %{count: 0}
  end

  test "dispatches Babs gauge telemetry events" do
    handler_id = {__MODULE__, :babs_gauge_dispatch, make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach_many(
        handler_id,
        [[:babs, :citizens], [:babs, :hardlines], [:babs, :tickets]],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

    try do
      Measurements.dispatch(
        citizen_snapshot_provider: fn -> [%{durable_status: "running"}] end,
        live_hardline_count_provider: fn -> 3 end,
        ticket_list_provider: fn ->
          {:ok, %{tickets: [%{state: "open"}, %{state: "cancelled"}], invalid: []}}
        end
      )

      events = receive_events(9)

      assert {[:babs, :citizens], %{count: 1}, %{status: "running"}} in events
      assert {[:babs, :citizens], %{count: 0}, %{status: "stopped"}} in events
      assert {[:babs, :citizens], %{count: 0}, %{status: "failed"}} in events
      assert {[:babs, :hardlines], %{live: 3}, %{}} in events
      assert {[:babs, :tickets], %{count: 1}, %{state: "open"}} in events
      assert {[:babs, :tickets], %{count: 0}, %{state: "in_progress"}} in events
      assert {[:babs, :tickets], %{count: 0}, %{state: "pending_approval"}} in events
      assert {[:babs, :tickets], %{count: 0}, %{state: "closed"}} in events
      assert {[:babs, :tickets], %{count: 1}, %{state: "cancelled"}} in events

      refute_receive {:telemetry_event, _event, _measurements, _metadata}
    after
      :telemetry.detach(handler_id)
    end
  end

  test "counts the default PaneRegistry when no hardline provider override is given" do
    baseline = registry_count(Babs.Citizens.PaneRegistry)
    slug_prefix = "default-registry-#{System.unique_integer([:positive])}"
    slugs = ["#{slug_prefix}-one", "#{slug_prefix}-two"]

    try do
      Enum.each(slugs, fn slug ->
        {:ok, _} = Registry.register(Babs.Citizens.PaneRegistry, slug, nil)
      end)

      events =
        Measurements.measurements(
          citizen_snapshot_provider: fn -> [] end,
          ticket_list_provider: fn -> {:ok, %{tickets: [], invalid: []}} end
        )

      assert gauge(events, [:babs, :hardlines], %{}) == %{live: baseline + 2}
    after
      Enum.each(slugs, &Registry.unregister(Babs.Citizens.PaneRegistry, &1))
    end
  end

  test "falls back to zero gauges when read providers are unavailable" do
    missing_registry = Module.concat(__MODULE__, "MissingPaneRegistry")

    events =
      Measurements.measurements(
        citizen_snapshot_provider: fn -> raise "snapshot unavailable" end,
        pane_registry: missing_registry,
        ticket_list_provider: fn -> {:error, :ticket_store_unavailable} end
      )

    assert gauge(events, [:babs, :citizens], %{status: "running"}) == %{count: 0}
    assert gauge(events, [:babs, :citizens], %{status: "stopped"}) == %{count: 0}
    assert gauge(events, [:babs, :citizens], %{status: "failed"}) == %{count: 0}
    assert gauge(events, [:babs, :hardlines], %{}) == %{live: 0}
    assert gauge(events, [:babs, :tickets], %{state: "open"}) == %{count: 0}
    assert gauge(events, [:babs, :tickets], %{state: "in_progress"}) == %{count: 0}
    assert gauge(events, [:babs, :tickets], %{state: "pending_approval"}) == %{count: 0}
    assert gauge(events, [:babs, :tickets], %{state: "closed"}) == %{count: 0}
    assert gauge(events, [:babs, :tickets], %{state: "cancelled"}) == %{count: 0}
  end

  defp create_ticket!(root, title, state) do
    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 title: title,
                 body: "Telemetry fixture",
                 state: state,
                 assignees: assignees_for_state(state)
               },
               root: root
             )

    ticket
  end

  defp assignees_for_state(state) when state in ["open", "cancelled"], do: []
  defp assignees_for_state(_state), do: ["running-one"]

  defp unique_registry! do
    name = Module.concat(__MODULE__, "PaneRegistry#{System.unique_integer([:positive])}")
    start_supervised!({Registry, keys: :unique, name: name})
    name
  end

  defp receive_events(count) do
    Enum.map(1..count, fn _index ->
      assert_receive {:telemetry_event, event, measurements, metadata}
      {event, measurements, metadata}
    end)
  end

  defp registry_count(registry) do
    registry
    |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [true]}])
    |> length()
  end

  defp gauge(events, event, metadata) do
    Enum.find_value(events, fn
      {^event, measurements, ^metadata} -> measurements
      _event -> nil
    end)
  end
end
