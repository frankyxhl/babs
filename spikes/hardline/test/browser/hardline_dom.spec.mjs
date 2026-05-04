import { expect, test } from "@playwright/test";

test("DOM rendering uses status dots and a single active Open Full control", async ({ page }) => {
  await page.goto("/");

  const result = await page.evaluate(async () => {
    const { renderSessions } = await import("/js/hardline_manager.js");
    const list = document.createElement("div");
    const clicked = [];

    renderSessions({
      document,
      list,
      activeSlug: "demo-a",
      sessions: [
        { slug: "demo-a", session: "babs-hardline-demo-a", alive: true },
        { slug: "demo-b", session: "babs-hardline-demo-b", alive: false }
      ],
      onSelect: (slug) => clicked.push(slug)
    });

    list.querySelector('[data-testid="session-select-demo-b"]').click();

    return {
      buttons: list.querySelectorAll("button").length,
      openFullButtons: document.querySelectorAll('[data-testid="open-full-button"]').length,
      upText: list.textContent.includes("up"),
      downText: list.textContent.includes("down"),
      activeClass: list.querySelector('[data-testid="session-select-demo-a"]').className,
      upClass: list.querySelector('[data-testid="session-status-demo-a"]').className,
      downClass: list.querySelector('[data-testid="session-status-demo-b"]').className,
      downAria: list.querySelector('[data-testid="session-status-demo-b"]').getAttribute("aria-label"),
      clicked
    };
  });

  expect(result.buttons).toBe(2);
  expect(result.openFullButtons).toBe(1);
  expect(result.upText).toBe(false);
  expect(result.downText).toBe(false);
  expect(result.activeClass).toContain("active");
  expect(result.upClass).toBe("status-dot up");
  expect(result.downClass).toBe("status-dot down");
  expect(result.downAria).toBe("down");
  expect(result.clicked).toEqual(["demo-b"]);
});

test("full-mode overlay helpers update visible state", async ({ page }) => {
  await page.goto("/");

  const result = await page.evaluate(async () => {
    const { hideFullError, resolveElements, showFullError } = await import("/js/hardline_manager.js");
    const elements = resolveElements(document);

    showFullError(elements, "Session not found: missing");
    const shown = {
      hidden: elements.fullOverlay.hidden,
      message: elements.fullOverlayMessage.textContent
    };

    hideFullError(elements);

    return {
      shown,
      hiddenAfterHide: elements.fullOverlay.hidden,
      messageAfterHide: elements.fullOverlayMessage.textContent
    };
  });

  expect(result.shown).toEqual({ hidden: false, message: "Session not found: missing" });
  expect(result.hiddenAfterHide).toBe(true);
  expect(result.messageAfterHide).toBe("");
});
