defmodule BabsWeb.TicketLive do
  @moduledoc """
  Read-only Ticket detail view.
  """

  use Phoenix.LiveView

  alias Babs.Citizens.Catalog
  alias Babs.Citizens.Tickets.Api
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
       Api.assign_ticket(socket.assigns.id, slug)
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
    <style>
      {Phoenix.HTML.raw(styles())}
    </style>

    <div class="tickets-page" data-testid="ticket-detail">
      <main class="tickets-shell">
        <header class="tickets-header">
          <div>
            <a class="back-link" href={TicketPath.index(@socket_token)}>
              <BabsWeb.Icon.icon name="arrow-left" /> Tickets
            </a>
            <h1>{@ticket.title}</h1>
            <p class="tickets-subtitle">{@ticket.id}</p>
          </div>

          <nav class="tickets-nav" aria-label="Ticket detail navigation">
            <a class="button" href={CitizenPath.index(@socket_token)}>
              <BabsWeb.Icon.icon name="users" /> Citizens
            </a>
            <a class="button" href={TicketPath.index(@socket_token)}>
              <BabsWeb.Icon.icon name="list" /> Ticket List
            </a>
          </nav>
        </header>

        <div :if={Phoenix.Flash.get(@flash, :info)} class="ticket-flash" data-testid="ticket-flash-info">
          {Phoenix.Flash.get(@flash, :info)}
        </div>

        <div
          :if={Phoenix.Flash.get(@flash, :error)}
          class="ticket-flash ticket-flash-error"
          data-testid="ticket-flash-error"
        >
          {Phoenix.Flash.get(@flash, :error)}
        </div>

        <section class="detail-grid">
          <article class="detail-main">
            <div class={"state-badge state-#{@ticket.state}"}>{@ticket.state}</div>
            <pre class="ticket-body">{@ticket.body}</pre>
          </article>

          <aside class="detail-side">
            <section class="summary-panel action-panel" data-testid="ticket-actions">
              <h2>Actions</h2>
              <div class="ticket-actions">
                <button
                  :for={citizen <- @citizens}
                  :if={assignable?(@ticket)}
                  type="button"
                  class="button"
                  phx-click="assign"
                  phx-value-slug={citizen.slug}
                  disabled={ticket_action_busy?(@ticket_action_inflight)}
                  data-testid={"ticket-assign-#{citizen.slug}"}
                  aria-label={"Assign #{@ticket.id} to #{citizen.display_name}"}
                  title={"Assign to #{citizen.display_name}"}
                >
                  <BabsWeb.Icon.icon name="user-plus" /> {citizen.display_name}
                </button>

                <button
                  :if={ready_for_approval?(@ticket)}
                  type="button"
                  class="button"
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
                  class="button"
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
                    class="button button-danger"
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
                  class="button"
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
                  class="button button-danger"
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

            <section class="summary-panel">
              <h2>Frontmatter</h2>
              <dl>
                <div :for={{label, value} <- TicketPresenter.frontmatter(@ticket)} class="summary-row">
                  <dt>{label}</dt>
                  <dd>{value}</dd>
                </div>
              </dl>
            </section>

            <section :if={@ticket.warnings != []} class="summary-panel warning-panel">
              <h2>Warnings</h2>
              <p :for={warning <- @ticket.warnings}>{TicketPresenter.warning(warning)}</p>
            </section>
          </aside>
        </section>

        <section class="history-panel">
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
    <style>
      {Phoenix.HTML.raw(styles())}
    </style>

    <div class="tickets-page" data-testid="ticket-detail-error">
      <main class="tickets-shell">
        <header class="tickets-header">
          <div>
            <a class="back-link" href={TicketPath.index(@socket_token)}>
              <BabsWeb.Icon.icon name="arrow-left" /> Tickets
            </a>
            <h1>Ticket unavailable</h1>
            <p class="tickets-subtitle">{@id}</p>
          </div>
          <a class="button" href={CitizenPath.index(@socket_token)}>
            <BabsWeb.Icon.icon name="users" /> Citizens
          </a>
        </header>

        <section class="error-panel">
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
        |> assign(:citizens, citizens)
        |> assign(:error, nil)

      {:error, reason} ->
        socket
        |> assign(:ticket, nil)
        |> assign(:history, [])
        |> assign(:citizens, citizens)
        |> assign(:error, TicketPresenter.error_message(reason))
    end
  end

  def styles do
    """
    :root {
      color-scheme: dark;
      --bg: #0d0d10;
      --panel: #16181d;
      --panel-2: #1d2027;
      --line: #2a2f39;
      --text: #e7eaf0;
      --muted: #9da5b4;
      --danger: #dc6b6b;
      --accent: #55b3a6;
      --ok: #43d17d;
      --wait: #d7ae55;
      --done: #8ea0ff;
    }
    * { box-sizing: border-box; }
    html, body {
      min-height: 100%;
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font: 15px/1.5 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    .tickets-page { min-height: 100vh; padding: 28px clamp(14px, 3vw, 38px); }
    .tickets-shell { width: min(1180px, 100%); margin: 0 auto; display: grid; gap: 18px; }
    .tickets-header { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; }
    h1 { margin: 6px 0 0; font-size: 27px; line-height: 1.12; font-weight: 700; letter-spacing: 0; }
    h2 { margin: 0 0 10px; font-size: 15px; letter-spacing: 0; }
    .tickets-subtitle { margin: 5px 0 0; color: var(--muted); font-size: 13px; }
    .ticket-flash {
      border: 1px solid rgba(85, 179, 166, 0.5);
      border-radius: 8px;
      background: rgba(85, 179, 166, 0.12);
      color: var(--text);
      padding: 10px 12px;
      font-size: 13px;
    }
    .ticket-flash-error { border-color: rgba(220, 107, 107, 0.55); background: rgba(220, 107, 107, 0.12); }
    .tickets-nav { display: flex; align-items: center; justify-content: flex-end; gap: 8px; }
    .ticket-actions { display: flex; align-items: center; justify-content: flex-start; gap: 8px; flex-wrap: wrap; }
    .reject-form { flex: 1 1 100%; display: grid; gap: 8px; min-width: min(100%, 260px); }
    .reject-feedback {
      width: 100%;
      min-height: 92px;
      resize: vertical;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: var(--panel-2);
      color: var(--text);
      padding: 8px 10px;
      font: 13px/1.45 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    }
    .reject-feedback:disabled { opacity: 0.62; }
    .button, .back-link {
      border: 1px solid var(--line);
      border-radius: 6px;
      background: var(--panel-2);
      color: var(--text);
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 7px;
      min-height: 36px;
      padding: 7px 11px;
      text-decoration: none;
      white-space: nowrap;
      cursor: pointer;
    }
    .button:disabled { cursor: wait; opacity: 0.62; }
    .button-danger { color: var(--danger); }
    .back-link { min-height: 30px; padding: 5px 9px; color: var(--muted); font-size: 13px; }
    .button:hover, .back-link:hover { border-color: var(--accent); color: var(--text); }
    .icon { width: 16px; height: 16px; flex: 0 0 auto; }
    .detail-grid { display: grid; grid-template-columns: minmax(0, 1.4fr) minmax(280px, 0.6fr); gap: 14px; align-items: start; }
    .detail-main, .detail-side, .summary-panel, .history-panel, .error-panel {
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      padding: 14px;
    }
    .detail-side { display: grid; gap: 12px; padding: 0; border: 0; background: transparent; }
    .ticket-body {
      overflow: auto;
      margin: 14px 0 0;
      white-space: pre-wrap;
      color: var(--text);
      font: 13px/1.55 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    }
    dl { display: grid; gap: 8px; margin: 0; }
    .summary-row { display: grid; grid-template-columns: 110px minmax(0, 1fr); gap: 8px; min-width: 0; }
    dt { color: var(--muted); font-size: 12px; text-transform: uppercase; }
    dd { min-width: 0; margin: 0; overflow-wrap: anywhere; color: var(--text); font-size: 13px; }
    .warning-panel { border-color: var(--danger); }
    .warning-panel p { margin: 0; color: var(--danger); font-size: 13px; }
    .state-badge {
      display: inline-flex;
      width: fit-content;
      align-items: center;
      border: 1px solid var(--line);
      border-radius: 999px;
      padding: 3px 8px;
      color: var(--muted);
      font-size: 12px;
    }
    .state-open { color: var(--ok); }
    .state-in_progress { color: var(--wait); }
    .state-pending_approval { color: var(--accent); }
    .state-closed { color: var(--done); }
    .state-cancelled { color: var(--danger); }
    .history-list { display: grid; gap: 8px; margin: 0; padding: 0; list-style: none; }
    .history-event { border-top: 1px solid var(--line); padding-top: 8px; }
    .history-event:first-child { border-top: 0; padding-top: 0; }
    .history-event-name { display: inline-block; color: var(--text); font-weight: 700; }
    .history-event-meta { display: block; color: var(--muted); font-size: 12px; }
    .history-event-body { margin: 5px 0 0; color: var(--text); font-size: 13px; white-space: pre-wrap; }
    .error-panel { display: flex; align-items: flex-start; gap: 12px; color: var(--danger); }
    .error-panel p { margin: 0; color: var(--muted); }
    @media (max-width: 900px) {
      .tickets-header { flex-direction: column; }
      .tickets-nav { justify-content: flex-start; flex-wrap: wrap; }
      .detail-grid { grid-template-columns: minmax(0, 1fr); }
    }
    @media (max-width: 560px) {
      .tickets-page { padding: 18px 10px; }
      .summary-row { grid-template-columns: minmax(0, 1fr); }
    }
    """
  end

  defp param(params, key) when is_map(params), do: Map.get(params, key)
  defp param(_params, _key), do: nil

  defp citizen_options do
    Catalog.list_citizens()
    |> Enum.map(&%{slug: &1.slug, display_name: &1.display_name || &1.slug})
  rescue
    _error -> []
  end

  defp assignable?(ticket), do: ticket.state == "open" and ticket.assignees == []
  defp ready_for_approval?(ticket), do: ticket.state == "in_progress" and ticket.assignees != []
  defp unassignable?(ticket), do: ticket.state == "in_progress" and ticket.assignees != []
  defp cancellable?(ticket), do: ticket.state in ["open", "in_progress", "pending_approval"]
  defp approvable?(ticket), do: ticket.state == "pending_approval" and ticket.assignees != []
  defp rejectable?(ticket), do: ticket.state == "pending_approval" and ticket.assignees != []

  defp ticket_action_busy?(nil), do: false
  defp ticket_action_busy?(_action), do: true

  defp history_event_text(%{"body" => body}) when is_binary(body) and body != "", do: body

  defp history_event_text(%{"feedback" => feedback})
       when is_binary(feedback) and feedback != "",
       do: feedback

  defp history_event_text(_event), do: nil

  defp start_ticket_action(socket, action, fun) do
    if ticket_action_busy?(socket.assigns.ticket_action_inflight) do
      put_flash(socket, :error, "Ticket action already running")
    else
      socket
      |> assign(:ticket_action_inflight, action)
      |> start_async({:ticket_action, action}, fun)
    end
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
  defp ticket_action_success(:approve), do: "Approved ticket"
  defp ticket_action_success(:reject), do: "Rejected ticket"

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
