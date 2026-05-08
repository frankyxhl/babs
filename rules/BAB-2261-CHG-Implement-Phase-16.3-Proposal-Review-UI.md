# CHG-2261: Implement Phase 16.3 Proposal Review UI

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

Implement **Phase 16.3: Proposal review UI** from `BAB-2244` (Phase 16 Mayor
Rule Guided Proposals PRP).

This is the third small PR slice for Phase 16 Mayor rule-guided proposals. It
adds the human review surface and persisted human gate decisions for already
validated Mayor proposal artifacts. It must not create child Tickets yet; child
Ticket writing and routing remain Phase 16.4.

This slice will:

- Persist the Phase 16.3 proposal review state as root Ticket history events
  through the existing API -> Writer path only.
- Render a Mayor proposal panel on the root Ticket detail page when a proposal
  artifact exists.
- Render proposed children, roles, priority, inspector policy, risks,
  questions, and opaque rule refs.
- Render a compact root-to-child graph/tree preview as UI only; Ticket files and
  history JSONL remain authoritative.
- Support edit/remove/reject/approve controls with existing icon-button
  conventions.
- Validate edits before appending a revised proposal event.
- Persist approval/rejection decisions as history events that Phase 16.4 can
  consume.
- Keep the ordinary Ticket approval controls independent from Mayor proposal
  approval.

Out of scope:

- Dispatching a Mayor Citizen or injecting prompts into provider sessions.
- Parsing raw Mayor output in the UI.
- Creating child Ticket markdown files.
- Assigning or routing child Tickets.
- Running inspector council checks for child Tickets.
- Automatic proposal approval.
- Cross-machine or mobile Mayor behavior from Phase 17.

Depends on: `BAB-2259` Phase 16.1 Mayor policy/proposal schema and `BAB-2260`
Phase 16.2 Mayor selection/prompt assembly.

## Why

Phase 16.1 defined the Mayor policy/proposal schema, and Phase 16.2 added a
safe side-effect-free planner boundary. The operator now needs a readable,
auditable way to inspect, adjust, and human-gate a proposal before Phase 16.4
turns it into child Tickets.

Persisting review decisions in root Ticket history keeps the flywheel
append-only and makes approval/rejection visible to humans, tests, and later
execution code without introducing a second source of truth.

## Impact Analysis

- **Systems affected:** Ticket history events, Ticket API/Writer proposal
  review actions, Ticket presenter, Ticket detail LiveView, light-theme CSS,
  LiveView tests, Mayor proposal tests.
- **Runtime behavior:** Tickets without Mayor proposal events render as before.
  Mission Tickets with Mayor metadata but no proposal remain normal Tickets
  with a lightweight Mayor-ready state only.
- **Persistence:** root Ticket history JSONL receives proposal review events.
  No child Ticket files are written in this slice.
- **Data model:** latest proposal state is derived from append-only history
  events, not from hidden process state.
- **Alfred boundary:** `rules_refs` remain opaque display strings in the UI.
  Babs does not read, parse, expand, or embed Alfred SOP bodies in this slice.
- **Database:** no migration.
- **UI:** adds a review panel and graph/tree preview to Ticket detail.
- **Privacy:** fixtures and docs must not include raw provider logs, private
  hostnames, private IPs, local checkout paths, tokens, or secrets.
- **Rollback plan:** revert this CHG implementation. Existing Ticket markdown
  and history JSONL remain readable; proposal review events become inert
  history rows until a compatible implementation is restored.
  Future Phase 16.4 code must validate that an approved proposal event still
  has a matching prior proposal artifact or embedded proposal snapshot before
  creating child Tickets.

## Risks and Constraints

- Proposal artifacts can be large. The existing history event byte limit remains
  authoritative; oversized proposal or revision events propagate
  `{:history_event_too_large, ticket_id}` without rewriting Ticket markdown.
- Multiple browser sessions can edit the same proposal. Every review action must
  include the expected `proposal_id`; stale proposal ids or stale child indexes
  fail with stable errors and append no history event.
- A root Ticket has one active proposal in Phase 16.3. A newer
  `mayor_proposal_received` or `mayor_proposal_revised` event supersedes older
  active proposals; approval/rejection applies only to the latest active
  `proposal_id`.
- Removing the final proposed child would make the proposal invalid, so it is
  rejected before persistence.
