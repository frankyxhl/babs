# CHG-2207: Phase 1a Flywheel Hardening

**Applies to:** BAB project
**Last updated:** 2026-05-05
**Last reviewed:** 2026-05-05
**Status:** Completed
**Related:** `BAB-2201`, `BAB-2203`, `BAB-2204`, `BAB-2206` (Phase 0c JS extraction precedent), `BAB-1004`, `BAB-1106`, `BAB-1110`

---

## What

Add a short Phase 1a after Phase 1 flywheel ignition and before continuing Phase
2 product work.

Phase 1 proved the minimum flywheel: Babs can host Citizens in browser terminals,
survive reload/restart, and let Clare implement/commit the first Phase 2 slice.
Phase 1a hardens that foundation by raising test coverage, extracting browser
terminal JavaScript into testable modules, and moving the proven Hardline
full-window terminal user experience from `spikes/hardline/` into the main Babs
terminal page.

---

## Why

The Phase 1 acceptance gates passed, but the coverage baseline is too low for a
system that will now be extended by browser-hosted AI Citizens:

```text
mise exec -- mix test --cover

:babs_citizens   44.48%
:babs            18.37%
```

The low coverage is not because the Phase 1 gates were fake. It is because the
current tests focus on critical workflows and leave many modules partially or
indirectly tested. Also, the Phase 1 browser terminal still has inline
JavaScript and a simpler visual surface than the Phase 0a/0b Hardline manager
experience.

Doing this hardening now prevents two forms of early drift:

- **Quality drift:** future Citizens build on code without clear coverage gates.
- **UX drift:** the proven `:4010` hardline experience and the main Babs
  terminal evolve separately.

---

## Impact

Expected impact:

- no change to the Phase 1 flywheel acceptance result
- no ticket/billboard automation yet
- no full `/citizens` manager console yet
- terminal page JavaScript moves from `TerminalLive` inline script into static
  modules under `apps/babs/priv/static/js/`
- browser logic gains JavaScript unit tests and browser-harness BDD coverage
- Elixir modules gain focused tests and explicit coverage thresholds
- terminal visual/interaction behavior aligns with the Phase 0b full-window
  hardline mode where it makes sense for `/citizens/<slug>`
- Elena is a Phase 1a experimental GitHub Copilot CLI coverage check, not a
  Phase 1 flywheel acceptance dependency

Risk:

- adding coverage gates can encourage low-value tests if the target is treated
  as a number rather than a behavior contract
- browser-harness BDD tests may become flaky or intrusive if they share live
  operator tmux sessions or the operator's active browser tab
- extracting inline terminal JavaScript can break browser connection/resize
  behavior if not covered by BDD characterization first
- copying the entire Phase 0a manager UI too early would conflict with roadmap
  Phases 4-6, where spawn/list/stop/start UI belongs

---

## Plan

1. Keep Phase 1a scoped to hardening and terminal UX parity.
2. Preserve Phase 1's accepted gates and commits; do not rewrite Phase 1 as
   incomplete.
3. Establish the coverage RED/GREEN sequence before adding coverage tests:
   - record the current `mix test --cover` coverage gap as the RED baseline
   - explicitly note that Mix currently reports coverage percentages without a
     configured project threshold; Phase 1a replaces passive reporting with
     staged, project-owned thresholds that can pass with behavior-focused tests
   - do not require CI or local gate enforcement to pass during the middle of
     the refactor while thresholds are intentionally unmet
   - land explicit threshold configuration only after the new tests are in place
     and prove the configured targets pass
4. Add explicit coverage configuration for both umbrella apps.
   - Prefer Mix's built-in `test_coverage` configuration in each app, with
     `mix test --cover` proving the threshold fails before the new tests and
     passes after them. If built-in per-app thresholding is not sufficient, add
     a small project-local coverage check rather than relying on an unverified
     percentage in prose.
   - Treat named core-module coverage as a human-enforced PR review checklist
     unless a project-local checker explicitly supports that granularity; Mix's
     built-in threshold is aggregate only.
