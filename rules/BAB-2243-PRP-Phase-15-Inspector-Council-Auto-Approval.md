# PRP-2243: Phase 15 Inspector Council Auto-Approval

**Applies to:** BAB project
**Last updated:** 2026-05-07
**Last reviewed:** 2026-05-07
**Status:** Approved
**Date:** 2026-05-07
**Requested by:** Operator
**Priority:** High

---

## What Is It?

Add Phase 15: Inspector Council Auto-Approval.

Phase 15 lets Babs ask one or more Citizen inspectors to decide whether a
Ticket in `pending_approval` should be approved or rejected. This is Ticket
lifecycle inspection, not GitHub PR review automation. The human operator stays
the default inspector until a Ticket or configuration explicitly enables
automatic inspection.

The operator decision for Phase 15 is broader than the original roadmap: the
approval decision may be made by another Citizen or by multiple Citizens. The
single-inspector path is therefore a special case of an Inspector Council.

## Problem

V0-M made Tickets durable and conversational, but the approval step still
depends on the human operator:

- A Citizen can move work to `pending_approval`.
- The Ticket UI can approve or reject.
- Cross-Citizen comments and direct CLI replies are persisted.
- Phase 14 will provide multi-role routing.

The flywheel still stalls when the operator must manually inspect every
`pending_approval` Ticket. That is acceptable for early dogfood, but Phase 15 is
where Babs starts reducing the operator approval bottleneck.

The old roadmap described a dedicated Citizen with `role: inspector`. That is
too narrow now that Phase 14 supports multi-role Citizens and the operator wants
multiple Citizens to judge when useful.

Concrete gaps:

- No Ticket-level policy decides whether approval is human or automatic.
- No Inspector Council selection exists.
- No durable history events represent inspection requests and decisions.
- No structured decision parser distinguishes `approve`, `reject`, and
  unparseable inspector replies.
- No quorum reducer can combine decisions from multiple inspectors.
- The UI cannot show pending inspector decisions or explain why a Ticket was
  auto-approved or rejected.

## Dependencies

- Phase 13a multi-turn Ticket sessions provide turn/attempt correlation for
  inspection prompt delivery and captured replies.
- Phase 13f provider runtime contracts provide capability and timeout surfaces
  for direct CLI and Hardline-backed Citizens.
- Phase 14 multi-role routing provides normalized roles for inspector
  selection.
- Phase 11 human approval UI remains the fallback and override path.

## Proposed Solution

### 1. Inspection Policy

Keep the existing top-level Ticket `inspector` field for compatibility and
compact display. Add structured inspection policy under Ticket `metadata`:

```yaml
inspector: user
metadata:
  inspection:
    mode: human        # human | auto
    strategy: single   # single | council
    roles: ["inspector"]
    citizens: []
    quorum: all_pass
    max_inspectors: 3
    allow_self_inspection: false
```

Rules:

- `mode: human` preserves current Phase 11 behavior.
- `mode: auto` lets Babs select inspector Citizens and request decisions.
- `strategy: single` selects one inspector.
- `strategy: council` selects up to `max_inspectors` inspectors.
- `roles` uses Phase 14 normalized Citizen roles.
- `citizens` optionally pins named inspector Citizens.
- Named Citizens and role-selected Citizens can be combined, then de-duplicated.
- `allow_self_inspection: false` excludes current assignees by default.
- If no eligible inspector is available, Babs leaves the Ticket in
  `pending_approval` and marks inspection as requiring human action.

The first implementation should support `quorum: all_pass`. Other quorum modes
such as `majority` or `any_pass` can be schema-reserved but must not silently
behave differently until implemented.

When a Ticket transitions to `pending_approval`, Babs checks
`metadata.inspection.mode`. If it is `auto`, inspector selection begins. If it
is missing or `human`, current human approval behavior remains unchanged.

### 2. Inspector Selection

Inspector selection builds on Phase 14 role routing:

- Candidate Citizens must be non-stale, known to Babs, and eligible for Ticket
  execution through their configured backend.
- Candidate Citizens must have at least one requested inspection role or be
  explicitly named in `metadata.inspection.citizens`.
