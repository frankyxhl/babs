defmodule Babs.Citizens.Tickets.StateMachine do
  @moduledoc """
  Legal Ticket lifecycle transitions for the Phase 9-10 flywheel.
  """

  alias Babs.Citizens.Citizen.Config, as: CitizenConfig
  alias Babs.Citizens.Tickets.Ticket

  @states ~w(open in_progress pending_approval closed cancelled)

  @spec assign(Ticket.t(), String.t()) :: {:ok, Ticket.t()} | {:error, term()}
  def assign(%Ticket{state: "open", assignees: []} = ticket, slug) when is_binary(slug) do
    if CitizenConfig.valid_slug?(slug) do
      {:ok, %{ticket | state: "in_progress", assignees: [slug]}}
    else
      {:error, {:invalid_slug, slug}}
    end
  end

  def assign(%Ticket{state: "open", assignees: []}, slug) do
    {:error, {:invalid_slug, slug}}
  end

  def assign(%Ticket{state: from}, _slug),
    do: {:error, {:invalid_transition, from, "in_progress"}}

  @spec unassign(Ticket.t(), String.t()) :: {:ok, Ticket.t()} | {:error, term()}
  def unassign(%Ticket{state: "in_progress", assignees: assignees} = ticket, slug)
      when is_binary(slug) do
    cond do
      not CitizenConfig.valid_slug?(slug) ->
        {:error, {:invalid_slug, slug}}

      slug in assignees ->
        remaining = List.delete(assignees, slug)
        state = if remaining == [], do: "open", else: "in_progress"
        {:ok, %{ticket | state: state, assignees: remaining}}

      true ->
        {:error, {:not_assigned, ticket.id, slug}}
    end
  end

  def unassign(%Ticket{state: "in_progress"}, slug), do: {:error, {:invalid_slug, slug}}

  def unassign(%Ticket{state: from}, _slug), do: {:error, {:invalid_transition, from, "open"}}

  @spec transition(Ticket.t(), String.t(), String.t() | nil) ::
          {:ok, Ticket.t(), String.t()} | {:error, term()}
  def transition(%Ticket{} = ticket, to_state, event) when to_state in @states do
    case event_for(ticket.state, to_state, event) do
      {:ok, event_name} -> {:ok, %{ticket | state: to_state}, event_name}
      {:error, reason} -> {:error, reason}
    end
  end

  def transition(%Ticket{}, to_state, _event), do: {:error, {:invalid_state, to_state}}

  defp event_for("open", "cancelled", event), do: require_event(event, "cancelled")
  defp event_for("in_progress", "pending_approval", nil), do: {:ok, "state_change"}
  defp event_for("in_progress", "pending_approval", "state_change"), do: {:ok, "state_change"}

  defp event_for("in_progress", "pending_approval", event),
    do: require_event(event, "state_change")

  defp event_for("in_progress", "cancelled", event), do: require_event(event, "cancelled")
  defp event_for("pending_approval", "closed", nil), do: {:ok, "state_change"}
  defp event_for("pending_approval", "closed", "state_change"), do: {:ok, "state_change"}
  defp event_for("pending_approval", "closed", "approved"), do: {:ok, "approved"}
  defp event_for("pending_approval", "closed", event), do: require_event(event, "approved")
  defp event_for("pending_approval", "in_progress", event), do: require_event(event, "rejected")
  defp event_for("pending_approval", "cancelled", event), do: require_event(event, "cancelled")
  defp event_for(from, to, _event), do: {:error, {:invalid_transition, from, to}}

  defp require_event(nil, event), do: {:ok, event}
  defp require_event(event, event), do: {:ok, event}
  defp require_event(other, event), do: {:error, {:invalid_transition_event, other, event}}
end
