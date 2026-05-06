import { expect, test } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const paneSourcePath = "apps/babs_citizens/lib/babs_citizens/hardline/pane.ex";
const webSourcePath = "apps/babs/lib/babs_web/channels/pane_channel.ex";
const ticketsRoot = process.env.BABS_TICKETS_ROOT || "var/tickets";
const runtimeRoot = process.env.BABS_ROOT || process.env.RELEASE_ROOT || process.cwd();
const workspaceRoot = process.env.BABS_WORKSPACE_ROOT || join(runtimeRoot, "workspaces");

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

async function createShellCitizen(page, slug) {
  await page.goto("/citizens/new");
  await expect(page.getByTestId("new-citizen-form")).toBeVisible();
  await expectLiveViewConnected(page);

  await page.getByTestId("citizen-slug").fill(slug);
  await page.getByTestId("citizen-display-name").fill(`E2E ${slug}`);
  await page.getByTestId("citizen-cli-preset").selectOption("shell");
  await page.getByTestId("citizen-cwd").fill(slug);
  await page.getByTestId("citizen-description").fill("");
  await page.getByTestId("create-citizen-button").click();

  await expect(page).toHaveURL(new RegExp(`/citizens/${slug}(\\?.*)?$`));
  await expect(page.getByTestId("terminal")).toBeVisible();
  await expect(page.locator(".xterm")).toBeVisible();
  await expect(page.getByTestId("connection-status")).toHaveAttribute(
    "data-state",
    "connected"
  );
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

async function expectLiveViewConnected(page) {
  await expect
    .poll(async () => await page.evaluate(() => window.liveSocket?.isConnected?.() || false))
    .toBe(true);
}

async function waitForIndexStatus(page, slug, status) {
  await expect(page.getByTestId(`citizen-status-${slug}`)).toContainText(status);
}

async function submitAttachForm(page, slug, target) {
  await page.getByTestId("attach-citizen-select").selectOption(slug);
  await expect(page.getByTestId("attach-citizen-select")).toHaveValue(slug);
  await page.getByTestId("attach-target-select").selectOption(target);
  await expect(page.getByTestId("attach-target-select")).toHaveValue(target);
  await page.getByTestId("attach-submit").click();
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

function appendTicketHistory(id, event) {
  writeFileSync(ticketHistoryPath(id), `${JSON.stringify(event)}\n`, { flag: "a" });
}

function cleanupTicket(id) {
  rmSync(ticketMarkdownPath(id), { force: true });
  rmSync(ticketHistoryPath(id), { force: true });
}

function startExternalTmuxSession(sessionName) {
  const cwd = join(workspaceRoot, sessionName);
  cleanupExternalTmuxSession(sessionName);
  mkdirSync(cwd, { recursive: true });
  execFileSync("tmux", ["new-session", "-d", "-s", sessionName, "-c", cwd, "/bin/zsh -f"]);
}

function externalTmuxSessionAlive(sessionName) {
  try {
    execFileSync("tmux", ["has-session", "-t", sessionName], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

function externalTmuxCaptureContains(sessionName, marker) {
  try {
    const output = execFileSync("tmux", ["capture-pane", "-p", "-t", sessionName, "-S", "-80"], {
      encoding: "utf8",
    });
    return output.includes(marker);
  } catch {
    return false;
  }
}

function externalTmuxPaneId(sessionName) {
  return execFileSync("tmux", ["list-panes", "-t", sessionName, "-F", "#{pane_id}"], {
    encoding: "utf8",
  }).trim();
}

function tmuxWindowCount(sessionName) {
  const output = execFileSync("tmux", ["list-windows", "-t", sessionName, "-F", "#{window_id}"], {
    encoding: "utf8",
  });

  return output.trim().split("\n").filter(Boolean).length;
}

function webLogCount(pattern) {
  const session = process.env.BABS_WEB_TMUX_SESSION;

  if (!session) {
    return null;
  }

  try {
    const output = execFileSync("tmux", ["capture-pane", "-p", "-t", session, "-S", "-2000"], {
      encoding: "utf8",
    });

    return output.split(pattern).length - 1;
  } catch {
    return null;
  }
}

async function waitForWebLogIncrease(pattern, before, timeout = 20_000) {
  await expect.poll(() => webLogCount(pattern), { timeout }).toBeGreaterThan(before);
}

async function waitForCitizensReload(restartsBefore, readyBefore, joinsBefore) {
  if ([restartsBefore, readyBefore, joinsBefore].some((count) => count === null)) {
    await new Promise((resolve) => setTimeout(resolve, 8_000));
    return;
  }

  await waitForWebLogIncrease("Babs.DevReloader restarted :babs_citizens", restartsBefore);
  await waitForWebLogIncrease("Babs citizen ready: sentinel", readyBefore);
  await waitForWebLogIncrease("JOINED pane:sentinel", joinsBefore);
}

function tmuxPrefixPress() {
  const prefix = execFileSync("tmux", ["show-options", "-gqv", "prefix"], { encoding: "utf8" }).trim();
  const control = /^C-(.)$/i.exec(prefix);

  if (!control) {
    throw new Error(`unsupported tmux prefix in E2E: ${prefix}`);
  }

  return `Control+${control[1].toUpperCase()}`;
}

function cleanupExternalTmuxSession(sessionName) {
  if (!sessionName.startsWith("bdd-e2e-external-")) {
    throw new Error(`refusing to clean non-E2E external tmux session: ${sessionName}`);
  }

  try {
    execFileSync("tmux", ["kill-session", "-t", sessionName], { stdio: "ignore" });
  } catch {
    // The session may already be gone; cleanup is best-effort.
  }
  rmSync(join(workspaceRoot, sessionName), { recursive: true, force: true });
}

function cleanupSpawnedCitizen(slug) {
  if (!slug.startsWith("bdd-e2e-")) {
    throw new Error(`refusing to clean non-E2E citizen slug: ${slug}`);
  }

  try {
    execFileSync("tmux", ["kill-session", "-t", `babs-${slug}`], { stdio: "ignore" });
  } catch {
    // Imported Citizens may not own a Babs tmux session.
  }

  rmSync(join(runtimeRoot, "citizens", `citizen-${slug}.toml`), { force: true });
  rmSync(join(workspaceRoot, slug), { recursive: true, force: true });

  const code = `Application.ensure_all_started(:babs_citizens); case Babs.Citizens.Repo.get_by(Babs.Citizens.CitizenRecord, slug: ${JSON.stringify(
    slug
  )}) do nil -> :ok; record -> Babs.Citizens.Repo.delete!(record) end`;

  try {
    execFileSync("mise", ["exec", "--", "mix", "run", "-e", code], { stdio: "ignore" });
  } catch {
    // Do not hide the browser assertion result if best-effort DB cleanup fails.
  }
}

test("sentinel terminal connects and forwards keyboard input to tmux", async ({ page }) => {
  await connectSentinel(page);
  await runCommandAndExpect(page, "BABS_PHASE1_BROWSER_OK");
});

test("browser terminal forwards tmux prefix shortcut sequences", async ({ page }) => {
  const slug = `bdd-e2e-keys-${Date.now()}`;
  const session = `babs-${slug}`;

  try {
    await createShellCitizen(page, slug);
    const before = tmuxWindowCount(session);

    await page.locator(".xterm-helper-textarea").click({ force: true });
    await page.evaluate(() => window.__babsTerminalClient?.terminal.focus());
    await page.keyboard.press(tmuxPrefixPress());
    await page.keyboard.press("c");

    await expect.poll(() => tmuxWindowCount(session)).toBe(before + 1);
  } finally {
    cleanupSpawnedCitizen(slug);
  }
});

test("browser terminal owns readline-style Ctrl and Alt shortcut sequences", async ({ page }) => {
  const slug = `bdd-e2e-shortcuts-${Date.now()}`;
  const ctrlMarker = `BABS_CTRL_A_${Date.now()}`;
  const altMarker = `BABS_ALT_B_${Date.now()}`;

  try {
    await createShellCitizen(page, slug);

    await page.locator(".xterm-helper-textarea").click({ force: true });
    await page.evaluate(() => window.__babsTerminalClient?.terminal.focus());

    await page.keyboard.insertText("echo SHOULD_NOT_PRINT");
    await page.keyboard.press("Control+A");
    await page.keyboard.insertText(`printf '${ctrlMarker}\\n'; # `);
    await page.keyboard.press("Enter");

    await expect
      .poll(async () => await page.locator(".xterm").innerText())
      .toContain(ctrlMarker);

    await page.keyboard.insertText("echo no_marker #");
    await page.keyboard.press("Alt+B");
    await page.keyboard.insertText(`; printf '${altMarker}\\n' `);
    await page.keyboard.press("Enter");

    await expect
      .poll(async () => await page.locator(".xterm").innerText())
      .toContain(altMarker);
  } finally {
    cleanupSpawnedCitizen(slug);
  }
});

test("browser terminal restores focus after Escape so extension shortcuts do not steal input", async ({
  page
}) => {
  const slug = `bdd-e2e-escape-focus-${Date.now()}`;
  const marker = `BABS_ESCAPE_FOCUS_${Date.now()}`;

  try {
    await createShellCitizen(page, slug);

    await page.evaluate(() => {
      document.addEventListener(
        "keydown",
        (event) => {
          if (event.key === "Escape") {
            window.setTimeout(() => {
              document.body.tabIndex = -1;
              document.body.focus();
            }, 0);
          }
        },
        true
      );
    });

    await page.locator(".xterm-helper-textarea").click({ force: true });
    await page.evaluate(() => window.__babsTerminalClient?.terminal.focus());
    await page.keyboard.press("Escape");

    await expect
      .poll(() =>
        page.evaluate(() =>
          document.activeElement?.classList.contains("xterm-helper-textarea") || false
        )
      )
      .toBe(true);

    await page.keyboard.insertText(`printf '${marker}\\n'`);
    await page.keyboard.press("Enter");

    await expect
      .poll(async () => await page.locator(".xterm").innerText())
      .toContain(marker);
  } finally {
    cleanupSpawnedCitizen(slug);
  }
});

test("sentinel terminal keeps receiving output after citizens reload", async ({ page }) => {
  await connectSentinel(page);
  await runCommandAndExpect(page, "BABS_PHASE1_BEFORE_RELOAD");

  const restartsBefore = webLogCount("Babs.DevReloader restarted :babs_citizens");
  const readyBefore = webLogCount("Babs citizen ready: sentinel");
  const joinsBefore = webLogCount("JOINED pane:sentinel");
  const source = readFileSync(paneSourcePath, "utf8");
  writeFileSync(paneSourcePath, source);

  await waitForCitizensReload(restartsBefore, readyBefore, joinsBefore);

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
    await expect(page.getByTestId("ticket-comments-chat")).toBeVisible();
    await expect(page.getByTestId("ticket-comments-empty")).toBeVisible();
    await expect(page.getByTestId("ticket-comment-form")).toBeVisible();
    await expect(page.locator('[data-testid="ticket-comment"] [data-icon="send"]')).toBeVisible();

    await page.getByTestId("ticket-comment-body").fill(comment);
    await page.getByTestId("ticket-comment").click();

    await expect(page.getByTestId("ticket-flash-info")).toContainText("Comment stored");
    await expect(page.getByTestId("ticket-comment-message").filter({ hasText: comment })).toBeVisible();
  } finally {
    cleanupTicket(id);
  }
});

test("ticket index creates a ticket and opens chat-ready detail", async ({ page }) => {
  const title = `E2E Created Ticket ${Date.now()}`;
  const body = "Created from the browser new ticket form.";
  let id;

  try {
    await page.goto("/tickets");
    await expect(page.getByTestId("tickets-index")).toBeVisible();
    await expect(page.getByTestId("tickets-new")).toBeVisible();
    await expect(page.locator('[data-testid="tickets-new"] [data-icon="plus"]')).toBeVisible();

    await page.getByTestId("tickets-new").click();
    await expect(page).toHaveURL(/\/tickets\/new$/);
    await expect(page.getByTestId("new-ticket-form")).toBeVisible();
    await expectLiveViewConnected(page);

    await page.getByTestId("ticket-title").fill(title);
    await page.getByTestId("ticket-priority").selectOption("high");
    await page.getByTestId("ticket-body").fill(body);
    await page.getByTestId("create-ticket-button").click();

    await expect(page).toHaveURL(/\/tickets\/T-\d{4}-\d{2}-\d{2}-\d{3}(\?.*)?$/);
    id = new URL(page.url()).pathname.split("/").pop();

    await expect(page.getByTestId("ticket-detail")).toBeVisible();
    await expect(page.getByTestId("ticket-detail")).toContainText(title);
    await expect(page.getByTestId("ticket-detail")).toContainText(body);
    await expect(page.getByTestId("ticket-comments-chat")).toBeVisible();
    await expect(page.getByTestId("ticket-comments-empty")).toBeVisible();
    await expect(page.getByTestId("ticket-comment-form")).toBeVisible();
    await expect(page.locator('[data-testid="ticket-comment"] [data-icon="send"]')).toBeVisible();
  } finally {
    if (id) cleanupTicket(id);
  }
});

test("ticket detail refreshes captured citizen replies from history", async ({ page }) => {
  const id = allocateTicketId();
  const reply = `E2E captured citizen reply ${Date.now()}.`;

  try {
    writeTicket(id, "E2E Captured Reply Ticket", "Browser reply capture body.");
    await page.goto(`/tickets/${id}`);

    await expect(page.getByTestId("ticket-detail")).toBeVisible();
    await expect(page.getByTestId("ticket-comments-empty")).toBeVisible();

    appendTicketHistory(id, {
      ts: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
      event: "comment",
      by: "clare",
      ticket_id: id,
      body: reply,
    });

    await expect(page.getByTestId("ticket-comment-message").filter({ hasText: reply })).toBeVisible();
    await expect(page.getByTestId("ticket-comment-message").filter({ hasText: "clare" })).toBeVisible();
  } finally {
    cleanupTicket(id);
  }
});

test("external tmux attach uses detach semantics and leaves imported session alive", async ({
  page,
}) => {
  test.setTimeout(60_000);

  const suffix = Date.now();
  const slug = `bdd-e2e-import-${suffix}`;
  const externalSession = `bdd-e2e-external-${suffix}`;
  let paneId;

  try {
    await createShellCitizen(page, slug);

    await page.goto("/citizens");
    await expectLiveViewConnected(page);
    await waitForIndexStatus(page, slug, "up");
    await page.getByTestId(`citizen-stop-${slug}`).click();
    await waitForIndexStatus(page, slug, "stopped");

    startExternalTmuxSession(externalSession);
    expect(externalTmuxSessionAlive(externalSession)).toBe(true);
    paneId = externalTmuxPaneId(externalSession);
    const preexistingMarker = `BABS_E2E_IMPORTED_PREEXISTING_${suffix}`;
    execFileSync("tmux", [
      "send-keys",
      "-t",
      externalSession,
      `printf '${preexistingMarker}\\n'`,
      "Enter",
    ]);
    expect(externalTmuxCaptureContains(externalSession, preexistingMarker)).toBe(true);

    await page.goto("/citizens/attach");
    await expect(page.getByTestId("attach-citizen-page")).toBeVisible();
    await expectLiveViewConnected(page);
    await expect(page.getByTestId("attach-submit")).toBeVisible();
    await expect(page.locator('[data-testid="attach-submit"] [data-icon="link"]')).toBeVisible();

    await submitAttachForm(page, slug, paneId);

    await expect(page).toHaveURL(new RegExp(`/citizens/${slug}(\\?.*)?$`));
    await expect(page.locator(".xterm")).toBeVisible();
    await expect(page.getByTestId("connection-status")).toHaveAttribute(
      "data-state",
      "connected"
    );
    await expect(page.getByTestId("terminal-ownership-badge")).toContainText("Imported");
    await expect(page.getByTestId("terminal-lifecycle-reminder")).toContainText("Detach only");
    await expect(page.getByTestId("terminal-stop")).toContainText("Detach");
    await expect(page.getByTestId("terminal-restart")).toContainText("Reattach");
    await expect
      .poll(async () => await page.locator(".xterm").innerText())
      .toContain(preexistingMarker);

    const marker = `BABS_E2E_IMPORTED_ATTACH_${suffix}`;
    await runCommandAndExpect(page, marker);
    expect(externalTmuxCaptureContains(externalSession, marker)).toBe(true);

    await page.getByTestId("terminal-stop").click();
    await expect(page).toHaveURL(/\/citizens(\?.*)?$/);
    await waitForIndexStatus(page, slug, "stopped");
    expect(externalTmuxSessionAlive(externalSession)).toBe(true);
  } finally {
    cleanupSpawnedCitizen(slug);
    cleanupExternalTmuxSession(externalSession);
  }
});
