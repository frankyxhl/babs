defmodule BabsWeb.TicketLive do
  @moduledoc """
  Read-only Ticket detail view.
  """

  use Phoenix.LiveView

  alias Babs.Citizens.Catalog
  alias Babs.Citizens.TicketBackend
  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Conversation
  alias Babs.Citizens.Tickets.Error
  alias Babs.Citizens.Tickets.Watcher
  alias BabsWeb.CitizenPath
  alias BabsWeb.TicketPath
  alias BabsWeb.TicketPresenter

  @impl true
  def mount(params, session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Babs.Citizens.PubSub, Watcher.topic())

    id = param(params, "id") || Map.get(session, "id")

    {:ok,
     socket
     |> assign(:id, id)
     |> assign(:socket_token, Map.get(session, "socket_token", ""))
     |> assign(:ticket_action_inflight, nil)
     |> assign_ticket()}
  end

  @impl true
  def handle_event("assign", %{"slug" => slug}, socket) do
    {:noreply,
     start_ticket_action(socket, {:assign, slug}, fn ->
       with :ok <- ensure_assignable_citizen(slug) do
         Api.assign_ticket(socket.assigns.id, slug)
       end
     end)}
  end

  def handle_event("transition", %{"to" => to_state} = params, socket) do
    event = blank_to_nil(Map.get(params, "event"))

    {:noreply,
     start_ticket_action(socket, {:transition, to_state, event}, fn ->
       Api.transition_ticket(socket.assigns.id, to_state, event)
     end)}
  end

  def handle_event("unassign", %{"slug" => slug}, socket) do
    {:noreply,
     start_ticket_action(socket, {:unassign, slug}, fn ->
       Api.unassign_ticket(socket.assigns.id, slug)
     end)}
  end

  def handle_event("approve", _params, socket) do
    {:noreply,
     start_ticket_action(socket, :approve, fn ->
       Api.approve_ticket(socket.assigns.id)
     end)}
  end

  def handle_event("reject", %{"feedback" => feedback}, socket) do
    case String.trim(feedback || "") do
      "" ->
        {:noreply, put_flash(socket, :error, "Rejection feedback is required")}

      value ->
        {:noreply,
         start_ticket_action(socket, :reject, fn ->
           Api.reject_ticket(socket.assigns.id, value)
         end)}
    end
  end

  def handle_event("comment", %{"body" => body}, socket) do
    case String.trim(body || "") do
      "" ->
        {:noreply, put_flash(socket, :error, "Comment body is required")}

      value ->
        {:noreply,
         start_ticket_action(socket, {:comment, value}, fn ->
           Api.comment_ticket(socket.assigns.id, %{body: value, by: "user"})
         end)}
    end
  end

  @impl true
  def handle_async({:ticket_action, action}, {:ok, result}, socket) do
    {:noreply, apply_ticket_action_result(socket, action, result)}
  end

  def handle_async({:ticket_action, action}, {:exit, reason}, socket) do
    {:noreply, apply_ticket_action_result(socket, action, {:error, reason})}
  end

  @impl true
  def handle_info({:tickets_changed, _payload}, socket) do
    {:noreply, assign_ticket(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(%{error: nil} = assigns) do
    ~H"""
    <div class="ks-page" data-testid="ticket-detail">
      <main class="ks-shell">
        <header class="ks-header">
          <div>
            <a class="ks-button" href={TicketPath.index(@socket_token)}>
              <BabsWeb.Icon.icon name="arrow-left" /> Tickets
            </a>
            <h1>{@ticket.title}</h1>
            <p class="ks-subtitle">{@ticket.id}</p>
          </div>

          <nav class="ks-nav" aria-label="Ticket detail navigation">
            <a class="ks-button" href={CitizenPath.index(@socket_token)}>
              <BabsWeb.Icon.icon name="users" /> Citizens
            </a>
            <a class="ks-button" href={TicketPath.index(@socket_token)}>
              <BabsWeb.Icon.icon name="list" /> Ticket List
            </a>
          </nav>
        </header>

        <div :if={Phoenix.Flash.get(@flash, :info)} class="ks-card ticket-flash" data-testid="ticket-flash-info">
          {Phoenix.Flash.get(@flash, :info)}
        </div>

        <div
          :if={Phoenix.Flash.get(@flash, :error)}
          class="ks-card ticket-flash ticket-flash-error"
          data-testid="ticket-flash-error"
        >
          {Phoenix.Flash.get(@flash, :error)}
        </div>

        <section class="ticket-layout">
          <aside class="ticket-rail" data-testid="ticket-state-rail">
            <section class="rail-block">
              <p class="rail-label">State</p>
              <span class={state_badge_class(@ticket.state)}><span class="dot"></span>{@ticket.state}</span>
            </section>

            <section class="rail-block">
              <p class="rail-label">Ticket Body</p>
              <pre class="ticket-body">{@ticket.body}</pre>
            </section>

            <section class="rail-block" data-testid="ticket-actions">
              <p class="rail-label">Actions</p>
              <div class="rail-actions">
                <button
                  :for={citizen <- @citizens}
                  :if={assignable?(@ticket)}
                  type="button"
                  class="ks-button"
                  phx-click="assign"
                  phx-value-slug={citizen.slug}
                  disabled={ticket_action_busy?(@ticket_action_inflight)}
                  data-testid={"ticket-assign-#{citizen.slug}"}
                  aria-label={"Assign #{@ticket.id} to #{citizen.display_name} using #{citizen.ticket_backend_label}"}
                  title={"Assign to #{citizen.display_name} using #{citizen.ticket_backend_label}: #{citizen.assign_hint}"}
                >
                  <BabsWeb.Icon.icon name="user-plus" />
                  <span>{citizen.display_name}</span>
                  <span class="badge">{citizen.ticket_backend_label}</span>
                  <span class="muted-inline">{citizen.assign_hint}</span>
                </button>

                <button
                  :if={ready_for_approval?(@ticket)}
                  type="button"
                  class="ks-button"
                  phx-click="transition"
                  phx-value-to="pending_approval"
                  disabled={ticket_action_busy?(@ticket_action_inflight)}
                  data-testid="ticket-transition-pending_approval"
                  aria-label="Move to pending approval"
                  title="Move to pending approval"
                >
                  <BabsWeb.Icon.icon name="route" /> Pending Approval
                </button>

                <button
                  :if={approvable?(@ticket)}
                  type="button"
                  class="ks-button primary"
                  phx-click="approve"
                  disabled={ticket_action_busy?(@ticket_action_inflight)}
                  data-testid="ticket-approve"
                  aria-label="Approve ticket"
                  title="Approve ticket"
                >
                  <BabsWeb.Icon.icon name="check" /> Approve
                </button>

                <form
                  :if={rejectable?(@ticket)}
                  class="reject-form"
                  phx-submit="reject"
                  data-testid="ticket-reject-form"
                >
                  <textarea
                    name="feedback"
                    class="reject-feedback"
                    rows="4"
                    required
                    disabled={ticket_action_busy?(@ticket_action_inflight)}
                    data-testid="ticket-reject-feedback"
                    aria-label="Rejection feedback"
                  ></textarea>
                  <button
                    type="submit"
                    class="ks-button danger"
                    disabled={ticket_action_busy?(@ticket_action_inflight)}
                    data-testid="ticket-reject"
                    aria-label="Reject ticket"
                    title="Reject ticket"
                  >
                    <BabsWeb.Icon.icon name="x" /> Reject
                  </button>
                </form>

                <button
                  :for={slug <- @ticket.assignees}
                  :if={unassignable?(@ticket)}
                  type="button"
                  class="ks-button"
                  phx-click="unassign"
                  phx-value-slug={slug}
                  phx-confirm={"Unassign #{slug} from #{@ticket.id}?"}
                  disabled={ticket_action_busy?(@ticket_action_inflight)}
                  data-testid={"ticket-unassign-#{slug}"}
                  aria-label={"Unassign #{slug}"}
                  title={"Unassign #{slug}"}
                >
                  <BabsWeb.Icon.icon name="undo" /> Unassign {slug}
                </button>

                <button
                  :if={cancellable?(@ticket)}
                  type="button"
                  class="ks-button danger"
                  phx-click="transition"
                  phx-value-to="cancelled"
                  phx-value-event="cancelled"
                  phx-confirm={"Cancel #{@ticket.id}?"}
                  disabled={ticket_action_busy?(@ticket_action_inflight)}
                  data-testid="ticket-transition-cancelled"
                  aria-label="Cancel ticket"
                  title="Cancel ticket"
                >
                  <BabsWeb.Icon.icon name="ban" /> Cancel
                </button>
              </div>
            </section>

            <section class="rail-block">
              <p class="rail-label">Frontmatter</p>
              <dl class="stat-list">
                <div :for={{label, value} <- TicketPresenter.frontmatter(@ticket)} class="summary-row">
                  <dt>{label}</dt>
                  <dd>{value}</dd>
                </div>
              </dl>
            </section>

            <section :if={@ticket.warnings != []} class="rail-block warning-panel">
              <p class="rail-label">Warnings</p>
              <p :for={warning <- @ticket.warnings}>{TicketPresenter.warning(warning)}</p>
            </section>

            <section :if={failed_attempts(@conversation) != []} class="rail-block">
              <p class="rail-label">Failed Delivery</p>
              <div class="rail-actions">
                <button
                  :for={attempt <- failed_attempts(@conversation)}
                  type="button"
                  class="ks-button danger"
                  disabled
                  data-testid="ticket-retry-delivery"
                  title={"Retry #{attempt.citizen_slug}"}
                  aria-label={"Retry #{attempt.citizen_slug}"}
                >
                  <BabsWeb.Icon.icon name="refresh" /> Retry {attempt.citizen_slug}
                </button>
                <a
                  :for={attempt <- failed_attempts(@conversation)}
                  class="ks-button"
                  href={CitizenPath.terminal(attempt.citizen_slug, @socket_token)}
                  data-testid="ticket-open-terminal"
                  title={"Open #{attempt.citizen_slug} terminal"}
                  aria-label={"Open #{attempt.citizen_slug} terminal"}
                >
                  <BabsWeb.Icon.icon name="maximize" /> Open Terminal
                </a>
              </div>
            </section>
          </aside>

          <article class="chat-card" data-testid="ticket-detail-chat">
            <header class="chat-head">
            <div>
              <h2>Ticket Chat</h2>
              <p>Operator follow-ups, Citizen replies, and delivery state.</p>
            </div>
            </header>

          <div :if={@conversation.messages == []} class="empty-state" data-testid="ticket-comments-empty">
            No comments yet.
          </div>

          <ol :if={@conversation.messages != []} class="message-list">
            <li
              :for={message <- @conversation.messages}
              class={message_class(message)}
              data-testid="ticket-chat-message"
            >
              <div class="bubble">
                <div class="meta">
                  <strong>{message.author}</strong>
                  <time>{message.ts}</time>
                  <span
                    :for={attempt <- message_attempts(@conversation, message)}
                    class={status_badge_class(attempt.status)}
                    data-testid="ticket-turn-status"
                  >
                    <span class="dot"></span>{attempt.citizen_slug}: {attempt.status}
                  </span>
                  <span :if={message.legacy?} class="badge imported">legacy</span>
                </div>
                <p>{message.body}</p>
              </div>
            </li>
          </ol>

          <form
            :if={commentable?(@ticket)}
            class="composer"
            phx-submit="comment"
            data-testid="ticket-comment-form"
          >
            <textarea
              name="body"
              rows="3"
              required
              disabled={ticket_action_busy?(@ticket_action_inflight)}
              data-testid="ticket-comment-body"
              aria-label="Ticket comment"
              placeholder="Write a message to this ticket..."
            ></textarea>
            <button
              type="submit"
              class="ks-button primary"
              disabled={ticket_action_busy?(@ticket_action_inflight)}
              data-testid="ticket-comment"
              aria-label="Add ticket comment"
              title="Add ticket comment"
            >
              <BabsWeb.Icon.icon name="send" /> Send
            </button>
          </form>
          </article>
        </section>

        <section class="ks-card">
          <h2>History</h2>
          <ol class="history-list">
            <li :for={event <- @history} class="history-event" data-testid="ticket-history-event">
              <span class="history-event-name">{event["event"]}</span>
              <span class="history-event-meta">{event["ts"]} by {event["by"]}</span>
              <p :if={history_event_text(event)} class="history-event-body">
                {history_event_text(event)}
              </p>
            </li>
          </ol>
        </section>
      </main>
    </div>

    <script type="module" src="/js/live_boot.js">
    </script>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="ks-page" data-testid="ticket-detail-error">
      <main class="ks-shell">
        <header class="ks-header">
          <div>
            <a class="ks-button" href={TicketPath.index(@socket_token)}>
              <BabsWeb.Icon.icon name="arrow-left" /> Tickets
            </a>
            <h1>Ticket unavailable</h1>
            <p class="ks-subtitle">{@id}</p>
          </div>
          <a class="ks-button" href={CitizenPath.index(@socket_token)}>
            <BabsWeb.Icon.icon name="users" /> Citizens
          </a>
        </header>

        <section class="ks-card error-panel">
          <BabsWeb.Icon.icon name="triangle-alert" />
          <div>
            <h2>{@error}</h2>
            <p>The Ticket file is missing or invalid in the configured runtime root.</p>
          </div>
        </section>
      </main>
    </div>

    <script type="module" src="/js/live_boot.js">
    </script>
    """
  end

  defp assign_ticket(socket) do
    citizens = citizen_options()

    case Api.show_ticket(socket.assigns.id, known_citizens: Enum.map(citizens, & &1.slug)) do
      {:ok, %{ticket: ticket, history: history}} ->
        socket
        |> assign(:ticket, ticket)
        |> assign(:history, history)
        |> assign(:conversation, Conversation.from_history(history))
        |> assign(:citizens, citizens)
        |> assign(:error, nil)

      {:error, reason} ->
        socket
        |> assign(:ticket, nil)
        |> assign(:history, [])
        |> assign(:conversation, Conversation.from_history([]))
        |> assign(:citizens, citizens)
        |> assign(:error, TicketPresenter.error_message(reason))
    end
  end

  defp param(params, key) when is_map(params), do: Map.get(params, key)
  defp param(_params, _key), do: nil

  defp citizen_options do
    Catalog.list_configured_or_imported_citizens()
    |> Enum.map(fn citizen ->
      backend = citizen.ticket_backend || "hardline"

      %{
        slug: citizen.slug,
        display_name: citizen.display_name || citizen.slug,
        ticket_backend: backend,
        ticket_backend_label: TicketBackend.label(backend),
        assign_hint: TicketBackend.assign_hint(backend)
      }
    end)
  rescue
    _error -> []
  end

  defp ensure_assignable_citizen(slug) do
    if Enum.any?(Catalog.list_configured_or_imported_citizens(), &(&1.slug == slug)) do
      :ok
    else
      {:error, {:unknown_citizen, slug}}
    end
  end

  defp assignable?(ticket), do: ticket.state == "open" and ticket.assignees == []
  defp ready_for_approval?(ticket), do: ticket.state == "in_progress" and ticket.assignees != []
  defp unassignable?(ticket), do: ticket.state == "in_progress" and ticket.assignees != []
  defp cancellable?(ticket), do: ticket.state in ["open", "in_progress", "pending_approval"]
  defp approvable?(ticket), do: ticket.state == "pending_approval" and ticket.assignees != []
  defp rejectable?(ticket), do: ticket.state == "pending_approval" and ticket.assignees != []
  defp commentable?(ticket), do: ticket.state not in ["closed", "cancelled"]

  defp ticket_action_busy?(nil), do: false
  defp ticket_action_busy?(_action), do: true

  defp history_event_text(%{"body" => body}) when is_binary(body) and body != "", do: body

  defp history_event_text(%{"feedback" => feedback})
       when is_binary(feedback) and feedback != "",
       do: feedback

  defp history_event_text(_event), do: nil

  defp state_badge_class("open"), do: "badge open"
  defp state_badge_class("in_progress"), do: "badge working"
  defp state_badge_class("pending_approval"), do: "badge pending"
  defp state_badge_class("closed"), do: "badge captured"
  defp state_badge_class("cancelled"), do: "badge failed"
  defp state_badge_class(_state), do: "badge"

  defp status_badge_class("captured"), do: "badge captured"
  defp status_badge_class("delivered"), do: "badge delivered"
  defp status_badge_class("failed"), do: "badge failed"
  defp status_badge_class("queued"), do: "badge queued"
  defp status_badge_class("busy"), do: "badge pending"
  defp status_badge_class(_status), do: "badge"

  defp message_class(%{legacy?: true}), do: "message legacy"
  defp message_class(%{role: :user}), do: "message mine"
  defp message_class(%{role: :system}), do: "message system"
  defp message_class(_message), do: "message citizen"

  defp message_attempts(conversation, %{turn_id: turn_id}) do
    Conversation.attempts_for_turn(conversation, turn_id)
  end

  defp failed_attempts(conversation) do
    conversation.attempts
    |> Map.values()
    |> Enum.filter(&(&1.status == "failed"))
    |> Enum.sort_by(&{&1.turn_id, &1.citizen_slug, &1.attempt_id})
  end

  defp start_ticket_action(socket, action, fun) do
    if ticket_action_busy?(socket.assigns.ticket_action_inflight) do
      put_flash(socket, :error, "Ticket action already running")
    else
      socket
      |> assign(:ticket_action_inflight, action)
      |> start_async({:ticket_action, action}, fun)
    end
  end

  defp apply_ticket_action_result(
         socket,
         {:comment, _body},
         {:ok, %{delivery: {:comment_notification_failed, _ok_slugs, failures}}}
       ) do
    socket
    |> assign(:ticket_action_inflight, nil)
    |> assign_ticket()
    |> put_flash(:error, "Comment stored; notification failed for #{failed_slugs(failures)}")
  end

  defp apply_ticket_action_result(socket, action, {:ok, _result}) do
    socket
    |> assign(:ticket_action_inflight, nil)
    |> assign_ticket()
    |> put_flash(:info, ticket_action_success(action))
  end

  defp apply_ticket_action_result(socket, _action, {:error, reason}) do
    socket
    |> assign(:ticket_action_inflight, nil)
    |> assign_ticket()
    |> put_flash(:error, Error.message(reason))
  end

  defp ticket_action_success({:assign, slug}), do: "Assigned to #{slug}"
  defp ticket_action_success({:transition, to_state, _event}), do: "Moved to #{to_state}"
  defp ticket_action_success({:unassign, slug}), do: "Unassigned #{slug}"
  defp ticket_action_success({:comment, _body}), do: "Comment stored"
  defp ticket_action_success(:approve), do: "Approved ticket"
  defp ticket_action_success(:reject), do: "Rejected ticket"

  defp failed_slugs(failures) do
    failures
    |> Enum.map(fn {slug, _reason} -> slug end)
    |> Enum.join(", ")
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
