# CHG-2222: Implement Phase 11 Approval UI

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

Implement Phase 11 from `BAB-2217` / `BAB-2218`: operator approval and
rejection for Tickets in `pending_approval`.

This slice adds:

- Approval and rejection APIs for pending-approval Tickets.
- Rejection feedback as required persisted Ticket history.
- History-first rejection feedback injection into assigned Citizen terminals.
- Temporary Mix bridge commands for approve/reject while ADR-complete `bb`
  remains deferred.
- `/tickets/<id>` approval and rejection controls with semantic icons.
- Unit, LiveView, browser-harness BDD, coverage, Trinity, and PR review
  validation for the approval loop.

This CHG intentionally does not implement Phase 12 cross-Citizen comments or
the `bb ticket comment` command. Rejection feedback is a Phase 11 inspector
decision, not the general comment workflow. The first browser implementation
will use an inline required feedback form instead of a modal; the acceptance
requirement is nonblank feedback captured before rejection, and a modal can
replace the inline form in a later UI-polish slice if needed.
Phase 12 is deferred to a separate PR to keep this slice reviewable and because
general comments have different delivery and multi-participant semantics than
inspector rejection feedback.
This explicitly splits the original `BAB-2218` PR D scope into two reviewable
slices: Phase 11 approval/rejection first, then Phase 12 comments in a follow-up
CHG. This branch updates `BAB-2218` to reflect that split.

Authority references for this CHG are `BAB-2217`, `BAB-2218`, `BAB-2221`,
`BAB-1111`, `BAB-1004`, and `BAB-1503`.

## Why

Phase 9-10 lets the operator assign a Ticket to a Citizen and move it to
`pending_approval`, but the operator still cannot complete the flywheel from
the browser. Phase 11 closes the human-inspector loop for V0-M:

1. Citizen work reaches `pending_approval`.
2. The operator approves, closing the Ticket.
3. Or the operator rejects with feedback, returning the Ticket to
   `in_progress`.
4. Babs records the decision in Ticket history first.
5. Rejection feedback is mirrored into the assigned Citizen terminal so the
   Citizen can continue.

This makes a single-ticket work cycle usable before Phase 12 adds general
comments between participants.

## Impact Analysis

- **Systems affected:** `:babs_citizens` Ticket state machine, writer/API,
  feedback injection boundary, temporary Mix ticket bridge tasks, `/tickets`
  LiveView, browser BDD tests, roadmap/tracker docs.
- **Data affected:** Runtime Ticket markdown and history JSONL under the
  configured tickets root. No Ticket runtime data is committed to git.
- **SQLite affected:** Read-only Citizen lookup/status through the existing
  Catalog/Lifecycle boundary. No Ticket tables are added.
- **Runtime behavior:** Rejection feedback is injected into currently assigned
  Citizens after rejection state/history are persisted.
- **Security/privacy:** Feedback text is operator-entered runtime data. Babs
  must not log env maps, tokens, socket tokens, host-local paths, private URLs,
  or raw lifecycle errors into browser flashes, public PR text, or Ticket
  history. Injection errors must be typed/redacted before display or
  persistence.
- **Rollback plan:** Revert this PR. Existing Phase 7-10 Ticket files remain
  readable. Any `approved`, `rejected`, or feedback-injection history events
  created by this slice still render generically in the Phase 8 timeline after
  rollback.

## Implementation Plan

1. RED: Add state-machine tests for explicit approval event handling:
   - `pending_approval -> closed` via `approved`
   - legal existing `pending_approval -> closed` fallback stays compatible when
     invoked as a plain state change
   - wrong event names for otherwise legal transitions extend the existing
     `invalid_transition_event` coverage instead of returning a generic invalid
     transition.
