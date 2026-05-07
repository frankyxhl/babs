# CHG-2236: Implement Phase 13a.4 Direct Backend UI Controls

**Applies to:** BAB project
**Last updated:** 2026-05-07
**Last reviewed:** 2026-05-07
**Status:** Approved
**Date:** 2026-05-07
**Requested by:** Operator
**Priority:** High
**Change Type:** Normal

---

## What

Implement a focused Phase 13a.4 follow-up for the direct CLI backend that was
added in `BAB-2235`.

Scope:

- Add a visible Ticket backend control to the New Citizen UI so the operator can
  create a Citizen as:
  - `hardline` - always-on tmux terminal, current default.
  - `direct_cli` - no default tmux start; Ticket assignment starts a supervised
    direct CLI turn.
- Persist the selected backend through `Spawner`, TOML, and SQLite.
- When a new Citizen is created with `direct_cli`, create the durable Citizen
  and workspace but leave the Hardline lifecycle stopped instead of launching
  tmux immediately.
- Redirect direct-only Citizen creation back to the Citizens index instead of a
  terminal page.
- Render the configured Ticket backend in the Citizens index and Ticket assign
  buttons so the operator can see which delivery path assignment will use.
- Make stopped-assign semantics explicit in tests and operator-facing UI:
  - `hardline`: assignment starts/uses Hardline and injects into tmux.
  - `direct_cli`: assignment does not start tmux; it starts a direct provider
    turn and stores replies in Ticket chat.
- `lazy_tmux`: recognized by config but not offered as a creation option in
    this slice. `Spawner` creation accepts only `hardline` and `direct_cli` in
    this CHG; `lazy_tmux` remains valid for imported/preexisting config rows but
    is not creatable from the browser until the full lazy-tmux implementation.

Out of scope:

- Full `lazy_tmux` resume/open-terminal behavior.
- Editing an existing Citizen's backend after creation.
- Live quota-consuming Claude/Codex/Copilot validation.
- Reworking the whole New Citizen page visual system.

Deferred gates approved by the operator on 2026-05-07: full `lazy_tmux`,
backend editing for existing Citizens, live provider validation, and broader UI
visual rework.

## Why

Phase 13a.3 made direct CLI provider sessions work, but the browser still hides
that capability. Operators currently need manual SQLite/TOML edits to opt into
`direct_cli`, and UI-created Citizens always start a tmux Hardline even when the
desired workflow is Ticket-only direct execution.

The assignment behavior also needs to be visible and deterministic: a stopped
Citizen should not surprise the operator by starting a terminal when the Citizen
is configured for direct CLI turns.

## Impact Analysis

- **Systems affected:** New Citizen LiveView, Citizen Spawner, Catalog insert
  path, Citizen status snapshots/index UI, Ticket detail assignment UI,
  browser-harness BDD, and focused Elixir tests.
- **Data:** no migration. Existing `ticket_backend` and `status` columns are
  reused.
- **Runtime:** direct-only creation intentionally avoids starting the Hardline
  lifecycle. Existing lifecycle Start/Open controls remain available if the
  operator later wants an interactive terminal.
- **Consistency risk:** New Citizen creation spans TOML, workspace creation, and
  SQLite. Existing partial-failure safeguards must stay intact: validation runs
  before side effects; SQLite insert failure must not start lifecycle; direct
  creation must not introduce a hidden tmux start in any failure path.
- **Privacy:** no prompts, provider stdout, private IPs, host paths, or tokens
  are added to public docs or review artifacts.
- **Rollback plan:** revert the implementation PR as one review unit, even if it
  contains multiple RED/GREEN/REFACTOR commits. Existing Citizen rows remain
  valid because `ticket_backend` already existed before this slice. After
  revert, `direct_cli` Citizens keep the column value, but the browser creation
  selector and direct-only creation guard disappear; operators can still repair
  behavior by editing TOML/SQLite back to `hardline` or by moving forward to the
  next direct-backend UI slice. A Citizen created as `direct_cli` immediately
  before rollback is data-safe: the row and TOML remain valid, and no tmux
  session is owned by Babs unless the operator explicitly started one.

## Implementation Plan

