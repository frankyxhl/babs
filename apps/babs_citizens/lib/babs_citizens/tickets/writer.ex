defmodule Babs.Citizens.Tickets.Writer do
  @moduledoc """
  One lazy GenServer per Ticket id that serializes Babs-owned writes.
  """

  use GenServer

  alias Babs.Citizens.Citizen.Config, as: CitizenConfig
  alias Babs.Citizens.Catalog
  alias Babs.Citizens.DirectCli.Runner, as: DirectRunner
  alias Babs.Citizens.ExecutionLock
  alias Babs.Citizens.Tickets.Conversation
  alias Babs.Citizens.Tickets.Error
  alias Babs.Citizens.Tickets.History
  alias Babs.Citizens.Tickets.Injector
  alias Babs.Citizens.Tickets.ReplyCapture
  alias Babs.Citizens.Tickets.StateMachine
  alias Babs.Citizens.Tickets.Store
  alias Babs.Citizens.Tickets.TicketMarkdown
  alias Babs.Citizens.Tickets.TurnIds

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
           events <- comment_events(ticket, body, now, by, notify?, turn, opts),
           :ok <- validate_events(id, events),
           :ok <- write_markdown(state.root, id, TicketMarkdown.render(updated)),
           :ok <- append_events(state.root, id, events) do
        if notify? do
          inject_comment(state.root, updated, body, now, by, turn, opts)
        else
          {:ok, %{ticket: updated, delivery: :comment_stored}}
        end
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
        case Injector.prepare(slug, opts) do
          :ok ->
            persist_assignment(state.root, path, original, assigned, slug, opts)

          {:error, reason} ->
            persist_assignment_failure(state.root, path, original, ticket, slug, reason, opts)
        end
      end

    {:reply, result, state}
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

  @impl true
  def handle_info({:idle_timeout, ref}, %{idle_ref: ref} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:idle_timeout, _stale_ref}, state) do
    {:noreply, state}
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

  defp persist_assignment(root, path, original, assigned, slug, opts) do
    id = assigned.id
    now = now(opts)
    by = by(opts)
    assigned = %{assigned | updated_at: now}

    with :ok <- run_before_write(path, opts),
         :ok <- detect_conflict(path, original, id),
         :ok <- write_markdown(root, id, TicketMarkdown.render(assigned)),
         :ok <- append_events(root, id, assignment_events(assigned, slug, now, by)),
         prompt <- Injector.prompt(assigned, slug) do
      case Injector.inject(slug, prompt, opts) do
        :ok ->
          with :ok <- History.append(root, id, injected_event(assigned, slug, now)) do
            track_reply_capture(root, assigned, slug, now, opts)
            {:ok, %{ticket: assigned, delivery: {:injected, slug}}}
          end

        {:error, reason} ->
          _ignored = History.append(root, id, injection_failed_event(assigned, slug, now, reason))
          {:error, reason}
      end
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

  defp assignment_events(ticket, slug, now, by) do
    [
      %{
        "ts" => now,
        "event" => "assigned",
        "by" => by,
        "ticket_id" => ticket.id,
        "to" => [slug]
      },
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
    prompt = Injector.comment_prompt(ticket, slug, by, body, conversation)

    case delivery_backend(slug, opts) do
      "direct_cli" ->
        deliver_direct_comment(root, ticket, slug, prompt, turn, opts)

      "lazy_tmux" ->
        deliver_hardline_comment(root, ticket, slug, prompt, now, by, turn, opts)

      _backend ->
        deliver_hardline_comment(root, ticket, slug, prompt, now, by, turn, opts)
    end
  end

  defp deliver_direct_comment(root, ticket, slug, prompt, turn, opts) do
    with {:ok, config} <- direct_config(slug, opts),
         :ok <-
           DirectRunner.start_turn(
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
             },
             opts
           ) do
      :ok
    else
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

    with :ok <- Injector.prepare(slug, opts),
         :ok <- Injector.inject(slug, prompt, opts),
         :ok <- History.append(root, ticket.id, feedback_injected_event(ticket, slug, now, by)) do
      track_reply_capture(root, ticket, slug, now, opts)
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

  defp append_events(root, id, events) do
    Enum.reduce_while(events, :ok, fn event, :ok ->
      case History.append(root, id, event) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
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

  defp require_assignees(%{id: id, assignees: assignees}) do
    if assignees == [], do: {:error, {:no_assignees, id}}, else: :ok
  end

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