2. GREEN: Extend `Babs.Citizens.Tickets.StateMachine` so Phase 11 approval can
   use event name `approved`, while existing Phase 9-10
   `pending_approval -> closed` compatibility via nil or `state_change` is
   preserved. The existing `pending_approval -> in_progress` transition via
   `rejected` is extended at the writer/API layer to require and persist a
   `feedback` payload; rejecting without feedback remains an error.
   The generic `transition_ticket` writer path must not allow Phase 11-owned
   events to bypass their richer semantics: `pending_approval -> in_progress`
   with `event = "rejected"` returns a typed `use_reject_ticket` error, and
   `pending_approval -> closed` with `event = "approved"` returns a typed
   `use_approve_ticket` error. Plain `pending_approval -> closed` via nil or
   `state_change` remains compatible.
3. RED: Add Writer/API tests for:
   - approving a `pending_approval` Ticket closes it and appends `approved`
     plus `state_change` history,
   - rejecting requires nonblank feedback,
   - rejection requires at least one assignee, moves
     `pending_approval -> in_progress`, appends `rejected` plus
     `state_change` history with feedback, and injects the feedback prompt to
     all current `assignees`,
   - malformed or manually edited pending-approval Tickets with empty assignees
     are rejected before injection,
   - feedback injection failure leaves the Ticket `in_progress` and records a
     redacted advisory event,
   - illegal approve/reject states do not rewrite markdown.
4. GREEN: Add serialized mutations:
   - `approve_ticket(ticket_id, opts)`
   - `reject_ticket(ticket_id, feedback, opts)`
   Both must reuse the existing per-Ticket writer and conflict detection. The
   actor is carried in `opts[:by]` and defaults to `"user"` for browser and Mix
   bridge paths.
5. GREEN: Define approval/rejection history semantics:
   - `approved`: `ts`, `event`, `by`, `ticket_id`, `from`, `to`
   - existing `state_change`: `ts`, `event`, `by`, `ticket_id`, `from`, `to`
   - `rejected`: `ts`, `event`, `by`, `ticket_id`, `from`, `to`, `feedback`
   - `feedback_injection_attempted`: `ts`, `event`, `by`, `ticket_id`,
     `injected_to`, `kind`
   - `feedback_injected`: `ts`, `event`, `by`, `ticket_id`, `injected_to`,
     `kind`
   - `feedback_injection_failed`: `ts`, `event`, `by`, `ticket_id`,
     `injected_to`, `kind`, `error`
   The `kind` field must be the literal string `"rejection_feedback"` in this
   slice. It exists to keep these terminal mirrors distinct from the Phase 9
   assignment prompt injection events. The `rejected` event schema extends the
   Phase 9-10 `rejected` transition event by adding `feedback`.
   Approval writes `approved` followed by the existing `state_change` event.
   Rejection writes `rejected`, then `state_change`, then
   `feedback_injection_attempted` before terminal injection, followed by either
   `feedback_injected` or `feedback_injection_failed`.
   `feedback_injection_attempted` is one event whose `injected_to` value is the
   list of all target assignee slugs. Delivery outcome events are per assignee
   and also use list-form `injected_to` containing the single target slug, to
   match Phase 9's assignment injection convention.
6. GREEN: Use this rejection feedback prompt template for each assigned Citizen:
   ```text
   [Babs Ticket T-YYYY-MM-DD-NNN rejected]
   State: in_progress
   Assignee: <slug>

   Feedback from user:
   <feedback>

   Please address the feedback and continue work in this terminal.
   ```
   The prompt is injected as one terminal input payload with a trailing newline.
7. GREEN: Preserve history-first behavior. Rejection state/history must be
   persisted before terminal injection. Feedback is injected to every current
   assignee listed in the Ticket frontmatter. Stopped assignees use the same
   auto-start/verify boundary as Phase 9 assignment injection. If feedback
   injection fails for one or more assignees, the Ticket remains `in_progress`
   with the `rejected` and `state_change` events plus advisory
   `feedback_injection_failed` event(s). A feedback retry action is deferred to
   a future CHG, matching the Phase 9 assignment-injection retry deferral.
