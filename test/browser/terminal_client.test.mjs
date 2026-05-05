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
  constructor() {
    this.cols = 120;
    this.rows = 32;
  }

  loadAddon() {}
  open() {}
  writeln() {}
  write() {}
  onData() {}
}

class FakeFitAddon {
  fit() {}
}

class FakeSocket {
  constructor() {
    this.channelInstance = new FakeChannel();
    FakeSocket.instances.push(this);
  }

  connect() {}

  channel() {
    return this.channelInstance;
  }
}

FakeSocket.instances = [];

class FakeChannel {
  on() {}
  push() {}

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
  it("restores connected status after LiveView patches the badge back to connecting", () => {
    FakeSocket.instances = [];

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

    status.dataset.state = "connecting";
    status.textContent = "connecting";
    document.dispatchEvent(new Event("phx:update"));

    assert.equal(status.dataset.state, "connected");
    assert.equal(status.textContent, "connected sentinel");
  });

  it("restores connected status if LiveView replaces the badge element", () => {
    FakeSocket.instances = [];

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