5. Set initial coverage gates high enough to matter:
   - `:babs_citizens`: minimum 80% total line coverage, with core modules each
     either covered or explicitly justified:
     `Babs.Citizens.Citizen.Config`,
     `Babs.Citizens.CitizenConfig`,
     `Babs.Citizens.Lifecycle`,
     `Babs.Citizens.Runner`,
     `Babs.Citizens.ReattachScanner`,
     `Babs.Citizens.Hardline.Pane`, and
     `Babs.Citizens.Hardline.Transcript`.
   - `:babs`: minimum 70% total line coverage after excluding generated or
     trivial Phoenix boilerplate only where justified. If exclusions are needed,
     use the project-local coverage check path from Plan item 4 with an explicit
     exclusion list, for example `BabsWeb.Router`, `BabsWeb.Endpoint`, and
     `Babs.Application`.
   - new pure browser JavaScript modules: covered by Node unit tests.
   - Rationale: these targets materially raise the current baseline
     (`:babs_citizens` from 44.48% to 80%, `:babs` from 18.37% to 70%) while
     keeping the first hardening pass focused on behavioral seams rather than
     generated Phoenix boilerplate.
6. Add targeted Elixir tests before implementation changes:
   - `TerminalController` route behavior: `/` redirects to `/citizens/sentinel`,
     missing citizens return `text/plain` 404 with `citizen not found: <slug>`
   - `TerminalLive` render contract and required DOM hooks
   - `DevReloader` debounce/restart decision paths
   - `ReattachScanner` config-error and start/reattach edge cases
   - `Runner` command construction and safe tmux lifecycle edges
   - refactor `Mix.Tasks.Babs.GateA` into a thin task wrapper over a testable
     validator module so the sentinel reload state machine can be unit-tested
     without shelling through the full task every time
   - add a regression test preserving the existing `Hardline.Pane` hot-reload
     compatibility behavior where pre-transcript state without `:transcript_io`
     does not crash `write_transcript/2`
7. Extract browser terminal logic from `TerminalLive` into static modules:
   - before extraction starts, add and run browser-harness BDD characterization
     coverage for the current inline browser behavior so connect/type/reconnect/resize
     behavior is green before the refactor
   - `terminal_core.js` for pure input filtering, URL/slug helpers, status
     labels, and resize payload shaping
   - `terminal_client.js` for Phoenix Channel/xterm/FitAddon wiring
   - a small boot module loaded by `TerminalLive`
8. Add JavaScript unit tests using Node's built-in test runner where possible:
   - add a root `package.json` script: `test:js`
   - place terminal browser unit tests under `test/browser/`, for example
     `test/browser/terminal_core.test.mjs`
   - keep the root package as the owner of main Babs browser tests; use
     `spikes/hardline/package.json` only for the Phase 0 spike
   - add `test:js` alongside the browser scenario command rather than replacing
     browser-level tests
9. Add browser-harness BDD scenario tests for:
   - Given sentinel is configured, when the operator opens `/citizens/sentinel`,
     then the terminal connects and reports connected status
   - Given sentinel is connected, when the operator types
     `printf 'BABS_BDD_INPUT_OK\n'`, then the marker reaches tmux exactly once
   - Given sentinel is connected, when `:babs_citizens` reloads, then the same
     browser terminal reconnects and can still send/receive bytes
   - Given sentinel is connected, when `:babs` reloads, then the browser
     reconnects and input still works
   - Given a terminal page is open, when the viewport is resized, then xterm
     keeps stable full-window rows/cols and compact status chrome
   - Given Clare/Dylan/Elena are configured, when their CLIs are available, then
     their terminal pages can connect; skip with an explicit reason when CLI or
     auth state is unavailable
   - Given a missing citizen slug, when the operator opens `/citizens/<missing>`,
     then the response is 404 with clear `citizen not found` text
   - place browser-harness BDD helpers under `test/browser/bdd/`, for example
     `test/browser/bdd/run.py` and `test/browser/bdd/babs_steps.py`
   - add a root `package.json` script `test:bdd` that executes the BDD runner
     through `browser-harness`
   - use browser-harness `new_tab(...)` rather than navigating the operator's
     active tab, and close or mark test-created tabs where practical
   - support local attached-browser runs first, and document the isolated Chrome
     remote-debugging mode needed for unattended/CI-style runs
   - use isolated tmux session prefixes and cleanup for any BDD-created
     sessions, following the `BAB-2206` Phase 0c pattern
   - never stop, clean up, or destroy persistent seed sessions
     `babs-sentinel`, `babs-clare`, `babs-dylan`, or `babs-elena`; deterministic
     input scenarios may send bounded marker commands to `babs-sentinel`
   - use synthetic slugs such as `babs-bdd-*` for temporary sessions or missing
     citizen checks
   - add BDD setup/teardown cleanup for any `babs-bdd-*` tmux
     sessions left behind by failed runs
