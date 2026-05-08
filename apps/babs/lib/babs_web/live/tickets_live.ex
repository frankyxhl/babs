defmodule BabsWeb.TicketsLive do
  @moduledoc """
  Read-only Ticket/Billboard browser index.
  """

  use Phoenix.LiveView

  alias Babs.Citizens.Federation.PeerClient
  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Watcher
  alias BabsWeb.CitizenPath
  alias BabsWeb.TicketPath
  alias BabsWeb.TicketPresenter

  @remote_refresh_ms 5_000

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Babs.Citizens.PubSub, Watcher.topic())
      schedule_remote_refresh()
    end

    socket =
      socket
      |> assign(:socket_token, Map.get(session, "socket_token", ""))
      |> assign(:remote_peer, nil)
      |> assign(:remote_peer_inflight, false)
      |> assign_tickets()

    socket = if connected?(socket), do: start_remote_peer_fetch(socket), else: socket

    {:ok, socket}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, assign_tickets(socket)}
  end

  @impl true
  def handle_info({:tickets_changed, _payload}, socket) do
    {:noreply, assign_tickets(socket)}
  end

  def handle_info(:refresh_remote_peer, socket) do
    if connected?(socket) do
      schedule_remote_refresh()
      {:noreply, start_remote_peer_fetch(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:remote_peer, {:ok, peer}, socket) do
    {:noreply, socket |> assign(:remote_peer_inflight, false) |> assign(:remote_peer, peer)}
  end

  def handle_async(:remote_peer, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :remote_peer_inflight, false)}
  end

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

        <section :if={@remote_peer} class="remote-node" data-testid="remote-peer-tickets">
          <header class="remote-node-header">
            <h2 class="remote-node-title">
              <BabsWeb.Icon.icon name="route" />
              <span>{remote_node_label(@remote_peer)}</span>
            </h2>
            <div class="remote-badges">
              <span class="remote-badge remote-badge-readonly">Read-only</span>
              <span class={["remote-badge", remote_status_class(@remote_peer)]}>
                {remote_status(@remote_peer)}
              </span>
            </div>
          </header>

          <div class="remote-ticket-list" data-testid="remote-ticket-list">
            <article
              :for={ticket <- @remote_peer.tickets}
              class="remote-ticket-row"
              data-testid={"remote-ticket-#{remote_value(ticket, "id")}"}
            >
              <div class="remote-main">
                <BabsWeb.Icon.icon name="file-text" />
                <span>{remote_value(ticket, "title") || remote_value(ticket, "id")}</span>
              </div>
              <div class="remote-meta">{remote_value(ticket, "id")}</div>
              <div class="remote-meta">{remote_value(ticket, "state")}</div>
            </article>
            <div :if={@remote_peer.tickets == []} class="remote-meta" data-testid="remote-tickets-empty">
              No remote Tickets.
            </div>
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

  defp start_remote_peer_fetch(socket) do
    if socket.assigns.remote_peer_inflight do
      socket
    else
      previous_peer = Map.get(socket.assigns, :remote_peer)

      socket
      |> assign(:remote_peer_inflight, true)
      |> start_async(:remote_peer, fn -> remote_peer(previous_peer) end)
    end
  end

  defp remote_peer(previous_peer) do
    :babs
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:remote_peer_provider, &default_remote_peer/1)
    |> call_remote_peer_provider(previous_peer)
  end

  defp call_remote_peer_provider(provider, previous_peer) when is_function(provider, 1),
    do: provider.(previous_peer)

  defp call_remote_peer_provider(provider, _previous_peer) when is_function(provider, 0),
    do: provider.()

  defp default_remote_peer(previous_peer) do
    case PeerClient.fetch_first_peer(previous_snapshot: previous_peer) do
      {:ok, peer} -> peer
      {:error, _reason} -> nil
    end
  end

  defp remote_node_label(peer) do
    node = Map.get(peer, :node, %{})
    Map.get(node, "name") || Map.get(peer, :peer_name) || Map.get(peer, :peer_id) || "Remote Babs"
  end

  defp remote_status(peer), do: peer |> remote_status_key() |> String.replace("_", " ")

  defp remote_status_class(peer), do: "remote-badge-#{remote_status_key(peer)}"

  defp remote_status_key(peer) do
    case Map.get(peer, :status) do
      status when is_atom(status) -> Atom.to_string(status)
      status when is_binary(status) -> status
      _status -> "unknown"
    end
  end

  defp remote_value(map, key) when is_map(map),
    do: Map.get(map, key) || remote_atom_value(map, key)

  defp remote_value(_map, _key), do: nil

  defp remote_atom_value(map, "id"), do: Map.get(map, :id)
  defp remote_atom_value(map, "title"), do: Map.get(map, :title)
  defp remote_atom_value(map, "state"), do: Map.get(map, :state)
  defp remote_atom_value(_map, _key), do: nil

  defp schedule_remote_refresh do
    Process.send_after(self(), :refresh_remote_peer, @remote_refresh_ms)
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
    .remote-node {
      display: grid;
      gap: 10px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      padding: 12px;
    }
    .remote-node-header, .remote-badges {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 10px;
      min-width: 0;
    }
    .remote-node-title {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      min-width: 0;
      margin: 0;
      font-size: 16px;
    }
    .remote-node-title span {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .remote-badges { justify-content: flex-end; flex-wrap: wrap; }
    .remote-badge {
      border: 1px solid var(--line);
      border-radius: 999px;
      padding: 3px 8px;
      color: var(--muted);
      font-size: 12px;
    }
    .remote-badge-readonly { color: var(--wait); }
    .remote-badge-fresh { color: var(--ok); }
    .remote-badge-stale { color: var(--wait); }
    .remote-badge-unreachable, .remote-badge-config_error { color: var(--danger); }
    .remote-ticket-list { display: grid; gap: 8px; }
    .remote-ticket-row {
      display: grid;
      grid-template-columns: minmax(220px, 1fr) minmax(160px, 0.7fr) minmax(110px, 0.45fr);
      gap: 10px;
      align-items: center;
      min-width: 0;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel-2);
      padding: 10px;
    }
    .remote-main, .remote-meta {
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .remote-main {
      display: inline-flex;
      align-items: center;
      gap: 7px;
      font-weight: 700;
    }
    .remote-meta { color: var(--muted); font-size: 13px; }
    @media (max-width: 900px) {
      .ticket-counts { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .ticket-row, .ticket-row-invalid, .remote-ticket-row { grid-template-columns: minmax(0, 1fr); align-items: start; }
      .tickets-header { flex-direction: column; }
      .tickets-nav, .remote-badges { justify-content: flex-start; flex-wrap: wrap; }
    }
    @media (max-width: 560px) {
      .tickets-page { padding: 18px 10px; }
      .ticket-counts { grid-template-columns: 1fr; }
      .remote-node-header { align-items: flex-start; flex-direction: column; }
    }
    """
  end
end
