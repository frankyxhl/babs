# CHG-2221: Implement Phase 9-10 Assignment and State Machine

**Applies to:** BAB project
**Last updated:** 2026-05-06
**Last reviewed:** 2026-05-06
**Status:** Approved
**Date:** 2026-05-06
**Requested by:** Operator
**Priority:** High
**Change Type:** Normal

---

## What

Implement PR C from `BAB-2217` / `BAB-2218`: Phase 9 Ticket assignment plus
Phase 10 Ticket state-machine enforcement.

This change adds:

- Ticket assignment API and UI controls.
- Automatic start of a stopped Citizen before assignment injection.
- Ticket-body prompt injection into the assigned Citizen through
  `Hardline.Pane`.
- History-first assignment and injection events.
- A strict Ticket state machine for open, in_progress, pending_approval,
  closed, and cancelled.
- UI transition controls for the Phase 9-10 workflow with semantic icons.
- Temporary Mix bridge commands for assignment and transition, matching the
  existing Phase 7 temporary `mix babs.ticket.*` command surface.

This CHG intentionally does not implement the Phase 11 approval/reject feedback
modal or Phase 12 cross-Citizen comment routing UI. The state-machine backend
may support terminal transitions needed by Phase 11, but the browser approval
experience remains PR D scope.

Authority references for this CHG are `BAB-2217`, `BAB-2218`, `BAB-1111`,
`BAB-1110`, `BAB-1106`, `BAB-1002`, `BAB-1004`, and `BAB-1503`.

## Why

Phase 8 lets the operator browse the Billboard, but a Ticket still cannot move
from durable work item to active Citizen work. Phase 9-10 creates the first
usable flywheel path:

1. A Ticket exists on the Billboard with `assignees: []` and `state: open`.
2. The operator assigns it to a Citizen from `/tickets/<id>`.
3. Babs records the assignment in markdown and history.
4. Babs injects a clear prompt into the Citizen terminal.
5. The Ticket moves through legal states instead of accepting arbitrary
   frontmatter drift.

This is the minimum step that makes Tickets operational rather than only
readable.

## Impact Analysis

- **Systems affected:** `:babs_citizens` Ticket writer/API/runtime, Citizen
  lifecycle lookup/start boundary, Hardline pane injection, Mix ticket bridge
  tasks, `/tickets` and `/tickets/<id>` LiveViews, browser BDD tests.
- **Data affected:** Runtime Ticket markdown and history JSONL under the
  configured tickets root. No Ticket runtime data is committed to git.
- **SQLite affected:** Read-only Citizen lookup/status through the existing
  Catalog/Lifecycle boundary. No Ticket tables are added.
- **Runtime behavior:** Assigning a stopped Citizen auto-starts its tmux session
  and pane process before prompt injection.
- **Security/privacy:** Injected prompt text comes from the runtime Ticket body.
  Babs must not log env maps, tokens, local host paths, private URLs, or raw
  lifecycle errors into browser flashes, public PR text, or Ticket history.
  Start and injection errors must be reduced to typed/redacted reasons before
  display or persistence.
- **Rollback plan:** Revert this PR. Existing Phase 7-8 Ticket files remain
  readable because this change preserves the frontmatter schema and only adds
  history events. Any `pending_approval` files created by this slice still
  render in the existing Phase 8 Pending Approval group after rollback.

## Implementation Plan

1. RED: Add focused tests for state-machine legal and illegal transitions,
   including the explicit rejection of direct unassign from `pending_approval`.
2. GREEN: Add `Babs.Citizens.Tickets.StateMachine` with the approved matrix:
   - `open -> in_progress` by assignment
   - `open -> cancelled`
   - `in_progress -> open` via `unassigned`
   - `in_progress -> pending_approval`
   - `in_progress -> cancelled`
   - `pending_approval -> closed`
   - `pending_approval -> in_progress` via `rejected`
   - `pending_approval -> cancelled`
3. RED: Add Injector tests for known-Citizen validation, stopped-Citizen
   auto-start, start failure, missing pane after start, injection failure, and
   redacted error messages.
4. GREEN: Add an Injector boundary under `Babs.Citizens.Tickets` that:
   - validates the target Citizen slug exists,
   - auto-starts stopped or missing live panes via `Lifecycle.start_registered_citizen/2`,
   - verifies a live pane exists before injection,
   - calls `Hardline.Pane.inject/2`,
   - returns typed, redacted errors suitable for UI and CLI.
5. GREEN: Define the injected prompt template as:
   ```text
   [Babs Ticket T-YYYY-MM-DD-NNN assigned]
   Title: <title>
   State: in_progress
   Assignee: <slug>
   Path: <ticket markdown path>

   <ticket body>

   Please acknowledge the assignment and work in this terminal.
   ```
   The prompt is injected as one terminal input payload with a trailing newline.
   This intentionally omits the `bb ticket comment ...` footer from the
   `BAB-2217` example until the ADR-complete `bb` CLI exists; durable comment
   workflow is still Phase 12.
