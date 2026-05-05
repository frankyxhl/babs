import { expect, test } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";

const paneSourcePath = "apps/babs_citizens/lib/babs_citizens/hardline/pane.ex";
const webSourcePath = "apps/babs/lib/babs_web/channels/pane_channel.ex";

function commandExists(command) {
  try {
    execFileSync("sh", ["-lc", `command -v ${command}`], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

async function connectCitizen(page, slug) {
  await page.goto(`/citizens/${slug}`);

  await expect(page.locator(".xterm")).toBeVisible();
  await expect(page.getByTestId("connection-status")).toHaveAttribute(
    "data-state",
    "connected"
  );
}

async function connectSentinel(page) {
  await connectCitizen(page, "sentinel");
}

async function runCommandAndExpect(page, marker) {
  const command = `printf '\\033[2J\\033[H${marker}\\n'`;

  await page.locator(".xterm-helper-textarea").click({ force: true });
  await page.evaluate(() => window.__babsTerminalClient?.terminal.focus());
  await page.keyboard.insertText(command);
  await page.keyboard.press("Enter");

  await expect
    .poll(async () => await page.locator(".xterm").innerText())
    .toContain(marker);
}

async function expectTerminalHasContent(page) {
  await expect
    .poll(async () => (await page.locator(".xterm").innerText()).trim().length)
    .toBeGreaterThan(0);
}

test("sentinel terminal connects and forwards keyboard input to tmux", async ({ page }) => {
  await connectSentinel(page);
  await runCommandAndExpect(page, "BABS_PHASE1_BROWSER_OK");
});

test("sentinel terminal keeps receiving output after citizens reload", async ({ page }) => {
  await connectSentinel(page);
  await runCommandAndExpect(page, "BABS_PHASE1_BEFORE_RELOAD");

  const source = readFileSync(paneSourcePath, "utf8");
  writeFileSync(paneSourcePath, source);

  await page.waitForTimeout(2_000);
  await runCommandAndExpect(page, "BABS_PHASE1_AFTER_RELOAD");
});

test("sentinel terminal reconnects after web reload", async ({ page }) => {
  await connectSentinel(page);
  await runCommandAndExpect(page, "BABS_PHASE1_BEFORE_WEB_RELOAD");

  const reload = page.waitForEvent("load");
  const source = readFileSync(webSourcePath, "utf8");
  writeFileSync(webSourcePath, source);
  await reload;

  await expect(page.getByTestId("connection-status")).toHaveAttribute(
    "data-state",
    "connected"
  );
  await runCommandAndExpect(page, "BABS_PHASE1_AFTER_WEB_RELOAD");
});

test("clare browser terminal connects when Claude CLI is available", async ({ page }) => {
  test.skip(!commandExists("claude"), "claude CLI is not installed");

  await connectCitizen(page, "clare");
  await expectTerminalHasContent(page);
});

test("dylan browser terminal connects when Codex CLI is available", async ({ page }) => {
  test.skip(!commandExists("codex"), "codex CLI is not installed");

  await connectCitizen(page, "dylan");
  await expectTerminalHasContent(page);
});

test("missing citizen returns 404", async ({ page }) => {
  const response = await page.goto("/citizens/not-a-citizen");

  expect(response.status()).toBe(404);
  await expect(page.locator("body")).toContainText("citizen not found");
});
