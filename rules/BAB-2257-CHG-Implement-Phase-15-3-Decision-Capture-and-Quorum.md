# CHG-2257: Implement Phase 15.3 Decision Capture and Quorum

**Applies to:** BAB project
**Last updated:** 2026-05-08
**Last reviewed:** 2026-05-08
**Status:** Approved
**Date:** 2026-05-08
**Requested by:** Operator
**Priority:** High
**Change Type:** Feature

---

## What

Implement **Phase 15.3: decision capture and `all_pass` quorum** from
`BAB-2243`.

This is the third small PR slice for Phase 15 Inspector Council
auto-approval. Phase 15.1 added inspection policy and event constructors.
Phase 15.2 added inspector selection and redacted prompt assembly. Phase 15.3
will parse inspector replies, persist decisions/failures, and reduce those
decisions into conservative Ticket state transitions.

Scope:

- Add an inspection decision parser for fenced JSON or whole-body JSON replies.
- Accept only `approve`, `reject`, and `needs_changes` decisions.
- Require a non-empty `summary`; normalize `findings` to a list of maps.
- Treat parse failure, unknown decisions, invalid findings, or missing summary
  as `inspection_failed` with a redacted `unparseable` reason.
- Match inspector replies to the active inspection using `inspection_id`,
  inspector slug, and the `turn_id`/`attempt_id` from
  `inspection_prompt_delivered`.
- Append `inspection_decision` or `inspection_failed` through the per-ticket
  Writer.
- Implement `all_pass` quorum:
  - all selected inspectors must approve before the Ticket closes;
  - any `reject` or `needs_changes` immediately completes the inspection as
    rejected and returns the Ticket to `in_progress` with synthesized feedback;
  - any failed/unparseable inspector leaves the Ticket in `pending_approval`
    and records `requires_human`;
  - missing inspector replies keep the inspection pending.
- Append `inspection_completed` before any automatic state transition event.
- Map `needs_changes` to `inspection_completed.result: "rejected"` while
  preserving `decision: "needs_changes"` on the inspector decision event.
- Make inspection reduction idempotent per `inspection_id`; duplicate or late
  replies after `inspection_completed` must not re-transition the Ticket.
- Preserve the existing human approve/reject override path.

Out of scope:

- Approval-panel UI and browser E2E. That is Phase 15.4.
- New quorum modes such as `majority` or `any_pass`.
- Timeout scheduling or stale-inspection sweeps. Missing replies remain pending
  until a later timeout worker or human override; they never imply approval.
- Remote-node or federated inspector selection.
- Learning inspector quality scores.
- New database tables or migrations.

## Why

Phase 15.2 can ask selected inspectors for a decision, but Babs still cannot
understand or act on their replies. This slice creates the minimal automatic
approval loop while keeping the behavior conservative: only complete, valid,
all-pass decisions can close a Ticket, and ambiguous replies require human
action instead of guessing.

Keeping UI out of this slice makes the core lifecycle testable at the Writer
boundary before adding browser surfaces in Phase 15.4.

## Impact Analysis

- **Systems affected:** Ticket comment path, inspection event handling, Ticket
  state transitions, reply parsing, focused Ticket tests.
- **Runtime behavior:** Inspector comments that match an active inspection can
  append decision/failure events and may automatically transition the Ticket.
- **Human path:** Existing human approve/reject APIs and UI remain available.
- **Database:** no schema change.
- **Runtime data:** inspection decisions, failures, completion summaries, and
  automatic transition events are appended to Ticket history.
- **Privacy:** parser failures and completion summaries must not expose raw
  provider logs, env maps, local paths, private IPs, private hostnames, tokens,
  or secrets.
- **State machine:** automatic approval/rejection must use the existing
  `StateMachine.transition/3` rules for `pending_approval -> closed` and
  `pending_approval -> in_progress`, with `by: "system"` events.
- **Documentation:** no vocabulary change is expected because this slice uses
  existing Inspector/Inspection terms from `BAB-2243`; update `BAB-1002` only
  if implementation introduces a new user-facing term.
