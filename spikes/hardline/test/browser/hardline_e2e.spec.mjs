import { expect, test } from "@playwright/test";

import {
  captureScreen,
  cleanupSessions,
  cleanupTmuxPrefix,
  createSession,
  listSessions,
  uniqueSlug
} from "./support/hardline_helpers.mjs";

const createdSlugs = new Set();

test.describe.configure({ mode: "serial" });

test.afterEach(async ({ request }) => {
  await cleanupSessions(request, createdSlugs);
  createdSlugs.clear();
});

test.afterAll(() => {
  cleanupTmuxPrefix();
});

async function waitForConnected(page, slug) {
  await expect
    .poll(() => page.locator("#socket-status").textContent())
    .toContain(`connected ${slug}`);
}

async function createFromUi(page, slug, command = "") {
  await page.getByTestId("slug-input").fill(slug);
  await page.getByTestId("command-preset").selectOption(command);
  await page.getByTestId("create-button").click();
  await expect(page.locator("#active-title")).toHaveText(slug);
  await waitForConnected(page, slug);
  createdSlugs.add(slug);
}

test("Create a session with the default tmux shell", async ({ page, request }) => {
  const slug = uniqueSlug("default");
  await page.goto("/");

  await expect(page.getByTestId("slug-input")).toHaveValue(/^[a-z][a-z0-9-]{0,47}$/);
  await createFromUi(page, slug, "");

  await expect(page.locator("#meta-command")).toContainText("tmux default");

  const sessions = await listSessions(request);
  expect(sessions.find((session) => session.slug === slug)).toMatchObject({
    slug,
    command: "",
    alive: true
  });
});

test("Create a session with the zsh fast shell fallback", async ({ page, request }) => {
  const slug = uniqueSlug("fast");
  await page.goto("/");

  await createFromUi(page, slug, "/bin/zsh -f");
  await expect(page.locator("#meta-command")).toHaveText("/bin/zsh -f");

  const sessions = await listSessions(request);
  expect(sessions.find((session) => session.slug === slug)).toMatchObject({
    slug,
    command: "/bin/zsh -f",
    alive: true
  });
});

test("Suggested slug appears without typing and shuffle changes it", async ({ page }) => {
  await page.goto("/");

  const first = await page.getByTestId("slug-input").inputValue();
  expect(first).toMatch(/^[a-z][a-z0-9-]{0,47}$/);

  for (let attempt = 0; attempt < 5; attempt += 1) {
    await page.getByTestId("slug-reroll-button").click();
    const next = await page.getByTestId("slug-input").inputValue();

    if (next !== first) {
      expect(next).toMatch(/^[a-z][a-z0-9-]{0,47}$/);
      return;
    }
  }

  throw new Error("slug shuffle did not change the suggestion after 5 attempts");
});

test("Select a session, connect the terminal, and type without duplicate output events", async ({
  page,
  request
}) => {
  const slug = uniqueSlug("type");
  await createSession(request, slug, "");
  createdSlugs.add(slug);

  await page.goto("/");
  await page.getByTestId(`session-select-${slug}`).click();
  await waitForConnected(page, slug);

  await page.getByTestId("terminal").click();
  await page.keyboard.type("printf 'BABS_XTERM_OK\\n'");
  await page.keyboard.press("Enter");

  await expect.poll(() => captureScreen(request, slug)).toContain("BABS_XTERM_OK");
  await expect(page.getByTestId("dup-status")).toHaveText("dup:0");
});

test("Open the selected session in full-window mode", async ({ context, page }) => {
  const slug = uniqueSlug("full");
  await page.goto("/");
  await createFromUi(page, slug, "");

  const popupPromise = context.waitForEvent("page");
  await page.getByTestId("open-full-button").click();
  const popup = await popupPromise;

  await popup.waitForLoadState("domcontentloaded");
  await expect(popup).toHaveURL(new RegExp(`[?&]session=${slug}(&|$).*full=1|[?&]full=1(&|$).*session=${slug}`));
  await waitForConnected(popup, slug);
});

test("Refresh full-window mode and reconnect to the same tmux session", async ({ page, request }) => {
  const slug = uniqueSlug("refresh");
  const created = await createSession(request, slug, "");
  createdSlugs.add(slug);

  await page.goto(`/?session=${slug}&full=1`);
  await waitForConnected(page, slug);

  const before = (await listSessions(request)).find((session) => session.slug === slug);
  await page.reload();
  await waitForConnected(page, slug);
  const after = (await listSessions(request)).find((session) => session.slug === slug);

  expect(after.session).toBe(created.session.session);
  expect(after.session_id).toBe(before.session_id);
  expect(after.pane_pid).toBe(before.pane_pid);
});

test("Stop a selected managed session without touching other managed sessions", async ({
  page,
  request
}) => {
  const stoppedSlug = uniqueSlug("stop");
  const survivorSlug = uniqueSlug("stay");

  await createSession(request, stoppedSlug, "");
  await createSession(request, survivorSlug, "");
  createdSlugs.add(stoppedSlug);
  createdSlugs.add(survivorSlug);

  page.on("dialog", (dialog) => dialog.accept());
  await page.goto("/");
  await page.getByTestId(`session-select-${stoppedSlug}`).click();
  await waitForConnected(page, stoppedSlug);
  await page.getByTestId("stop-button").click();

  await expect(page.getByTestId("message-status")).toHaveText(`stopped ${stoppedSlug}`);
  const sessions = await listSessions(request);
  expect(sessions.some((session) => session.slug === stoppedSlug)).toBe(false);
  expect(sessions.some((session) => session.slug === survivorSlug && session.alive)).toBe(true);
  createdSlugs.delete(stoppedSlug);
});

test("Open a missing full-window session and see the error overlay", async ({ page }) => {
  const slug = uniqueSlug("missing");
  await page.goto(`/?session=${slug}&full=1`);

  await expect(page.getByTestId("full-overlay")).toBeVisible();
  await expect(page.locator("#full-overlay-message")).toHaveText(`Session not found: ${slug}`);
});