1. **Plan review**
   - Fill this CHG before code.
   - Run Trinity `fast-review` against the plan and fold blockers.

2. **RED tests**
   - Add Spawner tests for selected backend persistence and direct-only creation
     avoiding lifecycle start, including
     `creates_direct_cli_citizen_without_starting_lifecycle`,
     `persists_backend_choice_to_toml_and_sqlite`, and
     `rejects_lazy_tmux_from_browser_creation`.
   - Add NewCitizenLive tests for backend selector rendering, submission, and
     redirect behavior, including `renders_ticket_backend_selector` and
     `redirects_direct_cli_creation_to_citizens_index`.
   - Add StatusSnapshot/CitizensLive tests that expose backend labels without
     leaking env values, including `snapshot_exposes_ticket_backend_label` and
     `citizens_index_shows_ticket_backend`.
   - Add TicketLive test coverage that assign buttons show backend/start
     semantics, including `assign_button_labels_hardline_start_behavior` and
     `assign_button_labels_direct_cli_turn_behavior`.
   - Add browser-harness BDD for creating a deterministic direct CLI test
     Citizen from the UI and assigning a Ticket without starting tmux:
     `Scenario: direct CLI backend UI creation and assignment`.

3. **Implementation**
   - Add backend choices and validation to `Babs.Citizens.Spawner`.
   - Allow `Catalog.insert_new/2` to create a UI Citizen with explicit initial
     status while defaulting existing callers and one-argument injected insert
     test doubles to `running`.
   - Update NewCitizenLive to render icon-labeled backend choices and redirect
     direct-only creation to Citizens index.
   - Update `StatusSnapshot` to expose a safe backend label for UI rendering.
   - Update Citizens index and Ticket detail assignment UI with backend labels
     and stopped-assign hints.

4. **REFACTOR**
   - Extract shared backend label/description helpers when the same copy or
     display mapping is needed by NewCitizenLive, CitizensLive, and TicketLive.
   - Keep provider execution logic in `:babs_citizens`; avoid duplicating
     backend routing rules in browser-only code.

5. **Validation**
   - Run focused Elixir tests for Spawner, NewCitizenLive, CitizensLive,
     TicketLive, and relevant direct Ticket writer behavior.
   - Run focused browser-harness BDD for the new direct UI flow.
   - Run applicable formatting, JS/E2E, document, whitespace, and privacy gates
     before PR.

## Acceptance Criteria

- New Citizen UI has a visible, icon-labeled Ticket backend control.
- Backend defaults to `hardline`.
- Submitting with `direct_cli` persists TOML and SQLite `ticket_backend =
  "direct_cli"` and does not launch tmux by default.
- Direct-only creation redirects to `/citizens`, where the row shows `stopped`
  and `direct_cli`.
- Hardline creation preserves existing behavior and redirects to the terminal.
- Ticket detail assign buttons show which backend will be used and make
  stopped behavior clear enough for manual dogfood.
- Assigning a Ticket to a stopped deterministic `direct_cli` test Citizen starts
  a direct turn and captures the reply without starting a tmux session in BDD.
- Existing Hardline assignment auto-start behavior remains covered and green.

## Validation Plan

Planned commands:

```bash
mise exec -- mix test \
  apps/babs_citizens/test/babs_citizens/ticket_backend_test.exs \
  apps/babs_citizens/test/babs_citizens/spawner_test.exs \
  apps/babs_citizens/test/babs_citizens/status_snapshot_test.exs \
  apps/babs/test/babs_web/live/new_citizen_live_test.exs \
  apps/babs/test/babs_web/live/citizens_live_test.exs \
  apps/babs/test/babs_web/live/tickets_live_test.exs
BU_CDP_URL=http://127.0.0.1:9333 \
  BABS_BDD_SCENARIO="direct cli backend UI" \
  BABS_HTTP_PORT=4108 \
  BABS_BROWSER_BASE_URL=http://127.0.0.1:4108 \
  npm run test:bdd
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
mise exec -- mix test --cover --export-coverage phase13a4
mise exec -- mix cmd mix test.coverage
npm run test:js
npm run test:e2e
af validate --root <repo-root>
git diff --check
```

Final results:

