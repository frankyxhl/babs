# CHG-2206: Phase 0c Hardline Browser Test Harness

**Applies to:** BAB project
**Last updated:** 2026-05-04
**Last reviewed:** 2026-05-04
**Status:** Proposed
**Related:** `BAB-2205`, `BAB-2203`, `BAB-2204`, `BAB-2200`

---

## What

Plan a testing-only Phase 0c for the Hardline browser manager.

The phase will refactor inline JavaScript out of `index.html` and add automated
coverage for the browser manager's JavaScript behavior, BDD-style workflows, and
real browser/tmux E2E paths.

---

## Why

Phase 0b added enough browser behavior that static HTML string assertions are no
longer sufficient:

- full-window URL mode
- generated slug suggestions
- shell preset behavior
- active-session actions
- status dots and icon rendering
- Phoenix Channel/xterm connection behavior

The next safe step is not more UI feature work. It is making the existing UI
testable and repeatably validated.

---

## Impact

Expected impact:

- no new user-facing features
- JavaScript moves from inline HTML into testable static modules
- new JS/DOM tests cover pure behavior and rendering decisions
- new Playwright E2E tests exercise the live Hardline manager against tmux
- documentation gains a browser-test command and test-tier map

Risk:

- introducing a JavaScript test toolchain adds maintenance surface
- E2E tests can become flaky if they share tmux state with operator sessions
- CDN-loaded assets may need a fallback strategy for deterministic CI/offline
  runs

---

## Plan

1. Keep Phase 0c strictly testing/refactor-only.
2. Extract pure browser logic into `priv/static/js/hardline_core.js`.
3. Extract DOM/Phoenix/xterm wiring into `priv/static/js/hardline_manager.js`.
4. Add stable `data-testid` hooks.
5. Add JavaScript unit/DOM tests for URL parsing, shell presets, slug
   generation, command labels, status dots, and full-mode state.
6. Add Playwright BDD-style E2E tests for create/select/type/full/refresh/stop
   and missing-session workflows.
7. Ensure E2E tests use a unique tmux prefix and clean up all tmux sessions they
   create.
8. Update README test instructions and `BAB-2205` implementation result.
9. Run `mix test`, browser tests, `git diff --check`, and `af validate`.

---

## Acceptance

- Hardline manager browser logic is testable outside the full static page.
- Automated JS/DOM tests exist for pure manager behavior.
- Automated browser E2E tests exist for the main operator workflows.
- Tests isolate temporary tmux state and leave no sessions behind.
- Current Phase 0a/0b behavior is preserved.
- No official Phase 0 full-validation gate is marked complete.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-04 | Initial proposed CHG for Phase 0c testing/refactor-only browser harness | Codex |