- **Rollback:** revert this CHG implementation. Existing Tickets remain valid
  because all events are append-only and additive.

## Implementation Plan

1. **Review this CHG before code**
   - Run Trinity `fast-review` against this CHG.
   - Fold blockers and update status before implementation.

2. **RED/GREEN: add decision parser**
   - Add `Babs.Citizens.Tickets.InspectionDecisionParser`.
   - Parse fenced `json` blocks and whole-body JSON.
   - Validate decision, summary, and findings.
   - Add tests for approve, reject, needs_changes, malformed JSON, missing
     summary, invalid findings, and extra prose around a fenced JSON block.
   - REFACTOR: keep validation helpers private and keep parser output free of
     raw provider text.

3. **RED/GREEN: add quorum reducer**
   - Add `Babs.Citizens.Tickets.InspectionQuorum`.
   - Read selected inspectors from
     `inspection_requested`.
   - Reduce latest per-inspector `inspection_decision` / `inspection_failed`
     events for the active `inspection_id`.
   - Return `:pending`, `{:approved, summary}`, `{:rejected, feedback}`, or
     `{:requires_human, reason}`.
   - Add tests for all approved, one reject, one needs_changes, one failed, and
     missing decision paths.
   - REFACTOR: centralize idempotency checks so Writer integration can reuse
     the same completed-inspection guard.

4. **RED/GREEN: integrate with Writer comment path**
   - When `Api.comment_ticket/3` stores a comment from an inspector with a
     matching `turn_id` and `attempt_id`, parse it as an inspection reply.
   - Append `inspection_decision` on parse success.
   - Append `inspection_failed` on parse failure.
   - Re-run quorum after the new event.
   - If quorum approves, append `inspection_completed` and transition
     `pending_approval` to `closed` with system approval events.
   - If quorum rejects or needs changes, append `inspection_completed` and
     transition back to `in_progress` with synthesized feedback.
   - Synthesized feedback includes each non-approve inspector's slug, decision,
     summary, and findings; approve-only summaries are not injected as rejection
     feedback.
   - If quorum requires human action, append `inspection_completed` with
     `requires_human` and leave the Ticket in `pending_approval`.
   - Ignore duplicate replies identified by `inspection_id`, inspector slug,
     `turn_id`, and `attempt_id`, and ignore late replies after
     `inspection_completed`.
   - REFACTOR: keep automatic transition assembly close to existing approval and
     rejection event helpers so human override behavior remains unchanged.

5. **Regression coverage**
   - Existing human approval/reject tests remain green.
   - Inspector comments not tied to prompt delivery remain ordinary comments.
   - Duplicate or late inspector comments after completion do not re-transition
     the Ticket.
   - Non-inspector comments cannot satisfy quorum.
   - Two-inspector council closes only after both approve.

6. **Validation**
   - Run focused parser, reducer, and Writer inspection tests.
   - Run `mix format --check-formatted`.
   - Run `mix compile --warnings-as-errors`.
   - Run `mix test --max-cases 1`.
   - Run full `mix test`.
   - Run exported coverage gate.
   - Run `af validate --root .`.
   - Run `git diff --check`.
   - Run added-line privacy scan.

7. **Review and PR**
   - Run Trinity `fast-review` on the implementation diff.
   - Create the PR with `gh` as `ryosaeba1985`.
   - Follow `COR-1615` / `COR-1612` GitHub Codex loop, max five review rounds.

## Acceptance Criteria

- Inspector replies with valid `approve` decisions can close a
  `pending_approval` Ticket when every selected inspector approves.
- A `reject` decision returns the Ticket to `in_progress` with feedback.
- A `needs_changes` decision behaves as rejection for state transition while
  preserving the distinct decision value in history.
- Parse failures and invalid decisions record `inspection_failed`, mark the
  inspection as `requires_human`, and keep the Ticket in `pending_approval`.
- A two-inspector council with `all_pass` does not close until both inspectors
  approve.
- Human approve/reject override behavior remains unchanged.
- No UI or browser behavior is changed in this slice.

## Validation Commands