6. RED: Add Writer/API tests for assignment, unassignment, legal transitions,
   illegal transitions, write conflict preservation, start failure advisory
   history, and injection failure advisory history.
7. GREEN: Extend `Writer` and `Api` with serialized mutations:
   - `assign_ticket(ticket_id, citizen_slug, opts)`
   - `unassign_ticket(ticket_id, citizen_slug, opts)`
   - `transition_ticket(ticket_id, to_state, event, opts)`
   Each mutation rewrites markdown atomically, appends required history events,
   and preserves conflict detection.
8. GREEN: Define assignment history semantics:
   - successful assignment appends `assigned`, `state_change`,
     `injection_attempted`, and `injected`,
   - start failure appends `assignment_failed` without changing assignees/state,
   - injection failure appends `injection_failed` after the already-persisted
     assignment facts,
   - `assigned`, `state_change`, and `injection_attempted` are written before
     terminal injection.
9. GREEN: Use these new history event field schemas:
   - `assigned`: `ts`, `event`, `by`, `ticket_id`, `to` where `to` is a
     list of Citizen slugs
   - `state_change`: `ts`, `event`, `by`, `ticket_id`, `from`, `to`
   - `unassigned`: `ts`, `event`, `by`, `ticket_id`, `from`
   - `injection_attempted`: `ts`, `event`, `by`, `ticket_id`, `injected_to`
   - `injected`: `ts`, `event`, `by`, `ticket_id`, `injected_to`
   - `assignment_failed`: `ts`, `event`, `by`, `ticket_id`, `to`, `error`
   - `injection_failed`: `ts`, `event`, `by`, `ticket_id`, `injected_to`,
     `error`
   - `rejected`: `ts`, `event`, `by`, `ticket_id`, `from`, `to`
   - `cancelled`: `ts`, `event`, `by`, `ticket_id`, `from`, `to`
   Phase 11 may add an explicit `approved` event for the Approval UI; Phase
   9-10 closure may be represented by `state_change` alone.
10. GREEN: Explicitly accept the asymmetric injection-failure state: if
    assignment history and markdown are already persisted but terminal injection
    fails, the Ticket remains `in_progress` with its assignee and an
    `injection_failed` event. A future retry action may be added, but this slice
    must not erase durable assignment facts after a mirror-notification failure.
11. RED/GREEN: Add temporary Mix bridge commands:
   - `mix babs.ticket.assign T-... clare`
   - `mix babs.ticket.transition T-... pending_approval`
   - `mix babs.ticket.unassign T-... clare`
   These commands are a documented temporary deviation from the `bb ticket`
   UDS CLI in `BAB-1111` and `BAB-2217`; the internal API shape must stay
   compatible with the future `bb` commands.
12. RED: Add LiveView tests for assignment controls, unassignment controls,
    legal controls, success flashes, icon presence, and invalid transition error
    handling.
13. GREEN: Extend `/tickets/<id>`:
   - show assignment controls for known Citizens when a Ticket is on the
     Billboard,
   - show unassign controls only for `in_progress` Tickets with assignees,
   - unassigning the last assignee moves the Ticket back to the Billboard
     (`assignees: []`, `state: open`),
   - require a confirmation for unassign and cancel actions,
   - never show direct unassign controls for `pending_approval`,
   - show legal Phase 9-10 controls only,
   - include icons such as users, user-plus, route, check, undo, ban, and
     refresh,
   - preserve socket-token navigation.
14. RED/GREEN: Add browser-harness BDD scenarios for:
   - assigning a Billboard Ticket to a Citizen,
   - automatic start path when the Citizen is stopped when practical in the
     isolated browser environment,
   - walking `open -> in_progress -> pending_approval`.
15. REFACTOR: Extract shared Ticket mutation helpers only if the Writer code
    becomes difficult to read after assignment and transition support.
16. REFACTOR: Keep Phase 7 conflict detection as the crash-safety baseline for
    coupled markdown/history writes. Startup reconciliation for partial
    multi-event writes remains deferred unless tests expose a real inconsistency.
17. GREEN: Update docs with implementation facts, validation results, review
    results, and current Phase 9-10 status.

