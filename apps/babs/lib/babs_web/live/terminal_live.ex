defmodule BabsWeb.TerminalLive do
  @moduledoc """
  Phase 1 browser terminal for one Citizen.

  The LiveView owns the page shell and client-side xterm bootstrap. PTY bytes and
  keyboard input still flow through `BabsWeb.PaneChannel`, so reloads do not bind
  Hardline.Pane to a LiveView process.
  """

  use Phoenix.LiveView

  @impl true
  def mount(_params, %{"slug" => slug} = session, socket) do
    socket =
      socket
      |> assign(:slug, slug)
      |> assign(:socket_token, Map.get(session, "socket_token", ""))

    {:ok, socket}
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
        --danger: #dc6b6b;
      }

      * {
        box-sizing: border-box;
      }

      html, body, body > div, .terminal-page, #terminal {
        height: 100%;
        margin: 0;
        background: var(--bg);
      }

      .terminal-page {
        min-height: 100vh;
        width: 100vw;
        overflow: hidden;
      }

      #terminal {
        width: 100vw;
        height: 100vh;
        overflow: hidden;
        background: var(--terminal-bg);
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
    </style>
    <div class="terminal-page">
      <div id="connection-status" data-testid="connection-status" data-state="connecting">
        connecting
      </div>
      <div
        id="terminal"
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
    """
  end
end
