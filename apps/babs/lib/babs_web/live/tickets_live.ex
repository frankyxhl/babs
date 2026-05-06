defmodule BabsWeb.TicketsLive do
  @moduledoc """
  Read-only Ticket/Billboard browser index.
  """

  use Phoenix.LiveView

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Watcher
  alias BabsWeb.CitizenPath
  alias BabsWeb.TicketPath
  alias BabsWeb.TicketPresenter

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Babs.Citizens.PubSub, Watcher.topic())

    {:ok,
     socket
     |> assign(:socket_token, Map.get(session, "socket_token", ""))
     |> assign_tickets()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, assign_tickets(socket)}
  end

  @impl true
  def handle_info({:tickets_changed, _payload}, socket) do
    {:noreply, assign_tickets(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      <%= Phoenix.HTML.raw(styles()) %>
    </style>

    <div class="tickets-page" data-testid="tickets-index">
      <main class="tickets-shell">
        <header class="tickets-header">
          <div>
            <h1>Tickets</h1>
            <p class="tickets-subtitle">Runtime Billboard and Ticket files</p>
          </div>

          <nav class="tickets-nav" aria-label="Ticket navigation">
            <a class="button button-primary" href={TicketPath.new(@socket_token)} data-testid="tickets-new">
              <BabsWeb.Icon.icon name="plus" /> New
            </a>
            <a class="button" href={CitizenPath.index(@socket_token)} data-testid="tickets-nav-citizens">
              <BabsWeb.Icon.icon name="users" /> Citizens
            </a>
            <button
              type="button"
              class="button button-icon"
              phx-click="refresh"
              aria-label="Refresh tickets"
              title="Refresh tickets"
              data-testid="tickets-refresh"
            >
              <BabsWeb.Icon.icon name="refresh" />
            </button>
          </nav>
        </header>

        <section class="ticket-counts" aria-label="Ticket counts">
          <div :for={group <- @groups} class="ticket-count">
            <span class="ticket-count-label">{group.label}</span>
            <span class="ticket-count-value">{group.count}</span>
          </div>
        </section>

        <section
          :if={Enum.all?(@groups, &(&1.count == 0))}
          class="tickets-empty"
          data-testid="tickets-empty-state"
        >
          No tickets yet.
        </section>

        <section :for={group <- @groups} class="ticket-group" data-testid={"ticket-group-#{group.key}"}>
          <header class="ticket-group-header">
            <h2>{group.label}</h2>
            <span class="ticket-group-count">{group.count}</span>
          </header>

          <div :if={Map.has_key?(group, :tickets) and group.tickets != []} class="ticket-list">
            <article
              :for={ticket <- group.tickets}
              class="ticket-row"
              data-testid={"ticket-row-#{ticket.id}"}
            >
              <div class="ticket-main">
                <a class="ticket-title" href={TicketPath.detail(ticket.id, @socket_token)}>
                  <BabsWeb.Icon.icon name="file-text" />
                  {ticket.title}
                </a>
                <span class="ticket-id">{ticket.id}</span>
              </div>
              <div class={"state-badge state-#{ticket.state}"}>{ticket.state}</div>
              <div class="ticket-meta">{ticket.priority}</div>
              <div class="ticket-meta">{TicketPresenter.assignees(ticket.assignees)}</div>
              <a
                class="button button-compact"
                href={TicketPath.detail(ticket.id, @socket_token)}
                aria-label={"Open #{ticket.id}"}
                title={"Open #{ticket.id}"}
              >
                <BabsWeb.Icon.icon name="external-link" /> Open
              </a>
            </article>
          </div>

          <div :if={Map.has_key?(group, :invalid) and group.invalid != []} class="ticket-list">
            <article :for={invalid <- group.invalid} class="ticket-row ticket-row-invalid" data-testid="ticket-invalid-row">
              <div class="ticket-main">
                <span class="ticket-title">
                  <BabsWeb.Icon.icon name="triangle-alert" />
                  {invalid.file}
                </span>
                <span class="ticket-id">runtime file error</span>
              </div>
              <div class="ticket-error">{invalid.reason}</div>
            </article>
          </div>
        </section>
      </main>
    </div>

    <script type="module" src="/js/live_boot.js">
    </script>
    """
  end

  defp assign_tickets(socket) do
    case Api.list_tickets() do
      {:ok, %{tickets: tickets, invalid: invalid}} ->
        groups = TicketPresenter.groups(tickets, invalid)

        socket
        |> assign(:groups, groups)
        |> assign(:counts, TicketPresenter.counts(groups))
        |> assign(:error, nil)

      {:error, reason} ->
        socket
        |> assign(:groups, TicketPresenter.groups([], []))
        |> assign(:counts, %{})
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
      --accent-text: #07100e;
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
    h1 { margin: 0; font-size: 27px; line-height: 1.12; font-weight: 700; letter-spacing: 0; }
    h2 { margin: 0; font-size: 16px; line-height: 1.2; letter-spacing: 0; }
    .tickets-subtitle { margin: 5px 0 0; color: var(--muted); font-size: 13px; }
    .tickets-nav, .ticket-actions { display: flex; align-items: center; justify-content: flex-end; gap: 8px; }
    .button {
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
      font: inherit;
      cursor: pointer;
    }
    .button:hover { border-color: var(--accent); }
    .button-primary { border-color: transparent; background: var(--accent); color: var(--accent-text); font-weight: 700; }
    .button-primary:hover { color: var(--accent-text); }
    .button-icon { width: 36px; padding: 7px; }
    .button-compact { min-height: 32px; padding: 5px 9px; font-size: 13px; }
    .icon { width: 16px; height: 16px; flex: 0 0 auto; }
    .ticket-counts { display: grid; grid-template-columns: repeat(6, minmax(0, 1fr)); gap: 10px; }
    .ticket-count { min-width: 0; border: 1px solid var(--line); border-radius: 8px; background: var(--panel); padding: 12px; }
    .ticket-count-label { display: block; overflow: hidden; color: var(--muted); font-size: 12px; text-overflow: ellipsis; text-transform: uppercase; white-space: nowrap; }
    .ticket-count-value { display: block; margin-top: 4px; font-size: 24px; line-height: 1; font-weight: 700; }
    .tickets-empty { border: 1px solid var(--line); border-radius: 8px; background: var(--panel); padding: 24px; color: var(--muted); }
    .ticket-group { display: grid; gap: 8px; }
    .ticket-group-header { display: flex; align-items: center; gap: 8px; color: var(--text); }
    .ticket-group-count { color: var(--muted); font-size: 13px; }
    .ticket-list { display: grid; gap: 8px; }
    .ticket-row {
      display: grid;
      grid-template-columns: minmax(220px, 1.2fr) minmax(130px, 0.5fr) minmax(86px, 0.35fr) minmax(130px, 0.6fr) auto;
      gap: 12px;
      align-items: center;
      min-width: 0;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      padding: 12px;
    }
    .ticket-row-invalid { grid-template-columns: minmax(220px, 0.8fr) minmax(0, 1.2fr); }
    .ticket-main, .ticket-meta, .ticket-error { min-width: 0; }
    .ticket-title {
      display: inline-flex;
      align-items: center;
      gap: 7px;
      max-width: 100%;
      overflow: hidden;
      color: var(--text);
      font-weight: 700;
      text-decoration: none;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .ticket-title:hover { color: var(--accent); }
    .ticket-id, .ticket-meta, .ticket-error {
      display: block;
      overflow: hidden;
      color: var(--muted);
      font-size: 13px;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .ticket-error { color: var(--danger); }
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
    @media (max-width: 900px) {
      .ticket-counts { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .ticket-row, .ticket-row-invalid { grid-template-columns: minmax(0, 1fr); align-items: start; }
      .tickets-header { flex-direction: column; }
      .tickets-nav { justify-content: flex-start; flex-wrap: wrap; }
    }
    @media (max-width: 560px) {
      .tickets-page { padding: 18px 10px; }
      .ticket-counts { grid-template-columns: 1fr; }
    }
    """
  end
end
