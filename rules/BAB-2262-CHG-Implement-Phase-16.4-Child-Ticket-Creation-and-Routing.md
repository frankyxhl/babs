# CHG-2262: Implement Phase 16.4 Child Ticket Creation and Routing

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

Implement **Phase 16.4: Child Ticket creation and routing** from `BAB-2244`
after the Phase 16.3 proposal review UI.

This slice changes Mayor proposal approval from "record approval only" to
"record approval and materialize approved child Tickets". It must keep child
Ticket files under the configured tickets root, never under git, and must keep
root Ticket history as the auditable source of what was created.

This slice will:

- Create child Tickets from the latest pending approved proposal only when the
  operator clicks proposal approval.
- Set each child Ticket's `parent_ticket` to the root Ticket id.
- Preserve proposed title, body, type, priority, assignee role, inspector, and
  inspection metadata.
- Set child Ticket provenance to `"mayor:<slug>"` when the active proposal
  policy identifies a Mayor slug and `"mayor"` otherwise.
- Persist a root history event listing created child Ticket ids and their source
  proposal child indexes.
- Trigger Phase 14 role routing for child Tickets that have an `assignee_role`
  and no named assignees.
- Keep Phase 15 inspection metadata attached to child Tickets so their normal
  completion approval path can use the existing inspection policy.
- Render created child links/status on the root Ticket proposal panel after
  approval.
- Add BDD/E2E coverage for the human-gated mission -> proposal -> approve ->
  child Ticket flow.

Out of scope:

- Dispatching the Mayor provider or parsing raw Mayor output. Phase 16.4 still
  uses persisted proposal artifacts; provider dispatch remains a later slice.
- Creating GitHub issues, branches, commits, or PRs from Mayor output.
- Cross-machine Mayor execution or mobile-specific behavior from Phase 17.
- Automatic approval without a human gate.
- Mayor councils or conflict resolution between multiple Mayors.
- Dependency graph scheduling between child Tickets.

Depends on:

- `BAB-2259` Phase 16.1 Mayor policy/proposal schema.
- `BAB-2260` Phase 16.2 Mayor selection and prompt assembly.
- `BAB-2261` Phase 16.3 proposal review UI and persisted review events.

## Why

Phase 16.3 lets the operator inspect, edit, reject, and approve a Mayor
proposal, but approval is still inert. The flywheel is not complete until an
approved proposal becomes real child Tickets that role routing and Inspector
Council flows can execute.

Writing children through the existing Ticket storage and Writer paths keeps the
Mayor workflow aligned with the rest of Babs: Tickets remain filesystem runtime
data, Ticket history remains append-only, and role routing/inspection behavior
stays visible and testable.

## Impact Analysis

- **Systems affected:** Mayor proposal review approval path, Ticket creation,
  Ticket history events, role routing, Ticket detail presenter/UI, LiveView
  tests, BDD/E2E tests.
- **Runtime behavior:** Before Phase 16.4, proposal approval records only a
  root history event. After Phase 16.4, approval also creates child Tickets and
  records a created-children event.
- **Persistence:** new child Ticket markdown files plus child history JSONL
  files are written under the configured tickets root. Root history receives
  `mayor_children_created`.
- **Data model:** proposal approval remains append-only. Child Ticket ids are
  concrete runtime data and must not be derived later by re-reading a proposal
  alone.
- **Role routing:** child Tickets with `assignee_role` should be routed by the
  existing Phase 14 path. If no candidate exists, child creation remains
  successful and the root event records the routing failure for that child.
- **Inspection:** child `metadata.inspection` is preserved; no inspection is
  requested during creation.
- **Database:** no migration expected.
- **Privacy:** fixtures and docs must not include raw provider logs, private
  hostnames, private IPs, local checkout paths, tokens, or secrets.
- **Rollback plan:** revert this CHG implementation. Existing child Tickets
  created by the feature remain normal Ticket files; the operator may close,
  cancel, or delete runtime Ticket data manually according to normal runtime
  operations. No git-tracked runtime data is introduced.

## Risks and Constraints