## Validation Plan

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`
- `mise exec -- mix test --cover --export-coverage phase9_10`
- `mise exec -- mix cmd mix test.coverage`
- `npm run test:js`
- `npm run test:bdd`
- `npm run test:e2e`
- `mise exec -- mix babs.gate_a`
- `af validate --root .`
- `git diff --check`
- Privacy scan for public PR text and changed files.

Optional or conditional validation:

- Multi-CLI assignment smoke against Clare, Dylan, Flora, and Elena when their
  credentials and local CLIs are available. Missing credentials should skip the
  smoke rather than fail the slice.

Umbrella coverage is run as export plus per-app coverage summary so each
umbrella child uses its own configured threshold and ignore list.

## Review Plan

- Plan review: Trinity fast-review using GLM and DeepSeek.
- Implementation review: Trinity fast-review using GLM and DeepSeek on the
  implementation diff.
- PR review: GitHub Codex review loop per `COR-1615`, capped at five rounds by
  `BAB-2218`.

## Review Results

- R1 `.trinity/reviews/20260506-131442-rules-BAB-2221-CHG-Implement-Phase-9-10-Assignment-and-State-Machine.md`:
  GLM PASS 9.0/10; DeepSeek FIX 7.95/10. Fixed DeepSeek blockers and advisories
  by adding authority references, RED/GREEN/REFACTOR labels, security/privacy,
  prompt template, injection failure asymmetry, history event schemas, and
  unassign UI rules.
- R2 `.trinity/reviews/20260506-132421-rules-BAB-2221-CHG-Implement-Phase-9-10-Assignment-and-State-Machine.md`:
  GLM PASS 9.10/10 and DeepSeek PASS 9.2/10 with advisories only. Folded low
  cost advisories into this CHG: prompt-template authority note, list-form
  `assigned.to`, Phase 11 `approved` extension point, title formatting, Mix
  bridge deviation, function argument names, mandatory auto-start wording,
  last-assignee unassign semantics, and crash-reconciliation scope.
- Implementation R1 `.trinity/reviews/20260506-135803-BAB-2221-phase-9-10-implementation`:
  GLM PASS and DeepSeek PASS with non-blocking advisories. Addressed the
  low-cost implementation advisories by adding invalid Citizen slug guards,
  redacted pane lookup errors, friendlier persisted error text, a resilient
  assign Mix task success fallback, and concurrent assignment coverage.
- Implementation R2 `.trinity/reviews/20260506-141039-BAB-2221-phase-9-10-implementation-r2`:
  GLM PASS and DeepSeek PASS. Remaining notes are non-blocking polish and do
  not affect Phase 9-10 acceptance.

## Implementation Results

Local implementation on `codex/m3-phase-9-10-assignment-state` adds:

- `Babs.Citizens.Tickets.StateMachine` for legal Phase 9-10 transitions.
- `Babs.Citizens.Tickets.Injector` for known-Citizen validation,
  stopped-Citizen auto-start, pane verification, prompt construction, and
  redacted terminal injection errors.
- Serialized `assign_ticket/3`, `unassign_ticket/3`, and
  `transition_ticket/4` APIs backed by the existing per-Ticket writer.
- History-first assignment semantics: `assigned`, `state_change`, and
  `injection_attempted` are persisted before terminal injection; `injected`,
  `assignment_failed`, or `injection_failed` records the delivery result.
- Temporary Mix bridge tasks:
  `mix babs.ticket.assign`, `mix babs.ticket.transition`, and
  `mix babs.ticket.unassign`.
- `/tickets/<id>` action controls with icons for assign, pending approval,
  unassign, and cancel; direct unassign is hidden and rejected once a Ticket is
  in `pending_approval`.
- Browser-harness BDD coverage for assignment auto-start, prompt injection, and
  `open -> in_progress -> pending_approval`.

Local validation passed on 2026-05-06:

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`: `:babs_citizens` 181 tests, `:babs` 59 tests
- `mise exec -- mix test --cover --export-coverage phase9_10`
- `mise exec -- mix cmd mix test.coverage`: `:babs_citizens` 82.36%,
  `:babs` 84.36%
- `npm run test:js`: 8 tests
- `npm run test:bdd`: all required scenarios passed; optional workspace-root
  and stopped seed-CLI smokes skipped
- `npm run test:e2e`: 4 passed, 2 optional seed CLI checks skipped
- `mise exec -- mix babs.gate_a`
- `af validate --root .`: 117 documents, 0 issues
- `git diff --check`
- Privacy scan of changed files found no private Tailscale IPs, host-local
  absolute paths, or credential values.

## Acceptance

- A valid open Billboard Ticket can be assigned to a known Citizen.
- A stopped assigned Citizen is auto-started before injection.
- The assigned Citizen receives the Ticket prompt in its pane.
- Assignment and injection facts are persisted in history before terminal
  injection.
- Injection failure leaves an explicit `injection_failed` advisory event while
  preserving durable assignment facts.
- Illegal state transitions return typed errors and do not rewrite the Ticket.
- Direct unassign from `pending_approval` is rejected and not shown in the UI.
- UI shows only controls owned by Phase 9-10 and only when legal for the current
  Ticket state.
- All required validation passes before PR.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-06 | Initial version | — |
| 2026-05-06 | Draft Phase 9-10 PR C implementation contract | Codex |
| 2026-05-06 | Fold in Trinity R1 findings on authority references, RED/GREEN labels, prompt template, history schemas, privacy, and unassign rules | Codex |
| 2026-05-06 | Mark approved after Trinity R2 GLM and DeepSeek PASS; fold in advisory clarifications | Codex |
| 2026-05-06 | Implement Phase 9-10 assignment/state-machine slice with unit, LiveView, BDD, E2E, Gate A, coverage, Alfred validation, and privacy scan passing locally | Codex |
| 2026-05-06 | Address Trinity implementation advisories with invalid-slug guards, redacted pane lookup errors, friendlier history error text, resilient assign Mix output, and concurrent assignment coverage | Codex |