```bash
mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/inspection_decision_parser_test.exs
mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/inspection_quorum_test.exs
mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/inspection_decision_capture_test.exs
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test --max-cases 1
mise exec -- mix test
mise exec -- mix test --cover --export-coverage phase15_3 && mise exec -- mix cmd mix test.coverage
af validate --root .
git diff --check
git diff -U0 | rg -n '^\+.*(100\.122|wukong|/Users/frank|api_token|secret|token)' || true
```

## Results

- 2026-05-08 Trinity CHG review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-153708-rules-BAB-2257-CHG-Implement-Phase-15-3-Decision-Capture-and-Quorum.md`.
  - GLM PASS at 9.26/10 and DeepSeek PASS at 9.1/10; no blocking findings.
  - Folded advisories for timeout deferral, feedback composition,
    `InspectionQuorum` naming, documentation scope, existing state-machine
    usage, early reject/needs_changes termination, duplicate/late reply
    idempotency, `needs_changes` result mapping, and explicit REFACTOR passes.
- 2026-05-08 implementation:
  - Added `Babs.Citizens.Tickets.InspectionDecisionParser` for fenced JSON and
    whole-body JSON inspector replies.
  - Added `Babs.Citizens.Tickets.InspectionQuorum` for `all_pass` reduction,
    active prompt matching, completion detection, and duplicate terminal-event
    detection.
  - Extended `inspection_decision` and `inspection_failed` events with optional
    `turn_id` and `attempt_id`.
  - Integrated matching inspector replies into the per-ticket Writer comment
    path for approve, reject, needs_changes, unparseable, and pending council
    outcomes.
  - Automatic approve/reject uses existing state-machine transitions and keeps
    human approve/reject override behavior unchanged.
- 2026-05-08 Trinity implementation review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-155635-Phase-15.3-decision-capture-implementation-diff`.
  - GLM PASS and DeepSeek PASS; no blocking findings.
  - Folded advisories by adding a reducer guard for empty inspector lists,
    accepting indented JSON closing fences, and adding Writer integration
    coverage for `needs_changes` and duplicate matching replies.