- Focused Elixir RED/GREEN suite:
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/ticket_backend_test.exs`:
    2 tests, 0 failures.
  - Focused Spawner/StatusSnapshot/NewCitizenLive/CitizensLive/TicketsLive
    suite: 60 tests, 0 failures.
  - Focused P2 regression suite after GitHub Codex review R1: 46 tests,
    0 failures.
- `python3 -m py_compile test/browser/bdd/babs_steps.py
  test/browser/bdd/run.py`: passed.
- Focused browser-harness BDD with isolated Chrome CDP on local port 9333:
  `direct cli backend UI creation and assignment` passed.
- `mise exec -- mix format --check-formatted`: passed.
- `mise exec -- mix compile --warnings-as-errors`: passed.
- `mise exec -- mix test`: 397 tests, 0 failures.
- Coverage export/report:
  - `mise exec -- mix test --cover --export-coverage phase13a4`: 397 tests,
    0 failures.
  - `mise exec -- mix cmd mix test.coverage`: passed with `:babs_citizens`
    82.27% total and `:babs` 88.50% total.
- `npm run test:js`: 15 tests, 0 failures.
- `npm run test:e2e`: 13 tests total, 11 passed, 2 skipped.
- `af validate --root <repo-root>`: 144 documents checked, 0 issues found.
- `git diff --check`: passed.
- Diff privacy scan for the operator's private network address, local checkout
  path, GitHub tokens, and OpenAI-style API keys: no matches in the current
  diff.

## Review Results

- Plan review R1: GLM PASS; DeepSeek FIX 8.45/10 with advisory-only document
  findings. Folded References, deferred-gates, rollback, terminology, and title
  consistency fixes before implementation.
- Plan review R2: GLM PASS 9.2/10; DeepSeek FIX 8.9/10 with advisory-only TDD
  specificity findings. Folded concrete RED scenarios, REFACTOR step,
  lazy-tmux creation boundary, partial-failure risk, StatusSnapshot scope, and
  rollback-unit clarifications before implementation.
- Plan review R3: GLM PASS 9.3/10; DeepSeek PASS 9.2/10. Remaining findings
  are advisory implementation/detail improvements and can be handled during the
  RED/GREEN/REFACTOR pass.
- Implementation review R1: GLM PASS; DeepSeek PASS. No blocking issues.
  Advisory follow-ups only: optional stricter insert arity handling, direct unit
  assertions for creation descriptions / `Catalog.insert_new/2`, and optional
  traceability polish.
- GitHub Codex PR review R1 on commit `396418dfa7`: two P2 findings fixed:
  reject `direct_cli` browser creation for unsupported CLI presets, and avoid
  advertising unimplemented lazy-tmux assignment behavior.

## References

- `BAB-2232` Phase 13a Multi-Turn Ticket Sessions and Direct CLI Backend PRP
- `BAB-2235` Phase 13a.3 Direct CLI Provider Sessions CHG
- `BAB-1002` Naming and Vocabulary
- `BAB-1107` SQLite for Durable Citizen Registry
- `BAB-1112` Multi-AI-CLI Citizen Configuration
- `BAB-1503` Babs Phase Delivery Workflow adapter
- `BAB-2300` Build Roadmap
- GitHub issue #28: Phase 13a.4 Direct CLI backend controls tracking issue

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-07 | Initial version | — |
| 2026-05-07 | Fill Phase 13a.4 contract for direct backend UI controls and stopped-assign semantics | Codex |
| 2026-05-07 | Fold Trinity R1 plan-review advisories for references, deferred gates, rollback, terminology, and title consistency | Codex |
| 2026-05-07 | Fold Trinity R2 plan-review advisories for concrete RED tests, REFACTOR step, lazy-tmux creation boundary, partial-failure risk, StatusSnapshot scope, rollback unit, and ADR references | Codex |
| 2026-05-07 | Record Trinity R3 plan-review PASS from GLM and DeepSeek | Codex |
| 2026-05-07 | Record implementation validation results and GitHub tracking issue #28 | Codex |
| 2026-05-08 | Record Trinity implementation review PASS from GLM and DeepSeek | Codex |
| 2026-05-08 | Record GitHub Codex R1 P2 fixes and refreshed validation counts | Codex |