10. Move the Phase 0b full-window terminal UX into `/citizens/<slug>`:
   - follow the implementation precedent in
     `spikes/hardline/priv/static/js/hardline_manager.js` and the Phase 0b
     docs `BAB-2203` / `BAB-2204`
   - black xterm surface
   - stable full-viewport layout
   - status dot or compact connection status
   - size status
   - restrained chrome matching `BAB-1004`, using its palette where practical
     and documenting any deliberate deviations
   - expect the xterm background to move from the current Phase 1 `#101014`
     terminal surface to `BAB-1004`'s pure black `#000000`
11. Do not move Phase 0a manager lifecycle controls yet:
    - create/list/switch/stop/start UI remains roadmap Phases 4-6 unless a
      separate PRP changes that sequence.
12. Replace the current temporary hardcoded dev bind address with an explicit
    environment switch in `config/dev.exs`:
    - current worktree state is `ip: {0, 0, 0, 0}` for ad hoc Tailscale testing
    - Phase 1a changes the default back to local-only `127.0.0.1`
    - `config/dev.exs` reads `BABS_HTTP_IP` via `System.get_env/1` at compile
      time and parses dotted IPv4 values such as `127.0.0.1` or `0.0.0.0` into
      endpoint IP tuples
    - changing `BABS_HTTP_IP` between modes requires recompilation because this
      lives in compile-time dev config
    - invalid, empty, or non-IPv4 values fail fast with a clear dev config error
    - Tailscale/manual remote testing uses `BABS_HTTP_IP=0.0.0.0`
13. Update docs:
    - record Phase 1a in `BAB-2300` under Bootstrap, between Phase 1 and
      Phase 2
    - move the "last manual phase" tag from the Phase 1 entry to the new Phase
      1a entry in `BAB-2300`
    - keep `BAB-2207` as the combined Phase 1a proposal/change document unless
      a separate PRP is requested before implementation
    - record Elena as post-Phase-1 experimental CLI coverage
    - document the test-tier map and commands
14. After implementation is complete, run validation:
    - `mise exec -- mix format --check-formatted`
    - `mise exec -- mix compile --warnings-as-errors`
    - `mise exec -- mix test`
    - `mise exec -- mix test --cover`
    - `npm run test:js` for browser unit tests
    - `npm run test:bdd` for browser-harness BDD scenario tests
    - `npm run test:e2e` for the preserved Playwright smoke suite
    - `mise exec -- mix babs.gate_a`
    - `af validate --root /Users/frank/Projects/babs-phase1-impl`

---

## Test Tier Map

| Command | Tier | Purpose |
|---------|------|---------|
| `mise exec -- mix test` | Elixir unit/integration | Fast behavioral coverage for OTP lifecycle, channels, config, Gate A validator, and terminal render contracts |
| `mise exec -- mix test --cover` | Elixir coverage gate | Enforces `:babs_citizens` 80% and `:babs` 70% thresholds with justified generated-boilerplate exclusions |
| `npm run test:js` | Browser JavaScript unit | Tests pure terminal browser helpers extracted from `TerminalLive` |
| `npm run test:bdd` | Browser-harness BDD | Drives the attached browser through terminal connect/type/reload/resize/missing-citizen scenarios |
| `npm run test:e2e` | Legacy Playwright smoke | Preserves existing browser smoke coverage while browser-harness becomes the primary BDD tier |
| `mise exec -- mix babs.gate_a` | Phase 1 flywheel gate | Verifies sentinel survives `:babs_citizens` restart with tmux session and pane PID stable |
| `af validate --root /Users/frank/Projects/babs-phase1-impl` | Documentation gate | Validates BAB/COR document structure and references |

---

## Acceptance

Phase 1a is complete when all of the following hold:

- Phase 1 remains accepted and its flywheel closeout is not weakened.
- `mix test --cover` passes with explicit coverage thresholds.
- New/changed browser terminal JavaScript is covered by unit tests.
- Browser-harness BDD scenario tests cover the main browser terminal workflows.
- `/citizens/<slug>` terminal UX matches the useful parts of the `:4010`
  full-window hardline experience.