- The UI graph is only a product aid. Root Ticket markdown and root history
  JSONL remain the source of truth.
- Phase 16.3 does not create the first proposal from a provider response.
  Development and LiveView tests will seed `mayor_proposal_received` events as
  fixtures. A later dispatch/persistence slice may create the same event from a
  parsed Mayor reply.

## History Event Contract

All proposal review events use the existing Ticket history JSONL path and keep
the standard required keys: `ts`, `event`, `by`, and `ticket_id`.
`proposal_id` follows the Phase 16.1 `BAB-2259` rule: `prop_` plus lowercase
letters, digits, underscores, or hyphens. Whenever an event carries both a
top-level `proposal_id` and a nested `proposal.proposal_id`, the two values
must match.

Initial proposal artifact event, seeded by tests in this slice and produced by a
future Mayor-dispatch slice:

```json
{
  "ts": "2026-05-08T00:01:00Z",
  "event": "mayor_proposal_received",
  "by": "flora",
  "ticket_id": "T-...",
  "proposal_id": "prop_...",
  "proposal": {
    "proposal_id": "prop_...",
    "root_ticket_id": "T-...",
    "summary": "Split the mission into focused child Tickets.",
    "rules_refs_used": ["BAB-1503"],
    "children": [{"title": "First child", "body": "Do the first slice."}],
    "risks": [],
    "questions": []
  }
}
```

Revision event:

```json
{
  "ts": "2026-05-08T00:02:00Z",
  "event": "mayor_proposal_revised",
  "by": "user",
  "ticket_id": "T-...",
  "proposal_id": "prop_...",
  "action": "edit_child",
  "child_index": 0,
  "proposal": {
    "proposal_id": "prop_...",
    "root_ticket_id": "T-...",
    "summary": "Split the mission into focused child Tickets.",
    "rules_refs_used": ["BAB-1503"],
    "children": [{"title": "Edited child", "body": "Do the revised slice."}],
    "risks": [],
    "questions": []
  }
}
```

Approval event:

```json
{
  "ts": "2026-05-08T00:03:00Z",
  "event": "mayor_proposal_approved",
  "by": "user",
  "ticket_id": "T-...",
  "proposal_id": "prop_...",
  "proposal": {
    "proposal_id": "prop_...",
    "root_ticket_id": "T-...",
    "summary": "Split the mission into focused child Tickets.",
    "rules_refs_used": ["BAB-1503"],
    "children": [{"title": "First child", "body": "Do the first slice."}],
    "risks": [],
    "questions": []
  }
}
```

Rejection event:

```json
{
  "ts": "2026-05-08T00:03:00Z",
  "event": "mayor_proposal_rejected",
  "by": "user",
  "ticket_id": "T-...",
  "proposal_id": "prop_...",
  "feedback": "Needs a smaller first slice.",
  "proposal": {
    "proposal_id": "prop_...",
    "root_ticket_id": "T-...",
    "summary": "Split the mission into focused child Tickets.",
    "rules_refs_used": ["BAB-1503"],
    "children": [{"title": "First child", "body": "Do the first slice."}],
    "risks": [],
    "questions": []
  }
}
```

The abbreviated `proposal` values above reference the canonical Phase 16.1
proposal schema from `BAB-2259`; implementation tests must use fully valid
proposal maps.
Valid revision `action` values are `"edit_child"` and `"remove_child"`.
For `"remove_child"`, `child_index` is the index in the pre-removal child list.

## Implementation Plan

1. **Review this CHG before code**
   - Run Trinity review with GLM and DeepSeek.
   - Fold blocking findings before implementation.

