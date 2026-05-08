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

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial Phase 15.3 decision capture and quorum CHG | Codex |
| 2026-05-08 | Mark Approved after Trinity fast-review PASS/PASS and fold advisories | Codex |