- `config/dev.exs` defaults the dev endpoint to `127.0.0.1`, and
  `BABS_HTTP_IP=0.0.0.0 mise exec -- mix phx.server` supports Tailscale testing.
- Billboard/ticket automation remains explicitly deferred to Phase 6.5/7+.
- Validation commands in the Plan section pass.

## Experimental Validation

Elena is a manual Phase 1a experimental validation, not an automated acceptance
gate. Before Phase 1a closeout, the operator should launch Elena with
`gh copilot` when GitHub Copilot CLI is installed and authenticated, record the
result in this CHG, and explicitly mark the check skipped if local CLI/auth
state is unavailable.

Recorded result: Elena connected in the seed-citizen browser scenario when the
`gh` CLI was available. The manual Copilot CLI probe returned
`BABS_ELENA_COPILOT_OK`; this remains experimental coverage, not a Phase 1
flywheel gate.

---

## Out Of Scope

- Formal ticket/billboard implementation
- `bb` CLI
- automatic citizen-to-citizen comments
- `/citizens/new` spawn UI
- full citizen manager list/switch/stop/start UI
- SQLite-backed citizens table
- replacing the Phase 0 official long-run validation

---

## Result

Implemented on 2026-05-05.

Validation passed:

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`: `:babs_citizens` 37 tests, `:babs` 16 tests
- `mise exec -- mix test --cover`: `:babs_citizens` 81.38% against 80%;
  `:babs` 75.64% against 70%
- `npm run test:js`: 5 Node unit tests
- `npm run test:bdd`: 7 browser-harness BDD scenarios
- `npm run test:e2e`: 6 preserved Playwright smoke tests
- `mise exec -- mix babs.gate_a`: Gate A PASS
- `BABS_HTTP_IP=0.0.0.0 mise exec -- mix eval ...`: endpoint IP parsed as
  `{0, 0, 0, 0}`
- `af validate --root /Users/frank/Projects/babs-phase1-impl`: 95 documents,
  0 issues

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-05 | Initial proposed CHG for Phase 1a flywheel hardening: coverage gates, terminal JS testability, and Hardline UX parity | Codex |
| 2026-05-05 | Trinity fast-review follow-up: clarify current `0.0.0.0` bind state, specify `BABS_HTTP_IP` implementation in `config/dev.exs`, justify coverage thresholds, clarify Elena as a Phase 1a experimental check, and reference the fully qualified Transcript module | Codex |
| 2026-05-05 | Trinity fast-review R2 follow-up: specify coverage enforcement mechanism, compile-time dev env parsing, `npm run test:js`, `BAB-2300` insertion point, and E2E tmux isolation cleanup | Codex |
| 2026-05-05 | Trinity GLM follow-up: add explicit coverage RED/GREEN sequencing, root JS test ownership, persistent seed-session E2E protections, GateA validator refactor target, Phase 0b UX file references, and hot-reload regression coverage note | Codex |
| 2026-05-05 | Trinity DeepSeek follow-up: clarify replacement of Mix's 90% default coverage threshold, use fully qualified core module names, preserve existing `test:e2e`, define invalid `BABS_HTTP_IP` behavior, and require `BAB-2300` last-manual-phase wording update | Codex |
| 2026-05-05 | Trinity DeepSeek PASS follow-up: correct Mix coverage-threshold wording, clarify compile-time `BABS_HTTP_IP` parsing, normalize Plan indentation, and specify moving the `BAB-2300` last-manual-phase tag | Codex |
| 2026-05-05 | Trinity fast-review PASS follow-up: clarify coverage gap wording, human-enforced per-module coverage review, E2E-before-extraction sequencing, `:babs` coverage exclusion mechanics, Elena manual validation, and full-window palette transition | Codex |
| 2026-05-05 | Add browser-harness BDD test tier: replace Playwright-specific BDD wording with explicit Given/When/Then terminal scenarios, `test:bdd`, attached-browser safety rules, and isolated-run documentation requirement | Codex |
| 2026-05-05 | Begin Phase 1a implementation; add test-tier map and mark CHG In Progress | Codex |
| 2026-05-05 | Complete Phase 1a implementation: coverage gates, browser JS extraction, browser-harness BDD, terminal UX parity, `BABS_HTTP_IP`, and validation results | Codex |