- Approval must be idempotent. If `mayor_children_created` already exists for
  the same active `proposal_id`, repeated approval must return a stable
  already-materialized result and must not create duplicate children.
- Approval must still reject stale `proposal_id` or stale proposal revision
  tokens from old browser sessions.
- Child creation writes several files. Implementation must pre-validate every
  child Ticket before writing any child file. If a later write fails after
  earlier children were created, the implementation must avoid appending a root
  created-children event and must return a redacted error that lists only
  created child ids, not host paths or raw IO details.
- Child Ticket ids must come from the existing Ticket id allocator; tests must
  not assume hard-coded ids except where a deterministic date/root makes that
  safe.
- If child files are written successfully but the root
  `mayor_children_created` event cannot be appended, the implementation should
  make a best-effort attempt to append a minimal created-children marker before
  returning a redacted error. If that also fails, orphan child Tickets are
  detectable by `parent_ticket` matching the root Ticket and by the absence of a
  root `mayor_children_created` event; operator cleanup follows normal runtime
  Ticket operations.
- Role routing is best-effort after child creation. A routing failure should be
  recorded in root history and exposed in the UI, but it must not delete child
  Tickets.
- Phase 16.4 must not make Babs parse Alfred SOP bodies. `rules_refs` remain
  opaque provenance strings.

## History Event Contract

Phase 16.4 keeps the Phase 16.3 approval event and adds one root event after
children are written:

```json
{
  "ts": "2026-05-08T00:04:01Z",
  "event": "mayor_children_created",
  "by": "user",
  "ticket_id": "T-...",
  "proposal_id": "prop_...",
  "children": [
    {
      "child_index": 0,
      "ticket_id": "T-...",
      "title": "Implement backend slice",
      "priority": "normal",
      "inspector": "auto",
      "assignee_role": "developer",
      "routing": {"status": "assigned", "assignees": ["dylan"]}
    }
  ]
}
```

Routing status values:

- `"not_requested"`: no `assignee_role` or role routing disabled.
- `"assigned"`: existing role routing assigned at least one Citizen.
- `"failed"`: role routing returned a stable error; child Ticket still exists.

The event must not embed child Ticket bodies or raw provider output. Child
Ticket markdown and child history JSONL remain authoritative for child content.

`MayorProposalReview.from_history/2` remains the single reducer for proposal
state. Phase 16.4 extends it to surface the latest matching
`mayor_children_created` event so Presenter and Writer code do not duplicate
history scans for materialization state.

New stable result/error shapes:

- `{:ok, %{event: approved, children_created: created_event}}`: first approval
  materialized children.
- `{:ok, %{event: approved, children_created: created_event, already_materialized?: true}}`:
  repeated approval found existing materialization and created no duplicates.
- `{:error, {:mayor_child_tickets, {:partial_child_write, created_child_ids}}}`:
  one or more child files were written but root materialization could not be
  completed; `created_child_ids` contains only Ticket ids, never host paths or
  raw IO details.
- Per-child routing failures are represented inside
  `mayor_children_created.children[*].routing` as
  `%{"status" => "failed", "reason" => stable_reason}`.

## Implementation Plan

1. **Review this CHG before code**
   - Run Trinity review with GLM and DeepSeek.
   - Fold blocking findings before implementation.

2. **RED/GREEN: pure child materialization plan**
   - Add a pure helper, tentatively
     `Babs.Citizens.Tickets.MayorChildTickets`, that converts a validated
     pending proposal state into child Ticket attrs and a root summary event
     shape.
   - Keep this helper side-effect free. It may validate and transform proposal
     data but must not write files.
   - Preserve child `metadata.inspection`, compact `inspector`, priority, type,
     `assignee_role`, title, and body.
   - Set `parent_ticket` to the root Ticket id and `assigner` to Mayor
     provenance.
   - Add tests for valid mapping, empty/invalid proposal protection, inspection
     metadata preservation, and provenance.

