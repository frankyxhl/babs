defmodule Babs.Citizens.Tickets.InspectionQuorum do
  @moduledoc """
  Reduces Phase 15 inspection decisions using the initial all_pass quorum.
  """

  @spec reduce([map()], String.t()) ::
          {:ok,
           :pending
           | :completed
           | {:approved, map()}
           | {:rejected, map()}
           | {:requires_human, map()}}
          | {:error, term()}
  def reduce(history, inspection_id) when is_list(history) and is_binary(inspection_id) do
    cond do
      completed?(history, inspection_id) ->
        {:ok, :completed}

      request = request_event(history, inspection_id) ->
        reduce_request(history, inspection_id, request)

      true ->
        {:error, {:inspection_not_requested, inspection_id}}
    end
  end

  @spec completed?([map()], String.t()) :: boolean()
  def completed?(history, inspection_id) do
    Enum.any?(
      history,
      &match?(%{"event" => "inspection_completed", "inspection_id" => ^inspection_id}, &1)
    )
  end

  @spec active_inspection?([map()], String.t()) :: boolean()
  def active_inspection?(history, inspection_id)
      when is_list(history) and is_binary(inspection_id) do
    case active_request(history) do
      %{"inspection_id" => ^inspection_id} -> true
      _request -> false
    end
  end

  @spec active_request([map()]) :: map() | nil
  def active_request(history) when is_list(history) do
    latest_unresolved_request(history)
  end

  @spec match_prompt([map()], String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, map()} | :error
  def match_prompt(_history, _by, nil, _attempt_id), do: :error
  def match_prompt(_history, _by, _turn_id, nil), do: :error

  def match_prompt(history, by, turn_id, attempt_id) do
    history
    |> Enum.reverse()
    |> Enum.find(fn
      %{
        "event" => "inspection_prompt_delivered",
        "to" => ^by,
        "turn_id" => ^turn_id,
        "attempt_id" => ^attempt_id
      } ->
        true

      _event ->
        false
    end)
    |> case do
      nil -> :error
      prompt -> {:ok, prompt}
    end
  end

  @spec terminal_recorded?([map()], String.t(), String.t(), String.t(), String.t()) :: boolean()
  def terminal_recorded?(history, inspection_id, by, turn_id, attempt_id) do
    Enum.any?(history, fn
      %{
        "event" => "inspection_decision",
        "inspection_id" => ^inspection_id,
        "by" => ^by,
        "turn_id" => ^turn_id,
        "attempt_id" => ^attempt_id
      } ->
        true

      %{
        "event" => "inspection_failed",
        "inspection_id" => ^inspection_id,
        "to" => ^by,
        "turn_id" => ^turn_id,
        "attempt_id" => ^attempt_id
      } ->
        true

      _event ->
        false
    end)
  end

  defp reduce_request(history, inspection_id, request) do
    case get_in(request, ["policy", "quorum"]) || "all_pass" do
      "all_pass" ->
        inspectors = request["inspectors"] || []
        terminals = latest_terminals(history, inspection_id, inspectors)

        cond do
          inspectors == [] ->
            {:error, {:no_inspectors, inspection_id}}

          failed =
              Enum.find(inspectors, &match?(%{"event" => "inspection_failed"}, terminals[&1])) ->
            {:ok,
             {:requires_human,
              %{
                inspection_id: inspection_id,
                inspectors: inspectors,
                result: "requires_human",
                reason: "inspection_failed",
                failures: [terminals[failed]]
              }}}

          rejected = non_approve_decisions(terminals, inspectors) ->
            {:ok,
             {:rejected,
              %{
                inspection_id: inspection_id,
                inspectors: inspectors,
                result: "rejected",
                decisions: rejected,
                feedback: feedback(rejected)
              }}}

          Enum.all?(inspectors, &(decision(terminals[&1]) == "approve")) ->
            {:ok,
             {:approved,
              %{
                inspection_id: inspection_id,
                inspectors: inspectors,
                result: "approved",
                decisions: Enum.map(inspectors, &terminals[&1])
              }}}

          true ->
            {:ok, :pending}
        end

      quorum ->
        {:error, {:unsupported_quorum, quorum}}
    end
  end

  defp request_event(history, inspection_id) do
    history
    |> Enum.reverse()
    |> Enum.find(
      &match?(%{"event" => "inspection_requested", "inspection_id" => ^inspection_id}, &1)
    )
  end

  defp latest_unresolved_request(history) do
    history
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn
      {%{"event" => "inspection_requested"} = request, index} -> {request, index}
      {_event, _index} -> nil
    end)
    |> case do
      {%{"inspection_id" => inspection_id} = request, index} ->
        later_events = Enum.drop(history, index + 1)

        unless resolved_after_request?(later_events, inspection_id) do
          request
        end

      nil ->
        nil
    end
  end

  defp resolved_after_request?(events, inspection_id) do
    Enum.any?(events, &inspection_resolved_event?(&1, inspection_id))
  end

  defp inspection_resolved_event?(
         %{"event" => "inspection_completed", "inspection_id" => inspection_id},
         inspection_id
       ),
       do: true

  defp inspection_resolved_event?(
         %{"event" => event, "from" => "pending_approval", "to" => to},
         _inspection_id
       )
       when event in ["approved", "rejected", "state_change", "cancelled"] and
              to in ["closed", "in_progress", "cancelled"],
       do: true

  defp inspection_resolved_event?(_event, _inspection_id), do: false

  defp latest_terminals(history, inspection_id, inspectors) do
    inspector_set = MapSet.new(inspectors)

    history
    |> Enum.filter(&terminal_event?(&1, inspection_id, inspector_set))
    |> Enum.reduce(%{}, fn event, acc ->
      Map.put(acc, terminal_inspector(event), event)
    end)
  end

  defp terminal_event?(
         %{"event" => "inspection_decision", "inspection_id" => inspection_id, "by" => by},
         inspection_id,
         inspector_set
       ),
       do: MapSet.member?(inspector_set, by)

  defp terminal_event?(
         %{"event" => "inspection_failed", "inspection_id" => inspection_id, "to" => to},
         inspection_id,
         inspector_set
       ),
       do: MapSet.member?(inspector_set, to)

  defp terminal_event?(_event, _inspection_id, _inspector_set), do: false

  defp terminal_inspector(%{"event" => "inspection_decision", "by" => by}), do: by
  defp terminal_inspector(%{"event" => "inspection_failed", "to" => to}), do: to

  defp non_approve_decisions(terminals, inspectors) do
    decisions =
      inspectors
      |> Enum.map(&terminals[&1])
      |> Enum.filter(&(decision(&1) in ["reject", "needs_changes"]))

    if decisions == [], do: nil, else: decisions
  end

  defp decision(%{"event" => "inspection_decision", "decision" => decision}), do: decision
  defp decision(_event), do: nil

  defp feedback(decisions) do
    decisions
    |> Enum.map_join("\n\n", fn decision ->
      line = "#{decision["by"]} #{decision["decision"]}: #{decision["summary"]}"

      case findings_text(decision["findings"] || []) do
        "" -> line
        findings -> line <> "\n" <> findings
      end
    end)
  end

  defp findings_text(findings) do
    findings
    |> Enum.map(&finding_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map_join("\n")
  end

  defp finding_text(finding) when is_map(finding) do
    title = text(finding["title"] || finding["summary"] || finding["description"])
    severity = text(finding["severity"])

    cond do
      title != "" and severity != "" -> "- #{severity}: #{title}"
      title != "" -> "- #{title}"
      true -> ""
    end
  end

  defp finding_text(_finding), do: ""

  defp text(value) when is_binary(value), do: String.replace(String.trim(value), ~r/\s+/, " ")
  defp text(_value), do: ""
end