- Current assignees are excluded unless `allow_self_inspection` is true.
- Failed Citizens and external-owned Citizens without injection/execution
  capability are excluded.
- Tie-breaking should be deterministic: named Citizens first in configured
  order, then role-matched Citizens by least-recent inspection assignment, then
  slug order.

The selected inspector list is persisted to history before any prompt is sent,
so the operator can audit who was asked.

### 3. Inspection History Events

Represent inspection as Ticket history events. Suggested events:

```jsonl
{"event":"inspection_requested","ticket_id":"T-...","inspection_id":"insp_...","by":"system","policy":{...},"inspectors":["clare","dylan"]}
{"event":"inspection_prompt_delivered","ticket_id":"T-...","inspection_id":"insp_...","to":"clare","turn_id":"turn_...","attempt_id":"attempt_..."}
{"event":"inspection_decision","ticket_id":"T-...","inspection_id":"insp_...","by":"clare","decision":"approve","summary":"...","findings":[]}
{"event":"inspection_failed","ticket_id":"T-...","inspection_id":"insp_...","by":"system","to":"dylan","reason":"timeout"}
{"event":"inspection_completed","ticket_id":"T-...","inspection_id":"insp_...","result":"approved","quorum":"all_pass"}
```

History events must be appended through the existing per-ticket Writer. The
Ticket markdown frontmatter remains the state source of truth; history explains
how the decision happened.

Inspection prompts and inspector replies should also render as normal Ticket
chat messages where useful. The operator must be able to read the actual
reasoning before accepting the automation as trustworthy.

Inspection prompt delivery may use any existing eligible Ticket execution
backend: `direct_cli`, `hardline`, or later `lazy_tmux`. `turn_id` and
`attempt_id` should be used when the backend participates in the Phase 13a turn
model. Backend-specific failures and timeouts must be normalized into
`inspection_failed` without exposing raw provider output.

### 4. Inspector Prompt And Reply Contract

The inspection prompt should include:

- Ticket id, title, state, priority, assignees, and acceptance criteria.
- The Ticket body.
- Recent visible Ticket chat messages and captured replies.
- A concise delivery/status summary for the assignee work.
- The inspector's requested decision contract.

The prompt must not include raw local paths, private IPs, hostnames, env maps,
tokens, or raw provider transcripts. It should use the same redaction principles
as Phase 13a/13f prompt assembly.

Inspector replies should be captured as visible comments and parsed for a
structured decision. The first implementation can require a fenced JSON object:

```json
{
  "decision": "approve",
  "summary": "The acceptance criteria are met.",
  "findings": []
}
```

Allowed decisions:

- `approve`
- `reject`
- `needs_changes`

`needs_changes` is equivalent to `reject` for the Ticket state machine, but the
separate value is useful in the UI and history. If parsing fails, Babs persists
the raw visible comment as a normal comment, records `inspection_failed`, and
requires human action instead of guessing.

### 5. Quorum Reducer

For `quorum: all_pass`:

- All selected inspectors must return `approve` before Babs transitions the
  Ticket from `pending_approval` to `closed`.
- Any `reject` or `needs_changes` transitions the Ticket back to `in_progress`
  with synthesized feedback in history.
- Any failed/unparseable inspector decision leaves the Ticket in
  `pending_approval` and marks it as requiring human action.

Every automatic transition must append a normal `state_change` event with
`by: system` plus the related `inspection_id`.

Inspector non-response is a failure path, not an implicit rejection or approval.
Implementation CHGs should use provider/runtime timeouts from Phase 13f where
available. On timeout or cancelled delivery, Babs records `inspection_failed`
and requires human action.

Human override remains available at all times. The operator can approve, reject,
or cancel a Ticket even while inspection is pending.

### 6. UI

Update the Ticket approval UI:

- Show inspection mode: Human, Auto single, or Auto council.
- Show selected inspectors and per-inspector status.
- Render verdict badges for approve/reject/needs-changes/unparseable.
- Show the reason summary and findings in the Ticket chat/approval panel.
- Keep existing human approve/reject buttons visible as override controls.
- Allow Ticket create/edit flows to choose Human approval or Auto inspection
  from known inspector roles/Citizens.