3. **RED/GREEN: Writer/API approval materialization**
   - Extend `approve_mayor_proposal/3` through the existing API -> Writer path.
   - Reuse `MayorProposalReview` to re-read history, check pending status,
     check `proposal_id`, and check optional `proposal_revision`.
   - Before writing children, detect existing `mayor_children_created` for the
     active `proposal_id` and return a stable idempotent result without writing
     duplicates.
   - Pre-validate every child Ticket attrs through existing Ticket validation
     before any file write.
   - Write child Tickets under the configured tickets root using existing
     storage helpers.
   - Append child `created` history events through existing Ticket history
     conventions.
   - Preserve the existing Phase 16.3 `mayor_proposal_approved` append
     semantics; Phase 16.4 adds child file writes plus the root
     `mayor_children_created` event in the same root Writer path.
   - Add API/Writer tests proving child files are created, root history lists
     the child ids, repeated approval is idempotent, stale revision is rejected,
     and partial validation failure creates no child files.

4. **RED/GREEN: role routing integration**
   - For each created child with `assignee_role`, call the existing Phase 14
     role routing path after the child Ticket exists.
   - Record routing outcome per child in `mayor_children_created`.
   - Coordinate child Writer calls explicitly and independently: one child's
     `assign_by_role` failure must not abort routing attempts for later
     children.
   - Add tests for assigned, not requested, and failed routing outcomes.
   - Keep routing failures non-destructive: child Tickets remain visible and
     manually assignable.

5. **RED/GREEN: Ticket detail UI**
   - Extend `TicketPresenter.proposal_panel/2` to expose created child Ticket
     summaries after `mayor_children_created`.
   - Render created child ids as links to `/tickets/<child_id>` with role and
     routing status badges.
   - After child materialization, hide proposal edit/remove/reject/approve
     controls and show a "Children created" state.
   - Add LiveView tests for created-child rendering and link targets.

6. **BDD/E2E**
   - Add a browser-harness BDD scenario under `test/bdd/`, tentatively
     `test/bdd/phase16_4_mayor_child_ticket_creation.feature`, that
     creates/seeds a mission Ticket, seeds a valid proposal artifact, approves
     it in the browser, observes child Ticket links, opens a child Ticket, and
     verifies parent/provenance fields.
   - Add or extend an E2E smoke where practical. If browser-harness is blocked
     by connector authorization, record the blocker explicitly and keep ExUnit
     coverage authoritative for the PR.

7. **REFACTOR**
   - Keep proposal validation and child mapping outside LiveView.
   - Keep filesystem writes inside the existing Ticket storage/Writer boundary.
   - Avoid a separate child Ticket database table or hidden cache.
   - Keep root history and child Ticket files as the only authoritative data.

8. **Validation**
   - Run focused child materialization, API/Writer, Presenter, and LiveView
     tests.
   - Run `mix format --check-formatted`.
   - Run `mix compile --warnings-as-errors`.
   - Run `mix test --max-cases 1`.
   - Run full `mix test`.
   - Run exported coverage gate.
   - Run `npm run test:js`.
   - Run `npm run test:bdd` for the new browser-harness scenario, or document
     the exact connector blocker.
   - Run `af validate --root .`.
   - Run `git diff --check`.
   - Run added-line privacy scan and triage false positives.

9. **Review and PR**
   - Follow `BAB-1503` / `COR-1616` for the reviewed delivery slice.
   - Run Trinity implementation review with GLM and DeepSeek.
   - Create the PR with `gh` as `ryosaeba1985`.
   - Follow `COR-1615` / `COR-1612` GitHub Codex loop, max five review rounds.

## Acceptance Criteria

- Approving a pending Mayor proposal creates child Ticket markdown/history
  files under the configured tickets root.
- Every created child has `parent_ticket` set to the root Ticket id.
- Every created child preserves proposed title, body, type, priority,
  `assignee_role`, compact inspector, and `metadata.inspection`.
- Root history records `mayor_proposal_approved` and
  `mayor_children_created` with the created child Ticket ids.
- Repeated approval of the same materialized proposal does not create duplicate
  child Tickets.
- Stale `proposal_id` or stale proposal revision submissions append no history
  and create no child Tickets.
- Role routing runs for children with an `assignee_role`; routing failures are
  recorded but do not delete child Tickets.
