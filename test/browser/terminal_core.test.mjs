import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  allowedInput,
  connectionStatus,
  decodeBase64Bytes,
  printableAsciiPaste,
  resizePayload
} from "../../apps/babs/priv/static/js/terminal_core.js";

describe("terminal_core allowedInput", () => {
  it("allows shell controls, arrows, printable ASCII, and bounded paste", () => {
    assert.equal(allowedInput("\r"), true);
    assert.equal(allowedInput("\u0003"), true);
    assert.equal(allowedInput("\u001b[A"), true);
    assert.equal(allowedInput("printf 'ok\\n'"), true);
    assert.equal(allowedInput("x".repeat(4096)), true);
  });

  it("rejects empty paste, unicode, escape sequences outside arrows, and oversized input", () => {
    assert.equal(printableAsciiPaste(""), false);
    assert.equal(allowedInput("こんにちは"), false);
    assert.equal(allowedInput("\u001b[200~paste"), false);
    assert.equal(allowedInput("x".repeat(4097)), false);
  });
});

describe("terminal_core browser helpers", () => {
  it("decodes base64 channel payloads into bytes", () => {
    assert.deepEqual(Array.from(decodeBase64Bytes("QkFCUw==")), [66, 65, 66, 83]);
  });

  it("builds resize payloads from terminal dimensions", () => {
    assert.deepEqual(resizePayload({ cols: 120, rows: 32 }), { cols: 120, rows: 32 });
  });

  it("formats connection status labels", () => {
    assert.deepEqual(connectionStatus("connected", "sentinel"), {
      state: "connected",
      text: "connected sentinel"
    });
    assert.deepEqual(connectionStatus("error", "sentinel"), {
      state: "error",
      text: "join failed"
    });
    assert.deepEqual(connectionStatus("connecting", "sentinel"), {
      state: "connecting",
      text: "connecting"
    });
  });
});
