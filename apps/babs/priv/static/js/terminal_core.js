const maxInputBytes = 4096;
const blockedTerminalControls = ["\x1b]", "\x9d", "\x1bP", "\x1b_", "\x1b^"];
const terminalResponsePattern =
  /(?:\x1b\[\?[0-9;]*c|\x1b\[>[0-9;]*c|\x1b\[[0-9;]*R|\x1b\[[0-9?;]*n)/;
const terminalOwnedKeys = new Set([
  "ArrowDown",
  "ArrowLeft",
  "ArrowRight",
  "ArrowUp",
  "Backspace",
  "Delete",
  "End",
  "Enter",
  "Escape",
  "Home",
  "Insert",
  "PageDown",
  "PageUp",
  "Tab"
]);

for (let index = 1; index <= 12; index += 1) {
  terminalOwnedKeys.add(`F${index}`);
}

export function utf8ByteLength(data) {
  return new TextEncoder().encode(data).length;
}

export function allowedInput(data) {
  return (
    typeof data === "string" &&
    data.length > 0 &&
    utf8ByteLength(data) <= maxInputBytes &&
    !data.includes("\x00") &&
    !blockedTerminalControls.some((sequence) => data.includes(sequence)) &&
    !terminalResponsePattern.test(data)
  );
}

export function terminalShouldOwnKey(event) {
  if (!event || event.type !== "keydown" || event.metaKey) {
    return false;
  }

  return Boolean(event.ctrlKey || event.altKey || terminalOwnedKeys.has(event.key));
}

function createTerminalRefocusScheduler(terminal, scheduleRefocus) {
  const pendingRefocus = { current: false };

  return () => scheduleTerminalRefocus(terminal, scheduleRefocus, pendingRefocus);
}

function scheduleTerminalRefocus(terminal, scheduleRefocus, pendingRefocus) {
  if (pendingRefocus.current || typeof terminal.focus !== "function") {
    return;
  }

  pendingRefocus.current = true;
  let remaining = 2;
  const finish = () => {
    remaining -= 1;

    if (remaining === 0) {
      pendingRefocus.current = false;
    }
  };

  for (const delay of [0, 30]) {
    scheduleRefocus(() => {
      try {
        terminal.focus();
      } catch {
        // Browser focus can be transient during reload or extension handoff.
      } finally {
        finish();
      }
    }, delay);
  }
}

function shouldRecoverTerminalFocus(event, root, doc) {
  const activeElement = doc.activeElement;

  return Boolean(
    (event.target && root.contains?.(event.target)) ||
      (activeElement && root.contains?.(activeElement)) ||
      activeElement === doc.body
  );
}

export function installTerminalKeyboardHandler(terminal, options = {}) {
  if (!terminal || typeof terminal.attachCustomKeyEventHandler !== "function") {
    return false;
  }

  const scheduleRefocus =
    options.scheduleRefocus ||
    (typeof globalThis.setTimeout === "function" && globalThis.setTimeout.bind(globalThis));
  const refocusTerminal = scheduleRefocus
    ? createTerminalRefocusScheduler(terminal, scheduleRefocus)
    : () => {};

  terminal.attachCustomKeyEventHandler((event) => {
    if (terminalShouldOwnKey(event)) {
      event.preventDefault?.();

      if (scheduleRefocus) {
        refocusTerminal();
      }
    }

    return true;
  });

  if (scheduleRefocus && options.document?.addEventListener && options.root) {
    options.document.addEventListener(
      "keydown",
      (event) => {
        if (
          terminalShouldOwnKey(event) &&
          shouldRecoverTerminalFocus(event, options.root, options.document)
        ) {
          refocusTerminal();
        }
      },
      true
    );
  }

  return true;
}

export function connectionStatus(state, slug) {
  if (state === "connected") {
    return { state: "connected", text: `connected ${slug}` };
  }

  if (state === "error") {
    return { state: "error", text: "join failed" };
  }

  return { state: "connecting", text: "connecting" };
}

export function decodeBase64Bytes(base64) {
  if (typeof atob === "function") {
    return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
  }

  if (typeof Buffer !== "undefined") {
    return Uint8Array.from(Buffer.from(base64, "base64"));
  }

  throw new Error("No base64 decoder available");
}

export function decodeTerminalOutput(decoder, base64) {
  return decoder.decode(decodeBase64Bytes(base64), { stream: true });
}

export function resizePayload(terminal) {
  return { cols: terminal.cols, rows: terminal.rows };
}
