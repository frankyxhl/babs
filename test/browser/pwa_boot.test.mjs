import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { registerBabsServiceWorker } from "../../apps/babs/priv/static/js/pwa_boot.js";

describe("pwa_boot service worker registration", () => {
  it("registers the service worker in a secure context when supported", async () => {
    const calls = [];
    const navigator = {
      serviceWorker: {
        register: async (url) => {
          calls.push(url);
          return { scope: "/" };
        }
      }
    };

    const result = await registerBabsServiceWorker({
      navigator,
      window: { isSecureContext: true }
    });

    assert.deepEqual(calls, ["/sw.js"]);
    assert.equal(result.status, "registered");
  });

  it("no-ops when the browser context is not secure", async () => {
    let called = false;
    const navigator = {
      serviceWorker: {
        register: async () => {
          called = true;
        }
      }
    };

    const result = await registerBabsServiceWorker({
      navigator,
      window: { isSecureContext: false }
    });

    assert.equal(called, false);
    assert.equal(result.status, "skipped");
    assert.equal(result.reason, "insecure-context");
  });

  it("no-ops when service workers are unsupported", async () => {
    const result = await registerBabsServiceWorker({
      navigator: {},
      window: { isSecureContext: true }
    });

    assert.equal(result.status, "skipped");
    assert.equal(result.reason, "unsupported");
  });

  it("keeps LiveView boot non-fatal when registration fails", async () => {
    const result = await registerBabsServiceWorker({
      navigator: {
        serviceWorker: {
          register: async () => {
            throw new Error("denied");
          }
        }
      },
      window: { isSecureContext: true }
    });

    assert.equal(result.status, "failed");
    assert.equal(result.reason, "denied");
  });
});
