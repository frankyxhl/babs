defmodule BabsWeb.TerminalLive do
  @moduledoc """
  Phase 1 browser terminal for one Citizen.

  The LiveView owns the page shell and client-side xterm bootstrap. PTY bytes and
  keyboard input still flow through `BabsWeb.PaneChannel`, so reloads do not bind
  Hardline.Pane to a LiveView process.
  """

  use Phoenix.LiveView

  @impl true
  def mount(_params, %{"slug" => slug}, socket) do
    {:ok, assign(socket, :slug, slug)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <link rel="stylesheet" href="/css/xterm.css" />
    <style>
      html, body, body > div, .terminal-page, #terminal {
        height: 100%;
        margin: 0;
        background: #101317;
      }
      .terminal-page {
        min-height: 100vh;
        width: 100vw;
        overflow: hidden;
      }
      #terminal {
        width: 100vw;
        height: 100vh;
      }
      #connection-status {
        position: fixed;
        top: 8px;
        right: 10px;
        z-index: 10;
        padding: 3px 7px;
        border-radius: 999px;
        background: rgba(16, 19, 23, 0.84);
        color: #d7dee8;
        font: 12px/1.4 system-ui, sans-serif;
      }
      #connection-status[data-state="connected"] { color: #7ee787; }
      #connection-status[data-state="error"] { color: #ff7b72; }
    </style>
    <div class="terminal-page">
      <div id="connection-status" data-testid="connection-status" data-state="connecting">
        connecting
      </div>
      <div id="terminal" data-testid="terminal" data-slug={@slug}></div>
    </div>
    <script src="/js/xterm.js">
    </script>
    <script src="/js/xterm-addon-fit.js">
    </script>
    <script type="module">
      import {Socket} from "/js/phoenix.mjs";

      const root = document.getElementById("terminal");
      const status = document.getElementById("connection-status");
      const terminal = new Terminal({convertEol: true, cursorBlink: true});
      const fit = new FitAddon.FitAddon();
      terminal.loadAddon(fit);
      terminal.open(root);
      fit.fit();

      const socket = new Socket("/socket", {});
      socket.connect();
      const channel = socket.channel(`pane:${root.dataset.slug}`, {});

      channel.on("output", (payload) => {
        const bytes = Uint8Array.from(atob(payload.base64), c => c.charCodeAt(0));
        terminal.write(new TextDecoder().decode(bytes));
      });

      channel.join()
        .receive("ok", () => {
          status.dataset.state = "connected";
          status.textContent = `connected ${root.dataset.slug}`;
          terminal.writeln("\r\n[babs connected]\r\n");
        })
        .receive("error", (reason) => {
          status.dataset.state = "error";
          status.textContent = "join failed";
          terminal.writeln(`\r\n[babs join failed: ${JSON.stringify(reason)}]\r\n`);
        });

      const allowedControls = new Set(["\r", "\n", "\t", "\x03", "\x04", "\x1a", "\x7f"]);
      const allowedArrows = new Set(["\x1b[A", "\x1b[B", "\x1b[C", "\x1b[D"]);
      const printableAsciiPaste = (data) =>
        data.length > 0 && data.length <= 4096 && Array.from(data).every((char) => {
          const code = char.charCodeAt(0);
          return code === 9 || code === 10 || code === 13 || code === 127 || (code >= 32 && code <= 126);
        });
      const allowedInput = (data) =>
        data.length <= 4096 && (allowedControls.has(data) || allowedArrows.has(data) || printableAsciiPaste(data));

      terminal.onData((data) => {
        if (allowedInput(data)) {
          channel.push("input", {data});
        }
      });

      const resize = () => {
        fit.fit();
        channel.push("resize", {cols: terminal.cols, rows: terminal.rows});
      };

      window.addEventListener("resize", resize);
      setTimeout(resize, 0);
    </script>
    """
  end
end
