import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  allowedInput,
  connectionStatus,
  decodeBase64Bytes,
  decodeTerminalOutput,
  installTerminalKeyboardHandler,
  resizePayload,
  terminalShouldOwnKey,
  utf8ByteLength
} from "../../apps/babs/priv/static/js/terminal_core.js";

describe("terminal_core allowedInput", () => {
  it("allows terminal-compatible xterm keyboard and paste data", () => {
    assert.equal(allowedInput("\r"), true);
    assert.equal(allowedInput("\u0002"), true);
    assert.equal(allowedInput("\u0003"), true);
    assert.equal(allowedInput("\u001b[A"), true);
    assert.equal(allowedInput("\u001b[1;5D"), true);
    assert.equal(allowedInput("\u001bOP"), true);
    assert.equal(allowedInput("\u001bb"), true);
    assert.equal(allowedInput("\u001b[200~paste\u001b[201~"), true);
    assert.equal(allowedInput("こんにちは"), true);
    assert.equal(allowedInput("printf 'ok\\n'"), true);
    assert.equal(allowedInput("x".repeat(4096)), true);
  });

  it("rejects empty input, nul bytes, unsafe terminal controls, and oversized input", () => {
    assert.equal(allowedInput(""), false);
    assert.equal(allowedInput("\u0000"), false);
    assert.equal(allowedInput("\u001b]52;c;clipboard\u0007"), false);
    assert.equal(allowedInput("\u001bPpayload"), false);
    assert.equal(allowedInput("\u001b[?1;2c"), false);
    assert.equal(allowedInput("\u001b[>0;276;0c"), false);
    assert.equal(allowedInput("\u001b[24;80R"), false);
    assert.equal(allowedInput("\u001b[24;80R\n"), false);
    assert.equal(allowedInput("pasted\u001b[?1;2c text"), false);
    assert.equal(allowedInput("\u001b[0n"), false);
    assert.equal(allowedInput("x".repeat(4097)), false);
  });

  it("counts input length by UTF-8 bytes", () => {
    assert.equal(utf8ByteLength("你"), 3);
    assert.equal(allowedInput("你".repeat(1365)), true);
    assert.equal(allowedInput("你".repeat(1366)), false);
  });
});

describe("terminal_core keyboard ownership", () => {
  function keyEvent(attrs) {
    let prevented = false;

    return {
      type: "keydown",
      key: "a",
      ctrlKey: false,
      altKey: false,
      metaKey: false,
      preventDefault() {
        prevented = true;
      },
      prevented() {
        return prevented;
      },
      ...attrs
    };
  }

  it("claims terminal shortcut keys while preserving browser Meta shortcuts", () => {
    assert.equal(terminalShouldOwnKey(keyEvent({ ctrlKey: true, key: "b" })), true);
    assert.equal(terminalShouldOwnKey(keyEvent({ altKey: true, key: "b" })), true);
    assert.equal(terminalShouldOwnKey(keyEvent({ key: "Tab" })), true);
    assert.equal(terminalShouldOwnKey(keyEvent({ key: "F2" })), true);
    assert.equal(terminalShouldOwnKey(keyEvent({ key: "ArrowLeft" })), true);
    assert.equal(terminalShouldOwnKey(keyEvent({ metaKey: true, key: "r" })), false);
    assert.equal(terminalShouldOwnKey(keyEvent({ type: "keyup", ctrlKey: true, key: "b" })), false);
  });

  it("installs a key handler that prevents browser defaults for terminal-owned keys", () => {
    let handler = null;
    const terminal = {
      attachCustomKeyEventHandler(callback) {
        handler = callback;
      }
    };

    assert.equal(installTerminalKeyboardHandler(terminal), true);
    assert.equal(typeof handler, "function");

    const ctrlB = keyEvent({ ctrlKey: true, key: "b" });
    assert.equal(handler(ctrlB), true);
    assert.equal(ctrlB.prevented(), true);

    const cmdR = keyEvent({ metaKey: true, key: "r" });
    assert.equal(handler(cmdR), true);
    assert.equal(cmdR.prevented(), false);
  });

  it("does not fail when xterm custom key handlers are unavailable", () => {
    assert.equal(installTerminalKeyboardHandler({}), false);
  });
});

describe("terminal_core browser helpers", () => {
  it("decodes base64 channel payloads into bytes", () => {
    assert.deepEqual(Array.from(decodeBase64Bytes("QkFCUw==")), [66, 65, 66, 83]);
  });

  it("streams split UTF-8 terminal output across channel payloads", () => {
    const decoder = new TextDecoder();
    const bytes = Buffer.from("你");
    const first = Buffer.from(bytes.subarray(0, 1)).toString("base64");
    const rest = Buffer.from(bytes.subarray(1)).toString("base64");

    assert.equal(decodeTerminalOutput(decoder, first), "");
    assert.equal(decodeTerminalOutput(decoder, rest), "你");
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
