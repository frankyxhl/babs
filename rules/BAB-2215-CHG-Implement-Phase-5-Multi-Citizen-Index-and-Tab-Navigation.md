# CHG-2215: Implement Phase 5 Multi Citizen Index and Tab Navigation

**Applies to:** BAB project
**Last updated:** 2026-05-06
**Last reviewed:** 2026-05-06
**Status:** Completed
**Date:** 2026-05-06
**Requested by:** —
**Priority:** Medium
**Change Type:** Normal

---

## What

Implement Phase 5 from
[BAB-2214](BAB-2214-PRP-Phase-5-Multi-Citizen-Index-and-Tab-Navigation.md):

- Add a read-only Citizen status snapshot boundary for fleet UI display.
- Add `/citizens` as the browser fleet index.
- Redirect `/` to `/citizens`.
- Add compact tab navigation to default terminal pages.
- Preserve pure full-window terminal mode at `/citizens/<slug>?full=1`.
- Preserve `socket_token` across index, new-citizen, tab, terminal, and full
  links.
- Add browser-harness BDD for multi-Citizen navigation and terminal switching.
- Add fast fd smoke coverage for at least three concurrent Citizens.
- Keep the 30 minute fd stability run documented but deferred to Phase 6 or the
  M2 gate.

## Why

Phase 4 made browser-based Citizen creation possible, but the operator still has
to know individual `/citizens/<slug>` URLs to switch between Citizens. Phase 5
turns the browser into a usable multi-Citizen console: the operator can see all
known Citizens, understand which ones are live, open any terminal, and switch
between active Citizens without URL hand-editing.

This is also the natural surface for Phase 6 lifecycle controls. Without the
index and tab navigation, stop/start/restart buttons would either be hidden on
single terminal pages or duplicated ad hoc.

## Impact Analysis

- **Systems affected:** `:babs_citizens` read-model/query layer,
  `:babs` router/controller/LiveView terminal pages, browser static terminal
  sizing behavior, browser-harness BDD, existing Playwright smoke if an exact
  duplicate is replaced, and BAB roadmap/tracker docs.
- **Data affected:** No production data migration. Runtime reads existing
  SQLite `citizens` rows and live Pane registry entries. Tests may create
  temporary shell Citizens, tmux sessions, workspaces, TOML files, transcripts,
  and SQLite rows under test roots.
- **Security/privacy:** Do not expose Citizen `env` values. Preserve
  `socket_token` only in generated local URLs and tests; do not log or publish
  real tokens. Do not add private IPs, hostnames, or local machine paths to
  public PR text.
- **UX impact:** `/` stops redirecting to sentinel and becomes the fleet entry
  point via `/citizens`. Default terminal pages gain compact chrome; pure
  terminal mode remains available through `?full=1`.
- **Rollback plan:** Revert the Phase 5 commit/PR. Existing Citizen TOML,
  SQLite rows, workspaces, tmux sessions, and transcripts remain compatible with
  Phase 4 terminal routes. If test-created Citizens remain, stop their tmux
  sessions and remove their test TOML/workspace/SQLite rows. Any bookmark or
  script that depended on `/` opening sentinel can use `/citizens/sentinel`
  directly after Phase 5; reverting restores the old root redirect.

## Implementation Plan

1. **RED: status snapshot read model**
   - Add tests for a `Babs.Citizens.StatusSnapshot` or equivalent boundary.
   - Cases:
     - SQLite `running` + `Lifecycle.lookup/1` succeeds -> runtime `:up`,
       visual `:idle`.
     - SQLite `running` + no live pane -> runtime `:reattaching`, visual
       `:waiting`.
     - SQLite `stopped` -> runtime `:stopped`, visual `:paused`.
     - SQLite `failed` -> runtime `:failed`, visual `:dead`.
     - `env` values are never present in snapshot output.
     - CLI labels cover `shell`, `claude`, `codex`, `droid`, `pi`,
       `copilot-cli`, and a custom fallback such as `fish (custom)`.
     - cwd labels display `workspaces/<relative>` when under workspace root and
       compact external paths without exposing env data.
   - Document in module docs or CHG notes that `:reattaching` is best-effort:
     it can mean a normal transient reattach window or a stale `running` row
     until heartbeat/lifecycle audit exists in a later phase.
   - Note that Phase 5 intentionally does not map `BAB-1004`'s `typing` visual
     state, because Phase 5 tracks lifecycle presence rather than output
     activity.
