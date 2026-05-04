# PRP-2205: Phase 0c — Hardline Browser Test Harness

**Applies to:** BAB project
**Last updated:** 2026-05-04
**Last reviewed:** 2026-05-04
**Status:** Implemented
**Depends on:** `BAB-2203` Phase 0b Hardline Full-Window Mode
**Does not replace:** `BAB-2200` official 24h+ full validation

---

## What Is It?

Phase 0c is a testing and refactoring phase for the Hardline browser manager in
`spikes/hardline/`.

Phase 0a and 0b intentionally moved quickly in a single static page. The UI now
has enough JavaScript behavior that static string assertions are no longer
enough. Phase 0c extracts browser logic into testable modules and adds focused
JavaScript, BDD-style, and browser E2E coverage.

---

## Problem

Current coverage is uneven:

- Elixir unit/integration coverage is strong for tmux lifecycle, manager API,
  pane server, validation scenarios, and static HTML contracts.
- JavaScript behavior is covered only by static `index_html_test.exs` string
  assertions.
- Browser behavior is covered by manual/Computer Use/curl smoke, not repeatable
  E2E tests.
- The UI logic still lives inline in `priv/static/index.html`, which makes pure
  browser behavior hard to unit test.

That is acceptable for a spike, but it is becoming too fragile as the manager
gains shell presets, generated slugs, icons, full-window mode, and terminal
connection behavior.

---

## Proposed Solution

Refactor only enough to make the existing browser manager testable:

- move manager JavaScript out of `index.html` into `priv/static/js/`
- split pure logic from DOM/Phoenix/xterm side effects
- keep static HTML/CSS behavior and user-facing functionality unchanged
- add stable `data-testid` hooks for browser tests
- add fast JavaScript/DOM tests for pure and rendered behavior
- add BDD-style browser scenarios for the main operator workflows
- add Playwright E2E tests that exercise the running `mix hardline.web` server
  with real tmux-backed sessions

Phase 0c is not a feature phase. Any UI or behavior changes should be limited to
refactoring fallout needed to preserve existing behavior under test.

---

## Non-Goals

- No new Hardline product features.
- No production Babs UI work.
- No replacement for the deferred 24h+ Phase 0 full validation.
- No broad CSS redesign.
- No change to tmux lifecycle semantics.
- No backend primary-viewer arbitration for simultaneous browser tabs.

---

## Test Layers

### Existing Elixir Layer

Keep `mix test` as the fast backend/static-contract gate:

- tmux command shapes and blank-command tmux-default behavior
- manager API and session lifecycle
- pane server byte path
- validation scenario helpers
- static HTML contract smoke

### JavaScript Unit/DOM Layer

Add a local browser-test toolchain under `spikes/hardline/`.

Target coverage:

- URL parsing: normal mode, `full=1`, missing `session`, invalid `session`
- `fullUrl(slug)` construction
- shell preset command selection
- command labels for tmux-default sessions
- generated slug suggestions avoid existing slugs and obey slug rules
- status dot rendering for alive/dead sessions
- one active `Open Full` control, no per-row duplicate full button
- full-mode error overlay state

### BDD-Style Scenarios

Add readable scenario names in the browser E2E suite. The initial scenarios are:

- Create a session with the default tmux shell.
- Create a session with the zsh fast shell fallback.
- Suggested slug appears without typing and shuffle changes it.
- Select a session and connect the terminal.
- Type `printf 'BABS_XTERM_OK\n'` and see it once with `dup:0`.
- Open the selected session in full-window mode.
- Refresh full-window mode and reconnect to the same tmux session.
- Stop a selected managed session without touching other managed sessions.
- Open a missing full-window session and see the error overlay.

### Browser E2E Layer

Use Playwright against a real local `mix hardline.web` process.

The E2E harness should:

- start the web server on an ephemeral or configured local port
- use a unique tmux prefix for each test run
- create temporary managed tmux sessions only under that prefix
- clean up all temporary tmux sessions and the web server after the run
- avoid touching operator sessions such as `babs-hardline-demo-a`
- verify browser DOM, URL, and tmux metadata where relevant

---

## Refactor Plan

1. Create `priv/static/js/hardline_core.js` for pure logic:
   - URL mode parsing
   - full-window URL creation
   - shell preset command selection
   - command labels
   - slug suggestion generation
2. Create `priv/static/js/hardline_manager.js` for DOM, API, Phoenix Channel,
   xterm.js, FitAddon, and lucide wiring.
3. Keep `index.html` responsible for structure, CSS, script includes, and boot.
4. Add `data-testid` attributes to stable controls and status surfaces.
5. Add a minimal JS test setup with package scripts.
6. Add Playwright tests under a dedicated browser-test directory.
7. Add a documented command for running only browser tests.
8. Update `mix test` static assertions so they verify script/module inclusion
   rather than large inline implementation strings.

---

## Acceptance

Phase 0c is done when:

- `index.html` no longer contains the bulk of the manager JavaScript.
- Pure JavaScript behavior has automated tests.
- Browser E2E tests cover create/select/type/full/refresh/stop/missing-session
  scenarios.
- E2E tests run with an isolated tmux prefix and leave no temporary sessions.
- Existing `mix test` still passes.
- New browser test command is documented in `spikes/hardline/README.md`.
- `af validate` passes.
- No Phase 0 official validation-gate status is changed.

## Implementation Result (2026-05-04)

Phase 0c is implemented in `spikes/hardline/`.

Implementation:

- `index.html` now keeps structure/CSS/CDN library includes and loads
  `/js/hardline_boot.js` as a module instead of carrying the bulk browser
  manager JavaScript inline.
- Pure browser logic lives in `priv/static/js/hardline_core.js`, covering URL
  mode parsing, full-window URL construction, shell preset command selection,
  command labels, slug suggestions, status-dot descriptors, stale-active
  selection handling, and full-mode unavailable messages.
- DOM/API/Phoenix Channel/xterm.js/lucide wiring lives in
  `priv/static/js/hardline_manager.js`, with exported DOM helpers for tests.
- Stable `data-testid` hooks were added to the create form, slug controls,
  active-session actions, session rows/status dots, terminal, overlay, and
  status surfaces.
- `Plug.Static` now serves the `priv/static/js/` module directory.
- A local Node/Playwright browser test toolchain was added under
  `spikes/hardline/`.

Validation evidence:

- `npm run test:js` passed: 9 pure JavaScript tests.
- `npm run test:e2e` passed: 10 Playwright DOM/E2E tests.
- Playwright E2E starts `mix hardline.web` on localhost with a unique
  `babs-e2e-*` tmux prefix and cleans up temporary managed sessions after each
  run.
- Browser E2E covers default-shell creation, zsh-fast fallback creation,
  slug suggestion/reroll, select/connect/type with `dup:0`, full-window launch,
  full-window refresh/reconnect to the same tmux session, stop without touching
  another managed session, and missing-session full-mode overlay.
- `mise exec -- mix test` passed: 59 tests, 0 failures.
- The official Phase 0 full validation gate remains deferred and unchanged.

---

## Open Questions

- Resolved for Phase 0c: use Node's built-in test runner for pure JavaScript and
  Playwright for DOM/E2E, invoked through npm scripts rather than a Mix wrapper.
- Remaining operational prerequisite: Playwright uses local Google Chrome by
  default. If a future CI environment lacks Chrome, install Playwright's
  managed browser binaries and run with `HARDLINE_E2E_CHANNEL=managed`.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-04 | Initial Phase 0c plan for Hardline browser test harness and JS refactor | Codex |
| 2026-05-04 | Implemented Phase 0c JS extraction plus Node/Playwright browser tests; local JS, E2E, and ExUnit validation passed | Codex |