- Ticket detail UI shows created child links/status after approval.
- Existing Ticket chat, assignment, inspection, ordinary approval, and proposal
  rejection behavior continues to work.
- BDD/E2E or a documented browser-harness blocker covers the human-gated
  mission -> proposal -> approve -> child Ticket path.
- No raw secrets, private hostnames, private IPs, local checkout paths, runtime
  Ticket data, or generated proposal data are published in docs, PR body,
  comments, or fixtures.

## Validation Commands

```bash
mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/mayor_child_tickets_test.exs apps/babs_citizens/test/babs_citizens/tickets/api_writer_store_test.exs apps/babs/test/babs_web/ticket_presenter_test.exs apps/babs/test/babs_web/live/tickets_live_test.exs
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test --max-cases 1
mise exec -- mix test
mise exec -- mix test --max-cases 1 --cover --export-coverage phase16_4 && mise exec -- mix cmd mix test.coverage
npm run test:js
npm run test:bdd
af validate --root .
git diff --check
git diff -U0 | rg -n '^\+.*(100\.[0-9]{1,3}|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|/Users/[^[:space:]]+|api_token|secret|token)' || true
```

## Results

- Plan review:
  - Trinity fast-review PASS/PASS for GLM and DeepSeek on 2026-05-08.
  - Folded advisories for assigner provenance, idempotency/retry wording,
    reducer ownership of `mayor_children_created`, routing failure stability,
    and browser-harness coverage.
- Implementation:
  - Added `Babs.Citizens.Tickets.MayorChildTickets` as the pure child planning
    and summary-event helper.
  - Approval now materializes child Ticket markdown/history files under the
    configured tickets root, records compact root `mayor_children_created`
    history, and repairs a retry case where children were recorded before the
    approval event.
  - Approval now validates a preflight root `mayor_children_created` marker
    before writing child Tickets, so an oversized root materialization event
    cannot leave unmarked child Ticket files behind.
  - Child materialization now rejects multiline child titles before rendering
    Ticket markdown, matching the normal Ticket creation path.
  - Child Tickets now carry compact Mayor materialization metadata so a retry
    can recover already-written children and repair a missing root marker after
    a transient root-history append failure.
  - Recovery now requires valid child history, repairing a missing child
    `created` event before treating a materialized child as recoverable.
  - Once child materialization has started, proposal edit/remove/reject actions
    are blocked; approval remains available to repair a missing approval/root
    marker.
  - Recovered children must match the current planned child fields, preventing
    stale child Tickets from being recorded for a later edited proposal.
  - Role routing is attempted per child and records `assigned`,
    `not_requested`, or `failed` without deleting created children.
  - Ticket detail renders created child Ticket links, role/inspector badges,
    and routing status after materialization.
  - Browser-harness BDD now includes `mayor proposal approval creates child
    tickets`.
- Implementation review:
  - Trinity fast-review R1 PASS/PASS for GLM and DeepSeek. DeepSeek reported a
    non-blocking stale-revision advisory on the already-materialized return
    path; fixed with a Writer-level guard and regression test.
  - Trinity fast-review R2 PASS/PASS for GLM and DeepSeek after the fix, with
    no blocking findings.
  - GitHub Codex Review R1 found two actionable issues: root materialization
    event validation occurred after child writes, and multiline child titles
    could render as truncated Markdown headings. Both were fixed with regression
    tests before the second GitHub review request.
  - GitHub Codex Review R2 found one additional actionable retry issue after a
    root-history append failure. Fixed by recovering existing materialized
    children from child Ticket metadata before allocating new child IDs.
  - GitHub Codex Review R3 found one additional child audit-trail issue in the
    recovery path. Fixed by requiring or repairing child `created` history
    before recording recovered children in the root marker.
  - GitHub Codex Review R4 found two additional edge cases: edits/rejections
    after materialization had started, and stale recovered children after
    proposal edits. Both were fixed with regression coverage before the fifth
    and final GitHub review request.