- 2026-05-08 final Trinity implementation review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-160906-Phase-15.3-decision-capture-final-diff`.
  - GLM PASS and DeepSeek PASS; no blocking findings.
- 2026-05-08 GitHub Codex review round 1:
  - Reviewed commit `2ad8bbb11e`.
  - Fixed P2 "Ignore replies to superseded inspection requests" by requiring
    matched prompts to belong to the latest unresolved `inspection_requested`
    event before parsing/reducing a reply.
  - Added reducer and Writer regression coverage for superseded inspection
    requests.
- 2026-05-08 GitHub Codex review round 2:
  - Reviewed commit `462ec39ee7`.
  - Fixed P2 "Attach inspection_id to automatic transition events" by tagging
    inspection-driven `approved`, `rejected`, and `state_change` history events
    with the related `inspection_id`.
  - Hardened the active-request model by rejecting a second
    `request_inspection` call while the latest inspection is still unresolved.
  - Added regression coverage for overlapping inspection requests and
    inspection-linked transition auditability.
- 2026-05-08 PR round 2 validation:
  - Focused quorum/Writer/request tests passed: 19 tests.
  - `mise exec -- mix format --check-formatted` passed.
  - `mise exec -- mix compile --warnings-as-errors` passed.
  - `mise exec -- mix test --max-cases 1` passed: 432 `:babs_citizens` tests
    and 88 `:babs` tests.
  - `mise exec -- mix test` passed: 432 `:babs_citizens` tests and 88 `:babs`
    tests.
  - `mise exec -- mix test --cover --export-coverage phase15_3 && mise exec -- mix cmd mix test.coverage`
    passed: `:babs_citizens` 85.64%, `:babs` 89.27%.
  - `af validate --root .` passed: 166 documents checked, 0 issues found.
  - `git diff --check` passed.
  - Added-line privacy scan found no private hostnames, private IPs, local
    checkout paths, tokens, or secrets.
- 2026-05-08 GitHub Codex review round 3:
  - Reviewed commit `ba6973b737`.
  - Fixed P2 "Clear stale inspections after human overrides" by treating
    human `pending_approval -> closed/in_progress/cancelled` override
    transitions as resolving the previously active inspection request.
  - Added reducer coverage for human override resolution and Writer/API
    coverage proving a human rejection can be followed by a fresh inspection
    request after the Ticket returns to `pending_approval`.
- 2026-05-08 PR round 3 validation:
  - Focused quorum/Writer/request tests passed: 21 tests.
  - `mise exec -- mix format --check-formatted` passed.
  - `mise exec -- mix compile --warnings-as-errors` passed.
  - `mise exec -- mix test --max-cases 1` passed: 434 `:babs_citizens` tests
    and 88 `:babs` tests.
  - `mise exec -- mix test` passed: 434 `:babs_citizens` tests and 88 `:babs`
    tests.
  - `mise exec -- mix test --cover --export-coverage phase15_3 && mise exec -- mix cmd mix test.coverage`
    passed: `:babs_citizens` 85.62%, `:babs` 89.27%.
  - `af validate --root .` passed: 166 documents checked, 0 issues found.
  - `git diff --check` passed.
  - Added-line privacy scan found no private hostnames, private IPs, local
    checkout paths, tokens, or secrets.
- 2026-05-08 GitHub Codex review round 4:
  - Reviewed commit `57426d7a5e`.
  - Fixed P2 "Keep superseded inspections from becoming active again" by
    making `active_request/1` consider only the latest
    `inspection_requested`; if that latest request is resolved, no older
    request can become active again.
  - Added reducer coverage for overlapping requests where the latest request
    completes as `requires_human`.
- 2026-05-08 PR round 4 validation:
  - Focused quorum/Writer/request tests passed: 22 tests.
  - `mise exec -- mix format --check-formatted` passed.
  - `mise exec -- mix compile --warnings-as-errors` passed.
  - `mise exec -- mix test --max-cases 1` passed: 435 `:babs_citizens` tests
    and 88 `:babs` tests.
  - `mise exec -- mix test` passed: 435 `:babs_citizens` tests and 88 `:babs`
    tests.
  - `mise exec -- mix test --cover --export-coverage phase15_3 && mise exec -- mix cmd mix test.coverage`
    passed: `:babs_citizens` 85.66%, `:babs` 89.27%.
  - `af validate --root .` passed: 166 documents checked, 0 issues found.
  - `git diff --check` passed.
  - Added-line privacy scan found no private hostnames, private IPs, local
    checkout paths, tokens, or secrets.
- 2026-05-08 local validation:
  - Focused Phase 15.3 parser/quorum/Writer tests passed: 23 tests.
  - Focused existing Writer/API/inspection-event tests passed: 58 tests.
  - `mise exec -- mix format --check-formatted` passed.
  - `mise exec -- mix compile --warnings-as-errors` passed.
  - `mise exec -- mix test --max-cases 1` passed: 432 `:babs_citizens` tests
    and 88 `:babs` tests.
  - `mise exec -- mix test` passed: 432 `:babs_citizens` tests and 88 `:babs`
    tests.
  - `mise exec -- mix test --cover --export-coverage phase15_3 && mise exec -- mix cmd mix test.coverage`
    passed: `:babs_citizens` 85.71%, `:babs` 89.27%.
  - `af validate --root .` passed: 166 documents checked, 0 issues found.
  - `git diff --check` passed.
  - Added-line privacy scan found no private hostnames, private IPs, local
    checkout paths, tokens, or secrets.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial Phase 15.3 decision capture and quorum CHG | Codex |
| 2026-05-08 | Mark Approved after Trinity fast-review PASS/PASS and fold advisories | Codex |
| 2026-05-08 | Implement decision parser, quorum reducer, Writer capture integration, and local validation | Codex |
| 2026-05-08 | Record Trinity implementation review and folded advisory coverage | Codex |
| 2026-05-08 | Record final Trinity implementation review PASS/PASS | Codex |
| 2026-05-08 | Record Codex R1 superseded-inspection fix and regression coverage | Codex |