8. RED/GREEN: Add temporary Mix bridge commands:
   - `mix babs.ticket.approve T-...`
   - `mix babs.ticket.reject T-... "feedback text"`
   These commands are a documented temporary bridge until ADR-complete `bb`
   exists.
9. RED: Add LiveView tests for:
   - Approve button appears only for `pending_approval`.
   - Reject feedback form appears only for `pending_approval`.
   - Reject requires nonblank feedback.
   - Approve closes the Ticket and hides assignment, transition, approval, and
     rejection controls.
   - Reject returns to `in_progress`, shows assignment controls appropriate for
     that state, while the pre-rejection `pending_approval` view does not show
     direct unassign controls.
   - All new controls include icons and accessible labels.
10. GREEN: Extend `/tickets/<id>`:
    - show Approve with `check` icon for `pending_approval`,
    - show Reject with `x` icon and a required feedback textarea for
      `pending_approval`; do not reuse `undo`, which already means unassign,
    - hide approval/rejection controls for all other states,
    - use async actions and the existing `ticket_action_inflight` guard,
    - flash typed/redacted errors only.
11. RED/GREEN: Add browser-harness BDD for:
    - assign Ticket to a shell Citizen,
    - move it to `pending_approval`,
    - stop the shell Citizen to verify rejection feedback auto-starts it,
    - reject with feedback and verify the feedback appears in the Citizen
      transcript input,
    - move it to `pending_approval` again,
    - approve and verify the Ticket becomes `closed`.
    Use a browser-created shell Citizen in the isolated BDD environment so this
    flow does not depend on external AI CLI credentials.
12. REFACTOR: Extract shared writer helpers only if either approval/rejection
    mutation function exceeds 30 lines or the same history-append pattern is
    duplicated in both functions; keep changes localized to the Ticket
    boundary.
13. GREEN: Update docs with implementation facts, validation results, review
    results, and Phase 11 status.

