defmodule Babs.Citizens.Tickets.Writer do
  @moduledoc """
  One lazy GenServer per Ticket id that serializes Babs-owned writes.
  """

  use GenServer

  alias Babs.Citizens.Citizen.Config, as: CitizenConfig
  alias Babs.Citizens.Catalog
  alias Babs.Citizens.DirectCli.Adapters
  alias Babs.Citizens.DirectCli.Runner, as: DirectRunner
  alias Babs.Citizens.ExecutionLock
  alias Babs.Citizens.ProviderSessions
  alias Babs.Citizens.Tickets.Conversation
  alias Babs.Citizens.Tickets.Error
  alias Babs.Citizens.Tickets.History
  alias Babs.Citizens.Tickets.Injector
  alias Babs.Citizens.Tickets.InspectionDecisionParser
  alias Babs.Citizens.Tickets.InspectionEvents
  alias Babs.Citizens.Tickets.InspectionQuorum
  alias Babs.Citizens.Tickets.InspectorSelector
  alias Babs.Citizens.Tickets.MayorChildTickets
  alias Babs.Citizens.Tickets.MayorProposalReview
  alias Babs.Citizens.Tickets.PromptAssembler
  alias Babs.Citizens.Tickets.ReplyCapture
  alias Babs.Citizens.Tickets.RoleRouter
  alias Babs.Citizens.Tickets.StateMachine
  alias Babs.Citizens.Tickets.Store
  alias Babs.Citizens.Tickets.Ticket
  alias Babs.Citizens.Tickets.TicketId
  alias Babs.Citizens.Tickets.TicketMarkdown
  alias Babs.Citizens.Tickets.TurnIds
  alias Babs.Citizens.Tickets.WriterSupervisor

  require Logger

  @idle_timeout 60_000
  @ticket_backends ~w(hardline direct_cli lazy_tmux)

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    root = Keyword.fetch!(opts, :tickets_root)
    GenServer.start_link(__MODULE__, opts, name: via(root, id))
  end

  def via(root, id), do: {:via, Registry, {Babs.Citizens.Tickets.WriterRegistry, {root, id}}}

  def create(pid, ticket, opts \\ []) do
    GenServer.call(pid, {:create, ticket, opts}, 30_000)
  end

  def comment(pid, id, attrs, opts \\ []) do
    GenServer.call(pid, {:comment, id, attrs, opts}, 30_000)
  end

  def assign(pid, id, slug, opts \\ []) do
    GenServer.call(pid, {:assign, id, slug, opts}, 30_000)
  end

  def assign_by_role(pid, id, opts \\ []) do
    GenServer.call(pid, {:assign_by_role, id, opts}, 30_000)
  end

  def unassign(pid, id, slug, opts \\ []) do
    GenServer.call(pid, {:unassign, id, slug, opts}, 30_000)
  end

  def transition(pid, id, to_state, event, opts \\ []) do
    GenServer.call(pid, {:transition, id, to_state, event, opts}, 30_000)
  end

  def approve(pid, id, opts \\ []) do
    GenServer.call(pid, {:approve, id, opts}, 30_000)
  end

  def reject(pid, id, feedback, opts \\ []) do
    GenServer.call(pid, {:reject, id, feedback, opts}, 30_000)
  end

  def append_history_events(pid, id, events, opts \\ []) do
    GenServer.call(pid, {:append_history_events, id, events, opts}, 30_000)
  end

  def revise_mayor_proposal_child(pid, id, proposal_id, child_index, attrs, opts \\ []) do
    GenServer.call(
      pid,
      {:revise_mayor_proposal_child, id, proposal_id, child_index, attrs, opts},
      30_000
    )
  end

  def remove_mayor_proposal_child(pid, id, proposal_id, child_index, opts \\ []) do
    GenServer.call(
      pid,
      {:remove_mayor_proposal_child, id, proposal_id, child_index, opts},
      30_000
    )
  end

  def approve_mayor_proposal(pid, id, proposal_id, opts \\ []) do
    GenServer.call(pid, {:approve_mayor_proposal, id, proposal_id, opts}, 30_000)
  end

  def reject_mayor_proposal(pid, id, proposal_id, feedback, opts \\ []) do
    GenServer.call(pid, {:reject_mayor_proposal, id, proposal_id, feedback, opts}, 30_000)
  end

  def request_inspection(pid, id, opts \\ []) do
    GenServer.call(pid, {:request_inspection, id, opts}, 30_000)
  end

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    root = Keyword.fetch!(opts, :tickets_root)
    cleanup_temp_files(root, id)
    {:ok, %{id: id, root: root, idle_ref: schedule_idle(opts)}}
  end

  @impl true
  def handle_call({:create, ticket, opts}, _from, state) do
    state = reset_idle(state, opts)

    result =
      with :ok <- write_markdown(state.root, ticket.id, TicketMarkdown.render(ticket)),
           :ok <- History.append(state.root, ticket.id, created_event(ticket)) do
        {:ok, ticket}
      end

    {:reply, result, state}
  end

  def handle_call({:comment, id, attrs, opts}, _from, state) do
    state = reset_idle(state, opts)
    path = TicketMarkdown.path(state.root, id)

    result =
      with {:ok, original} <- read_current(path, id),
           {:ok, ticket} <- Store.read_ticket(state.root, id, opts),
           {:ok, body} <- comment_body(attrs),
           {:ok, by} <- comment_by(attrs),
           :ok <- ensure_commentable(ticket),
           :ok <- run_before_write(path, opts),
           :ok <- detect_conflict(path, original, id),
           now <- now(opts),
           updated = %{ticket | updated_at: now},
           notify? <- Keyword.get(opts, :notify_assignees, true),
           turn <- comment_turn(ticket, attrs, now, by, notify?),
           history <- read_history_for_prompt(state.root, id),
           {:ok, comment} <-
             comment_with_inspection(ticket, updated, history, body, now, by, notify?, turn, opts),
           :ok <- validate_events(id, comment.events),
           :ok <- write_markdown(state.root, id, TicketMarkdown.render(comment.ticket)),
           :ok <- append_events(state.root, id, comment.events) do
        after_comment_append(state.root, comment, body, now, by, notify?, turn, opts)
      end

    {:reply, result, state}
  end

  def handle_call({:assign, id, slug, opts}, _from, state) do
    state = reset_idle(state, opts)
    path = TicketMarkdown.path(state.root, id)

    result =
      with {:ok, original} <- read_current(path, id),
           {:ok, ticket} <- Store.read_ticket(state.root, id, opts),
           {:ok, assigned} <- StateMachine.assign(ticket, slug) do
        case delivery_backend(slug, opts) do
          "direct_cli" = backend ->
            persist_assignment(state.root, path, original, assigned, slug, opts, backend)

          backend ->
            case Injector.prepare(slug, opts) do
              :ok ->
                persist_assignment(state.root, path, original, assigned, slug, opts, backend)

              {:error, reason} ->
                persist_assignment_failure(state.root, path, original, ticket, slug, reason, opts)
            end
        end
      end

    {:reply, result, state}
  end

  def handle_call({:assign_by_role, id, opts}, _from, state) do
    state = reset_idle(state, opts)
    {:reply, assign_by_role_with_retry(state.root, id, opts, 8), state}
  end

  def handle_call({:unassign, id, slug, opts}, _from, state) do
    state = reset_idle(state, opts)
    path = TicketMarkdown.path(state.root, id)

    result =
      with {:ok, original} <- read_current(path, id),
           {:ok, ticket} <- Store.read_ticket(state.root, id, opts),
           {:ok, updated} <- StateMachine.unassign(ticket, slug),
           :ok <- run_before_write(path, opts),
           :ok <- detect_conflict(path, original, id),
           now <- now(opts),
           by <- by(opts),
           updated <- %{updated | updated_at: now},
           :ok <- write_markdown(state.root, id, TicketMarkdown.render(updated)),
           :ok <- append_events(state.root, id, unassign_events(ticket, updated, slug, now, by)) do
        {:ok, %{ticket: updated}}
      end

    {:reply, result, state}
  end

  def handle_call({:transition, id, to_state, event, opts}, _from, state) do
    state = reset_idle(state, opts)
    path = TicketMarkdown.path(state.root, id)

    result =
      with {:ok, original} <- read_current(path, id),
           {:ok, ticket} <- Store.read_ticket(state.root, id, opts),
           :ok <- guard_phase11_transition(ticket, to_state, event),
           {:ok, updated, event_name} <- StateMachine.transition(ticket, to_state, event),
           :ok <- run_before_write(path, opts),
           :ok <- detect_conflict(path, original, id),
           now <- now(opts),
           by <- by(opts),
           updated <- %{updated | updated_at: now},
           :ok <- write_markdown(state.root, id, TicketMarkdown.render(updated)),
           :ok <-
             History.append(
               state.root,
               id,
               transition_event(event_name, ticket.state, updated.state, id, now, by)
             ) do
        {:ok, %{ticket: updated}}
      end

    {:reply, result, state}
  end

  def handle_call({:approve, id, opts}, _from, state) do
    state = reset_idle(state, opts)
    path = TicketMarkdown.path(state.root, id)

    result =
      with {:ok, original} <- read_current(path, id),
           {:ok, ticket} <- Store.read_ticket(state.root, id, opts),
           :ok <- require_assignees(ticket),
           {:ok, updated, "approved"} <- StateMachine.transition(ticket, "closed", "approved"),
           :ok <- run_before_write(path, opts),
           :ok <- detect_conflict(path, original, id),
           now <- now(opts),
           by <- by(opts),
           updated <- %{updated | updated_at: now},
           events <- approval_events(ticket, updated, now, by),
           :ok <- validate_events(id, events),
           :ok <- write_markdown(state.root, id, TicketMarkdown.render(updated)),
           :ok <- append_events(state.root, id, events) do
        {:ok, %{ticket: updated}}
      end

    {:reply, result, state}
  end

  def handle_call({:reject, id, feedback, opts}, _from, state) do
    state = reset_idle(state, opts)
    path = TicketMarkdown.path(state.root, id)

    result =
      with {:ok, original} <- read_current(path, id),
           {:ok, ticket} <- Store.read_ticket(state.root, id, opts),
           {:ok, feedback} <- reject_feedback(feedback),
           :ok <- require_assignees(ticket),
           {:ok, updated, "rejected"} <-
             StateMachine.transition(ticket, "in_progress", "rejected"),
           :ok <- run_before_write(path, opts),
           :ok <- detect_conflict(path, original, id),
           now <- now(opts),
           by <- by(opts),
           updated <- %{updated | updated_at: now},
           events <- rejection_events(ticket, updated, feedback, now, by),
           :ok <- validate_events(id, events),
           :ok <- write_markdown(state.root, id, TicketMarkdown.render(updated)),
           :ok <- append_events(state.root, id, events) do
        inject_feedback(state.root, updated, feedback, now, by, opts)
      end

    {:reply, result, state}
  end

  def handle_call({:append_history_events, id, events, opts}, _from, state) do
    state = reset_idle(state, opts)

    result =
      with :ok <- validate_events(id, events),
           :ok <- append_events(state.root, id, events) do
        :ok
      end

    {:reply, result, state}
  end

  def handle_call(
        {:revise_mayor_proposal_child, id, proposal_id, child_index, attrs, opts},
        _from,
        state
      ) do
    state = reset_idle(state, opts)

    result =
      proposal_review_action(state.root, id, opts, fn ticket, history, event_opts ->
        MayorProposalReview.revise_child(
          ticket,
          history,
          proposal_id,
          child_index,
          attrs,
          event_opts
        )
      end)

    {:reply, result, state}
  end

  def handle_call(
        {:remove_mayor_proposal_child, id, proposal_id, child_index, opts},
        _from,
        state
      ) do
    state = reset_idle(state, opts)

    result =
      proposal_review_action(state.root, id, opts, fn ticket, history, event_opts ->
        MayorProposalReview.remove_child(ticket, history, proposal_id, child_index, event_opts)
      end)

    {:reply, result, state}
  end

  def handle_call({:approve_mayor_proposal, id, proposal_id, opts}, _from, state) do
    state = reset_idle(state, opts)

    result = approve_mayor_proposal_with_children(state.root, id, proposal_id, opts)

    {:reply, result, state}
  end

  def handle_call({:reject_mayor_proposal, id, proposal_id, feedback, opts}, _from, state) do
    state = reset_idle(state, opts)

    result =
      proposal_review_action(state.root, id, opts, fn ticket, history, event_opts ->
        MayorProposalReview.reject(ticket, history, proposal_id, feedback, event_opts)
      end)

    {:reply, result, state}
  end

  def handle_call({:request_inspection, id, opts}, _from, state) do
    state = reset_idle(state, opts)

    result = request_inspection_once(state.root, id, opts)

    {:reply, result, state}
  end

  @impl true
  def handle_info({:idle_timeout, ref}, %{idle_ref: ref} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:idle_timeout, _stale_ref}, state) do
    {:noreply, state}
  end

  defp assign_by_role_with_retry(root, id, opts, retries_left) do
    case assign_by_role_once(root, id, opts) do
      {:error, {:execution_busy, _slug}} when retries_left > 0 ->
        assign_by_role_with_retry(root, id, opts, retries_left - 1)

      result ->
        result
    end
  end

  defp assign_by_role_once(root, id, opts) do
    path = TicketMarkdown.path(root, id)

    with {:ok, ticket} <- Store.read_ticket(root, id, opts),
         :ok <- ensure_role_routable(ticket),
         {:ok, %{slug: slug, role: role}} <-
           RoleRouter.resolve(ticket, Keyword.put(opts, :tickets_root, root)) do
      opts = Keyword.put(opts, :via_role, role)
      backend = delivery_backend(slug, opts)

      case backend do
        "direct_cli" ->
          persist_reserved_direct_assignment(root, path, id, slug, opts, backend)

        _backend ->
          persist_reserved_hardline_assignment(root, path, id, slug, opts, backend)
      end
    end
  end

  defp created_event(ticket) do
    %{
      "ts" => ticket.created_at,
      "event" => "created",
      "by" => ticket.assigner,
      "ticket_id" => ticket.id
    }
  end

  defp comment_event(ticket, now, by, body, turn) do
    %{
      "ts" => now,
      "event" => "comment",
      "by" => by,
      "ticket_id" => ticket.id,
      "body" => body
    }
    |> put_optional("message_id", turn.message_id)
    |> put_optional("turn_id", turn.turn_id)
    |> put_optional("attempt_id", turn.captured_attempt_id)
  end

  defp comment_events(ticket, body, now, by, notify?, turn, opts) do
    events =
      [comment_event(ticket, now, by, body, turn)] ++ turn_created_events(ticket, now, by, turn)

    events
    |> maybe_add_notification_attempts(ticket, now, by, notify?, turn, opts)
    |> maybe_add_captured_reply_event(ticket, now, by, notify?, turn)
  end

  defp comment_with_inspection(ticket, updated, history, body, now, by, notify?, turn, opts) do
    base_events = comment_events(ticket, body, now, by, notify?, turn, opts)

    case inspection_reply_effect(ticket, updated, history, base_events, body, now, by, turn) do
      {:ok, :none} ->
        {:ok, %{ticket: updated, events: base_events, after_append: :comment}}

      {:ok, effect} ->
        {:ok,
         %{
           ticket: effect.ticket,
           events: base_events ++ effect.events,
           after_append: effect.after_append
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp inspection_reply_effect(
         %{state: "pending_approval"} = ticket,
         updated,
         history,
         base_events,
         body,
         now,
         by,
         %{turn_id: turn_id, captured_attempt_id: attempt_id}
       )
       when is_binary(turn_id) and is_binary(attempt_id) do
    with {:ok, prompt} <- InspectionQuorum.match_prompt(history, by, turn_id, attempt_id),
         inspection_id <- prompt["inspection_id"],
         true <- InspectionQuorum.active_inspection?(history, inspection_id),
         false <- InspectionQuorum.completed?(history, inspection_id),
         false <-
           InspectionQuorum.terminal_recorded?(history, inspection_id, by, turn_id, attempt_id),
         {:ok, terminal_event} <-
           inspection_terminal_event(ticket.id, inspection_id, by, body, now, turn_id, attempt_id) do
      history_for_quorum = history ++ base_events ++ [terminal_event]

      with {:ok, reduction} <- InspectionQuorum.reduce(history_for_quorum, inspection_id) do
        apply_inspection_reduction(updated, terminal_event, reduction, now)
      end
    else
      :error -> {:ok, :none}
      true -> {:ok, :none}
      false -> {:ok, :none}
      {:error, reason} -> {:error, reason}
    end
  end

  defp inspection_reply_effect(_ticket, _updated, _history, _events, _body, _now, _by, _turn),
    do: {:ok, :none}

  defp inspection_terminal_event(ticket_id, inspection_id, by, body, now, turn_id, attempt_id) do
    case InspectionDecisionParser.parse(body) do
      {:ok, decision} ->
        InspectionEvents.decision(
          ticket_id,
          inspection_id,
          by,
          decision.decision,
          decision.summary,
          decision.findings,
          now: now,
          turn_id: turn_id,
          attempt_id: attempt_id
        )

      {:error, reason} ->
        InspectionEvents.failed(ticket_id, inspection_id, by, {:unparseable, reason},
          now: now,
          turn_id: turn_id,
          attempt_id: attempt_id
        )
    end
  end

  defp apply_inspection_reduction(ticket, terminal_event, :pending, _now) do
    {:ok,
     %{
       ticket: ticket,
       events: [terminal_event],
       after_append: :inspection_recorded
     }}
  end

  defp apply_inspection_reduction(ticket, terminal_event, :completed, _now) do
    {:ok,
     %{
       ticket: ticket,
       events: [terminal_event],
       after_append: :inspection_recorded
     }}
  end

  defp apply_inspection_reduction(ticket, terminal_event, {:approved, result}, now) do
    with {:ok, completed} <-
           InspectionEvents.completed(ticket.id, result.inspection_id, "approved", "all_pass",
             now: now
           ),
         {:ok, closed, "approved"} <- StateMachine.transition(ticket, "closed", "approved") do
      closed = %{closed | updated_at: now}

      {:ok,
       %{
         ticket: closed,
         events:
           [terminal_event, completed] ++
             inspection_transition_events(
               approval_events(ticket, closed, now, "system"),
               result.inspection_id
             ),
         after_append: {:inspection_completed, "approved"}
       }}
    end
  end

  defp apply_inspection_reduction(ticket, terminal_event, {:rejected, result}, now) do
    with {:ok, completed} <-
           InspectionEvents.completed(ticket.id, result.inspection_id, "rejected", "all_pass",
             now: now
           ),
         {:ok, in_progress, "rejected"} <-
           StateMachine.transition(ticket, "in_progress", "rejected") do
      in_progress = %{in_progress | updated_at: now}

      {:ok,
       %{
         ticket: in_progress,
         events:
           [terminal_event, completed] ++
             inspection_transition_events(
               rejection_events(ticket, in_progress, result.feedback, now, "system"),
               result.inspection_id
             ),
         after_append: {:feedback, result.feedback}
       }}
    end
  end

  defp apply_inspection_reduction(ticket, terminal_event, {:requires_human, result}, now) do
    with {:ok, completed} <-
           InspectionEvents.completed(
             ticket.id,
             result.inspection_id,
             "requires_human",
             "all_pass",
             now: now
           ) do
      {:ok,
       %{
         ticket: ticket,
         events: [terminal_event, completed],
         after_append: {:inspection_completed, "requires_human"}
       }}
    end
  end

  defp after_comment_append(
         root,
         %{after_append: :comment, ticket: ticket},
         body,
         now,
         by,
         notify?,
         turn,
         opts
       ) do
    if notify? do
      inject_comment(root, ticket, body, now, by, turn, opts)
    else
      {:ok, %{ticket: ticket, delivery: :comment_stored}}
    end
  end

  defp after_comment_append(
         root,
         %{after_append: {:feedback, feedback}, ticket: ticket},
         _body,
         now,
         _by,
         _notify?,
         _turn,
         opts
       ) do
    inject_feedback(root, ticket, feedback, now, "system", opts)
  end

  defp after_comment_append(
         _root,
         %{after_append: {:inspection_completed, result}, ticket: ticket},
         _body,
         _now,
         _by,
         _notify?,
         _turn,
         _opts
       ) do
    {:ok, %{ticket: ticket, delivery: {:inspection_completed, result}}}
  end

  defp after_comment_append(
         _root,
         %{after_append: :inspection_recorded, ticket: ticket},
         _body,
         _now,
         _by,
         _notify?,
         _turn,
         _opts
       ) do
    {:ok, %{ticket: ticket, delivery: :inspection_recorded}}
  end

  defp persist_assignment(root, path, original, assigned, slug, opts, backend) do
    now = now(opts)
    by = by(opts)
    assigned = %{assigned | updated_at: now}
    turn = assignment_turn(slug, now, backend)

    with :ok <-
           persist_assignment_start(
             root,
             path,
             original,
             assigned,
             slug,
             opts,
             backend,
             turn,
             now,
             by
           ),
         prompt <- Injector.prompt(assigned, slug) do
      deliver_assignment(root, assigned, slug, prompt, now, backend, turn, opts)
    end
  end

  defp persist_assignment_start(
         root,
         path,
         original,
         assigned,
         slug,
         opts,
         backend,
         turn,
         now,
         by
       ) do
    with :ok <- run_before_write(path, opts),
         :ok <- detect_conflict(path, original, assigned.id),
         :ok <- write_markdown(root, assigned.id, TicketMarkdown.render(assigned)),
         :ok <-
           append_events(
             root,
             assigned.id,
             assignment_events(
               assigned,
               slug,
               now,
               by,
               backend,
               turn,
               Keyword.get(opts, :via_role)
             )
           ) do
      :ok
    end
  end

  defp persist_reserved_hardline_assignment(root, path, id, slug, opts, backend) do
    ExecutionLock.with_lock(slug, fn ->
      with {:ok, original} <- read_current(path, id),
           {:ok, ticket} <- Store.read_ticket(root, id, opts),
           :ok <- ensure_role_routable(ticket),
           {:ok, assigned} <- StateMachine.assign(ticket, slug),
           :ok <- Injector.prepare(slug, opts) do
        now = now(opts)
        by = by(opts)
        assigned = %{assigned | updated_at: now}
        turn = assignment_turn(slug, now, backend)

        with :ok <-
               persist_assignment_start(
                 root,
                 path,
                 original,
                 assigned,
                 slug,
                 opts,
                 backend,
                 turn,
                 now,
                 by
               ),
             prompt <- Injector.prompt(assigned, slug) do
          deliver_reserved_hardline_assignment(root, assigned, slug, prompt, now, opts)
        end
      end
    end)
  end

  defp persist_reserved_direct_assignment(root, path, id, slug, opts, backend) do
    now = now(opts)
    by = by(opts)
    turn = assignment_turn(slug, now, backend)

    with {:ok, ticket} <- Store.read_ticket(root, id, opts),
         {:ok, config} <- direct_config(slug, opts) do
      preflight = fn direct_turn ->
        prepare_reserved_direct_assignment(
          root,
          path,
          id,
          slug,
          opts,
          backend,
          turn,
          now,
          by,
          direct_turn
        )
      end

      direct_opts =
        opts
        |> Keyword.put(:before_start, preflight)
        |> Keyword.put(:suppress_busy_events, true)

      case DirectRunner.start_turn(
             direct_turn(root, ticket, slug, "", turn, config, nil),
             direct_opts
           ) do
        :ok ->
          with {:ok, assigned} <- Store.read_ticket(root, id, opts),
               :ok <- History.append(root, id, injected_event(assigned, slug, now)) do
            {:ok, %{ticket: assigned, delivery: {:injected, slug}}}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp prepare_reserved_direct_assignment(
         root,
         path,
         id,
         slug,
         opts,
         backend,
         turn,
         now,
         by,
         direct_turn
       ) do
    with {:ok, original} <- read_current(path, id),
         {:ok, ticket} <- Store.read_ticket(root, id, opts),
         :ok <- ensure_role_routable(ticket),
         {:ok, assigned} <- StateMachine.assign(ticket, slug) do
      assigned = %{assigned | updated_at: now}
      prompt = Injector.prompt(assigned, slug)

      with :ok <-
             persist_assignment_start(
               root,
               path,
               original,
               assigned,
               slug,
               opts,
               backend,
               turn,
               now,
               by
             ) do
        {:ok, %{direct_turn | prompt: prompt}}
      end
    end
  end

  defp deliver_reserved_hardline_assignment(root, assigned, slug, prompt, now, opts) do
    with :ok <- Injector.inject(slug, prompt, opts),
         :ok <- History.append(root, assigned.id, injected_event(assigned, slug, now)) do
      track_reply_capture(root, assigned, slug, now, opts)
      {:ok, %{ticket: assigned, delivery: {:injected, slug}}}
    else
      {:error, reason} ->
        _ignored =
          History.append(root, assigned.id, injection_failed_event(assigned, slug, now, reason))

        {:error, reason}
    end
  end

  defp deliver_assignment(root, assigned, slug, prompt, now, "direct_cli", turn, opts) do
    case deliver_direct_turn(root, assigned, slug, prompt, turn, opts) do
      :ok ->
        with :ok <- History.append(root, assigned.id, injected_event(assigned, slug, now)) do
          {:ok, %{ticket: assigned, delivery: {:injected, slug}}}
        end

      {:error, reason} ->
        _ignored =
          History.append(root, assigned.id, injection_failed_event(assigned, slug, now, reason))

        {:error, reason}
    end
  end

  defp deliver_assignment(root, assigned, slug, prompt, now, _backend, _turn, opts) do
    ExecutionLock.with_lock(slug, fn ->
      with :ok <- Injector.inject(slug, prompt, opts),
           :ok <- History.append(root, assigned.id, injected_event(assigned, slug, now)) do
        track_reply_capture(root, assigned, slug, now, opts)
        {:ok, %{ticket: assigned, delivery: {:injected, slug}}}
      end
    end)
    |> case do
      {:ok, %{ticket: _assigned, delivery: {:injected, _slug}}} = result ->
        result

      {:error, reason} ->
        _ignored =
          History.append(root, assigned.id, injection_failed_event(assigned, slug, now, reason))

        {:error, reason}
    end
  end

  defp persist_assignment_failure(root, path, original, ticket, slug, reason, opts) do
    with :ok <- run_before_write(path, opts),
         :ok <- detect_conflict(path, original, ticket.id),
         :ok <-
           History.append(
             root,
             ticket.id,
             assignment_failed_event(ticket, slug, now(opts), reason)
           ) do
      {:error, reason}
    end
  end

  defp assignment_events(ticket, slug, now, by, via_role) do
    [
      ticket
      |> assigned_event(slug, now, by)
      |> put_optional("via_role", via_role)
      |> put_optional("body", role_assignment_body(slug, via_role)),
      transition_event("state_change", "open", "in_progress", ticket.id, now, by),
      %{
        "ts" => now,
        "event" => "injection_attempted",
        "by" => "system",
        "ticket_id" => ticket.id,
        "injected_to" => [slug]
      }
    ]
  end

  defp assignment_events(ticket, slug, now, by, "direct_cli", turn, via_role) do
    ticket = %{ticket | assignees: [slug]}

    assignment_events(ticket, slug, now, by, via_role) ++
      turn_created_events(ticket, now, by, turn) ++
      [turn_delivery_attempted_event(ticket, now, turn, slug, delivery_backend: "direct_cli")]
  end

  defp assignment_events(ticket, slug, now, by, _backend, _turn, via_role),
    do: assignment_events(ticket, slug, now, by, via_role)

  defp assigned_event(ticket, slug, now, by) do
    %{
      "ts" => now,
      "event" => "assigned",
      "by" => by,
      "ticket_id" => ticket.id,
      "to" => [slug]
    }
  end

  defp role_assignment_body(_slug, nil), do: nil
  defp role_assignment_body(slug, via_role), do: "assigned to #{slug} via role #{via_role}"

  defp unassign_events(original, updated, slug, now, by) do
    events = [
      %{
        "ts" => now,
        "event" => "unassigned",
        "by" => by,
        "ticket_id" => original.id,
        "from" => [slug]
      }
    ]

    if original.state != updated.state do
      events ++
        [transition_event("state_change", original.state, updated.state, original.id, now, by)]
    else
      events
    end
  end

  defp approval_events(original, updated, now, by) do
    [
      transition_event("approved", original.state, updated.state, original.id, now, by),
      transition_event("state_change", original.state, updated.state, original.id, now, by)
    ]
  end

  defp rejection_events(original, updated, feedback, now, by) do
    [
      transition_event("rejected", original.state, updated.state, original.id, now, by)
      |> Map.put("feedback", feedback),
      transition_event("state_change", original.state, updated.state, original.id, now, by),
      %{
        "ts" => now,
        "event" => "feedback_injection_attempted",
        "by" => by,
        "ticket_id" => original.id,
        "injected_to" => original.assignees,
        "kind" => "rejection_feedback"
      }
    ]
  end

  defp transition_event(event_name, from, to, id, now, by) do
    %{
      "ts" => now,
      "event" => event_name,
      "by" => by,
      "ticket_id" => id,
      "from" => from,
      "to" => to
    }
  end

  defp injected_event(ticket, slug, now) do
    %{
      "ts" => now,
      "event" => "injected",
      "by" => "system",
      "ticket_id" => ticket.id,
      "injected_to" => [slug]
    }
  end

  defp assignment_failed_event(ticket, slug, now, reason) do
    %{
      "ts" => now,
      "event" => "assignment_failed",
      "by" => "system",
      "ticket_id" => ticket.id,
      "to" => [slug],
      "error" => error_text(reason)
    }
  end

  defp injection_failed_event(ticket, slug, now, reason) do
    %{
      "ts" => now,
      "event" => "injection_failed",
      "by" => "system",
      "ticket_id" => ticket.id,
      "injected_to" => [slug],
      "error" => error_text(reason)
    }
  end

  defp feedback_injected_event(ticket, slug, now, by) do
    %{
      "ts" => now,
      "event" => "feedback_injected",
      "by" => by,
      "ticket_id" => ticket.id,
      "injected_to" => [slug],
      "kind" => "rejection_feedback"
    }
  end

  defp feedback_injection_failed_event(ticket, slug, now, by, reason) do
    %{
      "ts" => now,
      "event" => "feedback_injection_failed",
      "by" => by,
      "ticket_id" => ticket.id,
      "injected_to" => [slug],
      "kind" => "rejection_feedback",
      "error" => error_text(reason)
    }
  end

  defp turn_created_events(_ticket, _now, _by, %{new_turn?: false}), do: []

  defp turn_created_events(ticket, now, by, %{new_turn?: true} = turn) do
    [
      %{
        "ts" => now,
        "event" => "turn_created",
        "by" => by,
        "ticket_id" => ticket.id,
        "turn_id" => turn.turn_id,
        "prompt_message_id" => turn.message_id,
        "to" => ticket.assignees
      }
      |> put_optional("parent_turn_id", turn.parent_turn_id)
    ]
  end

  defp maybe_add_notification_attempts(events, ticket, now, by, true, turn, opts) do
    legacy_events =
      if ticket.assignees == [],
        do: [],
        else: [comment_notification_attempted_event(ticket, now, by)]

    turn_events =
      if is_binary(turn.turn_id) and map_size(turn.attempt_ids) > 0 do
        Enum.map(ticket.assignees, fn slug ->
          turn_delivery_attempted_event(ticket, now, turn, slug, opts)
        end)
      else
        []
      end

    events ++ legacy_events ++ turn_events
  end

  defp maybe_add_notification_attempts(events, _ticket, _now, _by, _notify?, _turn, _opts),
    do: events

  defp maybe_add_captured_reply_event(events, ticket, now, by, false, %{
         turn_id: turn_id,
         message_id: message_id,
         captured_attempt_id: attempt_id
       })
       when is_binary(turn_id) and is_binary(attempt_id) do
    events ++
      [
        %{
          "ts" => now,
          "event" => "turn_reply_captured",
          "by" => "system",
          "ticket_id" => ticket.id,
          "turn_id" => turn_id,
          "attempt_id" => attempt_id,
          "by_citizen" => by,
          "message_id" => message_id
        }
      ]
  end

  defp maybe_add_captured_reply_event(events, _ticket, _now, _by, _notify?, _turn), do: events

  defp turn_delivery_attempted_event(ticket, now, turn, slug, opts) do
    %{
      "ts" => now,
      "event" => "turn_delivery_attempted",
      "by" => "system",
      "ticket_id" => ticket.id,
      "turn_id" => turn.turn_id,
      "attempt_id" => Map.fetch!(turn.attempt_ids, slug),
      "to" => slug,
      "backend" => delivery_backend(slug, opts),
      "status" => "queued"
    }
  end

  defp turn_delivered_event(ticket, slug, now, turn, backend) do
    %{
      "ts" => now,
      "event" => "turn_delivered",
      "by" => "system",
      "ticket_id" => ticket.id,
      "turn_id" => turn.turn_id,
      "attempt_id" => Map.fetch!(turn.attempt_ids, slug),
      "to" => slug,
      "backend" => backend
    }
  end

  defp comment_notification_attempted_event(ticket, now, by) do
    %{
      "ts" => now,
      "event" => "comment_notification_attempted",
      "by" => by,
      "ticket_id" => ticket.id,
      "injected_to" => ticket.assignees,
      "kind" => "ticket_comment"
    }
  end

  defp comment_notified_event(ticket, slug, now, by) do
    %{
      "ts" => now,
      "event" => "comment_notified",
      "by" => by,
      "ticket_id" => ticket.id,
      "injected_to" => [slug],
      "kind" => "ticket_comment"
    }
  end

  defp comment_notification_failed_event(ticket, slug, now, by, reason) do
    %{
      "ts" => now,
      "event" => "comment_notification_failed",
      "by" => by,
      "ticket_id" => ticket.id,
      "injected_to" => [slug],
      "kind" => "ticket_comment",
      "error" => error_text(reason)
    }
  end

  defp inject_comment(root, ticket, body, now, by, turn, opts) do
    conversation =
      root
      |> read_history_for_prompt(ticket.id)
      |> Conversation.from_history()

    results =
      Enum.map(ticket.assignees, fn slug ->
        {slug, deliver_comment(root, ticket, slug, body, now, by, turn, opts, conversation)}
      end)

    ok_slugs =
      results
      |> Enum.filter(fn {_slug, result} -> result == :ok end)
      |> Enum.map(fn {slug, :ok} -> slug end)

    failures =
      results
      |> Enum.filter(fn {_slug, result} -> match?({:error, _reason}, result) end)
      |> Enum.map(fn {slug, {:error, reason}} -> {slug, reason} end)

    if failures == [] do
      {:ok, %{ticket: ticket, delivery: {:comment_notified, ok_slugs}}}
    else
      {:ok, %{ticket: ticket, delivery: {:comment_notification_failed, ok_slugs, failures}}}
    end
  end

  defp deliver_comment(root, ticket, slug, body, now, by, turn, opts, conversation) do
    case delivery_backend(slug, opts) do
      "direct_cli" ->
        full_prompt = Injector.comment_prompt(ticket, slug, by, body, conversation)
        prompt = direct_comment_prompt(ticket, slug, body, opts, full_prompt)
        deliver_direct_comment(root, ticket, slug, prompt, full_prompt, turn, opts)

      "lazy_tmux" ->
        prompt = Injector.comment_prompt(ticket, slug, by, body, conversation)
        deliver_hardline_comment(root, ticket, slug, prompt, now, by, turn, opts)

      _backend ->
        prompt = Injector.comment_prompt(ticket, slug, by, body, conversation)
        deliver_hardline_comment(root, ticket, slug, prompt, now, by, turn, opts)
    end
  end

  defp direct_comment_prompt(ticket, slug, body, opts, full_prompt) do
    if compact_direct_comment?(ticket, slug, opts) do
      PromptAssembler.compact_follow_up_prompt(ticket, latest_message: body)
    else
      full_prompt
    end
  end

  defp compact_direct_comment?(ticket, slug, opts) do
    with {:ok, config} <- direct_config(slug, opts),
         {:ok, adapter} <- direct_adapter(config, opts),
         session when not is_nil(session) <-
           ProviderSessions.get_active(slug, ticket.id, adapter.provider(), "direct_cli") do
      active_resumable_session?(session)
    else
      _other -> false
    end
  rescue
    _error -> false
  catch
    :exit, _reason -> false
  end

  defp direct_adapter(config, opts) do
    case Keyword.fetch(opts, :adapter) do
      {:ok, adapter} -> {:ok, adapter}
      :error -> Adapters.resolve(config, opts)
    end
  end

  defp active_resumable_session?(session) do
    Map.get(session, :status) == "active" and
      session
      |> Map.get(:provider_session_id)
      |> case do
        value when is_binary(value) -> String.trim(value) != ""
        _other -> false
      end
  end

  defp deliver_direct_comment(root, ticket, slug, prompt, fallback_prompt, turn, opts) do
    deliver_direct_turn(root, ticket, slug, prompt, turn, opts, fallback_prompt)
  end

  defp deliver_direct_turn(root, ticket, slug, prompt, turn, opts, fallback_prompt \\ nil) do
    with {:ok, config} <- direct_config(slug, opts),
         :ok <-
           DirectRunner.start_turn(
             direct_turn(root, ticket, slug, prompt, turn, config, fallback_prompt),
             opts
           ) do
      :ok
    else
      {:error, {:execution_busy, _slug} = reason} ->
        {:error, reason}

      {:error, reason} ->
        _ignored =
          append_events(
            root,
            ticket.id,
            turn_delivery_failed_events(ticket, slug, now(opts), turn, reason, "direct_cli")
          )

        {:error, reason}
    end
  end

  defp direct_turn(root, ticket, slug, prompt, turn, config, fallback_prompt) do
    %{
      root: root,
      ticket_id: ticket.id,
      slug: slug,
      turn_id: turn.turn_id,
      attempt_id: Map.fetch!(turn.attempt_ids, slug),
      backend: "direct_cli",
      prompt: prompt,
      config: config,
      fallback: :hardline
    }
    |> maybe_put_fallback_prompt(fallback_prompt)
  end

  defp maybe_put_fallback_prompt(turn, prompt) when is_binary(prompt) and prompt != "" do
    Map.put(turn, :fallback_prompt, prompt)
  end

  defp maybe_put_fallback_prompt(turn, _prompt), do: turn

  defp deliver_hardline_comment(root, ticket, slug, prompt, now, by, turn, opts) do
    backend = delivery_backend(slug, opts)

    ExecutionLock.with_lock(slug, fn ->
      with :ok <- Injector.prepare(slug, opts),
           :ok <- Injector.inject(slug, prompt, opts),
           :ok <-
             append_events(
               root,
               ticket.id,
               [comment_notified_event(ticket, slug, now, by)] ++
                 turn_delivered_events(ticket, slug, now, turn, backend)
             ) do
        track_reply_capture(root, ticket, slug, now, opts, turn)
        :ok
      end
    end)
    |> case do
      :ok ->
        :ok

      {:error, reason} ->
        _ignored =
          append_events(
            root,
            ticket.id,
            [comment_notification_failed_event(ticket, slug, now, by, reason)] ++
              turn_delivery_failed_events(ticket, slug, now, turn, reason, backend)
          )

        {:error, reason}
    end
  end

  defp inject_feedback(root, ticket, feedback, now, by, opts) do
    failures =
      ticket.assignees
      |> Enum.map(fn slug ->
        {slug, deliver_feedback(root, ticket, slug, feedback, now, by, opts)}
      end)
      |> Enum.filter(fn {_slug, result} -> match?({:error, _reason}, result) end)
      |> Enum.map(fn {slug, {:error, reason}} -> {slug, reason} end)

    if failures == [] do
      {:ok, %{ticket: ticket, delivery: {:feedback_injected, ticket.assignees}}}
    else
      {:error, {:feedback_injection_failed, ticket.id, failures}}
    end
  end

  defp deliver_feedback(root, ticket, slug, feedback, now, by, opts) do
    prompt = Injector.feedback_prompt(ticket, slug, feedback)

    case delivery_backend(slug, opts) do
      "direct_cli" ->
        deliver_direct_feedback(root, ticket, slug, prompt, now, by, opts)

      _backend ->
        deliver_hardline_feedback(root, ticket, slug, prompt, now, by, opts)
    end
  end

  defp deliver_direct_feedback(root, ticket, slug, prompt, now, by, opts) do
    turn = single_slug_turn(slug, now)
    ticket = %{ticket | assignees: [slug]}

    with :ok <-
           append_events(
             root,
             ticket.id,
             turn_created_events(ticket, now, by, turn) ++
               [
                 turn_delivery_attempted_event(ticket, now, turn, slug,
                   delivery_backend: "direct_cli"
                 )
               ]
           ),
         :ok <- deliver_direct_turn(root, ticket, slug, prompt, turn, opts),
         :ok <- History.append(root, ticket.id, feedback_injected_event(ticket, slug, now, by)) do
      :ok
    else
      {:error, reason} ->
        _ignored =
          History.append(
            root,
            ticket.id,
            feedback_injection_failed_event(ticket, slug, now, by, reason)
          )

        {:error, reason}
    end
  end

  defp deliver_hardline_feedback(root, ticket, slug, prompt, now, by, opts) do
    ExecutionLock.with_lock(slug, fn ->
      with :ok <- Injector.prepare(slug, opts),
           :ok <- Injector.inject(slug, prompt, opts),
           :ok <- History.append(root, ticket.id, feedback_injected_event(ticket, slug, now, by)) do
        track_reply_capture(root, ticket, slug, now, opts)
        :ok
      end
    end)
    |> case do
      :ok ->
        :ok

      {:error, reason} ->
        _ignored =
          History.append(
            root,
            ticket.id,
            feedback_injection_failed_event(ticket, slug, now, by, reason)
          )

        {:error, reason}
    end
  end

  defp assignment_turn(slug, now, "direct_cli"), do: single_slug_turn(slug, now)
  defp assignment_turn(_slug, _now, _backend), do: %{new_turn?: false}

  defp single_slug_turn(slug, now) do
    %{
      turn_id: TurnIds.generate!(:turn, now),
      message_id: TurnIds.generate!(:message, now),
      captured_attempt_id: nil,
      parent_turn_id: nil,
      attempt_ids: %{slug => TurnIds.generate!(:attempt, now)},
      new_turn?: true
    }
  end

  defp append_events(root, id, events) do
    Enum.reduce_while(events, :ok, fn event, :ok ->
      case History.append(root, id, event) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp proposal_review_action(root, id, opts, fun) do
    with {:ok, ticket} <- Store.read_ticket(root, id, opts),
         {:ok, history} <- History.read(root, id),
         event_opts <- proposal_event_opts(opts),
         {:ok, event} <- fun.(ticket, history, event_opts),
         :ok <- validate_events(id, [event]),
         :ok <- append_events(root, id, [event]) do
      {:ok, %{event: event}}
    end
  end

  defp approve_mayor_proposal_with_children(root, id, proposal_id, opts) do
    with {:ok, ticket} <- Store.read_ticket(root, id, opts),
         {:ok, history} <- History.read(root, id),
         {:ok, state} <- MayorProposalReview.from_history(ticket, history),
         :ok <- ensure_materialized_proposal_id(state, proposal_id),
         :ok <- ensure_materialized_proposal_revision(state, opts) do
      case state.children_created do
        created when is_map(created) ->
          append_missing_mayor_approval(root, ticket, history, state, proposal_id, created, opts)

        _not_created ->
          materialize_mayor_children(root, ticket, history, state, proposal_id, opts)
      end
    end
  end

  defp append_missing_mayor_approval(
         _root,
         _ticket,
         _history,
         %{decision: decision},
         _proposal_id,
         created,
         _opts
       )
       when is_map(decision) do
    {:ok,
     %{
       event: decision,
       children_created: created,
       already_materialized?: true
     }}
  end

  defp append_missing_mayor_approval(root, ticket, history, _state, proposal_id, created, opts) do
    event_opts = proposal_event_opts(opts)

    with {:ok, approval} <- MayorProposalReview.approve(ticket, history, proposal_id, event_opts),
         :ok <- validate_events(ticket.id, [approval]),
         :ok <- append_events(root, ticket.id, [approval]) do
      {:ok,
       %{
         event: approval,
         children_created: created,
         already_materialized?: true
       }}
    end
  end

  defp materialize_mayor_children(root, ticket, history, state, proposal_id, opts) do
    event_opts = proposal_event_opts(opts)

    with {:ok, approval} <- MayorProposalReview.approve(ticket, history, proposal_id, event_opts),
         {:ok, plan} <- MayorChildTickets.plan(ticket, state),
         preflight_children_created <-
           MayorChildTickets.preflight_children_created_event(ticket, plan, event_opts),
         :ok <- validate_events(ticket.id, [preflight_children_created, approval]),
         {:ok, created_children} <- create_or_recover_mayor_children(root, plan, opts) do
      append_materialized_mayor_children(
        root,
        ticket,
        plan,
        created_children,
        approval,
        event_opts,
        opts
      )
    else
      {:error, {:mayor_child_tickets, _reason}} = error ->
        error

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp append_materialized_mayor_children(
         root,
         ticket,
         plan,
         created_children,
         approval,
         event_opts,
         opts
       ) do
    routed_children = route_mayor_children(root, created_children, opts)

    children_created =
      MayorChildTickets.children_created_event(ticket, plan, routed_children, event_opts)

    events = [children_created, approval]

    with :ok <- append_events(root, ticket.id, events) do
      {:ok, %{event: approval, children_created: children_created}}
    end
  end

  defp ensure_materialized_proposal_id(%{proposal_id: proposal_id}, proposal_id), do: :ok

  defp ensure_materialized_proposal_id(%{proposal_id: expected}, actual),
    do: {:error, {:mayor_proposal_review, {:stale_proposal_id, expected, actual}}}

  defp ensure_materialized_proposal_revision(%{revision_token: expected}, opts) do
    case Keyword.get(opts, :proposal_revision) do
      nil -> :ok
      ^expected -> :ok
      actual -> {:error, {:mayor_proposal_review, {:stale_proposal_revision, expected, actual}}}
    end
  end

  defp create_or_recover_mayor_children(root, plan, opts) do
    case recover_mayor_children(root, plan, opts) do
      {:ok, []} -> create_mayor_children(root, plan, opts)
      {:ok, children} -> {:ok, children}
      {:error, _reason} = error -> error
    end
  end

  defp recover_mayor_children(root, plan, opts) do
    with {:ok, existing} <- existing_mayor_children(root, plan, opts) do
      expected_count = length(plan.children)

      cond do
        map_size(existing) == 0 ->
          {:ok, []}

        map_size(existing) == expected_count ->
          {:ok,
           Enum.map(plan.children, &%{child: &1, ticket: Map.fetch!(existing, &1.child_index)})}

        true ->
          existing_ids =
            existing
            |> Map.values()
            |> Enum.map(& &1.id)
            |> Enum.sort()

          {:error,
           {:mayor_child_tickets, {:partial_child_write, existing_ids, :missing_root_marker}}}
      end
    end
  end

  defp existing_mayor_children(root, plan, opts) do
    root
    |> Path.join("T-*.md")
    |> Path.wildcard()
    |> Enum.reduce_while({:ok, %{}}, fn path, {:ok, acc} ->
      id = Path.basename(path, ".md")

      case existing_mayor_child(root, id, plan, opts) do
        {:ok, nil} ->
          {:cont, {:ok, acc}}

        {:ok, ticket} ->
          {:cont, {:ok, Map.put(acc, materialized_child_index(ticket), ticket)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp existing_mayor_child(root, id, plan, opts) do
    with {:ok, ticket} <- Store.read_ticket(root, id, opts),
         true <- materialized_child?(ticket, plan),
         :ok <- ensure_materialized_child_history(root, ticket) do
      {:ok, ticket}
    else
      false ->
        {:ok, nil}

      {:error, {:not_found, _id}} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, {:mayor_child_tickets, {:unrecoverable_child_history, id, reason}}}
    end
  end

  defp materialized_child?(%Ticket{} = ticket, plan) do
    materialization = metadata_value(ticket.metadata, "mayor_materialization")

    with true <- ticket.parent_ticket == plan.root_ticket_id,
         %{} <- materialization,
         true <- metadata_value(materialization, "proposal_id") == plan.proposal_id,
         index when is_integer(index) <- metadata_value(materialization, "child_index"),
         true <- Enum.any?(plan.children, &(&1.child_index == index)) do
      true
    else
      _not_match -> false
    end
  end

  defp materialized_child_index(%Ticket{} = ticket) do
    ticket.metadata
    |> metadata_value("mayor_materialization")
    |> metadata_value("child_index")
  end

  defp ensure_materialized_child_history(root, %Ticket{} = ticket) do
    case History.read(root, ticket.id) do
      {:ok, history} ->
        if Enum.any?(history, &(&1["event"] == "created" and &1["ticket_id"] == ticket.id)) do
          :ok
        else
          {:error, {:invalid_history, {ticket.id, 0, :missing_created_event}}}
        end

      {:error, {:invalid_history, {id, 0, :missing_history}}} when id == ticket.id ->
        History.append(root, ticket.id, created_event(ticket))

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp metadata_value(map, key) when is_map(map) do
    atom_key =
      try do
        String.to_existing_atom(key)
      rescue
        ArgumentError -> nil
      end

    Map.get(map, key) || (atom_key && Map.get(map, atom_key))
  end

  defp metadata_value(_value, _key), do: nil

  defp create_mayor_children(root, plan, opts) do
    plan.children
    |> Enum.reduce_while({:ok, []}, fn child, {:ok, acc} ->
      case create_mayor_child(root, child, opts) do
        {:ok, ticket} ->
          {:cont, {:ok, [%{child: child, ticket: ticket} | acc]}}

        {:error, reason} ->
          created_ids =
            acc
            |> Enum.reverse()
            |> Enum.map(& &1.ticket.id)

          {:halt, {:error, {:mayor_child_tickets, {:partial_child_write, created_ids, reason}}}}
      end
    end)
    |> case do
      {:ok, children} -> {:ok, Enum.reverse(children)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_mayor_child(root, child, opts) do
    case TicketId.claim_next(root, opts) do
      {:ok, id, path} ->
        case persist_mayor_child(root, id, path, child, opts) do
          {:ok, ticket} ->
            {:ok, ticket}

          {:error, _reason} = error ->
            cleanup_empty_claim(path)
            error
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp persist_mayor_child(root, id, path, child, opts) do
    with ticket <- child_ticket(id, path, child.attrs, opts),
         {:ok, ticket} <- normalize_ticket(ticket, opts),
         {:ok, pid} <-
           WriterSupervisor.start_writer(ticket.id, Keyword.put(opts, :tickets_root, root)),
         {:ok, ticket} <- __MODULE__.create(pid, ticket, opts) do
      {:ok, ticket}
    end
  end

  defp child_ticket(id, path, attrs, opts) do
    now = now(opts)

    %Ticket{
      id: id,
      type: attrs.type,
      state: attrs.state,
      assigner: attrs.assigner,
      assignees: attrs.assignees,
      assignee_role: attrs.assignee_role,
      inspector: attrs.inspector,
      priority: attrs.priority,
      parent_ticket: attrs.parent_ticket,
      created_at: now,
      updated_at: now,
      metadata: attrs.metadata,
      title: attrs.title,
      body: attrs.body,
      path: path,
      warnings: []
    }
  end

  defp normalize_ticket(ticket, opts) do
    case TicketMarkdown.parse(TicketMarkdown.render(ticket),
           path: ticket.path,
           known_citizens: Keyword.get(opts, :known_citizens)
         ) do
      {:ok, ticket} -> {:ok, ticket}
      {:error, reason} -> {:error, reason}
    end
  end

  defp cleanup_empty_claim(path) do
    case File.read(path) do
      {:ok, ""} -> File.rm(path)
      _result -> :ok
    end
  end

  defp route_mayor_children(root, created_children, opts) do
    Enum.map(created_children, fn %{child: child, ticket: ticket} ->
      routing = route_mayor_child(root, ticket, child, opts)

      %{
        child_index: child.child_index,
        ticket_id: ticket.id,
        title: ticket.title,
        priority: ticket.priority,
        inspector: ticket.inspector,
        assignee_role: ticket.assignee_role,
        routing: routing
      }
    end)
  end

  defp route_mayor_child(_root, _ticket, %{route?: false}, _opts) do
    %{"status" => "not_requested"}
  end

  defp route_mayor_child(_root, %Ticket{assignees: assignees}, %{route?: true}, _opts)
       when is_list(assignees) and assignees != [] do
    %{"status" => "assigned", "assignees" => assignees}
  end

  defp route_mayor_child(root, ticket, %{route?: true}, opts) do
    with {:ok, pid} <-
           WriterSupervisor.start_writer(ticket.id, Keyword.put(opts, :tickets_root, root)),
         {:ok, %{ticket: assigned}} <- __MODULE__.assign_by_role(pid, ticket.id, opts) do
      %{"status" => "assigned", "assignees" => assigned.assignees}
    else
      {:error, reason} -> %{"status" => "failed", "reason" => error_text(reason)}
    end
  end

  defp proposal_event_opts(opts) do
    [now: now(opts), by: by(opts)]
    |> Keyword.merge(Keyword.take(opts, [:proposal_revision]))
  end

  defp request_inspection_once(root, id, opts) do
    with {:ok, ticket} <- Store.read_ticket(root, id, opts),
         :ok <- ensure_pending_approval(ticket),
         history <- read_history_for_prompt(root, id),
         :ok <- ensure_no_active_inspection(history),
         {:ok, selection} <-
           InspectorSelector.select(ticket, Keyword.put(opts, :tickets_root, root)),
         now <- now(opts),
         inspection_id <- Keyword.get(opts, :inspection_id) || InspectionEvents.new_id(now),
         {:ok, request} <-
           inspection_request(ticket, selection, history, inspection_id, now, opts),
         :ok <- validate_events(id, request.events),
         :ok <- append_events(root, id, request.events) do
      {:ok, Map.drop(request, [:events])}
    end
  end

  defp inspection_request(ticket, selection, history, inspection_id, now, opts) do
    inspectors = Enum.map(selection.inspectors, & &1.slug)

    with {:ok, requested} <-
           InspectionEvents.requested(ticket.id, inspection_id, selection.policy, inspectors,
             now: now
           ),
         {:ok, deliveries, prompts} <-
           inspection_prompt_deliveries(
             ticket,
             history,
             selection.inspectors,
             inspection_id,
             now,
             opts
           ) do
      {:ok,
       %{
         inspection_id: inspection_id,
         policy: selection.policy,
         inspectors: selection.inspectors,
         prompts: prompts,
         events: [requested | deliveries]
       }}
    end
  end

  defp inspection_prompt_deliveries(ticket, history, inspectors, inspection_id, now, opts) do
    Enum.reduce_while(inspectors, {:ok, [], []}, fn inspector, {:ok, events, prompts} ->
      turn_id = TurnIds.generate!(:turn, now)
      attempt_id = TurnIds.generate!(:attempt, now)

      prompt =
        PromptAssembler.inspection_prompt(ticket, history, inspector.slug,
          inspection_id: inspection_id,
          max_messages: Keyword.get(opts, :max_messages, 12)
        )

      case InspectionEvents.prompt_delivered(
             ticket.id,
             inspection_id,
             inspector.slug,
             turn_id,
             attempt_id,
             now: now
           ) do
        {:ok, event} ->
          prompt_info = %{
            to: inspector.slug,
            prompt: prompt,
            turn_id: turn_id,
            attempt_id: attempt_id
          }

          {:cont, {:ok, events ++ [event], prompts ++ [prompt_info]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp read_history_for_prompt(root, ticket_id) do
    case History.read(root, ticket_id) do
      {:ok, events} ->
        events

      {:error, reason} ->
        Logger.warning(
          "Babs Ticket #{ticket_id} history read failed before prompt assembly: #{inspect(reason)}"
        )

        []
    end
  end

  defp track_reply_capture(root, ticket, slug, now, opts, turn \\ %{}) do
    capture = Keyword.get(opts, :reply_capture, &ReplyCapture.track/1)

    if is_function(capture, 1) do
      _ignored =
        capture.(
          %{
            root: root,
            ticket_id: ticket.id,
            slug: slug,
            started_at: now,
            turn_id: Map.get(turn, :turn_id),
            attempt_id: turn |> Map.get(:attempt_ids, %{}) |> Map.get(slug)
          }
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()
        )
    end

    :ok
  end

  defp turn_delivered_events(_ticket, _slug, _now, %{turn_id: nil}, _backend), do: []

  defp turn_delivered_events(ticket, slug, now, turn, backend) do
    if Map.has_key?(turn.attempt_ids, slug) do
      [turn_delivered_event(ticket, slug, now, turn, backend)]
    else
      []
    end
  end

  defp turn_delivery_failed_events(ticket, slug, now, turn, reason, backend) do
    if Map.has_key?(turn.attempt_ids, slug) do
      [turn_delivery_failed_event(ticket, slug, now, turn, reason, backend)]
    else
      []
    end
  end

  defp turn_delivery_failed_event(ticket, slug, now, turn, reason, backend) do
    %{
      "ts" => now,
      "event" => "turn_delivery_failed",
      "by" => "system",
      "ticket_id" => ticket.id,
      "turn_id" => turn.turn_id,
      "attempt_id" => Map.fetch!(turn.attempt_ids, slug),
      "to" => slug,
      "backend" => backend,
      "error" => error_text(reason)
    }
  end

  defp delivery_backend(slug, opts) do
    case Keyword.get(opts, :delivery_backend) do
      fun when is_function(fun, 1) ->
        normalize_ticket_backend(fun.(slug))

      backend when is_binary(backend) ->
        normalize_ticket_backend(backend)

      _other ->
        case fetch_citizen_config(slug, opts) do
          {:ok, config} -> normalize_ticket_backend(config_backend(config))
          {:error, _reason} -> "hardline"
        end
    end
  end

  defp ensure_no_active_inspection(history) do
    case InspectionQuorum.active_request(history) do
      nil ->
        :ok

      %{"inspection_id" => inspection_id} ->
        {:error, {:inspection_already_pending, inspection_id}}
    end
  end

  defp inspection_transition_events(events, inspection_id) do
    Enum.map(events, fn
      %{"event" => event} = transition when event in ["approved", "rejected", "state_change"] ->
        Map.put(transition, "inspection_id", inspection_id)

      event ->
        event
    end)
  end

  defp direct_config(slug, opts), do: fetch_citizen_config(slug, opts)

  defp fetch_citizen_config(slug, opts) do
    cond do
      fetcher = Keyword.get(opts, :citizen_config_fetcher) ->
        normalize_config_result(fetcher.(slug), slug)

      configs = Keyword.get(opts, :direct_configs) ->
        fetch_config_from_map(configs, slug)

      config = Keyword.get(opts, :direct_config) ->
        normalize_config_result(config, slug)

      true ->
        fetch_config_from_catalog(slug)
    end
  end

  defp fetch_config_from_map(configs, slug) when is_map(configs) do
    configs
    |> Map.fetch(slug)
    |> case do
      {:ok, config} -> normalize_config_result(config, slug)
      :error -> {:error, {:unknown_citizen, slug}}
    end
  end

  defp fetch_config_from_map(_configs, slug), do: {:error, {:unknown_citizen, slug}}

  defp fetch_config_from_catalog(slug) do
    case Catalog.get_by_slug(slug) do
      nil -> {:error, {:unknown_citizen, slug}}
      record -> {:ok, Catalog.to_config(record)}
    end
  rescue
    error -> {:error, {:catalog_unavailable, Exception.message(error)}}
  catch
    :exit, reason -> {:error, {:catalog_unavailable, reason}}
  end

  defp normalize_config_result({:ok, config}, _slug), do: {:ok, config}
  defp normalize_config_result({:error, reason}, _slug), do: {:error, reason}
  defp normalize_config_result(nil, slug), do: {:error, {:unknown_citizen, slug}}
  defp normalize_config_result(config, _slug), do: {:ok, config}

  defp config_backend(config) when is_map(config) do
    Map.get(config, :ticket_backend) || Map.get(config, "ticket_backend")
  end

  defp config_backend(_config), do: nil

  defp normalize_ticket_backend(backend) when backend in @ticket_backends, do: backend
  defp normalize_ticket_backend(_backend), do: "hardline"

  defp comment_turn(ticket, attrs, now, by, notify?) do
    supplied_turn_id = fetch_attr(attrs, :turn_id)
    supplied_message_id = fetch_attr(attrs, :message_id)
    supplied_attempt_id = fetch_attr(attrs, :attempt_id)
    parent_turn_id = fetch_attr(attrs, :parent_turn_id)
    message_id = supplied_message_id || TurnIds.generate!(:message, now)

    cond do
      is_binary(supplied_turn_id) ->
        %{
          turn_id: supplied_turn_id,
          message_id: message_id,
          captured_attempt_id: supplied_attempt_id,
          parent_turn_id: parent_turn_id,
          attempt_ids: %{},
          new_turn?: false
        }

      by == "user" and notify? ->
        turn_id = TurnIds.generate!(:turn, now)

        %{
          turn_id: turn_id,
          message_id: message_id,
          captured_attempt_id: nil,
          parent_turn_id: parent_turn_id,
          attempt_ids:
            Map.new(ticket.assignees, fn slug ->
              {slug, TurnIds.generate!(:attempt, now)}
            end),
          new_turn?: true
        }

      true ->
        %{
          turn_id: nil,
          message_id: message_id,
          captured_attempt_id: nil,
          parent_turn_id: nil,
          attempt_ids: %{},
          new_turn?: false
        }
    end
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp validate_events(id, events) do
    Enum.reduce_while(events, :ok, fn event, :ok ->
      case History.validate_appendable(id, event) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp guard_phase11_transition(%{state: "pending_approval", id: id}, "in_progress", "rejected"),
    do: {:error, {:use_reject_ticket, id}}

  defp guard_phase11_transition(%{state: "pending_approval", id: id}, "in_progress", nil),
    do: {:error, {:use_reject_ticket, id}}

  defp guard_phase11_transition(%{state: "pending_approval", id: id}, "closed", "approved"),
    do: {:error, {:use_approve_ticket, id}}

  defp guard_phase11_transition(_ticket, _to_state, _event), do: :ok

  defp ensure_pending_approval(%{state: "pending_approval"}), do: :ok

  defp ensure_pending_approval(%{id: id, state: state}),
    do: {:error, {:inspection_requires_human, {:not_pending_approval, id, state}}}

  defp require_assignees(%{id: id, assignees: assignees}) do
    if assignees == [], do: {:error, {:no_assignees, id}}, else: :ok
  end

  defp ensure_role_routable(%{id: id, assignees: [_slug | _rest]}),
    do: {:error, {:role_route_already_assigned, id}}

  defp ensure_role_routable(_ticket), do: :ok

  defp ensure_commentable(%{state: state, id: id}) when state in ["closed", "cancelled"],
    do: {:error, {:terminal_ticket, id, state}}

  defp ensure_commentable(_ticket), do: :ok

  defp read_current(path, id) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, {:not_found, id}}
      {:error, reason} -> {:error, {:redacted_io_error, {:read_ticket, reason}}}
    end
  end

  defp run_before_write(path, opts) do
    before_write = Keyword.get(opts, :before_write, fn _path -> :ok end)

    case before_write.(path) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, {:before_write_failed, other}}
    end
  end

  defp detect_conflict(path, original, id) do
    case File.read(path) do
      {:ok, ^original} -> :ok
      {:ok, _changed} -> {:error, {:write_conflict, id}}
      {:error, :enoent} -> {:error, {:write_conflict, id}}
      {:error, reason} -> {:error, {:redacted_io_error, {:read_ticket, reason}}}
    end
  end

  defp comment_body(attrs) do
    case fetch_attr(attrs, :body) do
      value when is_binary(value) ->
        if String.trim(value) == "",
          do: {:error, {:invalid_history_event, :empty_body}},
          else: {:ok, value}

      _ ->
        {:error, {:invalid_history_event, {:missing_keys, ["body"]}}}
    end
  end

  defp comment_by(attrs) do
    case fetch_attr(attrs, :by) || "user" do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        cond do
          trimmed == "" ->
            {:error, {:invalid_comment_author, value}}

          trimmed == "user" or CitizenConfig.valid_slug?(trimmed) ->
            {:ok, trimmed}

          true ->
            {:error, {:invalid_comment_author, value}}
        end

      _ ->
        {:error, {:invalid_comment_author, fetch_attr(attrs, :by)}}
    end
  end

  defp reject_feedback(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, {:invalid_history_event, :empty_feedback}}
      trimmed -> {:ok, trimmed}
    end
  end

  defp reject_feedback(_value),
    do: {:error, {:invalid_history_event, {:missing_keys, ["feedback"]}}}

  defp fetch_attr(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp fetch_attr(attrs, key) when is_list(attrs),
    do: Keyword.get(attrs, key) || Keyword.get(attrs, Atom.to_string(key))

  defp by(opts) do
    case Keyword.get(opts, :by, "user") do
      value when is_binary(value) and value != "" -> value
      _value -> "user"
    end
  end

  defp error_text(reason), do: Error.message(reason)

  defp write_markdown(root, id, content) do
    temp_path = temp_path(root, id)
    final_path = TicketMarkdown.path(root, id)

    with :ok <- write_temp(temp_path, content),
         :ok <- install_temp(temp_path, final_path) do
      :ok
    end
  end

  defp write_temp(path, content) do
    case File.write(path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, {:redacted_io_error, {:write_ticket_temp, reason}}}
    end
  end

  defp install_temp(temp_path, final_path) do
    case File.rename(temp_path, final_path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:redacted_io_error, {:install_ticket, reason}}}
    end
  end

  defp temp_path(root, id) do
    unique = System.unique_integer([:positive, :monotonic])
    Path.join(root, ".#{id}.#{unique}.babs.md.tmp")
  end

  defp cleanup_temp_files(root, id) do
    prefix = ".#{id}."

    case File.ls(root) do
      {:ok, entries} ->
        entries
        |> Enum.filter(
          &(String.starts_with?(&1, prefix) and String.ends_with?(&1, ".babs.md.tmp"))
        )
        |> Enum.each(fn entry -> File.rm(Path.join(root, entry)) end)

      {:error, _reason} ->
        :ok
    end
  end

  defp now(opts), do: Keyword.get(opts, :now, DateTime.utc_now(:second) |> DateTime.to_iso8601())

  defp schedule_idle(opts) do
    ref = make_ref()

    Process.send_after(
      self(),
      {:idle_timeout, ref},
      Keyword.get(opts, :idle_timeout, @idle_timeout)
    )

    ref
  end

  defp reset_idle(%{idle_ref: ref} = state, opts) do
    Process.cancel_timer(ref)
    %{state | idle_ref: schedule_idle(opts)}
  end
end
