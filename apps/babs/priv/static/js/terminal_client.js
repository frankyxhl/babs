import { Socket } from "./phoenix.mjs";
import {
  allowedInput,
  connectionStatus,
  decodeTerminalOutput,
  installTerminalKeyboardHandler,
  resizePayload
} from "./terminal_core.js";

function applyConnectionStatus(status, state, slug) {
  const next = connectionStatus(state, slug);
  status.dataset.state = next.state;
  status.textContent = next.text;
}

function terminalOwnedStatus(doc, fallback) {
  return doc.getElementById(fallback.id) ?? fallback;
}

function terminalVisible(root) {
  return root.dataset.terminalVisible !== "false";
}

function deferTerminalBoot(options, root, status) {
  const doc = options.document ?? document;
  const win = options.window ?? window;
  let client = null;

  const startIfVisible = () => {
    if (client || !terminalVisible(root)) {
      return client;
    }

    client = bootTerminal({ ...options, root, status, deferUntilVisible: false });
    return client;
  };

  const deferred = {
    deferred: true,
    startIfVisible,
    get client() {
      return client;
    }
  };

  doc.addEventListener?.("phx:update", startIfVisible);
  win.__babsTerminalClient = deferred;

  return deferred;
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
  let statusState = "connecting";

  if (!root) {
    throw new Error("terminal root not found");
  }

  if (!status) {
    throw new Error("connection status not found");
  }

  if (options.deferUntilVisible !== false && !terminalVisible(root)) {
    return deferTerminalBoot(options, root, status);
  }

  const setConnectionStatus = (state) => {
    statusState = state;
    applyConnectionStatus(terminalOwnedStatus(doc, status), statusState, root.dataset.slug);
  };

  doc.addEventListener?.("phx:update", () => {
    applyConnectionStatus(terminalOwnedStatus(doc, status), statusState, root.dataset.slug);

    if (!terminalVisible(root)) {
      terminal?.blur?.();
    }
  });

  const terminal = new TerminalCtor({
    convertEol: true,
    cursorBlink: true,
    fontFamily: '"JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
    fontSize: 13,
    macOptionIsMeta: true,
    scrollback: 10_000,
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
  installTerminalKeyboardHandler(terminal, { document: doc, root, isActive: () => terminalVisible(root) });
  terminal.focus?.();
  fit.fit();

  const socket = new SocketCtor("/socket", { params: { token: root.dataset.socketToken || "" } });
  socket.connect();
  const channel = socket.channel(`pane:${root.dataset.slug}`, {});

  channel.on("output", (payload) => {
    terminal.write(decodeTerminalOutput(decoder, payload.base64));
  });

  channel
    .join()
    .receive("ok", () => {
      setConnectionStatus("connected");
      terminal.writeln("\r\n[babs connected]\r\n");
      terminal.focus?.();
    })
    .receive("error", (reason) => {
      setConnectionStatus("error");
      terminal.writeln(`\r\n[babs join failed: ${JSON.stringify(reason)}]\r\n`);
    });

  terminal.onData((data) => {
    if (terminalVisible(root) && allowedInput(data)) {
      channel.push("input", { data });
    }
  });

  const resize = () => {
    fit.fit();
    channel.push("resize", resizePayload(terminal));
  };

  win.addEventListener("resize", resize);

  let resizeObserver = null;

  if (typeof win.ResizeObserver === "function") {
    resizeObserver = new win.ResizeObserver(resize);
    resizeObserver.observe(root);
  }

  win.setTimeout(resize, 0);

  root.__babsTerminal = terminal;
  win.__babsTerminalClient = { terminal, fit, socket, channel, resize, resizeObserver };

  return { terminal, fit, socket, channel, resize, resizeObserver };
}