- Validation:
  - `mise exec -- mix format --check-formatted`: PASS.
  - `mise exec -- mix compile --warnings-as-errors`: PASS.
  - Focused ExUnit for child materialization/API/Error/Presenter/LiveView:
    PASS, 82 tests.
  - `mise exec -- mix test --max-cases 1`: PASS, 577 tests. One initial
    transient temp-directory cleanup failure was rerun and did not reproduce.
  - `mise exec -- mix test`: PASS, 577 tests.
  - Post-review-fix `mise exec -- mix test --max-cases 1 --cover
    --export-coverage phase16_4 && mise exec -- mix cmd mix test.coverage`:
    PASS. Coverage totals: `:babs_citizens` 86.68%, `:babs` 89.30%.
  - `npm run test:js`: PASS, 15 tests.
  - Focused `BABS_BDD_SCENARIO="mayor proposal approval creates child
    tickets" npm run test:bdd`: PASS.
  - Full `npm run test:bdd` with a temporary SQLite database and temporary
    tickets root: PASS.
  - `npm run test:e2e` with a temporary SQLite database and isolated port:
    PASS, 14 tests.
  - `af validate --root .`: PASS, 171 documents checked.
  - `git diff --check`: PASS.
  - Added-line privacy scan: PASS after triaging the only match,
    `@socket_token`, as an existing public LiveView parameter name rather than
    a secret.
  - Post-Codex-R2 focused ExUnit for Mayor child planning/API/Error paths:
    PASS, 55 tests.
  - Post-Codex-R2 `mise exec -- mix format --check-formatted`: PASS.
  - Post-Codex-R2 `mise exec -- mix compile --warnings-as-errors`: PASS.
  - Post-Codex-R2 `mise exec -- mix test`: PASS, 582 tests.
  - Post-Codex-R2 `npm run test:js`: PASS, 15 tests.
  - Post-Codex-R2 `af validate --root .`: PASS, 171 documents checked.
  - Post-Codex-R2 `git diff --check`: PASS.
  - Post-Codex-R2 added-line privacy scan: PASS, no matches.
  - Post-Codex-R2 validation also stabilized one test-only temporary-directory
    cleanup path that was failing after test assertions had passed.
  - Post-Codex-R3 focused ExUnit for Mayor child planning/API/Error paths:
    PASS, 55 tests.
  - Post-Codex-R3 `mise exec -- mix format --check-formatted`: PASS.
  - Post-Codex-R3 `mise exec -- mix compile --warnings-as-errors`: PASS.
  - Post-Codex-R3 `mise exec -- mix test`: PASS, 582 tests.
  - Post-Codex-R3 `npm run test:js`: PASS, 15 tests.
  - Post-Codex-R3 `af validate --root .`: PASS, 171 documents checked.
  - Post-Codex-R3 `git diff --check`: PASS.
  - Post-Codex-R3 added-line privacy scan: PASS, no matches.
  - Post-Codex-R4 focused ExUnit for Mayor child planning/API/Error paths:
    PASS, 56 tests.
  - Post-Codex-R4 `mise exec -- mix format --check-formatted`: PASS.
  - Post-Codex-R4 `mise exec -- mix compile --warnings-as-errors`: PASS.
  - Post-Codex-R4 `mise exec -- mix test`: PASS, 583 tests.
  - Post-Codex-R4 `npm run test:js`: PASS, 15 tests.
  - Post-Codex-R4 `af validate --root .`: PASS, 171 documents checked.
  - Post-Codex-R4 `git diff --check`: PASS.
  - Post-Codex-R4 added-line privacy scan: PASS, no matches.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial Phase 16.4 child Ticket creation and routing CHG | Codex |
| 2026-05-08 | Mark Approved after Trinity plan review and record implementation/validation results | Codex |
| 2026-05-08 | Record Trinity implementation R1/R2 PASS and post-review stale-revision fix | Codex |
| 2026-05-08 | Fix GitHub Codex R1 root-event preflight and multiline child-title findings | Codex |
| 2026-05-08 | Fix GitHub Codex R2 missing-root-marker retry recovery finding | Codex |
| 2026-05-08 | Fix GitHub Codex R3 child-history recovery audit finding | Codex |
| 2026-05-08 | Fix GitHub Codex R4 materialization edit lock and stale recovery findings | Codex |
