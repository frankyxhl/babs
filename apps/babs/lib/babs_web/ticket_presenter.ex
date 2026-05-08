defmodule BabsWeb.TicketPresenter do
  @moduledoc """
  Presentation helpers for Ticket LiveViews.
  """

  require Logger

  alias Babs.Citizens.Tickets.InspectionPolicy
  alias Babs.Citizens.Tickets.Error
  alias Babs.Citizens.Tickets.MayorProposalReview

  @groups [
    {"billboard", "Billboard"},
    {"open", "Open"},
    {"in_progress", "In Progress"},
    {"pending_approval", "Pending Approval"},
    {"closed", "Closed"},
    {"cancelled", "Cancelled"}
  ]

  @priority_rank %{"urgent" => 4, "high" => 3, "normal" => 2, "low" => 1}

  def groups(tickets, invalid) do
    valid_groups =
      Enum.map(@groups, fn {key, label} ->
        group_tickets =
          tickets
          |> Enum.filter(&(group_key(&1) == key))
          |> Enum.sort_by(&sort_key/1, :desc)

        %{key: key, label: label, count: length(group_tickets), tickets: group_tickets}
      end)

    invalid_group = %{
      key: "invalid",
      label: "Invalid",
      count: length(invalid),
      invalid: Enum.map(invalid, &invalid_row/1)
    }

    valid_groups ++ [invalid_group]
  end

  def counts(groups) do
    Enum.into(groups, %{}, &{&1.key, &1.count})
  end

  def assignees([]), do: "unassigned"
  def assignees(assignees), do: Enum.join(assignees, ", ")

  def warning({:unknown_citizen, slug}), do: "unknown citizen: #{slug}"
  def warning(warning), do: inspect(warning)

  def error_message({:not_found, _id}), do: "Ticket not found"
  def error_message(reason), do: Error.message(reason)

  def invalid_reason(reason), do: Error.message(reason)

  def inspection_panel(ticket, history) when is_list(history) do
    with {:ok, policy} <- InspectionPolicy.from_metadata(ticket.metadata || %{}) do
      request = latest_event(history, "inspection_requested")
      inspection_id = event_value(request, "inspection_id")
      request_policy = merged_request_policy(policy, event_value(request, "policy"))
      inspectors = selected_inspectors(request, request_policy)
      completed = latest_inspection_event(history, inspection_id, "inspection_completed")

      %{
        kind: inspection_kind(request_policy),
        mode: request_policy["mode"] || "human",
        strategy: request_policy["strategy"] || "single",
        label: inspection_label(request_policy),
        roles: list(request_policy["roles"]),
        citizens: list(request_policy["citizens"]),
        quorum: event_value(completed, "quorum") || request_policy["quorum"] || "all_pass",
        inspection_id: inspection_id,
        result: event_value(completed, "result"),
        inspectors: Enum.map(inspectors, &inspection_status(history, inspection_id, &1))
      }
    else
      {:error, _reason} ->
        inspection_unavailable()
    end
  rescue
    _error -> inspection_unavailable()
  end

  def frontmatter(ticket) do
    [
      {"ID", ticket.id},
      {"Type", ticket.type},
      {"State", ticket.state},
      {"Priority", ticket.priority},
      {"Assigner", ticket.assigner},
      {"Assignees", assignees(ticket.assignees)},
      {"Assignee role", ticket.assignee_role || "any"},
      {"Inspector", ticket.inspector},
      {"Parent", ticket.parent_ticket || "none"},
      {"Created", ticket.created_at},
      {"Updated", ticket.updated_at}
    ]
  end

  def proposal_panel(ticket, history) when is_list(history) do
    case MayorProposalReview.from_history(ticket, history) do
      :missing ->
        %{kind: :hidden}

      {:ok, %{status: :awaiting, policy: policy}} ->
        %{
          kind: :awaiting,
          status: :awaiting,
          actionable?: false,
          mayor: policy["mayor"] || "default",
          rules_refs: list(policy["rules_refs"])
        }

      {:ok, state} ->
        proposal_panel_from_state(state)

      {:error, reason} ->
        %{
          kind: :invalid,
          status: :invalid,
          actionable?: false,
          error: Error.message(reason)
        }
    end
  rescue
    error ->
      Logger.warning("Babs ticket proposal panel unavailable: #{Exception.message(error)}")

      %{
        kind: :invalid,
        status: :invalid,
        actionable?: false,
        error: Error.message({:mayor_proposal_review, {:invalid_proposal, error}})
      }
  end

  def proposal_panel(_ticket, _history), do: %{kind: :hidden}

  defp inspection_unavailable do
    %{
      kind: :unavailable,
      mode: "unknown",
      strategy: "unknown",
      label: "Inspection data unavailable",
      roles: [],
      citizens: [],
      quorum: nil,
      inspection_id: nil,
      result: nil,
      inspectors: []
    }
  end

  defp proposal_panel_from_state(%{proposal: proposal} = state) do
    children = proposal_children(proposal)

    %{
      kind: :proposal,
      status: state.status,
      actionable?: state.status == :pending,
      proposal_id: state.proposal_id,
      revision_token: state.revision_token,
      summary: proposal["summary"],
      rules_refs: list(proposal["rules_refs_used"]),
      roles: proposal_roles(children),
      risks: list(proposal["risks"]),
      questions: list(proposal["questions"]),
      children: children,
      created_children: proposal_created_children(state.children_created),
      feedback: state.feedback,
      decision: state.decision
    }
  end

  defp proposal_children(proposal) do
    proposal
    |> Map.get("children", [])
    |> Enum.with_index()
    |> Enum.map(fn {child, index} ->
      %{
        index: index,
        number: index + 1,
        title: child["title"],
        body: child["body"],
        type: child["type"] || "assignment",
        priority: child["priority"] || "normal",
        assignee_role: child["assignee_role"] || "any",
        inspector: child["inspector"] || "user",
        inspection_mode:
          metadata_value(metadata_value(child["metadata"], "inspection"), "mode") || "human"
      }
    end)
  end

  defp metadata_value(map, key) when is_map(map) do
    atom_key =
      try do
        String.to_existing_atom(key)
      rescue
        ArgumentError -> nil
      end

    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> atom_key && Map.get(map, atom_key)
    end
  end

  defp metadata_value(_value, _key), do: nil

  defp proposal_roles(children) do
    children
    |> Enum.map(& &1.assignee_role)
    |> Enum.reject(&(&1 in [nil, "", "any"]))
    |> Enum.uniq()
  end

  defp proposal_created_children(%{"children" => children}) when is_list(children) do
    Enum.map(children, fn child ->
      routing = Map.get(child, "routing", %{})

      %{
        index: Map.get(child, "child_index"),
        number: created_child_number(Map.get(child, "child_index")),
        ticket_id: Map.get(child, "ticket_id"),
        title: Map.get(child, "title"),
        priority: Map.get(child, "priority") || "normal",
        inspector: Map.get(child, "inspector") || "user",
        assignee_role: Map.get(child, "assignee_role") || "any",
        routing_status: Map.get(routing, "status") || "unknown",
        routing_label: proposal_routing_label(routing)
      }
    end)
  end

  defp proposal_created_children(_value), do: []

  defp created_child_number(index) when is_integer(index), do: index + 1
  defp created_child_number(_index), do: nil

  defp proposal_routing_label(%{"status" => "assigned", "assignees" => assignees}) do
    "assigned to #{assignees(assignees)}"
  end

  defp proposal_routing_label(%{"status" => "failed"}), do: "routing failed"
  defp proposal_routing_label(%{"status" => "not_requested"}), do: "routing not requested"
  defp proposal_routing_label(%{"status" => status}) when is_binary(status), do: status
  defp proposal_routing_label(_routing), do: "routing unknown"

  defp inspection_kind(%{"mode" => "auto", "strategy" => "council"}), do: :auto_council
  defp inspection_kind(%{"mode" => "auto"}), do: :auto_single
  defp inspection_kind(_policy), do: :human

  defp merged_request_policy(policy, request_policy) when is_map(request_policy),
    do: Map.merge(policy, request_policy)

  defp merged_request_policy(policy, _request_policy), do: policy

  defp inspection_label(%{"mode" => "auto", "strategy" => "council"}), do: "Auto council"
  defp inspection_label(%{"mode" => "auto"}), do: "Auto single"
  defp inspection_label(_policy), do: "Human approval"

  defp selected_inspectors(%{"inspectors" => inspectors}, _policy), do: list(inspectors)

  defp selected_inspectors(_request, policy) do
    case list(policy["citizens"]) do
      [] -> []
      citizens -> citizens
    end
  end

  defp inspection_status(history, inspection_id, slug) do
    decision = latest_inspector_event(history, inspection_id, slug, "inspection_decision", "by")
    failed = latest_inspector_event(history, inspection_id, slug, "inspection_failed", "to")

    delivered =
      latest_inspector_event(history, inspection_id, slug, "inspection_prompt_delivered", "to")

    cond do
      is_map(decision) ->
        %{
          slug: slug,
          status: decision["decision"] || "decision",
          status_label: decision_label(decision["decision"]),
          summary: decision["summary"],
          findings: list(decision["findings"])
        }

      is_map(failed) ->
        %{
          slug: slug,
          status: "failed",
          status_label: "Unparseable or failed",
          summary: failed["error"],
          findings: []
        }

      is_map(delivered) ->
        %{
          slug: slug,
          status: "delivered",
          status_label: "Prompt delivered",
          summary: nil,
          findings: []
        }

      true ->
        %{slug: slug, status: "pending", status_label: "Pending", summary: nil, findings: []}
    end
  end

  defp decision_label("approve"), do: "Approved"
  defp decision_label("reject"), do: "Rejected"
  defp decision_label("needs_changes"), do: "Needs changes"
  defp decision_label(_decision), do: "Decision"

  defp latest_inspector_event(history, inspection_id, slug, event, slug_key)
       when is_binary(inspection_id) do
    history
    |> Enum.reverse()
    |> Enum.find(fn candidate ->
      candidate["event"] == event and candidate["inspection_id"] == inspection_id and
        candidate[slug_key] == slug
    end)
  end

  defp latest_inspector_event(_history, _inspection_id, _slug, _event, _slug_key), do: nil

  defp latest_inspection_event(_history, nil, _event), do: nil

  defp latest_inspection_event(history, inspection_id, event) do
    history
    |> Enum.reverse()
    |> Enum.find(
      &(event_value(&1, "event") == event and event_value(&1, "inspection_id") == inspection_id)
    )
  end

  defp latest_event(history, event) do
    history
    |> Enum.reverse()
    |> Enum.find(&(event_value(&1, "event") == event))
  end

  defp event_value(map, key) when is_map(map), do: Map.get(map, key)
  defp event_value(_value, _key), do: nil

  defp list(values) when is_list(values), do: values
  defp list(_values), do: []

  defp group_key(%{state: "open", assignees: []}), do: "billboard"
  defp group_key(%{state: state}), do: state

  defp sort_key(ticket) do
    {Map.get(@priority_rank, ticket.priority, 0), ticket.updated_at, ticket.id}
  end

  defp invalid_row(%{path: path, reason: reason}) do
    %{file: Path.basename(path), reason: invalid_reason(reason)}
  end
end