## Validation Plan

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`
- `mise exec -- mix test --cover --export-coverage phase11`
- `mise exec -- mix cmd mix test.coverage`
- `npm run test:js`
- `npm run test:bdd`
- `npm run test:e2e`
- `mise exec -- mix babs.gate_a`
- `af validate --root .`
- `git diff --check`
- Privacy scan for public PR text and changed files.

Umbrella coverage is run as export plus per-app coverage summary so each
umbrella child uses its own configured threshold and ignore list.

Optional or conditional validation:

- Multi-CLI manual smoke against Clare, Dylan, Flora, and Elena when their
  credentials and local CLIs are available. Missing or stopped seed Citizens
  should skip the smoke rather than fail this slice.

## Review Plan

- Plan review: Trinity fast-review using GLM and DeepSeek.
- Implementation review: Trinity fast-review using GLM and DeepSeek on the
  implementation diff.
- PR review: GitHub Codex review loop per `COR-1615`, capped at five rounds by
  `BAB-2218`.

## Review Results

- R1 `.trinity/reviews/20260506-143047-rules-BAB-2222-CHG-Implement-Phase-11-Approval-UI.md`:
  GLM PASS and DeepSeek PASS 9.0/10 with non-blocking advisories. Folded
  clarification on Phase 11/12 split, feedback injection `kind`, Mix bridge
  acceptance, BDD shell-Citizen scope, invalid-transition-event wording, retry
  deferral, and pending-approval unassign wording.
- R2 `.trinity/reviews/20260506-143632-rules-BAB-2222-CHG-Implement-Phase-11-Approval-UI.md`:
  GLM PASS and DeepSeek raw FIX. Fixed DeepSeek blockers by specifying ordered
  history-first event sequences, `approved` plus `state_change`, all-assignee
  feedback targets, opts-based `by`, empty-assignee rejection, explicit PR D
  split, feedback attempted purpose, concrete UI controls, inline feedback form,
  rejected schema extension, and stopped-assignee auto-start BDD.
- R3 `.trinity/reviews/20260506-144347-rules-BAB-2222-CHG-Implement-Phase-11-Approval-UI.md-rules-BAB-2218-CHG-M3-Phase-7-12-Execution-Contract.md`:
  GLM PASS 9.3/10 and DeepSeek PASS with advisories. Fixed wording and
  cross-document advisories on feedback controls, rejected feedback extension,
  concrete refactor threshold, roadmap modal wording, and tracker `next_d`.
- R4 `.trinity/reviews/20260506-144950-rules-BAB-2222-CHG-Implement-Phase-11-Approval-UI.md-rules-BAB-2218-CHG-M3-Phase-7-12-Execution-Contract.md-rules-BAB-2300-PLN-Build-Roadmap.md-rules-BAB-3003-REF-Discussion-Tracker-2026-05-06.md`:
  GLM PASS and DeepSeek PASS. Folded remaining implementation advisories on
  generic transition bypass guards, cancel-notification deferral, feedback
  injection event granularity, positional Mix reject feedback, and reject icon
  choice. CHG approved for implementation.

## Implementation Results

Local implementation on `codex/m3-phase-11-approval-ui` adds:

- `approve_ticket/2` and `reject_ticket/3` public APIs using the existing
  per-Ticket writer.
- Explicit `approved` plus `state_change` history for approvals.
- Required rejection feedback, `rejected` plus `state_change` history, and
  history-first feedback injection events.
- Generic transition guards so `transition_ticket(..., "rejected")` and
  `transition_ticket(..., "approved")` cannot bypass Phase 11 semantics.
- Rejection feedback prompt generation through `Babs.Citizens.Tickets.Injector`.
- Temporary Mix bridge commands:
  `mix babs.ticket.approve T-...` and
  `mix babs.ticket.reject T-... "feedback text"`.
- `/tickets/<id>` approve/reject controls with `check` and `x` icons, inline
  required feedback form, async action handling, and typed/redacted flashes.
- Browser-harness BDD coverage for assign, pending approval, stopped-Citizen
  rejection feedback auto-start, feedback transcript input, re-submit to
  pending approval, and approve to `closed`.

Local validation passed on 2026-05-06:

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`: `:babs_citizens` 187 tests, `:babs` 60 tests
- `mise exec -- mix test --cover --export-coverage phase11`
- `mise exec -- mix cmd mix test.coverage`: `:babs_citizens` 83.00%,
  `:babs` 85.31%
- `npm run test:js`: 8 tests
- `npm run test:bdd`: all required scenarios passed; optional workspace-root
  and stopped seed-CLI smokes skipped
- `npm run test:e2e`: 4 passed, 2 optional seed CLI checks skipped
- `mise exec -- mix babs.gate_a`
- `af validate --root .`: 125 documents, 0 issues
- `git diff --check`
- Privacy scan of changed files found no private Tailscale IPs, host-local
  absolute paths, or credential values.

Trinity implementation fast-review R1
`.trinity/reviews/20260506-151059-BAB-2222-phase-11-implementation` passed with
GLM and DeepSeek. Non-blocking advisories were folded in by checking assignees
before approval transition, adding a stable empty-rejection-feedback message,
and extending the storage invariant test to cover manually invalid
`pending_approval` Tickets with no assignees. Targeted ticket tests, full
umbrella tests, coverage, JS, browser-harness BDD, E2E, Gate A, Alfred
validation, whitespace, and privacy checks passed again after these fixes.

Trinity implementation fast-review R2
`.trinity/reviews/20260506-152256-BAB-2222-phase-11-implementation-r2` passed
with GLM and DeepSeek. GLM left low-risk coverage advisories; the multi-assignee
rejection-feedback advisory was folded in with an explicit Writer/API test that
manually valid multi-assignee Ticket frontmatter injects feedback to every
current assignee. The empty-assignee approval case remains covered at the
storage invariant boundary because persisted `pending_approval` Tickets without
assignees are invalid before the writer mutation path is reached.

