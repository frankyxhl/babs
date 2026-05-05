import { Socket } from "/js/phoenix.mjs";
import { allowedInput, connectionStatus, decodeBase64Bytes, resizePayload } from "/js/terminal_core.js";

function applyConnectionStatus(status, state, slug) {
  const next = connectionStatus(state, slug);
  status.dataset.state = next.state;
  status.textContent = next.text;
}

export function bootTerminal(options = {}) {
  const doc = options.document ?? document;
  const win = options.window ?? window;
  const root = options.root ?? doc.getElementById("terminal");
  const status = options.status ?? doc.getElementById("connection-status");
  const TerminalCtor = options.Terminal ?? win.Terminal;
  const FitAddonCtor = options.FitAddon ?? win.FitAddon?.FitAddon;
  const SocketCtor = options.Socket ?? Socket;
  const TextDecoderCtor = options.TextDecoder ?? win.TextDecoder;

  if (!root) {
    throw new Error("terminal root not found");
  }

  if (!status) {
    throw new Error("connection status not found");
  }

  const terminal = new TerminalCtor({
    convertEol: true,
    cursorBlink: true,
    fontFamily: '"JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
    fontSize: 13,
    theme: {
      background: "#000000",
      foreground: "#e7eaf0",
      cursor: "#e7eaf0",
      selectionBackground: "#2f4f4c"
    }
  });
  const fit = new FitAddonCtor();
  const decoder = new TextDecoderCtor();

  terminal.loadAddon(fit);
  terminal.open(root);
  fit.fit();

  const socket = new SocketCtor("/socket", {});
  socket.connect();
  const channel = socket.channel(`pane:${root.dataset.slug}`, {});

  channel.on("output", (payload) => {
    terminal.write(decoder.decode(decodeBase64Bytes(payload.base64)));
  });

  channel
    .join()
    .receive("ok", () => {
      applyConnectionStatus(status, "connected", root.dataset.slug);
      terminal.writeln("\r\n[babs connected]\r\n");
    })
    .receive("error", (reason) => {
      applyConnectionStatus(status, "error", root.dataset.slug);
      terminal.writeln(`\r\n[babs join failed: ${JSON.stringify(reason)}]\r\n`);
    });

  terminal.onData((data) => {
    if (allowedInput(data)) {
      channel.push("input", { data });
    }
  });

  const resize = () => {
    fit.fit();
    channel.push("resize", resizePayload(terminal));
  };

  win.addEventListener("resize", resize);
  win.setTimeout(resize, 0);

  root.__babsTerminal = terminal;
  win.__babsTerminalClient = { terminal, fit, socket, channel, resize };

  return { terminal, fit, socket, channel, resize };
}
