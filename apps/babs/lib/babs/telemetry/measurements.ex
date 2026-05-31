defmodule Babs.Telemetry.Measurements do
  @moduledoc """
  Read-only Babs domain gauge measurements dispatched as Telemetry events for
  Phoenix LiveDashboard.
  """

  alias Babs.Citizens.StatusSnapshot
  alias Babs.Citizens.Tickets.Api, as: TicketsApi

  @citizen_statuses ~w(running stopped failed)
  @ticket_states ~w(open in_progress pending_approval closed cancelled)

  @doc """
  Dispatches the current Babs gauge measurements as Telemetry events.
  """
  def dispatch(opts \\ []) do
    opts
    |> measurements()
    |> Enum.each(fn {event, measurements, metadata} ->
      :telemetry.execute(event, measurements, metadata)
    end)
  end

  @doc """
  Builds Telemetry events for Babs gauges without dispatching them.
  """
  def measurements(opts \\ []) do
    citizen_count_measurements(opts) ++
      [hardline_measurement(opts)] ++
      ticket_count_measurements(opts)
  end

  defp citizen_count_measurements(opts) do
    counts =
      opts
      |> citizen_snapshots()
      |> count_known_values(@citizen_statuses, &Map.get(&1, :durable_status))

    Enum.map(@citizen_statuses, fn status ->
      {[:babs, :citizens], %{count: Map.fetch!(counts, status)}, %{status: status}}
    end)
  end

  defp citizen_snapshots(opts) do
    provider =
      Keyword.get(opts, :citizen_snapshot_provider, fn ->
        opts
        |> Keyword.get(:citizen_opts, [])
        |> StatusSnapshot.list()
      end)

    safe_call(provider, [])
  end

  defp hardline_measurement(opts) do
    provider =
      Keyword.get(opts, :live_hardline_count_provider, fn ->
        opts
        |> Keyword.get(:pane_registry, Babs.Citizens.PaneRegistry)
        |> registry_count()
      end)

    {[:babs, :hardlines], %{live: safe_count(provider)}, %{}}
  end

  defp ticket_count_measurements(opts) do
    counts =
      opts
      |> tickets()
      |> count_known_values(@ticket_states, &Map.get(&1, :state))

    Enum.map(@ticket_states, fn state ->
      {[:babs, :tickets], %{count: Map.fetch!(counts, state)}, %{state: state}}
    end)
  end

  defp tickets(opts) do
    provider =
      Keyword.get(opts, :ticket_list_provider, fn ->
        opts
        |> Keyword.get(:ticket_opts, [])
        |> TicketsApi.list_tickets()
      end)

    case safe_call(provider, {:ok, %{tickets: []}}) do
      {:ok, %{tickets: tickets}} when is_list(tickets) -> tickets
      _result -> []
    end
  end

  defp count_known_values(items, known_values, value_fun) do
    zero_counts = Map.new(known_values, &{&1, 0})

    Enum.reduce(items, zero_counts, fn item, counts ->
      case value_fun.(item) do
        value when is_map_key(counts, value) -> Map.update!(counts, value, &(&1 + 1))
        _unknown -> counts
      end
    end)
  end

  defp registry_count(registry) do
    registry
    |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [true]}])
    |> length()
  end

  defp safe_count(provider) do
    case safe_call(provider, 0) do
      count when is_integer(count) and count >= 0 -> count
      _value -> 0
    end
  end

  defp safe_call(fun, fallback) when is_function(fun, 0) do
    fun.()
  rescue
    _error -> fallback
  catch
    :exit, _reason -> fallback
    :throw, _reason -> fallback
  end
end
