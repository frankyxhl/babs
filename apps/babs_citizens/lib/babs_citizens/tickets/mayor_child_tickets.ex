defmodule Babs.Citizens.Tickets.MayorChildTickets do
  @moduledoc """
  Pure child Ticket materialization helpers for approved Mayor proposals.
  """

  alias Babs.Citizens.Tickets.Ticket

  @spec plan(Ticket.t(), map()) :: {:ok, map()} | {:error, term()}
  def plan(%Ticket{} = root_ticket, %{proposal: %{"children" => children}} = state)
      when is_list(children) do
    assigner = mayor_assigner(state)

    {:ok,
     %{
       proposal_id: state.proposal_id,
       assigner: assigner,
       root_ticket_id: root_ticket.id,
       children:
         children
         |> Enum.with_index()
         |> Enum.map(fn {child, index} -> child_plan(root_ticket, child, index, assigner) end)
     }}
  end

  def plan(_root_ticket, _state),
    do: {:error, {:mayor_child_tickets, :invalid_proposal_state}}

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

  defp child_plan(root_ticket, child, index, assigner) do
    assignee_role = child["assignee_role"]

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
        metadata: child["metadata"] || %{}
      }
    }
  end

  defp route?(value) when is_binary(value), do: String.trim(value) not in ["", "any"]
  defp route?(_value), do: false

  defp mayor_assigner(%{policy: %{"mayor" => slug}}) when is_binary(slug) and slug != "",
    do: "mayor:#{slug}"

  defp mayor_assigner(_state), do: "mayor"

  defp created_child_summary(child) do
    %{
      "child_index" => child.child_index,
      "ticket_id" => child.ticket_id,
      "title" => child.title,
      "priority" => child.priority,
      "inspector" => child.inspector,
      "assignee_role" => child.assignee_role,
      "routing" => child.routing
    }
  end
end
