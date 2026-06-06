defmodule BabsWeb.KitchenSinkLive do
  @moduledoc """
  Development-only UI kitchen sink for light-theme BabsWeb components.
  """

  use Phoenix.LiveView

  alias BabsWeb.CitizenPath
  alias BabsWeb.GitDiffComponent
  alias BabsWeb.TicketPath

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:socket_token, Map.get(session, "socket_token", ""))
     |> assign(:theme, "light")}
  end

  @impl true
  def handle_event("theme", %{"theme" => theme}, socket) when theme in ["light", "dark"] do
    {:noreply, assign(socket, :theme, theme)}
  end

  def handle_event("theme", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class={"ks-page ks-theme-#{@theme}"} data-testid="kitchen-sink" data-theme={@theme}>
      <main class="ks-shell">
        <header class="ks-header">
          <div>
            <p class="ks-eyebrow">Babs UI System</p>
            <h1>Kitchen Sink</h1>
            <p class="ks-subtitle">Light-first components for Phase 13a Ticket chat and operations chrome.</p>
          </div>

          <nav class="ks-nav" aria-label="Kitchen sink navigation">
            <a class="ks-button" href={TicketPath.index(@socket_token)}>
              <BabsWeb.Icon.icon name="list" /> Tickets
            </a>
            <a class="ks-button" href={CitizenPath.index(@socket_token)}>
              <BabsWeb.Icon.icon name="users" /> Citizens
            </a>
          </nav>
        </header>

        <section class="ks-toolbar" aria-label="Theme selector preview">
          <div>
            <h2>Theme Selector</h2>
            <p>Preview only. This sets the kitchen-sink theme so future controls have a target.</p>
          </div>
          <div class="segmented" role="group" aria-label="Theme">
            <button
              type="button"
              class={theme_button_class(@theme, "light")}
              phx-click="theme"
              phx-value-theme="light"
              data-testid="theme-light"
            >
              Light
            </button>
            <button
              type="button"
              class={theme_button_class(@theme, "dark")}
              phx-click="theme"
              phx-value-theme="dark"
              data-testid="theme-dark"
            >
              Dark
            </button>
          </div>
        </section>

        <section class="ks-grid">
          <article class="ks-card">
            <div class="card-head">
              <div>
                <h2>Buttons</h2>
                <p>Every action keeps an icon and stable dimensions.</p>
              </div>
            </div>
            <div class="button-row">
              <button class="ks-button primary" type="button">
                <BabsWeb.Icon.icon name="send" /> Send
              </button>
              <button class="ks-button" type="button">
                <BabsWeb.Icon.icon name="refresh" /> Retry
              </button>
              <button class="ks-button danger" type="button">
                <BabsWeb.Icon.icon name="ban" /> Cancel
              </button>
              <button class="ks-button" type="button" disabled>
                <BabsWeb.Icon.icon name="clock" /> Busy
              </button>
            </div>
          </article>

          <article class="ks-card">
            <div class="card-head">
              <div>
                <h2>Status Badges</h2>
                <p>Ticket, lifecycle, imported, and delivery state examples.</p>
              </div>
            </div>
            <div class="badge-grid">
              <span class="badge open"><span class="dot"></span> open</span>
              <span class="badge working"><span class="dot"></span> in progress</span>
              <span class="badge pending"><span class="dot"></span> pending approval</span>
              <span class="badge imported"><BabsWeb.Icon.icon name="link" /> Imported / External-owned</span>
              <span class="badge queued">queued</span>
              <span class="badge captured">captured</span>
              <span class="badge failed">failed</span>
            </div>
          </article>
        </section>

        <section class="ticket-layout">
          <aside class="ticket-rail" data-testid="ticket-state-rail">
            <div class="rail-block">
              <p class="rail-label">Ticket</p>
              <h2>T-2026-05-07-013</h2>
              <span class="badge working"><span class="dot"></span> in progress</span>
            </div>

            <div class="rail-block">
              <p class="rail-label">Assignees</p>
              <div class="avatar-row">
                <span>Clare</span>
                <span>Dylan</span>
                <span>Elena</span>
              </div>
            </div>

            <div class="rail-block">
              <p class="rail-label">Delivery</p>
              <dl class="stat-list">
                <div><dt>Clare</dt><dd>captured</dd></div>
                <div><dt>Dylan</dt><dd>delivered</dd></div>
                <div><dt>Elena</dt><dd>queued</dd></div>
              </dl>
            </div>

            <div class="rail-actions">
              <button class="ks-button primary" type="button">
                <BabsWeb.Icon.icon name="check" /> Approve
              </button>
              <button class="ks-button" type="button">
                <BabsWeb.Icon.icon name="maximize" /> Open Full
              </button>
            </div>
          </aside>

          <article class="chat-card" data-testid="ticket-chat-preview">
            <header class="chat-head">
              <div>
                <h2>Ticket Chat</h2>
                <p>Messaging-app flow with operational status kept nearby.</p>
              </div>
              <span class="badge captured">latest reply captured</span>
            </header>

            <ol class="message-list">
              <li class="message mine">
                <div class="bubble">
                  <div class="meta"><strong>You</strong><time>10:00</time><span class="badge delivered">delivered</span></div>
                  <p>Please make the ticket detail support a second follow-up turn.</p>
                </div>
              </li>
              <li class="message system">
                <div class="system-line">
                  <BabsWeb.Icon.icon name="route" /> Sent to Clare, Dylan, and Elena. Elena is queued behind another turn.
                </div>
              </li>
              <li class="message citizen">
                <div class="bubble">
                  <div class="meta"><strong>Clare</strong><time>10:01</time><span class="badge captured">captured</span></div>
                  <p>I will keep comments as visible messages and use turn events for delivery metadata.</p>
                </div>
              </li>
              <li class="message citizen">
                <div class="bubble warning">
                  <div class="meta"><strong>Dylan</strong><time>10:02</time><span class="badge failed">failed</span></div>
                  <p>Direct CLI resume failed. Falling back to Hardline on the next attempt.</p>
                </div>
              </li>
              <li class="message legacy">
                <div class="bubble">
                  <div class="meta"><strong>Legacy Comment</strong><time>09:54</time></div>
                  <p>This older comment has no turn_id but still renders normally.</p>
                </div>
              </li>
            </ol>

            <form class="composer">
              <textarea rows="3" placeholder="Write a follow-up..."></textarea>
              <button class="ks-button primary" type="button">
                <BabsWeb.Icon.icon name="send" /> Send
              </button>
            </form>
          </article>
        </section>

        <section data-testid="git-diff-preview">
          <GitDiffComponent.git_diff
            branch={git_branch_example()}
            status={git_status_example()}
            diff={git_diff_example()}
          />
        </section>

        <section class="ks-grid">
          <article class="ks-card">
            <div class="card-head">
              <div>
                <h2>Forms</h2>
                <p>Validation and dense inputs.</p>
              </div>
            </div>
            <form class="form-preview">
              <label>
                Title
                <input value="Say hello" />
              </label>
              <label>
                Assignee
                <select>
                  <option>Clare</option>
                  <option>Dylan</option>
                  <option>Elena</option>
                </select>
              </label>
              <p class="form-error"><BabsWeb.Icon.icon name="triangle-alert" /> Body is required.</p>
            </form>
          </article>

          <article class="ks-card">
            <div class="card-head">
              <div>
                <h2>Terminal In Light Shell</h2>
                <p>The terminal stays dark; surrounding controls stay light.</p>
              </div>
            </div>
            <div class="terminal-frame" data-testid="terminal-in-light-shell">
              <div class="terminal-top">
                <span>tmux: clare / 120x36</span>
                <button class="icon-button" type="button" aria-label="Open terminal">
                  <BabsWeb.Icon.icon name="maximize" />
                </button>
              </div>
              <pre>{terminal_example()}</pre>
            </div>
          </article>
        </section>

        <section class="ks-grid">
          <article class="ks-card" data-testid="tabs-preview">
            <div class="card-head">
              <div>
                <h2>Tabs</h2>
                <p>Compact navigation for Ticket views.</p>
              </div>
            </div>
            <div class="tab-list" role="tablist" aria-label="Ticket views">
              <button class="tab-button active" type="button" role="tab" aria-selected="true">
                Chat
              </button>
              <button class="tab-button" type="button" role="tab" aria-selected="false">
                Events
              </button>
              <button class="tab-button" type="button" role="tab" aria-selected="false">
                Files
              </button>
            </div>
          </article>

          <article class="ks-card" data-testid="table-preview">
            <div class="card-head">
              <div>
                <h2>Tables</h2>
                <p>Dense operational rows without decorative cards.</p>
              </div>
            </div>
            <div class="table-wrap">
              <table class="ks-table">
                <thead>
                  <tr>
                    <th>Citizen</th>
                    <th>Backend</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td>Clare</td>
                    <td>hardline</td>
                    <td><span class="badge captured">captured</span></td>
                  </tr>
                  <tr>
                    <td>Dylan</td>
                    <td>direct_cli</td>
                    <td><span class="badge delivered">delivered</span></td>
                  </tr>
                  <tr>
                    <td>Elena</td>
                    <td>copilot</td>
                    <td><span class="badge queued">queued</span></td>
                  </tr>
                </tbody>
              </table>
            </div>
          </article>
        </section>

        <section class="ks-grid">
          <article class="ks-card" data-testid="empty-state-preview">
            <div class="card-head">
              <div>
                <h2>Empty States</h2>
                <p>Quiet state for a Ticket with no captured replies yet.</p>
              </div>
            </div>
            <div class="empty-state">
              <BabsWeb.Icon.icon name="clock" />
              <strong>No captured replies</strong>
              <p>Delivery status remains visible while Citizens work.</p>
            </div>
          </article>

          <article class="modal-preview" data-testid="modal-preview">
            <div class="modal-head">
              <div>
                <h2>Modal</h2>
                <p>Confirmation surface for irreversible Ticket actions.</p>
              </div>
              <span class="badge pending">preview</span>
            </div>
            <p>
              Close this Ticket after the latest replies are captured and reviewed.
            </p>
            <div class="modal-actions">
              <button class="ks-button" type="button">Cancel</button>
              <button class="ks-button primary" type="button">
                <BabsWeb.Icon.icon name="check" /> Confirm
              </button>
            </div>
          </article>
        </section>
      </main>
    </div>
    """
  end

  defp theme_button_class(current, theme) do
    if current == theme, do: "segmented-button active", else: "segmented-button"
  end

  defp terminal_example do
    [
      "$ bb ticket show T-2026-05-07-013",
      "state: in_progress",
      "assignees: clare, dylan, elena",
      "",
      "assistant: ready for the next turn"
    ]
    |> Enum.join("\n")
  end

  defp git_branch_example do
    %{name: "issue/100-git-diff-liveview", detached?: false, truncated?: false}
  end

  defp git_status_example do
    %{text: " M apps/babs/lib/babs_web/live/ticket_live.ex", clean?: false, truncated?: false}
  end

  defp git_diff_example do
    %{
      text: """
      diff --git a/apps/babs/lib/babs_web/live/ticket_live.ex b/apps/babs/lib/babs_web/live/ticket_live.ex
      --- a/apps/babs/lib/babs_web/live/ticket_live.ex
      +++ b/apps/babs/lib/babs_web/live/ticket_live.ex
      @@ -10,2 +10,3 @@
       alias BabsWeb.TicketPath
      +alias BabsWeb.GitDiffComponent
       alias BabsWeb.TicketPresenter
      """,
      truncated?: false,
      base: nil
    }
  end
end
