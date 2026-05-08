defmodule Babs.Citizens.Tickets.MayorProposalReview do
  @moduledoc """
  Pure reduction and event construction for Phase 16 Mayor proposal review.
  """

  alias Babs.Citizens.Tickets.InspectionPolicy
  alias Babs.Citizens.Tickets.MayorPolicy
  alias Babs.Citizens.Tickets.MayorProposal

  @proposal_events ~w(mayor_proposal_received mayor_proposal_revised)
  @decision_events ~w(mayor_proposal_approved mayor_proposal_rejected)

  @spec from_history(map(), [map()]) :: :missing | {:ok, map()} | {:error, term()}
  def from_history(ticket, history) when is_list(history) do
    with {:ok, policy} <- policy(ticket) do
      case latest_proposal_event(history) do
        nil ->
          {:ok, %{status: :awaiting, policy: policy, proposal: nil, proposal_id: nil}}

        {event, index} ->
          with {:ok, proposal} <- normalize_event_proposal(ticket, policy, event) do
            decision = latest_decision_after(history, index, proposal["proposal_id"])

            {:ok,
             %{
               status: decision_status(decision),
               policy: policy,
               proposal: proposal,
               proposal_id: proposal["proposal_id"],
               revision_token: revision_token(event),
               source_event: event,
               decision: decision,
               feedback: decision && decision["feedback"]
             }}
          end
      end
    end
  end

  @spec revise_child(map(), [map()], String.t(), non_neg_integer(), map() | keyword(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def revise_child(ticket, history, proposal_id, child_index, attrs, opts \\ []) do
    with {:ok, state} <- pending_state(ticket, history, proposal_id, opts),
         {:ok, children} <- replace_child(state.proposal["children"], child_index, attrs),
         proposal <- Map.put(state.proposal, "children", children),
         {:ok, proposal} <- normalize_proposal(proposal, state.policy) do
      {:ok,
       proposal_event(ticket, "mayor_proposal_revised", proposal, opts, "edit_child", child_index)}
    else
      {:error, {:mayor_proposal, reason}} ->
        {:error, {:mayor_proposal_review, {:invalid_edit, {:mayor_proposal, reason}}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec remove_child(map(), [map()], String.t(), non_neg_integer(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def remove_child(ticket, history, proposal_id, child_index, opts \\ []) do
    with {:ok, state} <- pending_state(ticket, history, proposal_id, opts),
         {:ok, children} <- remove_child_at(state.proposal["children"], child_index),
         proposal <- Map.put(state.proposal, "children", children),
         {:ok, proposal} <- normalize_proposal(proposal, state.policy) do
      {:ok,
       proposal_event(
         ticket,
         "mayor_proposal_revised",
         proposal,
         opts,
         "remove_child",
         child_index
       )}
    else
      {:error, {:mayor_proposal, reason}} ->
        {:error, {:mayor_proposal_review, {:invalid_edit, {:mayor_proposal, reason}}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec approve(map(), [map()], String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def approve(ticket, history, proposal_id, opts \\ []) do
    with {:ok, state} <- pending_state(ticket, history, proposal_id, opts) do
      {:ok, proposal_event(ticket, "mayor_proposal_approved", state.proposal, opts)}
    end
  end

  @spec reject(map(), [map()], String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def reject(ticket, history, proposal_id, feedback, opts \\ []) do
    with {:ok, feedback} <- feedback(feedback),
         {:ok, state} <- pending_state(ticket, history, proposal_id, opts) do
      event =
        ticket
        |> proposal_event("mayor_proposal_rejected", state.proposal, opts)
        |> Map.put("feedback", feedback)

      {:ok, event}
    end
  end

  defp pending_state(ticket, history, proposal_id, opts) do
    with :ok <- ensure_non_terminal(ticket),
         {:ok, state} <- from_history(ticket, history),
         :ok <- ensure_has_proposal(state),
         :ok <- ensure_proposal_id(state.proposal_id, proposal_id),
         :ok <- ensure_revision(state, opts),
         :ok <- ensure_pending(state) do
      {:ok, state}
    end
  end

  defp policy(%{metadata: metadata}) do
    case MayorPolicy.from_metadata(metadata || %{}) do
      {:ok, policy} -> {:ok, policy}
      :missing -> :missing
      {:error, reason} -> {:error, {:mayor_proposal_review, {:invalid_policy, reason}}}
    end
  end

  defp latest_proposal_event(history) do
    history
    |> Enum.with_index()
    |> Enum.filter(fn {event, _index} -> event["event"] in @proposal_events end)
    |> List.last()
  end

  defp latest_decision_after(history, index, proposal_id) do
    history
    |> Enum.drop(index + 1)
    |> Enum.filter(fn event ->
      event["event"] in @decision_events and event["proposal_id"] == proposal_id
    end)
    |> List.last()
  end

  defp normalize_event_proposal(ticket, policy, event) do
    case event["proposal"] do
      proposal when is_map(proposal) ->
        with :ok <- ensure_event_proposal_id(event, proposal),
             {:ok, proposal} <- normalize_proposal(proposal, policy),
             :ok <- ensure_root_ticket(ticket, proposal) do
          {:ok, proposal}
        else
          {:error, reason} -> {:error, {:mayor_proposal_review, {:invalid_proposal, reason}}}
        end

      _value ->
        {:error, {:mayor_proposal_review, {:invalid_proposal, {:missing_proposal, event}}}}
    end
  end

  defp normalize_proposal(proposal, policy) do
    MayorProposal.normalize(proposal,
      max_children: policy["max_children"],
      allowed_roles: policy["allowed_roles"]
    )
  end

  defp ensure_event_proposal_id(%{"proposal_id" => id}, %{"proposal_id" => id}), do: :ok

  defp ensure_event_proposal_id(%{"proposal_id" => event_id}, %{"proposal_id" => proposal_id}),
    do: {:error, {:proposal_id_mismatch, event_id, proposal_id}}

  defp ensure_event_proposal_id(_event, _proposal), do: :ok

  defp ensure_root_ticket(%{id: id}, %{"root_ticket_id" => id}), do: :ok

  defp ensure_root_ticket(%{id: id}, %{"root_ticket_id" => root_id}),
    do: {:error, {:root_ticket_mismatch, id, root_id}}

  defp decision_status(nil), do: :pending
  defp decision_status(%{"event" => "mayor_proposal_approved"}), do: :approved
  defp decision_status(%{"event" => "mayor_proposal_rejected"}), do: :rejected
  defp decision_status(_event), do: :pending

  defp ensure_non_terminal(%{id: id, state: state}) when state in ["closed", "cancelled"],
    do: {:error, {:mayor_proposal_review, {:terminal_ticket, id, state}}}

  defp ensure_non_terminal(_ticket), do: :ok

  defp ensure_has_proposal(%{status: :awaiting}),
    do: {:error, {:mayor_proposal_review, :no_proposal}}

  defp ensure_has_proposal(_state), do: :ok

  defp ensure_proposal_id(expected, expected), do: :ok

  defp ensure_proposal_id(expected, actual),
    do: {:error, {:mayor_proposal_review, {:stale_proposal_id, expected, actual}}}

  defp ensure_revision(state, opts) do
    case Keyword.get(opts, :proposal_revision) do
      nil ->
        :ok

      "" ->
        :ok

      submitted when submitted == state.revision_token ->
        :ok

      submitted ->
        {:error,
         {:mayor_proposal_review, {:stale_proposal_revision, state.revision_token, submitted}}}
    end
  end

  defp ensure_pending(%{status: :pending}), do: :ok

  defp ensure_pending(%{status: status}),
    do: {:error, {:mayor_proposal_review, {:already_decided, status}}}

  defp replace_child(children, index, attrs) do
    with :ok <- ensure_child_index(children, index),
         {:ok, child} <-
           children
           |> Enum.at(index)
           |> apply_child_attrs(attrs) do
      {:ok, List.replace_at(children, index, child)}
    end
  end

  defp remove_child_at(children, index) do
    with :ok <- ensure_child_index(children, index),
         :ok <- ensure_not_last_child(children) do
      {:ok, List.delete_at(children, index)}
    end
  end

  defp ensure_child_index(children, index)
       when is_integer(index) and index >= 0 and index < length(children),
       do: :ok

  defp ensure_child_index(_children, index),
    do: {:error, {:mayor_proposal_review, {:invalid_child_index, index}}}

  defp ensure_not_last_child([_only]),
    do: {:error, {:mayor_proposal_review, {:invalid_edit, :empty_children}}}

  defp ensure_not_last_child(_children), do: :ok

  defp apply_child_attrs(child, attrs) do
    attrs = attr_map(attrs)

    child =
      child
      |> put_attr(attrs, "title")
      |> put_attr(attrs, "body")
      |> put_attr(attrs, "assignee_role")
      |> put_attr(attrs, "priority")

    apply_inspector(child, attrs)
  end

  defp attr_map(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp attr_map(attrs) when is_list(attrs) do
    attrs
    |> Enum.into(%{})
    |> attr_map()
  end

  defp put_attr(child, attrs, key) do
    if Map.has_key?(attrs, key), do: Map.put(child, key, Map.get(attrs, key)), else: child
  end

  defp apply_inspector(child, attrs) do
    case Map.get(attrs, "inspector") do
      nil ->
        {:ok, child}

      "user" ->
        metadata =
          child
          |> Map.get("metadata", %{})
          |> Map.delete("inspection")
          |> Map.delete(:inspection)

        {:ok,
         child
         |> Map.put("inspector", "user")
         |> Map.put("metadata", metadata)}

      "auto" ->
        case InspectionPolicy.normalize(%{"mode" => "auto", "roles" => ["inspector"]}) do
          {:ok, inspection} ->
            metadata =
              child
              |> Map.get("metadata", %{})
              |> Map.put("inspection", inspection)

            {:ok,
             child
             |> Map.put("inspector", "auto")
             |> Map.put("metadata", metadata)}

          {:error, reason} ->
            {:error, {:mayor_proposal_review, {:invalid_edit, reason}}}
        end

      value ->
        {:ok, Map.put(child, "inspector", value)}
    end
  end

  defp feedback(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, {:mayor_proposal_review, :empty_feedback}}
      trimmed -> {:ok, trimmed}
    end
  end

  defp feedback(_value), do: {:error, {:mayor_proposal_review, :empty_feedback}}

  defp proposal_event(ticket, event, proposal, opts, action \\ nil, child_index \\ nil) do
    %{
      "ts" => now(opts),
      "event" => event,
      "by" => by(opts),
      "ticket_id" => ticket.id,
      "proposal_id" => proposal["proposal_id"],
      "proposal" => proposal
    }
    |> put_optional("action", action)
    |> put_optional("child_index", child_index)
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp by(opts), do: Keyword.get(opts, :by, "user")
  defp now(opts), do: Keyword.get(opts, :now, DateTime.utc_now(:second) |> DateTime.to_iso8601())

  defp revision_token(event) do
    event
    |> Map.take(["event", "proposal_id", "proposal", "ts"])
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end
end
