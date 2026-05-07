defmodule BabsWeb.CitizensLive do
  @moduledoc """
  Multi-Citizen browser index.
  """

  use Phoenix.LiveView

  alias Babs.Citizens.{Catalog, Lifecycle, StatusSnapshot}
  alias BabsWeb.CitizenPath
  alias BabsWeb.TicketPath
  alias Phoenix.LiveView.JS

  @refresh_ms 1_000

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: schedule_refresh()

    {:ok,
     socket
     |> assign(:socket_token, Map.get(session, "socket_token", ""))
     |> assign(:lifecycle_inflight, %{})
     |> assign_snapshots()}
  end

  @impl true
  def handle_info(:refresh_citizens, socket) do
    if connected?(socket), do: schedule_refresh()

    {:noreply, assign_snapshots(socket)}
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

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      :root {
        color-scheme: dark;
        --bg: #0d0d10;
        --panel: #16181d;
        --panel-2: #1d2027;
        --line: #2a2f39;
        --text: #e7eaf0;
        --muted: #9da5b4;
        --field: #0b0c0f;
        --ok: #43d17d;
        --wait: #d7ae55;
        --paused: #9da5b4;
        --danger: #dc6b6b;
        --accent: #55b3a6;
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
      }

      button.button {
        font: inherit;
        cursor: pointer;
      }

      .button:hover {
        border-color: var(--accent);
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
        color: #07100e;
        font-weight: 700;
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
      .lifecycle-reminder {
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

      @media (max-width: 900px) {
        .citizens-counts { grid-template-columns: repeat(2, minmax(0, 1fr)); }
        .citizen-row {
          grid-template-columns: minmax(0, 1fr);
          align-items: start;
        }
        .citizen-actions { justify-content: flex-start; }
      }

      @media (max-width: 560px) {
        .citizens-page { padding: 18px 10px; }
        .citizens-header { flex-direction: column; }
        .citizens-nav { justify-content: flex-start; flex-wrap: wrap; }
        .citizens-counts { grid-template-columns: 1fr; }
        .citizen-actions { flex-wrap: wrap; }
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

  defp counts(snapshots) do
    base = %{total: length(snapshots), up: 0, reattaching: 0, stopped: 0, failed: 0}

    Enum.reduce(snapshots, base, fn snapshot, acc ->
      Map.update(acc, snapshot.live_status, 1, &(&1 + 1))
    end)
  end

  defp action?(citizen, action), do: Enum.member?(Map.get(citizen, :actions, []), action)

  defp button_label(%{imported?: true}, :start), do: "Attach"
  defp button_label(%{imported?: true}, :stop), do: "Detach"
  defp button_label(%{imported?: true}, :restart), do: "Reattach"
  defp button_label(_citizen, :start), do: "Start"
  defp button_label(_citizen, :stop), do: "Stop"
  defp button_label(_citizen, :restart), do: "Restart"

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
end