2. **RED/GREEN: proposal review state**
   - Add a focused helper, tentatively
     `Babs.Citizens.Tickets.MayorProposalReview`.
   - Keep this helper pure: it may reduce already-loaded history, validate
     proposal maps, and construct event maps, but it must not call
     `History.append/3`, `File.write/2`, or any other persistence function.
     Step 3's API -> Writer functions are the sole persistence path.
   - Read the latest proposal artifact from root history events:
     `mayor_proposal_received` or `mayor_proposal_revised`.
   - Validate artifacts through `MayorProposal.normalize/2` using the root
     Ticket Mayor policy bounds.
   - Derive review status from later `mayor_proposal_approved` or
     `mayor_proposal_rejected` events for the same `proposal_id`.
   - Treat `mayor_proposal_received` as fixture-seeded input in this slice;
     provider dispatch and initial event creation from raw Mayor output remain
     outside Phase 16.3.
   - Provide helpers to edit one child, remove one child, approve a proposal,
     and reject a proposal.
   - Construct `mayor_proposal_revised` event maps carrying the full normalized
     proposal snapshot plus an action label of `"edit_child"` or
     `"remove_child"`.
   - Construct approval/rejection event maps only; the Writer persists them.
     No path in Phase 16.3 writes child Tickets.
   - Add unit tests for pending, invalid, revised, approved, rejected, blank
     edit, successful non-last-child removal, remove-last-child, corrupt
     proposal event degradation, and stale proposal id cases.

3. **RED/GREEN: API and Writer actions**
   - Add serialized API functions around the Writer:
     - `revise_mayor_proposal_child(id, proposal_id, child_index, attrs, opts \\ [])`;
     - `remove_mayor_proposal_child(id, proposal_id, child_index, opts \\ [])`;
     - `approve_mayor_proposal(id, proposal_id, opts \\ [])`;
     - `reject_mayor_proposal(id, proposal_id, feedback, opts \\ [])`.
   - `attrs` accepts string or atom keys for `title`, `body`,
     `assignee_role`, `priority`, and `inspector`.
   - `inspector: "user"` clears child inspection metadata; `inspector: "auto"`
     writes normalized default auto inspection metadata using the existing
     inspector role. The edit helper resets `metadata.inspection` before
     calling `MayorProposal.normalize/2` so compact inspector and metadata
     cannot conflict.
   - `opts[:by]` defaults to `"user"` and `opts[:now]` follows the existing
     Ticket Writer timestamp convention.
   - Reuse the existing one-writer-per-Ticket path and history event validation.
   - Accept proposal review actions only while the root Ticket is non-terminal;
     `closed` or `cancelled` Tickets reject edit/remove/approve/reject attempts
     without appending history.
   - Return stable nested errors for no proposal, invalid proposal, stale
     proposal id, invalid child index, invalid edit, empty feedback, and already
     decided proposals.
   - Use these error shapes:
     - `{:mayor_proposal_review, :no_proposal}`;
     - `{:mayor_proposal_review, {:invalid_proposal, reason}}`;
     - `{:mayor_proposal_review, {:stale_proposal_id, expected, actual}}`;
     - `{:mayor_proposal_review, {:invalid_child_index, index}}`;
     - `{:mayor_proposal_review, {:invalid_edit, reason}}`;
     - `{:mayor_proposal_review, :empty_feedback}`;
     - `{:mayor_proposal_review, {:already_decided, status}}`.
   - Add API/Writer tests proving history append behavior and that approval
     does not create child Ticket files.
   - Blank edit fields map through `{:invalid_edit, reason}` using the
     underlying `MayorProposal.normalize/2` reason, such as `{:blank, "title"}`.

4. **RED/GREEN: Ticket detail proposal UI**
   - Add `TicketPresenter.proposal_panel/2`.
   - Assign the proposal panel in `TicketLive.assign_ticket/1`.
   - Render:
     - Mayor-ready state for mission Tickets with Mayor metadata and no
       proposal artifact: a compact disabled proposal panel saying
       "Awaiting Mayor proposal", showing the configured Mayor slug when
       pinned and the opaque `rules_refs`;
     - invalid proposal artifact errors;
     - pending proposal summary;
     - child cards/rows with editable title/body/role/priority/inspector
       fields;
     - per-child `assignee_role`, plus a derived summary of roles used across
       the children;
     - risks, questions, and opaque rules refs. Rule refs render as plain text
       list items, not links, because Babs must not resolve Alfred documents in
       this slice;
     - graph/tree preview root -> children;
     - reject/approve controls.
   - Treat corrupt proposal events as proposal events whose `proposal` payload
     is missing, not a map, or rejected by
     `Babs.Citizens.Tickets.MayorProposal.normalize/2`.
   - Use semantic icons for edit, remove, reject, approve, and graph/tree
     controls, matching the current Babs UI. Add missing `edit`, `trash`,
     and `git-branch` icon paths to `BabsWeb.Icon`; reuse `x` and `check` for
     reject/approve.
   - Render the graph/tree as a compact indented tree: one root node showing
     the root Ticket id/title and one child node per proposed child showing its
     title and route label.
   - Render validation errors in the existing flash error surface and keep
     field-level `data-testid` hooks on the relevant child form row.
   - Disable edit/remove/approve/reject controls after proposal rejection or
     approval.
   - Add LiveView tests for Mayor-ready awaiting state, proposal render,
     validation errors, edit/remove, rejection, approval, icons, and no child
     Ticket creation.

