import assert from "node:assert/strict";
import test from "node:test";

import {
  commandLabel,
  fullModeDeadSessionMessage,
  fullModeMissingSessionMessage,
  fullUrl,
  nextActiveSession,
  parsePageMode,
  selectedCommand,
  slugCharacters,
  slugFruits,
  slugPattern,
  statusDotDescriptor,
  suggestSlug
} from "../../priv/static/js/hardline_core.js";

test("parses normal and full-window URL modes", () => {
  assert.deepEqual(parsePageMode(""), {
    requestedFullMode: false,
    requestedSession: "",
    fullMode: false
  });

  assert.deepEqual(parsePageMode("?session=demo-a&full=1"), {
    requestedFullMode: true,
    requestedSession: "demo-a",
    fullMode: true
  });

  assert.deepEqual(parsePageMode("?full=1"), {
    requestedFullMode: true,
    requestedSession: "",
    fullMode: false
  });
});

test("constructs full-window URLs without losing existing origin", () => {
  assert.equal(
    fullUrl("http://localhost:4010/?x=1", "demo-a"),
    "http://localhost:4010/?x=1&session=demo-a&full=1"
  );
});

test("keeps shell preset command selection explicit", () => {
  assert.equal(selectedCommand(""), "");
  assert.equal(selectedCommand("/bin/zsh -f"), "/bin/zsh -f");
});

test("labels tmux-default and explicit commands", () => {
  assert.equal(commandLabel(), "-");
  assert.equal(commandLabel(null), "-");
  assert.equal(commandLabel({ command: "", pane_command: "zsh" }), "tmux default (zsh)");
  assert.equal(commandLabel({ command: "" }), "tmux default");
  assert.equal(commandLabel({ command: "/bin/zsh -f" }), "/bin/zsh -f");
  assert.equal(commandLabel({ pane_command: "zsh" }), "zsh");
});

test("suggests unused fruit-character slugs that obey manager slug rules", () => {
  const randomValues = [0.5, 0.5];
  const slug = suggestSlug([], () => randomValues.shift() ?? 0);

  assert.match(slug, slugPattern);
  assert.match(slug, /^[a-z]+-[a-z]+$/);
  assert(slugFruits.some((fruit) => slug.startsWith(`${fruit}-`)));
  assert(slugCharacters.some((character) => slug.endsWith(`-${character}`)));
});

test("avoids taken suggestions and falls back to numbered slugs", () => {
  const taken = [];

  for (const fruit of slugFruits) {
    for (const character of slugCharacters) {
      taken.push({ slug: `${fruit}-${character}` });
    }
  }

  assert.equal(suggestSlug(taken, () => 0), "mango-1");
});

test("describes status dots without textual up/down labels", () => {
  assert.deepEqual(statusDotDescriptor({ alive: true }), {
    className: "status-dot up",
    title: "up",
    ariaLabel: "up"
  });

  assert.deepEqual(statusDotDescriptor({ alive: false }), {
    className: "status-dot down",
    title: "down",
    ariaLabel: "down"
  });
});

test("drops stale active session after refresh", () => {
  assert.equal(nextActiveSession([], null), null);

  assert.deepEqual(
    nextActiveSession([{ slug: "demo-b" }], { slug: "demo-a" }),
    null
  );

  assert.deepEqual(
    nextActiveSession([{ slug: "demo-a", session: "tmux" }], { slug: "demo-a" }),
    { slug: "demo-a", session: "tmux" }
  );
});

test("builds full-mode unavailable messages", () => {
  assert.equal(fullModeMissingSessionMessage("gone"), "Session not found: gone");
  assert.equal(fullModeDeadSessionMessage("stopped"), "Session is not alive: stopped");
});
