defmodule Babs.Citizens.Tickets.InspectionEvents do
  @moduledoc """
  Constructors for Phase 15 inspection history events.
  """

  alias Babs.Citizens.Tickets.History
  alias Babs.Citizens.Tickets.TicketId

  @decisions ~w(approve reject needs_changes)
  @results ~w(approved rejected requires_human)
  @inspection_id_regex ~r/^insp_[0-9]{14}_[0-9]+$/

  @spec new_id(String.t() | DateTime.t(), keyword()) :: String.t()
  def new_id(timestamp \\ DateTime.utc_now(:second), opts \\ []) do
    unique =
      Keyword.get_lazy(opts, :unique, fn -> System.unique_integer([:positive, :monotonic]) end)

    "insp_#{stamp!(timestamp)}_#{unique}"
  end

  @spec requested(String.t(), String.t(), map(), [String.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def requested(ticket_id, inspection_id, policy, inspectors, opts \\ []) do
    with :ok <- validate_ticket_id(ticket_id),
         :ok <- validate_inspection_id(inspection_id),
         :ok <- validate_string_list(inspectors, :invalid_inspectors) do
      event =
        ticket_id
        |> base_event("inspection_requested", opts)
        |> Map.merge(%{
          "inspection_id" => inspection_id,
          "policy" => policy,
          "inspectors" => inspectors
        })

      appendable(ticket_id, event)
    end
  end

  @spec prompt_delivered(String.t(), String.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def prompt_delivered(ticket_id, inspection_id, to, turn_id, attempt_id, opts \\ []) do
    with :ok <- validate_ticket_id(ticket_id),
         :ok <- validate_inspection_id(inspection_id),
         :ok <- validate_non_empty(to, :invalid_inspector),
         :ok <- validate_non_empty(turn_id, :invalid_turn_id),
         :ok <- validate_non_empty(attempt_id, :invalid_attempt_id) do
      event =
        ticket_id
        |> base_event("inspection_prompt_delivered", opts)
        |> Map.merge(%{
          "inspection_id" => inspection_id,
          "to" => to,
          "turn_id" => turn_id,
          "attempt_id" => attempt_id
        })

      appendable(ticket_id, event)
    end
  end

  @spec decision(String.t(), String.t(), String.t(), String.t(), String.t(), [map()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def decision(ticket_id, inspection_id, by, decision, summary, findings, opts \\ []) do
    with :ok <- validate_ticket_id(ticket_id),
         :ok <- validate_inspection_id(inspection_id),
         :ok <- validate_non_empty(by, :invalid_inspector),
         :ok <- validate_decision(decision),
         :ok <- validate_non_empty(summary, :invalid_summary),
         :ok <- validate_findings(findings) do
      event =
        ticket_id
        |> base_event("inspection_decision", Keyword.put(opts, :by, by))
        |> Map.merge(%{
          "inspection_id" => inspection_id,
          "decision" => decision,
          "summary" => summary,
          "findings" => findings
        })

      appendable(ticket_id, event)
    end
  end

  @spec failed(String.t(), String.t(), String.t(), term(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def failed(ticket_id, inspection_id, to, reason, opts \\ []) do
    with :ok <- validate_ticket_id(ticket_id),
         :ok <- validate_inspection_id(inspection_id),
         :ok <- validate_non_empty(to, :invalid_inspector) do
      event =
        ticket_id
        |> base_event("inspection_failed", opts)
        |> Map.merge(%{
          "inspection_id" => inspection_id,
          "to" => to,
          "error" => inspection_error_text(reason)
        })

      appendable(ticket_id, event)
    end
  end

  @spec completed(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def completed(ticket_id, inspection_id, result, quorum, opts \\ []) do
    with :ok <- validate_ticket_id(ticket_id),
         :ok <- validate_inspection_id(inspection_id),
         :ok <- validate_result(result),
         :ok <- validate_quorum(quorum) do
      event =
        ticket_id
        |> base_event("inspection_completed", opts)
        |> Map.merge(%{
          "inspection_id" => inspection_id,
          "result" => result,
          "quorum" => quorum
        })

      appendable(ticket_id, event)
    end
  end

  defp base_event(ticket_id, event, opts) do
    %{
      "ts" => Keyword.get(opts, :now, DateTime.utc_now(:second) |> DateTime.to_iso8601()),
      "event" => event,
      "by" => Keyword.get(opts, :by, "system"),
      "ticket_id" => ticket_id
    }
  end

  defp appendable(ticket_id, event) do
    with :ok <- History.validate_appendable(ticket_id, event) do
      {:ok, event}
    end
  end

  defp validate_ticket_id(ticket_id), do: TicketId.validate(ticket_id)

  defp validate_inspection_id(value) when is_binary(value) do
    if value =~ @inspection_id_regex, do: :ok, else: {:error, {:invalid_inspection_id, value}}
  end

  defp validate_inspection_id(value), do: {:error, {:invalid_inspection_id, value}}

  defp validate_non_empty(value, reason) when is_binary(value) do
    if String.trim(value) == "", do: {:error, reason}, else: :ok
  end

  defp validate_non_empty(_value, reason), do: {:error, reason}

  defp validate_string_list(values, reason) when is_list(values) do
    if Enum.all?(values, &is_binary/1), do: :ok, else: {:error, reason}
  end

  defp validate_string_list(_values, reason), do: {:error, reason}

  defp validate_findings(values) when is_list(values) do
    if Enum.all?(values, &is_map/1), do: :ok, else: {:error, {:invalid_findings, values}}
  end

  defp validate_findings(value), do: {:error, {:invalid_findings, value}}

  defp validate_decision(value) when value in @decisions, do: :ok
  defp validate_decision(value), do: {:error, {:invalid_inspection_decision, value}}

  defp validate_result(value) when value in @results, do: :ok
  defp validate_result(value), do: {:error, {:invalid_inspection_result, value}}

  defp validate_quorum("all_pass"), do: :ok
  defp validate_quorum(value), do: {:error, {:unsupported_quorum, value}}

  defp inspection_error_text(:timeout), do: "Inspection failed: timeout"
  defp inspection_error_text({:timeout, _detail}), do: "Inspection failed: timeout"
  defp inspection_error_text(:unparseable), do: "Inspection failed: unparseable decision"

  defp inspection_error_text({:unparseable, _detail}),
    do: "Inspection failed: unparseable decision"

  defp inspection_error_text(_reason), do: "Inspection failed"

  defp stamp!(%DateTime{} = timestamp), do: format_datetime(timestamp)

  defp stamp!(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _offset} -> format_datetime(datetime)
      {:error, reason} -> raise ArgumentError, "invalid ISO8601 timestamp: #{inspect(reason)}"
    end
  end

  defp format_datetime(datetime) do
    datetime
    |> DateTime.to_unix(:second)
    |> DateTime.from_unix!(:second)
    |> then(fn dt ->
      [
        dt.year,
        dt.month,
        dt.day,
        dt.hour,
        dt.minute,
        dt.second
      ]
      |> Enum.map_join(&pad2_or_4/1)
    end)
  end

  defp pad2_or_4(value) when value >= 1000, do: Integer.to_string(value)
  defp pad2_or_4(value), do: value |> Integer.to_string() |> String.pad_leading(2, "0")
end