2. **GREEN: status snapshot implementation**
   - Use `Catalog.list_citizens/0` ordered by slug.
   - Use `Lifecycle.lookup/1` only for live-presence checks.
   - Do not mutate status, start/stop Citizens, or read/write TOML.
   - Keep the returned data display-safe and deterministic for LiveView tests.
3. **RED/GREEN: centralized Citizen URL helper**
   - Add a web helper such as `BabsWeb.CitizenPath`.
   - Generate `/citizens`, `/citizens/new`, `/citizens/<slug>`, and
     `/citizens/<slug>?full=1`.
   - Preserve optional `socket_token` and omit it when blank.
   - Run the existing Phase 4 socket-token regression tests before starting this
     step, then keep them green after the helper is introduced.
4. **RED/GREEN: routing and controller entry points**
   - Add `GET /citizens` before `GET /citizens/:slug`.
   - Add explicit `HEAD /citizens`, mirroring `HEAD /citizens/:slug`.
   - Change `/` to redirect to `/citizens`, preserving `socket_token` when
     present.
   - Keep `/citizens/new` routed through `TerminalController.new/2` per final
     Phase 4 behavior in `BAB-2213`: existing slug `new` terminal wins;
     otherwise render `BabsWeb.NewCitizenLive`.
5. **RED/GREEN: `/citizens` LiveView index**
   - Add `BabsWeb.CitizensLive`.
   - Render compact counts for total, up, stopped, failed, and reattaching.
   - Render rows ordered by slug with stable selectors:
     `citizen-row-<slug>`, `citizen-status-<slug>`,
     `citizen-open-<slug>`, and `citizen-full-<slug>`.
   - Render a compact empty state with `citizens-empty-state` and a
     `/citizens/new` link.
   - Refresh snapshots every 1 second while connected.
   - Add a LiveView test where status changes between ticks and the next tick
     refreshes the UI.
6. **RED/GREEN: terminal tab chrome and full mode**
   - Extend `TerminalController.show/2` and `TerminalLive` session assigns with
     `full?`.
   - Default `/citizens/<slug>` renders compact chrome:
     `Citizens` link, slug-ordered tabs with `citizen-tab-<slug>` selectors,
     active tab highlighting, status dots, and a `Full` link.
   - `/citizens/<slug>?full=1` renders the existing pure full-window terminal
     with no tab chrome.
   - For a single Citizen, keep the chrome visible with the `Citizens` link,
     active tab, and `Full` link.
   - Keep exactly one xterm root on the page.
   - Preserve xterm FitAddon behavior by exposing the compact chrome height as
     a CSS variable and giving the terminal container a stable
     `calc(100vh - var(--terminal-chrome-height))` height in default mode and
     full viewport height in full mode. Trigger the existing resize path after
     mount and on window resize.
7. **Browser-harness BDD and fd smoke**
   - Prefer browser-harness for Phase 5 BDD.
   - Create or seed three deterministic shell Citizens under an isolated test
     root.
   - Visit `/citizens`, verify index rows/statuses, and click through default
     terminal pages and `?full=1`.
   - Send a unique marker to each terminal exactly once.
   - fd fast-smoke baseline: sample the BEAM process fd count after all three
     Citizens are running but before any browser terminal connects.
   - Run at least three switch/input cycles across the three Citizens.
   - While terminals are connected, final fd count must be no more than
     baseline + 12; after browser cleanup, fd count must return to baseline + 4.
   - Fail closed on orphaned test tmux sessions, duplicate markers, or leaked
     browser processes/tabs.
   - Keep existing Playwright smoke unless a browser-harness scenario covers the
     exact same workflow; remove duplicate Playwright coverage only in the same
     commit that adds the replacement.