Buttons introduced for inspection actions should include icons and match the
existing light-theme Babs UI.

## Out of Scope

- GitHub PR code review automation.
- Trinity/Codex review orchestration.
- Mayor ticket decomposition or proposal approval.
- Remote-node inspection or cross-machine Citizen control.
- Role permissions/security scopes beyond inspection eligibility.
- Learning long-term inspector quality scores.
- Implementing `majority` or `any_pass` quorum behavior unless a later CHG
  explicitly scopes it.

## Implementation Slices

Phase 15 should be delivered in small reviewed PRs:

1. **15.1 Inspection policy and events**
   - Add inspection metadata validation.
   - Add `inspection_*` event helpers and tests.
   - Preserve existing human approval behavior.

2. **15.2 Inspector selection and prompt assembly**
   - Select named and role-based inspector Citizens.
   - Exclude stale/failed/self inspectors by default.
   - Add redacted prompt assembly fixtures.

3. **15.3 Decision capture and quorum**
   - Capture structured inspector replies.
   - Implement `all_pass` quorum.
   - Add state-machine integration tests for approve, reject, needs-changes,
     parse failure, and human override.

4. **15.4 UI, BDD, and E2E**
   - Add approval-panel UI for inspection status.
   - Add browser-harness BDD for one auto-approved Ticket and one rejected
     Ticket.
   - Add council coverage with two fake inspectors.
   - Verify existing human approval UI still works.

## Acceptance Criteria

- Existing `inspector: user` Tickets behave exactly as before.
- A Ticket can opt into automatic inspection through structured metadata.
- Babs can select one inspector Citizen by role or by explicit slug.
- Babs can select a small council of inspector Citizens.
- Assignee Citizens are excluded from inspecting their own work by default.
- Inspector prompts are redacted, fixture-tested, and visible/auditable through
  Ticket history.
- Parsed `approve` decisions can close a Ticket when quorum passes.
- Parsed `reject` or `needs_changes` decisions return the Ticket to
  `in_progress` with feedback.
- Unparseable inspector output never auto-approves.
- Human override remains available and tested.
- UI shows inspection mode, selected inspectors, statuses, decisions, and
  reasoning without collapsing into raw event dumps.
- BDD/E2E coverage proves at least one auto-approve path and one reject path.
- No raw secrets, private hostnames, private IPs, local checkout paths, or
  runtime Ticket data are published in docs, PR body, comments, or fixtures.

## Validation Plan

Each implementation CHG under Phase 15 should include focused tests first, then
the standard Babs validation stack where practical:

```bash
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
mise exec -- mix test --cover
npm run test:js
npm run test:e2e
npm run test:bdd
af validate --root .
git diff --check
```

For docs-only PRP work, `af validate --root .` and `git diff --check` are
sufficient locally; the GitHub Actions Test workflow provides the broader CI
gate after PR creation.

## Review Plan

- Review this PRP with Trinity `fast-review` and fold blockers before
  implementation CHGs.
- Implementation CHGs should update `BAB-1002` vocabulary so Inspector wording
  describes a Citizen role/council selected through `roles`, not only singular
  `role: inspector`.
- Each implementation CHG must follow `BAB-1503` / `COR-1616`.
- GitHub PRs must use the correct project GitHub identity and follow
  `COR-1612` + `COR-1615` review loops.
- Maximum five GitHub Codex review rounds per PR unless the operator explicitly
  extends the loop.

## Open Questions

None for the PRP. Implementation CHGs may still choose the exact UI control
shape and parser error messages after reading the current Ticket LiveView code.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-07 | Initial Phase 15 PRP for Inspector Council auto-approval | Codex |
| 2026-05-07 | Trinity R1 fast-review passed GLM and DeepSeek; folded advisories for Inspector Council roadmap heading, explicit pending-approval trigger, dependencies, timeout/failure handling, Hardline/direct backend support, inspection_failed events, and vocabulary follow-up | Codex |
