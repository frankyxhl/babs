const allowedControls = new Set(["\r", "\n", "\t", "\x03", "\x04", "\x1a", "\x7f"]);
const allowedArrows = new Set(["\x1b[A", "\x1b[B", "\x1b[C", "\x1b[D"]);
const maxInputBytes = 4096;

export function printableAsciiPaste(data) {
  return (
    data.length > 0 &&
    data.length <= maxInputBytes &&
    Array.from(data).every((char) => {
      const code = char.charCodeAt(0);
      return code === 9 || code === 10 || code === 13 || code === 127 || (code >= 32 && code <= 126);
    })
  );
}

export function allowedInput(data) {
  return (
    data.length <= maxInputBytes &&
    (allowedControls.has(data) || allowedArrows.has(data) || printableAsciiPaste(data))
  );
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

export function resizePayload(terminal) {
  return { cols: terminal.cols, rows: terminal.rows };
}