5. **REFACTOR**
   - Keep proposal validation and history reduction outside the LiveView.
   - Extract shared normalization/reduction logic into
     `MayorProposalReview` rather than duplicating it between Writer and
     Presenter paths.
   - Keep form parameter normalization small and local, then pass normalized
     attrs into the pure review helper.
   - Avoid adding a client-side JavaScript state model for proposal edits.
   - Keep CSS reusable for later Phase 16.4 child Ticket creation views.
   - Preserve existing Ticket chat, ordinary approval, and inspection panels.

6. **Validation**
   - Run focused Mayor proposal review/unit/LiveView tests.
   - Run `mix format --check-formatted`.
   - Run `mix compile --warnings-as-errors`.
   - Run `mix test --max-cases 1`.
   - Run full `mix test`.
   - Run exported coverage gate.
   - Run `af validate --root .`.
   - Run `git diff --check`.
   - Run added-line privacy scan.
     Triage false positives by checking whether the matching added line is a
     test/redaction pattern or a real private host/path/token leak.
   - Browser-harness BDD/E2E for the full mission -> proposal -> approve ->
     child Tickets flow is deferred to Phase 16.4, where child Ticket creation
     exists.

7. **Review and PR**
   - Run Trinity implementation review with GLM and DeepSeek.
   - Create the PR with `gh` as `ryosaeba1985`.
   - Follow `COR-1615` / `COR-1612` GitHub Codex loop, max five review rounds.

## Acceptance Criteria

- Tickets without Mayor proposal history render as before.
- Mission Tickets with valid Mayor metadata but no proposal show only a
  lightweight Mayor-ready state and do not dispatch providers.
- A valid persisted proposal renders child list, root-to-child graph/tree
  preview, roles, priority, inspector policy, risks, questions, and opaque rule
  refs.
- Operators can edit child title/body/role/priority/inspector fields, and valid
  edits append a normalized revised proposal event.
- Invalid edits show validation errors and do not append revised proposal
  events.
- Operators can remove proposed children except when that would leave the
  proposal empty.
- Corrupt or malformed proposal history events render a controlled invalid
  proposal panel rather than crashing the Ticket detail page.
- Operators can reject a proposal with feedback; rejection is persisted in root
  history.
- Operators can approve a proposal; approval is persisted in root history, but
  no child Ticket files are created in this slice.
- Proposal approval/rejection controls are disabled after a proposal decision.
- Existing Ticket chat, assignment, inspection, and ordinary approval behavior
  continues to work.
- LiveView tests cover render, validation error, edit/remove, reject, approve,
  and no-child-write behavior.
- No raw secrets, private hostnames, private IPs, local checkout paths, runtime
  Ticket data, or generated proposal data are published in docs, PR body,
  comments, or fixtures.

## Validation Commands

```bash
mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/mayor_proposal_review_test.exs apps/babs_citizens/test/babs_citizens/tickets/api_writer_store_test.exs apps/babs/test/babs_web/ticket_presenter_test.exs apps/babs/test/babs_web/live/tickets_live_test.exs
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test --max-cases 1
mise exec -- mix test
mise exec -- mix test --cover --export-coverage phase16_3 && mise exec -- mix cmd mix test.coverage
af validate --root .
git diff --check
git diff -U0 | rg -n '^\+.*(100\.[0-9]{1,3}|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|/Users/[^[:space:]]+|api_token|secret|token)' || true
```

## Results

