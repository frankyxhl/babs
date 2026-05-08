defmodule Babs.Citizens.Tickets.MayorChildTickets do
  @moduledoc """
  Pure child Ticket materialization helpers for approved Mayor proposals.
  """

  alias Babs.Citizens.Tickets.Ticket

  @preflight_ticket_id "T-9999-12-31-999"

  @spec plan(Ticket.t(), map()) :: {:ok, map()} | {:error, term()}
  def plan(%Ticket{} = root_ticket, %{proposal: %{"children" => children}} = state)
      when is_list(children) do
    assigner = mayor_assigner(state)

    with {:ok, planned_children} <-
           child_plans(root_ticket, children, assigner, state.proposal_id) do
      {:ok,
       %{
         proposal_id: state.proposal_id,
         assigner: assigner,
         root_ticket_id: root_ticket.id,
         children: planned_children
       }}
    end
  end

  def plan(_root_ticket, _state),
    do: {:error, {:mayor_child_tickets, :invalid_proposal_state}}

  @spec preflight_children_created_event(Ticket.t(), map(), keyword()) :: map()
  def preflight_children_created_event(%Ticket{} = root_ticket, plan, opts \\ []) do
    children = Enum.map(plan.children, &preflight_child_summary/1)
    children_created_event(root_ticket, plan, children, opts)
  end

  @spec children_created_event(Ticket.t(), map(), [map()], keyword()) :: map()
  def children_created_event(%Ticket{} = root_ticket, plan, children, opts \\ []) do
    %{
      "ts" => Keyword.get(opts, :now, DateTime.utc_now(:second) |> DateTime.to_iso8601()),
      "event" => "mayor_children_created",
      "by" => Keyword.get(opts, :by, "user"),
      "ticket_id" => root_ticket.id,
      "proposal_id" => plan.proposal_id,
      "children" => Enum.map(children, &created_child_summary/1)
    }
  end

  defp child_plans(root_ticket, children, assigner, proposal_id) do
    children
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {child, index}, {:ok, acc} ->
      case child_plan(root_ticket, child, index, assigner, proposal_id) do
        {:ok, planned} -> {:cont, {:ok, [planned | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, planned} -> {:ok, Enum.reverse(planned)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp child_plan(root_ticket, child, index, assigner, proposal_id) do
    assignee_role = child["assignee_role"]

    with :ok <- validate_title(child["title"], index) do
      {:ok,
       %{
         child_index: index,
         route?: route?(assignee_role),
         attrs: %{
           title: child["title"],
           body: child["body"],
           type: child["type"] || "assignment",
           state: "open",
           assigner: assigner,
           assignees: [],
           assignee_role: assignee_role,
           inspector: child["inspector"] || "user",
           priority: child["priority"] || "normal",
           parent_ticket: root_ticket.id,
           metadata:
             materialization_metadata(
               child["metadata"] || %{},
               root_ticket.id,
               proposal_id,
               index
             )
         }
       }}
    end
  end

  defp validate_title(title, index) when is_binary(title) do
    if String.contains?(title, ["\n", "\r"]) do
      {:error, {:mayor_child_tickets, {:invalid_child_title, index, :multiline}}}
    else
      :ok
    end
  end

  defp route?(value) when is_binary(value), do: String.trim(value) not in ["", "any"]
  defp route?(_value), do: false

  defp materialization_metadata(metadata, root_ticket_id, proposal_id, index) do
    Map.put(metadata, "mayor_materialization", %{
      "root_ticket_id" => root_ticket_id,
      "proposal_id" => proposal_id,
      "child_index" => index
    })
  end

  defp mayor_assigner(%{policy: %{"mayor" => slug}}) when is_binary(slug) and slug != "",
    do: "mayor:#{slug}"

  defp mayor_assigner(_state), do: "mayor"

  defp preflight_child_summary(child) do
    %{
      child_index: child.child_index,
      ticket_id: @preflight_ticket_id,
      title: child.attrs.title,
      priority: child.attrs.priority,
      inspector: child.attrs.inspector,
      assignee_role: child.attrs.assignee_role,
      routing: %{"status" => "not_requested"}
    }
  end

  defp created_child_summary(child) do
    %{
      "child_index" => child.child_index,
      "ticket_id" => child.ticket_id,
      "title" => child.title,
      "priority" => child.priority,
      "inspector" => child.inspector,
      "assignee_role" => child.assignee_role,
      "routing" => compact_routing(child.routing)
    }
  end

  defp compact_routing(%{"status" => "assigned", "assignees" => assignees})
       when is_list(assignees) do
    %{"status" => "assigned", "assignees" => Enum.filter(assignees, &is_binary/1)}
  end

  defp compact_routing(%{"status" => "failed", "reason" => reason}) when is_binary(reason),
    do: %{"status" => "failed", "reason" => reason}

  defp compact_routing(%{"status" => status})
       when status in ["assigned", "failed", "not_requested"],
       do: %{"status" => status}

  defp compact_routing(_routing), do: %{"status" => "unknown"}
end