Trinity implementation fast-review R3
`.trinity/reviews/20260506-153000-BAB-2222-phase-11-implementation-r3` passed
with GLM and DeepSeek. DeepSeek flagged one low-severity semantic bypass where
`transition_ticket(id, "in_progress", nil)` from `pending_approval` could use
the state machine's nil-event coercion to reject without feedback. That was
fixed by guarding the nil event in the writer and adding API coverage. Full
validation passed again after the fix:

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`: `:babs_citizens` 186 tests, `:babs` 60 tests
- `mise exec -- mix test --cover --export-coverage phase11`
- `mise exec -- mix cmd mix test.coverage`: `:babs_citizens` 82.93%,
  `:babs` 85.24%
- `npm run test:js`: 8 tests
- `npm run test:bdd`: all required scenarios passed; optional workspace-root
  and stopped seed-CLI smokes skipped
- `npm run test:e2e`: 4 passed, 2 optional seed CLI checks skipped
- `mise exec -- mix babs.gate_a`
- `af validate --root .`: 125 documents, 0 issues
- `git diff --check`
- Privacy scan of changed files found no private Tailscale IPs, host-local
  absolute paths, or credential values.

Trinity implementation fast-review R4
`.trinity/reviews/20260506-153907-BAB-2222-phase-11-implementation-r4` passed
with GLM and DeepSeek and no blocking findings. Both reviewers confirmed the
nil-event rejection bypass fix, history-first feedback injection, multi-assignee
coverage, typed/redacted errors, icon coverage, and Phase 9-10 compatibility.

GitHub Codex PR review R1 on PR #19 found one P2: oversized rejection feedback
could make the generated `rejected` history event exceed the JSONL event-size
limit after the Ticket markdown had already been rewritten to `in_progress`.
The fix validates generated approval/rejection events with
`History.validate_appendable/2` before rewriting markdown, then appends the
already validated events after the write. A regression test verifies oversized
rejection feedback leaves the Ticket in `pending_approval` with no `rejected`
history event. Full validation passed again after the fix:

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`: `:babs_citizens` 187 tests, `:babs` 60 tests
- `mise exec -- mix test --cover --export-coverage phase11`
- `mise exec -- mix cmd mix test.coverage`: `:babs_citizens` 83.06%,
  `:babs` 85.24%
- `npm run test:js`: 8 tests
- `npm run test:bdd`: all required scenarios passed; optional workspace-root
  and stopped seed-CLI smokes skipped
- `npm run test:e2e`: 4 passed, 2 optional seed CLI checks skipped
- `mise exec -- mix babs.gate_a`
- `af validate --root .`: 125 documents, 0 issues
- `git diff --check`
- Privacy scan of changed files found no private Tailscale IPs, host-local
  absolute paths, or credential values.

Trinity implementation fast-review R5
`.trinity/reviews/20260506-155822-BAB-2222-phase-11-post-codex-r1-fix`
passed with GLM and DeepSeek after the Codex R1 P2 fix. Reviewers confirmed the
pre-write event validation ordering and regression coverage; remaining notes
were non-blocking performance/symmetry observations for future cleanup.

