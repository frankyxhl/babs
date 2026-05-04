import { defineConfig } from "@playwright/test";

const port = Number(process.env.HARDLINE_E2E_PORT || "4110");
const prefix =
  process.env.HARDLINE_E2E_PREFIX || `babs-e2e-${Date.now()}-${process.pid}`;
const baseURL = `http://127.0.0.1:${port}`;

process.env.HARDLINE_E2E_PREFIX = prefix;
process.env.HARDLINE_E2E_BASE_URL = baseURL;

export default defineConfig({
  testDir: "./test/browser",
  testMatch: "**/*.spec.mjs",
  timeout: 45_000,
  expect: {
    timeout: 10_000
  },
  fullyParallel: false,
  workers: 1,
  reporter: [["list"]],
  use: {
    baseURL,
    channel: "chrome",
    headless: true,
    trace: "retain-on-failure"
  },
  webServer: {
    command: `mise exec -- mix hardline.web --host 127.0.0.1 --port ${port} --prefix ${prefix}`,
    url: baseURL,
    reuseExistingServer: false,
    timeout: 60_000,
    stdout: "pipe",
    stderr: "pipe"
  }
});
