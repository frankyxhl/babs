import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { bootTerminal } from "../../apps/babs/priv/static/js/terminal_client.js";

class FakeDocument extends EventTarget {
  constructor(root, status) {
    super();
    this.root = root;
    this.status = status;
  }

  getElementById(id) {
    if (id === "terminal") return this.root;
    if (id === "connection-status") return this.status;
    return null;
  }
}

class FakeTerminal {
  constructor(options = {}) {
    this.cols = 120;
    this.rows = 32;
    this.options = options;
    this.focusCount = 0;
    this.blurCount = 0;
    FakeTerminal.instances.push(this);
  }

  loadAddon() {}
  open() {}
  focus() {
    this.focusCount += 1;
  }
  blur() {
    this.blurCount += 1;
  }
  writeln() {}
  write() {}
  onData(callback) {
    this.dataHandler = callback;
  }
  attachCustomKeyEventHandler(handler) {
    this.keyHandler = handler;
  }
}

FakeTerminal.instances = [];

class FakeFitAddon {
  fit() {}
}

class FakeResizeObserver {
  constructor(callback) {
    this.callback = callback;
    this.observed = [];
    FakeResizeObserver.instances.push(this);
  }

  observe(element) {
    this.observed.push(element);
  }
}

FakeResizeObserver.instances = [];

class FakeSocket {
  constructor() {
    this.channelInstance = new FakeChannel();
    this.connectCount = 0;
    FakeSocket.instances.push(this);
  }

  connect() {
    this.connectCount += 1;
  }

  channel() {
    return this.channelInstance;
  }
}

FakeSocket.instances = [];

class FakeChannel {
  constructor() {
    this.pushed = [];
  }

  on() {}
  push(event, payload) {
    this.pushed.push({ event, payload });
  }

  join() {
    const chain = {
      receive: (status, callback) => {
        if (status === "ok") this.ok = callback;
        if (status === "error") this.error = callback;
        return chain;
      }
    };

    return chain;
  }
}

function fakeWindow() {
  return {
    Terminal: FakeTerminal,
    FitAddon: { FitAddon: FakeFitAddon },
    TextDecoder,
    ResizeObserver: FakeResizeObserver,
    addEventListener() {},
    setTimeout(callback) {
      callback();
    }
  };
}

function fakeElement(attrs = {}) {
  return {
    id: attrs.id,
    dataset: attrs.dataset ?? {},
    textContent: attrs.textContent ?? ""
  };
}

describe("terminal_client LiveView status ownership", () => {
  it("defers xterm and channel boot until the terminal tab is visible", () => {
    FakeSocket.instances = [];
    FakeTerminal.instances = [];
    FakeResizeObserver.instances = [];

    const root = fakeElement({
      id: "terminal",
      dataset: { slug: "sentinel", socketToken: "", terminalVisible: "false" }
    });
    const status = fakeElement({
      id: "connection-status",
      dataset: { state: "connecting" },
      textContent: "connecting"
    });
    const document = new FakeDocument(root, status);

    const deferred = bootTerminal({
      document,
      window: fakeWindow(),
      Terminal: FakeTerminal,
      FitAddon: FakeFitAddon,
      Socket: FakeSocket,
      TextDecoder
    });

    assert.equal(deferred.deferred, true);
    assert.equal(FakeTerminal.instances.length, 0);
    assert.equal(FakeSocket.instances.length, 0);

    root.dataset.terminalVisible = "true";
    document.dispatchEvent(new Event("phx:update"));

    assert.equal(FakeTerminal.instances.length, 1);
    assert.equal(FakeSocket.instances.length, 1);
    assert.equal(FakeSocket.instances[0].connectCount, 1);
    assert.equal(deferred.client.terminal, FakeTerminal.instances[0]);
  });

  it("does not send terminal input or claim keys after the terminal is hidden", () => {
    FakeSocket.instances = [];
    FakeTerminal.instances = [];
    FakeResizeObserver.instances = [];

    const root = fakeElement({
      id: "terminal",
      dataset: { slug: "sentinel", socketToken: "", terminalVisible: "true" }
    });
    const status = fakeElement({
      id: "connection-status",
      dataset: { state: "connecting" },
      textContent: "connecting"
    });
    const document = new FakeDocument(root, status);

    bootTerminal({
      document,
      window: fakeWindow(),
      Terminal: FakeTerminal,
      FitAddon: FakeFitAddon,
      Socket: FakeSocket,
      TextDecoder
    });

    const terminal = FakeTerminal.instances[0];
    const channel = FakeSocket.instances[0].channelInstance;

    terminal.dataHandler("visible input");
    assert.deepEqual(channel.pushed.at(-1), { event: "input", payload: { data: "visible input" } });

    root.dataset.terminalVisible = "false";
    document.dispatchEvent(new Event("phx:update"));

    const pushedBeforeHiddenInput = channel.pushed.length;
    terminal.dataHandler("hidden input");

    let prevented = false;
    terminal.keyHandler({
      type: "keydown",
      key: "Enter",
      preventDefault() {
        prevented = true;
      }
    });

    assert.equal(channel.pushed.length, pushedBeforeHiddenInput);
    assert.equal(prevented, false);
    assert.equal(terminal.blurCount, 1);
  });

  it("restores connected status after LiveView patches the badge back to connecting", () => {
    FakeSocket.instances = [];
    FakeTerminal.instances = [];
    FakeResizeObserver.instances = [];

    const root = fakeElement({
      id: "terminal",
      dataset: { slug: "sentinel", socketToken: "" }
    });
    const status = fakeElement({
      id: "connection-status",
      dataset: { state: "connecting" },
      textContent: "connecting"
    });
    const document = new FakeDocument(root, status);

    bootTerminal({
      document,
      window: fakeWindow(),
      Terminal: FakeTerminal,
      FitAddon: FakeFitAddon,
      Socket: FakeSocket,
      TextDecoder
    });

    FakeSocket.instances[0].channelInstance.ok();
    assert.equal(status.dataset.state, "connected");
    assert.equal(FakeTerminal.instances[0].options.macOptionIsMeta, true);
    assert.equal(FakeTerminal.instances[0].focusCount, 2);
    assert.equal(typeof FakeTerminal.instances[0].keyHandler, "function");
    assert.deepEqual(FakeResizeObserver.instances[0].observed, [root]);

    status.dataset.state = "connecting";
    status.textContent = "connecting";
    document.dispatchEvent(new Event("phx:update"));

    assert.equal(status.dataset.state, "connected");
    assert.equal(status.textContent, "connected sentinel");
  });

  it("restores connected status if LiveView replaces the badge element", () => {
    FakeSocket.instances = [];
    FakeTerminal.instances = [];
    FakeResizeObserver.instances = [];

    const root = fakeElement({
      id: "terminal",
      dataset: { slug: "sentinel", socketToken: "" }
    });
    const status = fakeElement({
      id: "connection-status",
      dataset: { state: "connecting" },
      textContent: "connecting"
    });
    const document = new FakeDocument(root, status);

    bootTerminal({
      document,
      window: fakeWindow(),
      Terminal: FakeTerminal,
      FitAddon: FakeFitAddon,
      Socket: FakeSocket,
      TextDecoder
    });

    FakeSocket.instances[0].channelInstance.ok();

    document.status = fakeElement({
      id: "connection-status",
      dataset: { state: "connecting" },
      textContent: "connecting"
    });
    document.dispatchEvent(new Event("phx:update"));

    assert.equal(document.status.dataset.state, "connected");
    assert.equal(document.status.textContent, "connected sentinel");
  });
});