8. **Docs and validation**
   - Update `BAB-2300`, this CHG, and the discussion tracker with final
     validation results.
   - Document the deferred 30 minute fd command for Phase 6/M2.
   - Run the validation stack listed below.

## Validation Plan

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`
- `mise exec -- mix test --cover`
- coverage must not regress below `:babs_citizens >= 80%` and `:babs >= 75%`
- `npm run test:js`
- browser-harness BDD for Phase 5 navigation/concurrency/fd smoke
- existing Playwright smoke unless deliberately replaced by equivalent
  browser-harness coverage
- `mise exec -- mix babs.gate_a`
- `af validate --root .`
- `git diff --check`

## Review / Approval

- `BAB-2214` PRP approved on 2026-05-06 after Trinity fast-review R2 passed
  with GLM and DeepSeek using Trinity 3.1.0 parallel provider dispatch.
- This CHG was approved on 2026-05-06 after Trinity fast-review with GLM and
  DeepSeek using Trinity 3.1.0 parallel provider dispatch. GLM returned PASS
  9.49/10; DeepSeek returned PASS 9.0/10 under `COR-1602` + `COR-1609`.
  Advisory clarifications for `HEAD /citizens`, socket-token regression timing,
  CSS chrome-height mechanism, and root redirect bookmark impact were folded in
  after review.
- GitHub Codex PR review loop after implementation follows `COR-1615`, capped
  at the operator's current maximum of five rounds.
- Trinity implementation fast-review passed on 2026-05-06 with GLM and
  DeepSeek using Trinity 3.1.0 parallel provider dispatch. GLM returned PASS
  9.19/10; DeepSeek returned PASS 9.38/10. Findings were advisory only.
- GitHub Codex PR review R1 found a P2 issue where terminal tabs could link to
  stopped, failed, or reattaching Citizens whose terminal routes return 404.
  Terminal tabs now include only pane-backed `:up` Citizens, with the active
  terminal preserved as a fallback. The `/citizens` index keeps non-live rows
  visible but disables their Open/Full controls instead of linking to 404
  routes.
- GitHub Codex PR review R2 found a P2 malformed-query issue where nested
  `socket_token` params could become maps and crash URL generation. Controller
  token extraction and `CitizenPath` now ignore non-string socket tokens, with
  regressions for root redirects, terminal rendering, and direct helper calls.
- GitHub Codex PR review R3 found a P2 issue where default terminal pages
  scheduled LiveView tab refreshes without loading `live_boot.js`, plus a P3
  issue where a fallback active tab could display the wrong status. Default
  terminal pages now load `live_boot.js`, terminal-owned connection status is
  restored after `phx:update`, and tab filtering preserves the active Citizen's
  real non-up status while hiding other non-up tabs.

## Deferred Validation

The 30 minute fd stability run is intentionally not a Phase 5 merge blocker.
It should be run in Phase 6 or at the M2 gate after stop/start/restart controls
exist. Phase 5 must still document the exact command and pass criteria during
implementation.

Deferred full-run command for Phase 6/M2:

```bash
BABS_BROWSER_BASE_URL=http://127.0.0.1:<port> \
BABS_HTTP_PORT=<port> \
BU_CDP_WS=<isolated-or-approved-browser-cdp-ws> \
npm run test:bdd
```

Pass criteria for the full run:

- At least three Citizens remain concurrently reachable through `/citizens`
  and terminal tabs for the full run duration.
- Each Citizen accepts a unique marker exactly once.
- Browser cleanup leaves no BDD tmux sessions, managed browser tabs, or BDD
  server listeners behind.
- fd count remains within the Phase 5 fast-smoke thresholds unless Phase 6/M2
  deliberately updates the threshold with measured evidence.

## Implementation Results

Implemented in branch `codex/phase-5-prep`:

- Added `Babs.Citizens.StatusSnapshot` as a read-only display boundary for
  SQLite Citizen rows plus live Pane presence. The snapshot maps running/live
  panes to `:up`, running/missing panes to best-effort `:reattaching`, stopped
  rows to `:stopped`, failed rows to `:failed`, and never exposes `env`.
- Added `BabsWeb.CitizenPath` for centralized `/citizens`, `/citizens/new`,
  terminal, full-window terminal, and optional `socket_token` URL generation.
- Added `/citizens` and `HEAD /citizens`, changed `/` to redirect to
  `/citizens`, and preserved the existing `/citizens/new` terminal-vs-form
  behavior from Phase 4.
- Added `BabsWeb.CitizensLive` with compact status counts, slug-ordered rows,
  stable selectors, display-safe CLI/cwd labels, token-preserving open/full
  links, and 1 second refresh ticks.
- Extended default terminal pages with compact tab chrome, slug-ordered status
  tabs, a `Citizens` link, a `Full` link, and stable terminal sizing using
  `calc(100vh - var(--terminal-chrome-height))`.
- Preserved pure full-window terminal mode at `/citizens/<slug>?full=1` with no
  tab chrome and exactly one xterm root.
- Expanded browser-harness BDD with a Phase 5 scenario that creates three shell
  Citizens, verifies index rows and tabs, sends unique terminal markers exactly
  once, checks full-window mode, and samples the managed BEAM fd count against
  the fast thresholds.

## Validation

Local validation on 2026-05-06:

- `mise exec -- mix format --check-formatted`: passed.
- `mise exec -- mix compile --warnings-as-errors`: passed.
- `mise exec -- mix test`: passed, `:babs_citizens` 120 tests and `:babs` 42
  tests.
- `mise exec -- mix test --cover`: passed, `:babs_citizens` 83.59% and
  `:babs` 84.10%.
- `npm run test:js`: passed, 8 Node tests.
- `BU_CDP_WS=<isolated Chrome CDP> BABS_BROWSER_BASE_URL=http://127.0.0.1:<port> BABS_HTTP_PORT=<port> npm run test:bdd`:
  passed, including the Phase 5 multi-Citizen index/tab/fd scenario, 12 passed
  scenarios plus 1 expected `BABS_WORKSPACE_ROOT` skip.
