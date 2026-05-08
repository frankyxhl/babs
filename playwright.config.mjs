import { defineConfig } from "@playwright/test";

const configuredBaseURL = process.env.BABS_E2E_BASE_URL?.replace(/\/$/, "");

function portFromBaseURL(url) {
  if (!url) return null;

  try {
    const parsed = new URL(url);
    return parsed.port || (parsed.protocol === "https:" ? "443" : "80");
  } catch {
    return null;
  }
}

const e2ePort = process.env.BABS_E2E_PORT || portFromBaseURL(configuredBaseURL) || "4000";
const baseURL = configuredBaseURL || `http://127.0.0.1:${e2ePort}`;

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
