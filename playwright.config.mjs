import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./test/browser",
  timeout: 30_000,
  expect: {
    timeout: 10_000
  },
  use: {
    baseURL: "http://127.0.0.1:4000",
    trace: "on-first-retry"
  },
  webServer: {
    command: "mise exec -- mix phx.server",
    url: "http://127.0.0.1:4000/citizens/sentinel",
    reuseExistingServer: !process.env.CI,
    timeout: 30_000
  }
});
