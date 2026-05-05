defmodule BabsWeb.TerminalLive do
  @moduledoc """
  Phase 1 browser terminal for one Citizen.

  The LiveView owns the page shell and client-side xterm bootstrap. PTY bytes and
  keyboard input still flow through `BabsWeb.PaneChannel`, so reloads do not bind
  Hardline.Pane to a LiveView process.
  """

  use Phoenix.LiveView

  alias Babs.Citizens.StatusSnapshot
  alias BabsWeb.CitizenPath

  @refresh_ms 1_000

  @impl true
  def mount(_params, %{"slug" => slug} = session, socket) do
    full? = full?(session)

    if connected?(socket) and not full?, do: schedule_refresh()

    socket =
      socket
      |> assign(:slug, slug)
      |> assign(:socket_token, Map.get(session, "socket_token", ""))
      |> assign(:full?, full?)
      |> assign_tabs()

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh_terminal_tabs, socket) do
    if connected?(socket) and not socket.assigns.full?, do: schedule_refresh()

    {:noreply, assign_tabs(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <link rel="stylesheet" href="/css/xterm.css" />
    <style>
      :root {
        color-scheme: dark;
        --bg: #0d0d10;
        --terminal-bg: #000000;
        --line: #2a2a30;
        --text: #e7eaf0;
        --muted: #9c9caa;
        --ok: #43d17d;
        --wait: #d7ae55;
        --paused: #9da5b4;
        --danger: #dc6b6b;
        --accent: #55b3a6;
      }

      * {
        box-sizing: border-box;
      }

      html, body, body > div, .terminal-page {
        height: 100%;
        margin: 0;
        background: var(--bg);
      }

      .terminal-page {
        --terminal-chrome-height: 46px;
        min-height: 100vh;
        width: 100vw;
        overflow: hidden;
      }

      .terminal-chrome {
        height: var(--terminal-chrome-height);
        display: grid;
        grid-template-columns: auto minmax(0, 1fr) auto;
        align-items: center;
        gap: 8px;
        border-bottom: 1px solid var(--line);
        background: #14151a;
        padding: 6px 8px;
      }

      .terminal-link,
      .terminal-tab {
        min-height: 32px;
        border: 1px solid var(--line);
        border-radius: 6px;
        background: #1a1d24;
        color: var(--muted);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 7px;
        padding: 5px 9px;
        text-decoration: none;
        white-space: nowrap;
      }

      .terminal-link:hover,
      .terminal-tab:hover {
        border-color: var(--accent);
        color: var(--text);
      }

      .terminal-tabs {
        min-width: 0;
        display: flex;
        gap: 6px;
        overflow-x: auto;
        scrollbar-width: thin;
      }

      .terminal-tab {
        max-width: 180px;
        flex: 0 0 auto;
      }

      .terminal-tab-label {
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .terminal-tab.is-active {
        border-color: var(--accent);
        color: var(--text);
        background: #20252b;
      }

      .status-dot {
        width: 8px;
        height: 8px;
        flex: 0 0 auto;
        border-radius: 999px;
        background: var(--paused);
      }

      .status-up .status-dot { background: var(--ok); }
      .status-reattaching .status-dot { background: var(--wait); }
      .status-stopped .status-dot { background: var(--paused); }
      .status-failed .status-dot { background: var(--danger); }

      #terminal {
        width: 100vw;
        overflow: hidden;
        background: var(--terminal-bg);
      }

      .terminal-page[data-mode="tabs"] #terminal {
        height: calc(100vh - var(--terminal-chrome-height));
      }

      .terminal-page[data-mode="full"] #terminal {
        height: 100vh;
      }

      #connection-status {
        position: fixed;
        top: 8px;
        right: 10px;
        z-index: 10;
        padding: 5px 8px;
        border: 1px solid var(--line);
        border-radius: 6px;
        background: rgba(16, 16, 20, 0.82);
        color: var(--muted);
        display: inline-flex;
        align-items: center;
        gap: 6px;
        font: 12px/1.4 system-ui, sans-serif;
      }

      #connection-status::before {
        content: "";
        width: 7px;
        height: 7px;
        border-radius: 999px;
        background: var(--muted);
        box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.35);
      }

      #connection-status[data-state="connected"] { color: var(--ok); }
      #connection-status[data-state="error"] { color: var(--danger); }
      #connection-status[data-state="connected"]::before { background: var(--ok); }
      #connection-status[data-state="error"]::before { background: var(--danger); }

      .terminal-page[data-mode="tabs"] #connection-status {
        top: calc(var(--terminal-chrome-height) + 8px);
      }

      @media (max-width: 680px) {
        .terminal-page { --terminal-chrome-height: 84px; }
        .terminal-chrome {
          grid-template-columns: auto auto;
          grid-template-rows: auto auto;
          align-items: stretch;
        }
        .terminal-tabs {
          grid-column: 1 / -1;
          grid-row: 2;
          order: 3;
        }
      }
    </style>
    <div class="terminal-page" data-mode={if @full?, do: "full", else: "tabs"}>
      <nav :if={!@full?} class="terminal-chrome" data-testid="terminal-chrome" aria-label="Citizen terminal navigation">
        <a class="terminal-link" href={CitizenPath.index(@socket_token)} data-testid="citizens-link">Citizens</a>
        <div class="terminal-tabs" aria-label="Citizen tabs">
          <a
            :for={citizen <- live_tabs(@tabs, @slug)}
            class={tab_class(citizen, @slug)}
            href={CitizenPath.terminal(citizen.slug, @socket_token)}
            data-testid={"citizen-tab-#{citizen.slug}"}
          >
            <span class="status-dot" aria-hidden="true"></span>
            <span class="terminal-tab-label">{citizen.slug}</span>
          </a>
        </div>
        <a
          class="terminal-link"
          href={CitizenPath.terminal(@slug, @socket_token, full?: true)}
          data-testid="terminal-full-link"
        >
          Full
        </a>
      </nav>
      <div
        id="connection-status"
        phx-update="ignore"
        data-testid="connection-status"
        data-state="connecting"
      >
        connecting
      </div>
      <div
        id="terminal"
        phx-update="ignore"
        data-testid="terminal"
        data-slug={@slug}
        data-socket-token={@socket_token}
      >
      </div>
    </div>
    <script src="/js/xterm.js">
    </script>
    <script src="/js/xterm-addon-fit.js">
    </script>
    <script type="module" src="/js/terminal_boot.js">
    </script>
    <script :if={!@full?} type="module" src="/js/live_boot.js">
    </script>
    """
  end

  defp assign_tabs(socket) do
    assign(socket, :tabs, tab_provider().(socket.assigns.slug))
  end

  defp live_tabs(tabs, slug) do
    tabs
    |> Enum.filter(&(&1.live_status == :up or &1.slug == slug))
    |> ensure_active_tab(slug)
    |> Enum.sort_by(& &1.slug)
  end

  defp ensure_active_tab(tabs, slug) do
    if Enum.any?(tabs, &(&1.slug == slug)) do
      tabs
    else
      tabs ++ [fallback_tab(slug)]
    end
  end

  defp fallback_tab(slug) do
    %{
      slug: slug,
      display_name: slug,
      live_status: :up,
      cli_label: "",
      cwd_label: "",
      last_error: nil
    }
  end

  defp tab_class(citizen, slug) do
    base =
      if citizen.slug == slug do
        "terminal-tab is-active"
      else
        "terminal-tab"
      end

    base <> " status-#{citizen.live_status}"
  end

  defp tab_provider do
    :babs
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:status_snapshot_provider, fn -> StatusSnapshot.list() end)
    |> then(fn provider -> fn _slug -> provider.() end end)
  end

  defp full?(%{"full?" => true}), do: true
  defp full?(%{"full?" => "true"}), do: true
  defp full?(%{"full" => value}) when value in ["1", "true"], do: true
  defp full?(_session), do: false

  defp schedule_refresh do
    Process.send_after(self(), :refresh_terminal_tabs, @refresh_ms)
  end
end
