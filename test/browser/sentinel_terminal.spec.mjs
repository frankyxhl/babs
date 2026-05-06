import { expect, test } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const paneSourcePath = "apps/babs_citizens/lib/babs_citizens/hardline/pane.ex";
const webSourcePath = "apps/babs/lib/babs_web/channels/pane_channel.ex";
const ticketsRoot = process.env.BABS_TICKETS_ROOT || "var/tickets";

function commandExists(command) {
  try {
    execFileSync("sh", ["-lc", `command -v ${command}`], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

async function connectCitizen(page, slug, opts = {}) {
  const response = await page.goto(`/citizens/${slug}`);

  if (opts.optional && response?.status() === 404) {
    test.skip(true, `${slug} citizen is not running`);
  }

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

function allocateTicketId() {
  const today = new Date().toISOString().slice(0, 10);

  for (let seq = 950; seq < 1000; seq += 1) {
    const id = `T-${today}-${String(seq).padStart(3, "0")}`;
    if (!existsSync(ticketMarkdownPath(id)) && !existsSync(ticketHistoryPath(id))) {
      return id;
    }
  }

  throw new Error("could not allocate E2E ticket id");
}

function ticketMarkdownPath(id) {
  return join(ticketsRoot, `${id}.md`);
}

function ticketHistoryPath(id) {
  return join(ticketsRoot, `${id}.history.jsonl`);
}

function writeTicket(id, title, body) {
  mkdirSync(ticketsRoot, { recursive: true });
  const now = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");

  writeFileSync(
    ticketMarkdownPath(id),
    `---
id: "${id}"
type: "assignment"
state: "open"
assigner: "e2e"
assignees: []
assignee_role: null
inspector: "user"
priority: "normal"
parent_ticket: null
created_at: "${now}"
updated_at: "${now}"
metadata: {"source":"playwright"}
---

# ${title}

${body}
`
  );

  writeFileSync(
    ticketHistoryPath(id),
    `${JSON.stringify({ ts: now, event: "created", by: "e2e", ticket_id: id })}\n`
  );
}

function cleanupTicket(id) {
  rmSync(ticketMarkdownPath(id), { force: true });
  rmSync(ticketHistoryPath(id), { force: true });
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

  await connectCitizen(page, "clare", { optional: true });
  await expectTerminalHasContent(page);
});

test("dylan browser terminal connects when Codex CLI is available", async ({ page }) => {
  test.skip(!commandExists("codex"), "codex CLI is not installed");

  await connectCitizen(page, "dylan", { optional: true });
  await expectTerminalHasContent(page);
});

test("missing citizen returns 404", async ({ page }) => {
  const response = await page.goto("/citizens/not-a-citizen");

  expect(response.status()).toBe(404);
  await expect(page.locator("body")).toContainText("citizen not found");
});

test("ticket detail stores operator comments from the browser", async ({ page }) => {
  const id = allocateTicketId();
  const comment = "E2E operator comment";

  try {
    writeTicket(id, "E2E Comment Ticket", "Browser comment body.");
    await page.goto(`/tickets/${id}`);

    await expect(page.getByTestId("ticket-detail")).toBeVisible();
    await expect(page.getByTestId("ticket-comment-form")).toBeVisible();
    await expect(page.locator('[data-testid="ticket-comment"] [data-icon="message-square"]')).toBeVisible();

    await page.getByTestId("ticket-comment-body").fill(comment);
    await page.getByTestId("ticket-comment").click();

    await expect(page.getByTestId("ticket-flash-info")).toContainText("Comment stored");
    await expect(page.getByTestId("ticket-detail")).toContainText(comment);
  } finally {
    cleanupTicket(id);
  }
});