- `npm run test:e2e`: passed, 6 Playwright smoke tests. `npm ci` was required
  first in this worktree because npm dev binaries were not installed.
- `mise exec -- mix babs.gate_a`: passed.
- `af validate --root .`: passed, 111 documents checked.
- `git diff --check`: passed.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-06 | Initial Phase 5 CHG draft from approved `BAB-2214` PRP | Codex |
| 2026-05-06 | Trinity fast-review approved CHG with GLM 9.49/10 and DeepSeek 9.0/10; fold in advisory clarifications and mark Approved | Codex |
| 2026-05-06 | Implement Phase 5 locally and record validation evidence, including browser-harness Phase 5 index/tab/fd BDD | Codex |
| 2026-05-06 | Record Trinity implementation fast-review PASS from GLM 9.19/10 and DeepSeek 9.38/10 | Codex |
| 2026-05-06 | Address GitHub Codex PR review R1 P2 by filtering terminal tabs to pane-backed Citizens and disabling non-live index actions | Codex |
| 2026-05-06 | Address GitHub Codex PR review R2 P2 by ignoring malformed non-string socket tokens | Codex |
| 2026-05-06 | Address GitHub Codex PR review R3 by booting LiveView on tabbed terminals, restoring terminal-owned status after LiveView patches, and preserving active non-up tab status | Codex |
