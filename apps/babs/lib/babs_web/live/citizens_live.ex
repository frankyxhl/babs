defmodule BabsWeb.CitizensLive do
  @moduledoc """
  Multi-Citizen browser index.
  """

  use Phoenix.LiveView

  alias Babs.Citizens.StatusSnapshot
  alias BabsWeb.CitizenPath

  @refresh_ms 1_000

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: schedule_refresh()

    {:ok,
     socket
     |> assign(:socket_token, Map.get(session, "socket_token", ""))
     |> assign_snapshots()}
  end

  @impl true
  def handle_info(:refresh_citizens, socket) do
    if connected?(socket), do: schedule_refresh()

    {:noreply, assign_snapshots(socket)}
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
        min-height: 36px;
        padding: 7px 11px;
        text-decoration: none;
        white-space: nowrap;
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

      .citizens-counts {
        display: grid;
        grid-template-columns: repeat(5, minmax(0, 1fr));
        gap: 10px;
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
        grid-template-columns: minmax(180px, 1.1fr) minmax(112px, 0.55fr) minmax(130px, 0.65fr) minmax(170px, 1fr) auto;
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
          <a class="button button-primary" href={CitizenPath.new(@socket_token)}>New Citizen</a>
        </header>

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
            </div>

            <div
              class={"status-pill status-#{citizen.live_status}"}
              data-testid={"citizen-status-#{citizen.slug}"}
            >
              <span class="status-dot" aria-hidden="true"></span>
              {citizen.live_status}
            </div>

            <div class="citizen-meta">{citizen.cli_label}</div>
            <div class={if citizen.last_error, do: "citizen-error", else: "citizen-meta"}>
              {citizen.last_error || citizen.cwd_label}
            </div>

            <div class="citizen-actions">
              <a
                :if={citizen.live_status == :up}
                class="button"
                href={CitizenPath.terminal(citizen.slug, @socket_token)}
                data-testid={"citizen-open-#{citizen.slug}"}
              >
                Open
              </a>
              <span
                :if={citizen.live_status != :up}
                class="button button-disabled"
                aria-disabled="true"
                data-testid={"citizen-open-#{citizen.slug}"}
              >
                Open
              </span>
              <a
                :if={citizen.live_status == :up}
                class="button"
                href={CitizenPath.terminal(citizen.slug, @socket_token, full?: true)}
                data-testid={"citizen-full-#{citizen.slug}"}
              >
                Full
              </a>
              <span
                :if={citizen.live_status != :up}
                class="button button-disabled"
                aria-disabled="true"
                data-testid={"citizen-full-#{citizen.slug}"}
              >
                Full
              </span>
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
      Map.update!(acc, snapshot.live_status, &(&1 + 1))
    end)
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh_citizens, @refresh_ms)
  end
end
