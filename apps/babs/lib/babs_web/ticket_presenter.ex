defmodule BabsWeb.TicketPresenter do
  @moduledoc """
  Presentation helpers for Ticket LiveViews.
  """

  alias Babs.Citizens.Tickets.Error

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

  defp group_key(%{state: "open", assignees: []}), do: "billboard"
  defp group_key(%{state: state}), do: state

  defp sort_key(ticket) do
    {Map.get(@priority_rank, ticket.priority, 0), ticket.updated_at, ticket.id}
  end

  defp invalid_row(%{path: path, reason: reason}) do
    %{file: Path.basename(path), reason: invalid_reason(reason)}
  end
end
