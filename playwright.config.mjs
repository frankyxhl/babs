import { defineConfig } from "@playwright/test";

const e2ePort = process.env.BABS_E2E_PORT || "4000";
const baseURL = process.env.BABS_E2E_BASE_URL || `http://127.0.0.1:${e2ePort}`;

export default defineConfig({
  testDir: "./test/browser",
  testMatch: "**/*.spec.mjs",
  timeout: 30_000,
  expect: {
    timeout: 10_000
  },
  use: {
    baseURL,
    trace: "on-first-retry"
  },
  webServer: {
    command: `env BABS_HTTP_PORT=${e2ePort} PORT=${e2ePort} mise exec -- mix phx.server`,
    url: `${baseURL}/citizens/sentinel`,
    reuseExistingServer: !process.env.CI && !process.env.BABS_E2E_PORT,
    timeout: 30_000
  }
});