- 2026-05-08 Trinity CHG review:
  - Round 1 packet:
    `.trinity/reviews/20260508-211811-rules-BAB-2261-CHG-Implement-Phase-16.3-Proposal-Review-UI.md`.
    GLM PASS; DeepSeek FIX at 8.48/10 with no blocking code-design findings
    but several CHG clarity gaps.
  - Round 2 packet:
    `.trinity/reviews/20260508-212539-rules-BAB-2261-CHG-Implement-Phase-16.3-Proposal-Review-UI.md`.
    GLM PASS; DeepSeek FIX at 8.45/10 with one blocking documentation finding
    around the pure helper vs Writer persistence boundary.
  - Round 3 packet:
    `.trinity/reviews/20260508-213324-rules-BAB-2261-CHG-Implement-Phase-16.3-Proposal-Review-UI.md`.
    GLM PASS; DeepSeek raw output scored 8.95/10 FIX because the draft
    introduced an unnecessary `"human"` inspector alias.
  - Round 4 packet:
    `.trinity/reviews/20260508-213854-rules-BAB-2261-CHG-Implement-Phase-16.3-Proposal-Review-UI.md`.
    GLM PASS at 9.2/10 and DeepSeek PASS at 9.0/10, with no blocking
    findings.
  - Folded review guidance for event provenance, exact API signatures, event
    payload schemas, pure-helper vs Writer persistence boundary, single active
    proposal semantics, root terminal-state guards, `proposal_id` consistency,
    inspector metadata edit semantics, graph/tree rendering shape, and
    Phase 16.4 BDD/E2E deferral.
- 2026-05-08 implementation:
  - Added `Babs.Citizens.Tickets.MayorProposalReview` as a pure history
    reducer and proposal review event constructor.
  - Added serialized Ticket API/Writer actions for proposal child edit,
    proposal child removal, proposal approval, and proposal rejection.
  - Added user-facing proposal review errors, including invalid policy,
    invalid proposal, stale proposal, invalid edit, empty feedback, already
    decided, and terminal Ticket cases.
  - Added `TicketPresenter.proposal_panel/2` and Ticket detail LiveView
    rendering for Mayor-ready, invalid, pending, approved, and rejected
    proposal states.
  - Added icon paths and CSS for proposal review cards, controls, and compact
    root-to-child graph/tree preview.
  - Added tests for pure review reduction, API/Writer append behavior,
    Presenter state projection, and LiveView edit/remove/reject/approve flows.
- 2026-05-08 validation:
  - Focused Phase 16.3 suite passed: 77 tests.
  - `mise exec -- mix format --check-formatted` passed.
  - `mise exec -- mix compile --warnings-as-errors` passed.
  - `mise exec -- mix test --max-cases 1` passed: `babs_citizens` 468 tests,
    `babs` 102 tests.
  - `mise exec -- mix test` passed: `babs_citizens` 468 tests, `babs` 102
    tests.
  - Coverage passed: `babs_citizens` 86.18%, `babs` 89.14%.
  - `npm run test:js` passed: 15 tests.
  - `npm run test:bdd` was attempted for regression signal but browser-harness
    produced no scenario output and was interrupted after the connector stalled;
    the Phase 16.3 CHG explicitly defers the full browser-harness mission ->
    proposal -> approve -> child Ticket flow to Phase 16.4.
  - `af validate --root .` passed: 170 documents checked, 0 issues.
  - `git diff --check` passed.
  - Added-line privacy scan found only expected CHG privacy-policy/scan-pattern
    text; no private runtime data, host-specific address, local checkout path,
    raw provider output, or credential was added.
- 2026-05-08 Trinity implementation review:
  - Initial implementation packet:
    `.trinity/reviews/20260508-220005-Phase-16.3-proposal-review-ui`.
    GLM PASS; DeepSeek FIX with blocking findings for CSS source/static
    fallback divergence and a potentially crashing inspector normalization
    pattern. Both were fixed before PR.
  - Fixed implementation packet:
    `.trinity/reviews/20260508-221223-Phase-16.3-proposal-review-ui`.
    GLM PASS; DeepSeek PASS with only non-blocking observations.
  - Advisory cleanup packet:
    `.trinity/reviews/20260508-221906-Phase-16.3-proposal-review-ui`.
    GLM PASS; DeepSeek raw output reported non-blocking CSS source/static
    concerns, so the new proposal styles were simplified to avoid new
    `color-mix()` fallback generation.
  - Final implementation packet:
    `.trinity/reviews/20260508-223154-Phase-16.3-proposal-review-ui`.
    GLM PASS and DeepSeek PASS, with no blocking findings.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial Phase 16.3 proposal review UI CHG | Codex |
