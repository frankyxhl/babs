# CHG-2216: Implement Phase 6 Stop Start Restart UI

**Applies to:** BAB project
**Last updated:** 2026-05-06
**Last reviewed:** 2026-05-06
**Status:** Approved
**Date:** 2026-05-06
**Requested by:** —
**Priority:** Medium
**Change Type:** Normal

---

## What

Implement Phase 6 from
[BAB-2300](BAB-2300-PLN-Build-Roadmap.md#phase-6--stop--start--restart-ui):

- Add explicit browser lifecycle controls for durable Citizens:
  `Start`, `Stop`, and `Restart`.
- Add a small lifecycle action boundary in `:babs_citizens` that starts and
  restarts Citizens from SQLite records, not from ad hoc UI state.
- Extend `/citizens` rows with status-appropriate controls.
- Extend default tabbed terminal pages with active-Citizen lifecycle controls.
- Preserve pure full-window terminal mode at `/citizens/<slug>?full=1` with no
  management chrome.
- Preserve configured workspaces, TOML files, SQLite identity/config, and
  transcripts across stop/start/restart.
- Add unit, LiveView/controller, browser-harness BDD, existing E2E, coverage,
  and Gate A validation.

This CHG does not add archive/delete, config editing, role editing, ticket
automation, or multi-node lifecycle coordination.

## Why

Phase 5 made Babs usable as a multi-Citizen console, but non-live rows are still
dead ends: the operator can see a stopped, failed, or reattaching Citizen, but
cannot recover it from the browser. The flywheel is still fragile because
routine lifecycle operations require terminal-side tmux or SQLite intervention.

Phase 6 closes that gap. It gives the operator explicit browser controls for
the lifecycle semantics already accepted in `BAB-1107`: Babs owns tmux sessions,
explicit `stop` kills only Babs-managed sessions, `start` reuses existing
Citizen config/workspace, and `restart` is a stop-plus-start of the same
Citizen.

This is the last management primitive needed before the Phase 6.5 manual ticket
dogfood: the operator can create, inspect, stop, restart, and recover Citizens
without leaving the Babs browser surface.

## Impact Analysis

- **Systems affected:** `:babs_citizens` lifecycle/catalog/status boundaries,
  tmux session control through `Babs.Citizens.Runner`, `BabsWeb.CitizensLive`,
  `BabsWeb.TerminalLive`, browser-harness BDD, existing Playwright smoke, Gate
  A validation, and roadmap/tracker docs.
- **Data affected:** SQLite `citizens.status` and `last_error`; Babs-managed
  tmux sessions named `babs-<slug>`; existing workspace directories and
  `transcript.jsonl` files. Phase 6 must not delete TOML files, workspaces,
  transcripts, or unprefixed tmux sessions.
- **Security/privacy:** UI actions must not expose `env`, tokens, local host
  paths, or private network addresses. Lifecycle errors shown in the browser
  must use `Catalog.redact_reason/1` or already-redacted `last_error` values.
  Public PR text must not include private Tailscale IPs or machine-local paths.
- **UX impact:** `/citizens` gains row-level lifecycle buttons. Default
  `/citizens/<slug>` gains compact active-Citizen controls. Full-window mode
  remains terminal-only. Stopped/failed/reattaching rows become recoverable from
  the index instead of showing disabled Open/Full controls only.
- **Known lifecycle gap:** `BAB-1107` describes a future polite TERM plus grace
  period before tmux kill. The current runtime does not record the nested AI CLI
  process tree separately from the tmux session, so Phase 6 implements the
  enforceable v0.1 behavior: terminate the Babs Pane attach, kill only the
  Babs-managed tmux session, preserve workspace/transcript, and defer exact
  nested process TERM/grace escalation.
- **Rollback plan:** Revert the Phase 6 implementation commit. Existing SQLite
  rows, TOML files, workspaces, and transcripts remain compatible with Phase 5.
  If rollback occurs after stopping Citizens, use `BAB-1505` to inspect or
  restore SQLite status before expecting boot-time auto-respawn; Phase 5
  intentionally skips rows with `status = "stopped"` or `status = "failed"`.

## Implementation Plan

1. **RED: lifecycle action boundary**
   - Add tests for explicit lifecycle operations before UI work.
   - Preferred public API:
     - `Lifecycle.start_registered_citizen(slug)`:
       loads `%CitizenRecord{}` from SQLite, converts with `Catalog.to_config/1`,
       starts or reattaches through the existing `start_config/1` path, and
       marks `running` only after a pane is ready.
     - `Lifecycle.stop_citizen(slug)`:
       keeps the existing explicit stop API, with any needed internal hardening.
     - `Lifecycle.restart_registered_citizen(slug)`:
       reads the SQLite row/config before stopping, stops the existing pane/tmux
       session, starts the same Citizen again, and preserves cwd/config.
   - Required cases:
     - stopped row starts and becomes `running`.
     - failed row can be retried with Start and clears `last_error` on success.
     - running row with a live pane treats Start as idempotent success.
     - running row without a live pane uses the same recovery path as
       reattaching/start and becomes `running` on success.
     - Stop terminates the Pane child, kills only `babs-<slug>`, marks
       `stopped`, and is idempotent when the pane or tmux session is already
       absent.
     - Restart is stop-plus-start for the same SQLite row and preserves cwd,
       cli, cli_args, env, role, id, TOML, workspace, and transcript path.
     - Start/restart failures mark `failed` with redacted `last_error`.
     - Stop failure must not mark `stopped` unless the tmux session is actually
       absent or killed.
     - Restart must abort and report the redacted stop error if Stop fails and
       the Babs-managed tmux session is still present; it must not start a
       second session or mark `running` over an unresolved stop failure.
     - Missing slug returns a structured `{:error, :not_found}`-style result.
     - Concurrent actions for the same slug serialize so rapid Start/Stop/
       Restart clicks cannot interleave lifecycle mutations.
   - Phase 6 follows the roadmap's v0.1 stop behavior: terminate the Babs pane
     attach, `tmux kill-session -t babs-<slug>`, and mark stopped. Exact nested
     AI CLI PID TERM tracking remains out of scope until Babs records the
     nested process tree.
2. **GREEN: lifecycle implementation**
   - Keep lifecycle mutation inside `:babs_citizens`; web LiveViews call this
     boundary rather than calling `Runner` or `Catalog` directly.
   - Reuse `Runner.session_name/1` so Babs touches only `babs-<slug>` sessions.
   - Reuse `Catalog.to_config/1` for SQLite-sourced starts.
   - Do not rewrite TOML on Start/Stop/Restart.
   - Use a local per-slug lifecycle action lock, likely Registry-backed like
     `Babs.Citizens.Spawner`, so same-slug lifecycle operations serialize while
     different Citizens can still be managed independently.
   - Preserve the existing reload safety rule from `BAB-1110`: `:babs_citizens`
     reload detaches/rebinds and must not call explicit stop semantics.
3. **RED/GREEN: action availability read model**
   - Either extend `StatusSnapshot` with display-safe `actions` or add a
     adjacent helper for UI action availability.
   - Required action matrix:
     - `:up`: Open, Full, Stop, Restart.
     - `:reattaching`: Start, Stop, disabled Open/Full, no Restart.
     - `:stopped`: Start, disabled Open/Full.
     - `:failed`: Start, disabled Open/Full, show redacted `last_error`.
   - Keep labels compact and status-driven; do not expose env or raw exception
     details.
   - `:reattaching` intentionally omits Restart because there is no live Pane to
     restart atomically; the operator can Stop to clear stale tmux state or
     Start to recover the existing durable Citizen.
4. **RED/GREEN: `/citizens` lifecycle controls**
   - Add row-level buttons with stable selectors:
     `citizen-start-<slug>`, `citizen-stop-<slug>`,
     `citizen-restart-<slug>`.
   - Use LiveView events, not query-string side effects.
   - Refresh the affected row/counts after action completion.
   - Show a compact success/error flash or inline row message using redacted
     error text.
   - Disable or hide impossible actions based on the action matrix.
   - Disable lifecycle buttons for the affected slug while a lifecycle event is
     in flight; avoid duplicate clicks creating concurrent operations.
   - Preserve existing Open/Full token-preserving links for `:up` rows.
5. **RED/GREEN: default terminal lifecycle controls**
   - Add compact active-Citizen controls to default `/citizens/<slug>` terminal
     chrome.
   - Stop from a terminal page should stop the Citizen and redirect to
     `/citizens` with a status message; it must not leave the operator on a
     dead terminal route.
   - Restart from a terminal page should restart the Citizen and land back on
     `/citizens/<slug>` after the new pane is ready.
   - During restart, keep the operator in the tabbed terminal shell with a
     compact `restarting`/disabled-controls state until the new pane is ready,
     then re-render the terminal route. If restart fails, redirect to the index
     or show the redacted failure rather than leaving a stale xterm surface.
   - Stopping a live terminal will disconnect the Channel and xterm client as
     the pane is intentionally killed; the redirect/status message is the
     expected UX, not an error.
   - Preserve `socket_token` in any redirect/link.
   - Do not add lifecycle controls to `?full=1`; full mode stays as close as
     possible to the Phase 4/5 pure terminal surface.
6. **Browser-harness BDD**
   - Add a Phase 6 scenario that creates a temporary shell Citizen from the UI,
     sends a marker, stops it from `/citizens`, verifies the row becomes
     stopped, verifies Open/Full are disabled, verifies the terminal route no
     longer opens, starts it again, verifies terminal reconnects, sends a second
     marker, and verifies both markers are in the same transcript path.
   - Add a restart scenario for a running shell Citizen: send a pre-restart
     marker, restart from browser UI, verify terminal reconnects, send a
     post-restart marker, and verify the workspace marker file and transcript
     are preserved.
   - Add a boot/reconciliation check: stopped Citizens must not auto-start after
     managed BDD server restart; running Citizens still auto-respawn/reattach.
   - BDD cleanup must stop/remove temporary test Citizens and leave no managed
     browser tabs, test tmux sessions, or BDD server listeners behind.
   - Tag or otherwise isolate tmux-dependent integration tests so pure unit
     tests stay fast and failures clearly identify whether they require tmux.
7. **Existing E2E and JS tests**
   - Keep existing Playwright smoke unless a browser-harness scenario fully
     replaces a workflow in the same commit.
   - Add JS unit tests only if new browser JS modules are introduced. If all UI
     behavior remains LiveView-rendered with no new static JS, existing
     `npm run test:js` still runs as a regression tier.
8. **Docs and validation**
   - Update `BAB-2300`, this CHG, and the discussion tracker with real
     validation results during implementation.
   - Record that archive/delete and nested AI process TERM are deferred.
   - Keep the Phase 5 30 minute fd stability command documented, but do not
     make it a Phase 6 merge blocker unless the operator explicitly schedules
     it.

## Validation Plan

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`
- `mise exec -- mix test --cover`
- coverage must remain above the current project gates:
  `:babs_citizens >= 80%` and `:babs >= 75%`
- `npm run test:js`
- `npm run test:bdd` with browser-harness, including the Phase 6 lifecycle
  controls scenarios
- `npm run test:e2e`
- `mise exec -- mix babs.gate_a`
- `af validate --root .`
- `git diff --check`

## Local Implementation Results

Implemented locally on branch `codex/phase-6-chg` on 2026-05-06:

- `Babs.Citizens.Lifecycle.start_registered_citizen/1` starts Citizens from
  SQLite records through `Catalog.to_config/1`.
- `Babs.Citizens.Lifecycle.restart_registered_citizen/1` performs stop then
  start for the same SQLite record and aborts if stop fails.
- Same-slug lifecycle actions serialize through
  `Babs.Citizens.LifecycleRegistry`; different slugs can proceed independently.
- `StatusSnapshot` exposes display-safe lifecycle `actions`.
- `/citizens` rows render Start, Stop, and Restart controls according to the
  accepted action matrix.
- Default `/citizens/<slug>` terminal chrome renders active-Citizen lifecycle
  controls; `?full=1` remains management-chrome-free.
- Browser-harness BDD now covers browser stop/start/restart and managed server
  restart reconciliation for stopped versus running Citizens.

Local validation passed:

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test` — 127 `:babs_citizens` tests and 47 `:babs` tests
  after implementation, then refreshed through coverage after review fixes.
- `mise exec -- mix test --cover` — `:babs_citizens` 83.88%, `:babs` 82.08%;
  final coverage run executed 128 `:babs_citizens` tests and 49 `:babs` tests.
- `npm run test:js`
- `BU_CDP_URL=http://127.0.0.1:9333 npm run test:bdd` using an isolated
  browser-harness Chrome profile; all scenarios passed except the pre-existing
  optional `BABS_WORKSPACE_ROOT` scenario skipped because that env var was not
  set.
- `npm run test:e2e` — 6 Playwright tests passed.
- `mise exec -- mix babs.gate_a`
- `af validate --root .` — 112 documents checked, 0 issues.
- `git diff --check`

The deferred 30 minute fd stability run remains non-blocking and was not run.

Implementation review:

- Initial Trinity fast-review on the full working-tree diff completed with
  DeepSeek PASS and GLM timeout. DeepSeek reported no blockers and advisory
  fixes for dead assignment, restart-failure terminal UX, and missing error
  tests.
- Follow-up scoped Trinity fast-review on `apps/` completed with GLM PASS and
  DeepSeek PASS on 2026-05-06:
  `.trinity/reviews/20260506-074611-apps`.
- DeepSeek's conditional item, a missing `/citizens` Stop button click test,
  was addressed after the review. Remaining findings are advisory follow-ups:
  shared LiveView lifecycle-helper extraction, possible async lifecycle actions
  instead of blocking LiveView handlers, and minor fallback-tab cleanup.

## Acceptance Criteria

- A stopped Citizen can be started from `/citizens`, reaches an interactive
  terminal, and its SQLite row becomes `running`.
- A failed Citizen can be retried from `/citizens`; success clears `last_error`,
  and failure keeps a redacted error visible.
- An up Citizen can be stopped from the browser; Babs kills only
  `babs-<slug>`, marks SQLite `stopped`, disables Open/Full, and does not delete
  workspace/TOML/transcript.
- An up Citizen can be restarted from the browser; the workspace and transcript
  path are preserved, and the Citizen reaches an interactive terminal again.
- Stopped Citizens stay stopped across managed Babs server restart.
- Running Citizens still auto-respawn or reattach across managed Babs server
  restart.
- Pure full-window terminal mode remains management-chrome-free.

## Out of Scope

- Archive/delete Citizen actions.
- Editing Citizen config, cwd, CLI preset, role, Mayor flag, or env from the
  lifecycle controls.
- Workspace deletion or transcript deletion.
- Multi-node/federated lifecycle coordination.
- Nested AI CLI process-tree tracking and exact TERM/grace/kill escalation.
- Ticket assignment, billboard UI, or Phase 6.5 manual dogfood execution.
- The deferred 30 minute fd stability run unless the operator explicitly opts
  in during this phase.

## Review / Approval Plan

- Reviewed this CHG with Trinity fast-review using GLM and DeepSeek on
  2026-05-06.
- Review directory:
  `.trinity/reviews/20260506-070151-rules-BAB-2216-CHG-Implement-Phase-6-Stop-Start-Restart-UI.md`.
- Review mode: `COR-1602` workflow with `COR-1609` CHG rubric and `COR-1613`
  decision recording. Approval threshold: both reviewers PASS with no blockers;
  target score >= 9.0/10.
- GLM returned PASS 9.05/10 with advisories only.
- DeepSeek returned PASS 9.0/10 with advisories only.
- Non-blocking advisories folded into this revision: explicit v0.1 TERM/grace
  gap, `:reattaching` Restart omission rationale, same-slug lifecycle action
  serialization, terminal Stop/Restart UX, Restart stop-failure behavior, and
  tmux-dependent test isolation.
- During implementation, follow `BAB-1503` with TDD/BDD first, Trinity code
  review before PR, and GitHub Codex PR review loop per `COR-1615`.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-06 | Initial Phase 6 CHG draft | Codex |
| 2026-05-06 | Trinity fast-review approved CHG with GLM 9.05/10 and DeepSeek 9.0/10; fold in advisory clarifications and mark Approved | Codex |