GitHub Codex PR review R2 on PR #19 found one P2: rejection feedback was
persisted in the `feedback` field but the browser history timeline rendered
only `body`, so the operator could not read the required rejection reason from
the Ticket detail page. The fix renders either `body` or `feedback` in the
history event body slot and adds LiveView coverage that a rejected Ticket shows
the feedback text after rejection. Full validation passed again after the fix:

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`: `:babs_citizens` 187 tests, `:babs` 60 tests
- `mise exec -- mix test --cover --export-coverage phase11`
- `mise exec -- mix cmd mix test.coverage`: `:babs_citizens` 83.00%,
  `:babs` 85.31%
- `npm run test:js`: 8 tests
- `npm run test:bdd`: all required scenarios passed; optional workspace-root
  and stopped seed-CLI smokes skipped
- `npm run test:e2e`: 4 passed, 2 optional seed CLI checks skipped
- `mise exec -- mix babs.gate_a`
- `af validate --root .`: 125 documents, 0 issues
- `git diff --check`
- Privacy scan of changed files found no private Tailscale IPs, host-local
  absolute paths, or credential values.

Trinity implementation fast-review R6
`.trinity/reviews/20260506-161511-BAB-2222-phase-11-post-codex-r2-fix`
passed with GLM and DeepSeek after the Codex R2 P2 fix. Reviewers confirmed
the feedback timeline rendering fix, existing comment-body compatibility, and
targeted LiveView coverage; remaining notes were non-blocking template
micro-optimization observations.

## Acceptance

- A pending-approval Ticket can be approved from `/tickets/<id>` and becomes
  `closed`.
- A pending-approval Ticket can be rejected from `/tickets/<id>` only with
  nonblank feedback and returns to `in_progress`.
- Mix bridge commands `mix babs.ticket.approve` and
  `mix babs.ticket.reject` function with the same typed errors as the browser
  path.
- Rejection feedback is persisted in history before terminal injection.
- Assigned Citizens receive the rejection feedback prompt in their terminal
  when running.
- Feedback injection failure is advisory and does not erase the rejected
  history/state transition.
- Approval/rejection controls are shown only when legal and include semantic
  icons.
- Phase 12 general comments remain out of scope.
- All required validation passes before PR.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-06 | Initial version | — |
| 2026-05-06 | Draft Phase 11 approval/reject UI implementation contract | Codex |
| 2026-05-06 | Fold Trinity R1 advisories on Phase 11/12 split rationale, feedback injection `kind`, Mix acceptance, BDD shell-Citizen scope, existing invalid-transition-event coverage, retry deferral, and pending-approval unassign wording | Codex |
| 2026-05-06 | Fold Trinity R2 DeepSeek FIX items on event ordering, approved plus state_change semantics, multi-assignee feedback targets, opts-based `by`, empty-assignee rejection, explicit PR D split, feedback attempted purpose, concrete UI controls, inline feedback form, rejected schema extension, and stopped-assignee auto-start BDD | Codex |
| 2026-05-06 | Fold Trinity R4 advisories by guarding generic transition bypasses, deferring cancel notification mirrors, defining feedback injection event granularity, using positional Mix reject feedback, and choosing `x` for reject icon | Codex |
| 2026-05-06 | Mark approved after Trinity R4 GLM and DeepSeek PASS | Codex |
| 2026-05-06 | Implement Phase 11 approval/reject UI with API, writer, Mix, LiveView, BDD, coverage, Gate A, E2E, Alfred validation, and privacy scan passing locally | Codex |
| 2026-05-06 | Fold Trinity implementation R1 advisories and rerun full Phase 11 validation | Codex |
| 2026-05-06 | Fold Trinity implementation R2 multi-assignee rejection-feedback coverage advisory | Codex |
| 2026-05-06 | Fix Trinity implementation R3 nil-event rejection bypass and rerun full Phase 11 validation | Codex |
| 2026-05-06 | Mark Phase 11 implementation ready for PR after Trinity R4 GLM and DeepSeek PASS | Codex |
| 2026-05-06 | Fix GitHub Codex PR review R1 P2 oversized rejection feedback history prevalidation finding | Codex |
| 2026-05-06 | Mark post-Codex-R1 fix approved after Trinity R5 GLM and DeepSeek PASS | Codex |
| 2026-05-06 | Fix GitHub Codex PR review R2 P2 rejection feedback timeline rendering finding | Codex |
| 2026-05-06 | Mark post-Codex-R2 fix approved after Trinity R6 GLM and DeepSeek PASS | Codex |
