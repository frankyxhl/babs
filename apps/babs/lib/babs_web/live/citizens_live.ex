defmodule BabsWeb.CitizensLive do
  @moduledoc """
  Multi-Citizen browser index.
  """

  use Phoenix.LiveView

  alias Babs.Citizens.{Catalog, Lifecycle, StatusSnapshot}
  alias Babs.Citizens.Federation.PeerClient
  alias BabsWeb.CitizenPath
  alias BabsWeb.TicketPath
  alias Phoenix.LiveView.JS

  @refresh_ms 1_000
  @remote_refresh_ms 5_000

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      schedule_refresh()
      schedule_remote_refresh()
    end

    socket =
      socket
      |> assign(:socket_token, Map.get(session, "socket_token", ""))
      |> assign(:lifecycle_inflight, %{})
      |> assign(:remote_peer, nil)
      |> assign(:remote_peer_inflight, false)
      |> assign_snapshots()

    socket = if connected?(socket), do: start_remote_peer_fetch(socket), else: socket

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh_citizens, socket) do
    if connected?(socket), do: schedule_refresh()

    {:noreply, assign_snapshots(socket)}
  end

  def handle_info(:refresh_remote_peer, socket) do
    if connected?(socket) do
      schedule_remote_refresh()
      {:noreply, start_remote_peer_fetch(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("lifecycle", %{"action" => action, "slug" => slug}, socket) do
    case parse_action(action) do
      {:ok, action} ->
        {:noreply, start_lifecycle(socket, action, slug)}

      :error ->
        {:noreply, put_flash(socket, :error, "Unknown lifecycle action")}
    end
  end

  def handle_event("remote_citizen_lifecycle", %{"action" => "restart", "slug" => slug}, socket) do
    if remote_citizen_control_allowed?(socket.assigns.remote_peer, slug) do
      case remote_citizen_action(:restart, socket.assigns.remote_peer, slug) do
        {:ok, _result} ->
          {:noreply, put_flash(socket, :info, "Remote restart sent")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Remote restart failed")}
      end
    else
      {:noreply, put_flash(socket, :error, "Remote citizen is read-only")}
    end
  end

  def handle_event("remote_citizen_lifecycle", _params, socket) do
    {:noreply, put_flash(socket, :error, "Unknown remote lifecycle action")}
  end

  @impl true
  def handle_async({:lifecycle, slug, action}, {:ok, result}, socket) do
    socket =
      socket
      |> clear_lifecycle_inflight(slug)
      |> then(fn socket -> assign_lifecycle_result(result, socket, action, slug) end)
      |> assign_snapshots()

    {:noreply, socket}
  end

  def handle_async({:lifecycle, slug, action}, {:exit, reason}, socket) do
    socket =
      socket
      |> clear_lifecycle_inflight(slug)
      |> then(fn socket -> assign_lifecycle_result({:error, reason}, socket, action, slug) end)
      |> assign_snapshots()

    {:noreply, socket}
  end

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
      :root {
        color-scheme: light;
        --bg: #f6f8fa;
        --panel: #ffffff;
        --panel-2: #f3f4f6;
        --line: #d0d7de;
        --line-strong: #8c959f;
        --text: #1f2328;
        --muted: #57606a;
        --field: #ffffff;
        --ok: #1a7f37;
        --wait: #9a6700;
        --paused: #6e7781;
        --danger: #cf222e;
        --accent: #0969da;
      }

      * { box-sizing: border-box; }

      html, body {
        min-height: 100%;
        margin: 0;
        background: var(--bg);
        color: var(--text);
        font: 15px/1.5 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }

      .citizens-page {
        min-height: 100vh;
        padding: 28px clamp(14px, 3vw, 38px);
      }

      .citizens-shell {
        width: min(1180px, 100%);
        margin: 0 auto;
        display: grid;
        gap: 18px;
      }

      .citizens-header {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 16px;
      }

      h1 {
        margin: 0;
        font-size: 27px;
        line-height: 1.12;
        font-weight: 700;
        letter-spacing: 0;
      }

      .citizens-subtitle {
        margin: 5px 0 0;
        color: var(--muted);
        font-size: 13px;
      }

      .button {
        border: 1px solid var(--line);
        border-radius: 6px;
        background: var(--panel);
        color: var(--text);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 7px;
        min-height: 44px;
        padding: 9px 12px;
        text-decoration: none;
        white-space: nowrap;
      }

      button.button {
        font: inherit;
        cursor: pointer;
      }

      .button:hover {
        border-color: var(--line-strong);
        background: var(--panel-2);
      }

      .button-disabled {
        cursor: not-allowed;
        opacity: 0.55;
      }

      .button-disabled:hover {
        border-color: var(--line);
        color: var(--text);
      }

      .button-primary {
        border-color: transparent;
        background: var(--accent);
        color: #ffffff;
        font-weight: 700;
      }

      .button-primary:hover {
        border-color: transparent;
        background: #0757b8;
        color: #ffffff;
      }

      .button-danger:hover {
        border-color: var(--danger);
      }

      .flash {
        border: 1px solid var(--line);
        border-radius: 8px;
        background: var(--panel);
        padding: 10px 12px;
        color: var(--text);
      }

      .flash-error {
        border-color: var(--danger);
        color: var(--danger);
      }

      .citizens-counts {
        display: grid;
        grid-template-columns: repeat(5, minmax(0, 1fr));
        gap: 10px;
      }

      .citizens-nav {
        display: flex;
        align-items: center;
        justify-content: flex-end;
        gap: 8px;
      }

      .icon {
        width: 16px;
        height: 16px;
        flex: 0 0 auto;
      }

      .citizens-count {
        min-width: 0;
        border: 1px solid var(--line);
        border-radius: 8px;
        background: var(--panel);
        padding: 12px;
      }

      .citizens-count-label {
        color: var(--muted);
        font-size: 12px;
        text-transform: uppercase;
      }

      .citizens-count-value {
        display: block;
        margin-top: 4px;
        font-size: 24px;
        line-height: 1;
        font-weight: 700;
      }

      .citizens-list {
        display: grid;
        gap: 10px;
      }

      .citizen-row {
        display: grid;
        grid-template-columns: minmax(180px, 1.1fr) minmax(112px, 0.55fr) minmax(130px, 0.65fr) minmax(120px, 0.55fr) minmax(170px, 1fr) auto;
        gap: 12px;
        align-items: center;
        min-width: 0;
        border: 1px solid var(--line);
        border-radius: 8px;
        background: var(--panel);
        padding: 12px;
      }

      .citizen-main,
      .citizen-meta,
      .citizen-error {
        min-width: 0;
      }

      .citizen-name {
        display: block;
        overflow: hidden;
        color: var(--text);
        font-weight: 700;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .citizen-slug,
      .citizen-meta,
      .citizen-error {
        overflow: hidden;
        color: var(--muted);
        font-size: 13px;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .citizen-error {
        color: var(--danger);
      }

      .ownership-badge,
      .lifecycle-reminder,
      .role-chip {
        display: inline-flex;
        align-items: center;
        width: fit-content;
        margin-top: 5px;
        border: 1px solid var(--line);
        border-radius: 999px;
        padding: 2px 7px;
        color: var(--wait);
        font-size: 12px;
        white-space: nowrap;
      }

      .lifecycle-reminder {
        margin-top: 0;
        color: var(--muted);
      }

      .role-list {
        display: flex;
        flex-wrap: wrap;
        gap: 5px;
        margin-top: 7px;
        min-width: 0;
      }

      .role-chip {
        gap: 5px;
        max-width: 100%;
        margin-top: 0;
        color: var(--accent);
        overflow: hidden;
      }

      .role-chip .icon {
        width: 13px;
        height: 13px;
      }

      .role-name,
      .role-skills {
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .role-skills {
        color: var(--muted);
      }

      .status-pill {
        display: inline-flex;
        align-items: center;
        gap: 7px;
        color: var(--muted);
        font-size: 13px;
      }

      .status-dot {
        width: 9px;
        height: 9px;
        flex: 0 0 auto;
        border-radius: 999px;
        background: var(--paused);
      }

      .status-up .status-dot { background: var(--ok); }
      .status-reattaching .status-dot { background: var(--wait); }
      .status-stopped .status-dot { background: var(--paused); }
      .status-failed .status-dot { background: var(--danger); }

      .citizen-actions {
        display: flex;
        justify-content: flex-end;
        gap: 8px;
      }

      .citizens-empty {
        border: 1px solid var(--line);
        border-radius: 8px;
        background: var(--panel);
        padding: 24px;
        color: var(--muted);
      }

      .remote-node {
        display: grid;
        gap: 10px;
        border: 1px solid var(--line);
        border-radius: 8px;
        background: var(--panel);
        padding: 12px;
      }

      .remote-node-header,
      .remote-badges {
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

      .remote-badges {
        justify-content: flex-end;
        flex-wrap: wrap;
      }

      .remote-badge {
        border: 1px solid var(--line);
        border-radius: 999px;
        padding: 3px 8px;
        color: var(--muted);
        font-size: 12px;
      }

      .remote-badge-readonly { color: var(--wait); }
      .remote-badge-write { color: var(--accent); }
      .remote-badge-control { color: var(--ok); }
      .remote-badge-fresh { color: var(--ok); }
      .remote-badge-stale { color: var(--wait); }
      .remote-badge-unreachable, .remote-badge-config_error { color: var(--danger); }

      .remote-list {
        display: grid;
        gap: 8px;
      }

      .remote-row {
        display: grid;
        grid-template-columns: minmax(180px, 1fr) minmax(110px, 0.45fr) minmax(120px, 0.55fr) auto;
        gap: 10px;
        align-items: center;
        min-width: 0;
        border: 1px solid var(--line);
        border-radius: 8px;
        background: var(--panel-2);
        padding: 10px;
      }

      .remote-main,
      .remote-meta {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .remote-main {
        font-weight: 700;
      }

      .remote-meta {
        color: var(--muted);
        font-size: 13px;
      }

      .remote-actions {
        display: flex;
        justify-content: flex-end;
      }

      @media (max-width: 900px) {
        .citizens-counts { grid-template-columns: repeat(2, minmax(0, 1fr)); }
        .citizen-row, .remote-row {
          grid-template-columns: minmax(0, 1fr);
          align-items: start;
        }
        .citizen-actions, .remote-badges, .remote-actions { justify-content: flex-start; }
      }

      @media (max-width: 560px) {
        .citizens-page { padding: 18px 10px; }
        .citizens-header { flex-direction: column; }
        .citizens-nav { justify-content: flex-start; flex-wrap: wrap; }
        .citizens-counts { grid-template-columns: 1fr; }
        .citizen-actions { flex-wrap: wrap; }
        .remote-node-header { align-items: flex-start; flex-direction: column; }
      }
    </style>

    <div class="citizens-page" data-testid="citizens-index">
      <main class="citizens-shell">
        <header class="citizens-header">
          <div>
            <h1>Citizens</h1>
            <p class="citizens-subtitle">Running terminals and durable Citizen records</p>
          </div>
          <nav class="citizens-nav" aria-label="Citizen navigation">
            <a class="button" href={TicketPath.index(@socket_token)} data-testid="citizens-nav-tickets">
              <BabsWeb.Icon.icon name="list" /> Tickets
            </a>
            <a class="button" href={CitizenPath.attach(@socket_token)} data-testid="citizens-nav-attach">
              <BabsWeb.Icon.icon name="link" /> Attach tmux
            </a>
            <a class="button button-primary" href={CitizenPath.new(@socket_token)}>
              <BabsWeb.Icon.icon name="plus" /> New Citizen
            </a>
          </nav>
        </header>

        <div :if={Phoenix.Flash.get(@flash, :info)} class="flash" data-testid="citizens-flash-info">
          {Phoenix.Flash.get(@flash, :info)}
        </div>

        <div
          :if={Phoenix.Flash.get(@flash, :error)}
          class="flash flash-error"
          data-testid="citizens-flash-error"
        >
          {Phoenix.Flash.get(@flash, :error)}
        </div>

        <section class="citizens-counts" aria-label="Citizen status counts">
          <div class="citizens-count" data-testid="citizens-count-total">
            <span class="citizens-count-label">Total</span>
            <span class="citizens-count-value">{@counts.total}</span>
          </div>
          <div class="citizens-count" data-testid="citizens-count-up">
            <span class="citizens-count-label">Up</span>
            <span class="citizens-count-value">{@counts.up}</span>
          </div>
          <div class="citizens-count" data-testid="citizens-count-reattaching">
            <span class="citizens-count-label">Reattaching</span>
            <span class="citizens-count-value">{@counts.reattaching}</span>
          </div>
          <div class="citizens-count" data-testid="citizens-count-stopped">
            <span class="citizens-count-label">Stopped</span>
            <span class="citizens-count-value">{@counts.stopped}</span>
          </div>
          <div class="citizens-count" data-testid="citizens-count-failed">
            <span class="citizens-count-label">Failed</span>
            <span class="citizens-count-value">{@counts.failed}</span>
          </div>
        </section>

        <section :if={@snapshots == []} class="citizens-empty" data-testid="citizens-empty-state">
          No Citizens yet.
        </section>

        <section :if={@snapshots != []} class="citizens-list" aria-label="Citizens">
          <article :for={citizen <- @snapshots} class="citizen-row" data-testid={"citizen-row-#{citizen.slug}"}>
            <div class="citizen-main">
              <span class="citizen-name">{citizen.display_name}</span>
              <span class="citizen-slug">{citizen.slug}</span>
              <div
                :if={role_count(citizen) > 0}
                class="role-list"
                data-testid={"citizen-roles-#{citizen.slug}"}
              >
                <span
                  :for={{role, index} <- Enum.with_index(citizen.roles)}
                  class="role-chip"
                  data-testid={"citizen-role-#{citizen.slug}-#{index}"}
                  title={role_title(role)}
                >
                  <BabsWeb.Icon.icon name="tag" />
                  <span class="role-name">{role_name(role)}</span>
                  <span :if={role_skills(role) != []} class="role-skills">
                    {Enum.join(role_skills(role), ", ")}
                  </span>
                </span>
              </div>
              <span
                :if={citizen.ownership_badge}
                class="ownership-badge"
                data-testid={"citizen-ownership-#{citizen.slug}"}
              >
                {citizen.ownership_badge}
              </span>
            </div>

            <div
              class={"status-pill status-#{citizen.live_status}"}
              data-testid={"citizen-status-#{citizen.slug}"}
            >
              <span class="status-dot" aria-hidden="true"></span>
              {citizen.live_status}
            </div>

            <div class="citizen-meta">{citizen.cli_label}</div>
            <div class="citizen-meta" data-testid={"citizen-backend-#{citizen.slug}"}>
              {citizen.ticket_backend_label}
            </div>
            <div class={if citizen.last_error, do: "citizen-error", else: "citizen-meta"}>
              {citizen.last_error || citizen.target_label || citizen.cwd_label}
            </div>

             <div class="citizen-actions" data-lifecycle-scope={citizen.slug}>
              <a
                 :if={action?(citizen, :open)}
                 class="button"
                href={CitizenPath.terminal(citizen.slug, @socket_token)}
                data-testid={"citizen-open-#{citizen.slug}"}
              >
                <BabsWeb.Icon.icon name="external-link" /> Open
              </a>
              <span
                :if={!action?(citizen, :open)}
                class="button button-disabled"
                aria-disabled="true"
                data-testid={"citizen-open-#{citizen.slug}"}
              >
                <BabsWeb.Icon.icon name="external-link" /> Open
              </span>
              <a
                :if={action?(citizen, :full)}
                class="button"
                href={CitizenPath.terminal(citizen.slug, @socket_token, full?: true)}
                data-testid={"citizen-full-#{citizen.slug}"}
              >
                <BabsWeb.Icon.icon name="maximize" /> Full
              </a>
              <span
                :if={!action?(citizen, :full)}
                class="button button-disabled"
                aria-disabled="true"
                data-testid={"citizen-full-#{citizen.slug}"}
              >
                <BabsWeb.Icon.icon name="maximize" /> Full
              </span>
               <button
                 :if={action?(citizen, :start)}
                 type="button"
                 class={["button", lifecycle_busy?(@lifecycle_inflight, citizen.slug) && "button-disabled"]}
                 phx-click={lifecycle_click(citizen.slug, :start)}
                 disabled={lifecycle_busy?(@lifecycle_inflight, citizen.slug)}
                 phx-disable-with="Starting"
                 data-testid={"citizen-start-#{citizen.slug}"}
               >
                <BabsWeb.Icon.icon name="play" /> {button_label(citizen, :start)}
              </button>
               <button
                 :if={action?(citizen, :stop)}
                 type="button"
                 class={[
                   "button button-danger",
                   lifecycle_busy?(@lifecycle_inflight, citizen.slug) && "button-disabled"
                 ]}
                 phx-click={lifecycle_click(citizen.slug, :stop)}
                 disabled={lifecycle_busy?(@lifecycle_inflight, citizen.slug)}
                 phx-disable-with="Stopping"
                 data-testid={"citizen-stop-#{citizen.slug}"}
               >
                <BabsWeb.Icon.icon name="square" /> {button_label(citizen, :stop)}
              </button>
              <span
                :if={action?(citizen, :stop) && citizen.lifecycle_reminder}
                class="lifecycle-reminder"
                data-testid={"citizen-lifecycle-reminder-#{citizen.slug}"}
              >
                {citizen.lifecycle_reminder}
              </span>
               <button
                 :if={action?(citizen, :restart)}
                 type="button"
                 class={["button", lifecycle_busy?(@lifecycle_inflight, citizen.slug) && "button-disabled"]}
                 phx-click={lifecycle_click(citizen.slug, :restart)}
                 disabled={lifecycle_busy?(@lifecycle_inflight, citizen.slug)}
                 phx-disable-with="Restarting"
                 data-testid={"citizen-restart-#{citizen.slug}"}
               >
                <BabsWeb.Icon.icon name="rotate-cw" /> {button_label(citizen, :restart)}
              </button>
            </div>
          </article>
        </section>

        <section :if={@remote_peer} class="remote-node" data-testid="remote-peer-citizens">
          <header class="remote-node-header">
            <h2 class="remote-node-title">
              <BabsWeb.Icon.icon name="route" />
              <span>{remote_node_label(@remote_peer)}</span>
            </h2>
            <div class="remote-badges">
              <span class={["remote-badge", remote_capability_class(@remote_peer)]}>
                {remote_capability_label(@remote_peer)}
              </span>
              <span class={["remote-badge", remote_status_class(@remote_peer)]}>
                {remote_status(@remote_peer)}
              </span>
            </div>
          </header>

          <div class="remote-list" data-testid="remote-citizen-list">
            <article
              :for={citizen <- @remote_peer.citizens}
              class="remote-row"
              data-testid={"remote-citizen-#{remote_value(citizen, "slug")}"}
            >
              <div class="remote-main">{remote_value(citizen, "display_name") || remote_value(citizen, "slug")}</div>
              <div class="remote-meta">{remote_value(citizen, "slug")}</div>
              <div class="remote-meta">{remote_value(citizen, "live_status")}</div>
              <div class="remote-actions">
                <button
                  type="button"
                  class={[
                    "button",
                    !remote_citizen_control_allowed?(@remote_peer, remote_value(citizen, "slug")) &&
                      "button-disabled"
                  ]}
                  phx-click="remote_citizen_lifecycle"
                  phx-value-action="restart"
                  phx-value-slug={remote_value(citizen, "slug")}
                  disabled={!remote_citizen_control_allowed?(@remote_peer, remote_value(citizen, "slug"))}
                  data-testid={"remote-citizen-restart-#{remote_value(citizen, "slug")}"}
                >
                  <BabsWeb.Icon.icon name="rotate-cw" /> Restart
                </button>
              </div>
            </article>
            <div :if={@remote_peer.citizens == []} class="remote-meta" data-testid="remote-citizens-empty">
              No remote Citizens.
            </div>
          </div>
        </section>
      </main>
    </div>

    <script type="module" src="/js/live_boot.js">
    </script>
    """
  end

  defp assign_snapshots(socket) do
    snapshots = StatusSnapshot.list()

    socket
    |> assign(:snapshots, snapshots)
    |> assign(:counts, counts(snapshots))
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

  defp counts(snapshots) do
    base = %{total: length(snapshots), up: 0, reattaching: 0, stopped: 0, failed: 0}

    Enum.reduce(snapshots, base, fn snapshot, acc ->
      Map.update(acc, snapshot.live_status, 1, &(&1 + 1))
    end)
  end

  defp action?(citizen, action), do: Enum.member?(Map.get(citizen, :actions, []), action)

  defp role_count(citizen), do: length(Map.get(citizen, :roles, []) || [])

  defp role_name(%{"name" => name}) when is_binary(name), do: name
  defp role_name(_role), do: ""

  defp role_skills(%{"skills" => skills}) when is_list(skills), do: skills
  defp role_skills(_role), do: []

  defp role_title(role) do
    case role_skills(role) do
      [] -> role_name(role)
      skills -> "#{role_name(role)}: #{Enum.join(skills, ", ")}"
    end
  end

  defp button_label(citizen, :start), do: if(detach_only?(citizen), do: "Attach", else: "Start")
  defp button_label(citizen, :stop), do: if(detach_only?(citizen), do: "Detach", else: "Stop")

  defp button_label(citizen, :restart),
    do: if(detach_only?(citizen), do: "Reattach", else: "Restart")

  defp detach_only?(citizen) do
    Map.get(citizen, :detach_authority?) == true and Map.get(citizen, :kill_authority?) != true
  end

  defp lifecycle_click(slug, action) do
    selector = lifecycle_button_selector(slug)

    JS.set_attribute({"disabled", "disabled"}, to: selector)
    |> JS.add_class("button-disabled", to: selector)
    |> JS.push("lifecycle", value: %{"action" => Atom.to_string(action), "slug" => slug})
  end

  defp lifecycle_button_selector(slug), do: ~s([data-lifecycle-scope="#{slug}"] button)

  defp lifecycle_busy?(inflight, slug), do: Map.has_key?(inflight, slug)

  defp parse_action("start"), do: {:ok, :start}
  defp parse_action("stop"), do: {:ok, :stop}
  defp parse_action("restart"), do: {:ok, :restart}
  defp parse_action(_action), do: :error

  defp start_lifecycle(socket, action, slug) do
    if lifecycle_busy?(socket.assigns.lifecycle_inflight, slug) do
      put_flash(socket, :error, "Lifecycle action already running for #{slug}")
    else
      socket
      |> assign(:lifecycle_inflight, Map.put(socket.assigns.lifecycle_inflight, slug, action))
      |> start_async({:lifecycle, slug, action}, fn -> lifecycle_action(action, slug) end)
      |> assign_snapshots()
    end
  end

  defp clear_lifecycle_inflight(socket, slug) do
    assign(socket, :lifecycle_inflight, Map.delete(socket.assigns.lifecycle_inflight, slug))
  end

  defp lifecycle_action(action, slug) do
    :babs
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:lifecycle_action, &default_lifecycle_action/2)
    |> then(fn handler -> handler.(action, slug) end)
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

  defp remote_citizen_action(action, peer, slug) do
    :babs
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:remote_citizen_action, &default_remote_citizen_action/3)
    |> then(fn handler -> handler.(action, peer, slug) end)
  end

  defp default_remote_citizen_action(:restart, peer, slug),
    do: PeerClient.lifecycle_citizen(peer, slug, "restart")

  defp remote_citizen_control_allowed?(peer, slug) when is_binary(slug) do
    remote_capability?(peer, "control") and remote_citizen_capability?(peer, slug, "control")
  end

  defp remote_citizen_control_allowed?(_peer, _slug), do: false

  defp remote_citizen_capability?(peer, slug, capability) when is_map(peer) do
    overrides =
      Map.get(peer, :citizen_capabilities) || Map.get(peer, "citizen_capabilities") || %{}

    case Map.get(overrides, slug) || Map.get(overrides, to_string(slug)) do
      nil -> true
      capabilities -> capability in capabilities
    end
  end

  defp remote_citizen_capability?(_peer, _slug, _capability), do: false

  defp remote_capability_label(peer) do
    cond do
      remote_capability?(peer, "control") -> "Control-enabled"
      remote_capability?(peer, "write") -> "Writable"
      true -> "Read-only"
    end
  end

  defp remote_capability_class(peer) do
    cond do
      remote_capability?(peer, "control") -> "remote-badge-control"
      remote_capability?(peer, "write") -> "remote-badge-write"
      true -> "remote-badge-readonly"
    end
  end

  defp remote_capability?(peer, capability) when is_map(peer) do
    capability in (Map.get(peer, :capabilities) || Map.get(peer, "capabilities") || [])
  end

  defp remote_capability?(_peer, _capability), do: false

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

  defp remote_atom_value(map, "slug"), do: Map.get(map, :slug)
  defp remote_atom_value(map, "display_name"), do: Map.get(map, :display_name)
  defp remote_atom_value(map, "live_status"), do: Map.get(map, :live_status)
  defp remote_atom_value(_map, _key), do: nil

  defp default_lifecycle_action(:start, slug), do: Lifecycle.start_registered_citizen(slug)
  defp default_lifecycle_action(:stop, slug), do: Lifecycle.stop_citizen(slug)
  defp default_lifecycle_action(:restart, slug), do: Lifecycle.restart_registered_citizen(slug)

  defp assign_lifecycle_result(:ok, socket, action, slug) do
    put_flash(socket, :info, "#{action_label(action)} #{slug}")
  end

  defp assign_lifecycle_result({:ok, _pid}, socket, action, slug) do
    put_flash(socket, :info, "#{action_label(action)} #{slug}")
  end

  defp assign_lifecycle_result({:error, reason}, socket, action, slug) do
    message = "#{action_error_label(action)} failed for #{slug}: #{Catalog.redact_reason(reason)}"
    put_flash(socket, :error, message)
  end

  defp action_label(:start), do: "Started"
  defp action_label(:stop), do: "Stopped"
  defp action_label(:restart), do: "Restarted"

  defp action_error_label(:start), do: "Start"
  defp action_error_label(:stop), do: "Stop"
  defp action_error_label(:restart), do: "Restart"

  defp schedule_refresh do
    Process.send_after(self(), :refresh_citizens, @refresh_ms)
  end

  defp schedule_remote_refresh do
    Process.send_after(self(), :refresh_remote_peer, @remote_refresh_ms)
  end
end
