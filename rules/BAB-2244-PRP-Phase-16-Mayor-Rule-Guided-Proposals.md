# PRP-2244: Phase 16 Mayor Rule-Guided Proposals

**Applies to:** BAB project
**Last updated:** 2026-05-07
**Last reviewed:** 2026-05-07
**Status:** Approved
**Date:** 2026-05-07
**Requested by:** Operator
**Priority:** High

---

## What Is It?

Add Phase 16: Mayor Rule-Guided Proposals.

Phase 16 introduces a Mayor Citizen that watches the Billboard for unassigned
mission-style Tickets and proposes child Ticket plans. The Mayor does not
directly execute work or silently create a large ticket tree. It produces an
auditable proposal that the human operator can review, edit, approve, or reject.

The operator wants the Mayor to eventually use Alfred-like rules. Phase 16 keeps
the existing Babs-Alfred boundary from `BAB-1108`: Babs does not parse SOP
documents. Instead, Babs records rule references in Ticket metadata and prompts
the Mayor Citizen to use `af` directly when composing a proposal.

## Problem

By Phase 15, Babs can route work by role and ask Inspector Citizens to approve
or reject completed Tickets. The next flywheel bottleneck is decomposition:

- The operator still has to break large work into child Tickets.
- Role routing cannot help if the parent Ticket does not describe the needed
  roles or child scopes.
- Inspector automation can judge completed work, but it cannot decide what work
  should exist.
- Alfred SOPs and Babs PRJ rules are useful planning material, but Babs should
  not become an Alfred parser.

The original roadmap described a Mayor that outputs `bb propose ...` and creates
draft tickets. That captures the direction, but Phase 16 needs a safer product
contract before implementation:

- proposals must be persisted and reviewable;
- proposal approval must be human-gated;
- rule references must be explicit and auditable;
- generated child Tickets must stay under the configured tickets root, not git;
- role routing and inspector policy must remain visible in the proposed output.

## Dependencies

- `BAB-1108`: Citizens use Alfred for SOP composition; Babs treats rule/SOP
  references as opaque text.
- `BAB-1002`: Mayor vocabulary and Ticket vocabulary define the operator-facing
  concepts this phase extends.
- Phase 14: normalized roles and role-based routing.
- Phase 15: optional Inspector Council policy for child Tickets.
- `BAB-1111`: `mission` and `proposal` Ticket types are schema-reserved.
- Phase 13a/13f: provider runtime and turn/session behavior for Mayor prompts.

## Proposed Solution

### 1. Mayor Citizen Eligibility

A Mayor is a normal Citizen with Mayor metadata:

- `is_mayor: true` in SQLite.
- A normalized role such as `mayor` or `planner`.
- A provider/backend capable of receiving Ticket turns.
- A Babs-owned workspace by default.

The first implementation should support one active Mayor. Multiple Mayor
Citizens can exist in the registry, but automatic proposal assignment should use
one selected/default Mayor until a later CHG defines Mayor election or councils.

Imported external-owned Citizens must not become automatic Mayors unless the
operator explicitly configures them for proposal execution.

### 2. Mayor Policy

Root Tickets can opt into Mayor planning through metadata:

```yaml
type: mission
assignees: []
assignee_role: null
metadata:
  mayor:
    mode: propose
    mayor: null
    rules_refs: ["BAB-1503", "COR-1616"]
    max_children: 5
    allowed_roles: ["developer", "inspector"]
    require_human_approval: true
```

Rules:

- `mode: propose` means Babs may ask a Mayor to create a proposal.
- `mayor: null` uses the default eligible Mayor; a slug pins a Mayor.
- `rules_refs` are opaque references passed to the Mayor prompt. Babs may
  validate that they are strings, but it must not parse their contents.
- `max_children` bounds proposal size.
- `allowed_roles` limits suggested `assignee_role` values to known or
  operator-approved roles. The example uses defined roles only; deployments may
  add roles such as `designer` through Phase 14 role configuration.
- `require_human_approval: true` is mandatory in Phase 16.

Tickets without Mayor metadata remain normal Billboard Tickets. Phase 16 should
not surprise the operator by automatically decomposing every unassigned Ticket.

### 3. Proposal Artifact

The Mayor returns a structured proposal that Babs persists as a `proposal`
Ticket or as proposal events attached to the root Ticket. The implementation CHG
may choose the storage shape, but it must preserve these fields:

```json
{
  "proposal_id": "prop_...",
  "root_ticket_id": "T-...",
  "summary": "Break the work into backend, frontend, validation, and docs.",
  "rules_refs_used": ["BAB-1503", "COR-1616"],
  "children": [
    {
      "title": "Implement role router",
      "type": "assignment",
      "body": "Scope and acceptance criteria...",
      "assignee_role": "developer",
      "inspector": "auto",
      "metadata": {
        "inspection": {"mode": "auto", "roles": ["inspector"]}
      }
    }
  ],
  "risks": [],
  "questions": []
}
```

Proposal persistence must use the existing Ticket Writer/history path. The raw
Mayor output is not authoritative until parsed, redacted, validated, and
persisted as a proposal artifact.

Child `metadata.inspection` is the canonical structured inspection policy from
Phase 15. The child-level `inspector` value is retained only because the Ticket
frontmatter schema already has a compact top-level `inspector` field. Proposal
validation should derive the compact `inspector` value from
`metadata.inspection` when it is omitted, and reject conflicts when both are
present but disagree.

`risks` and `questions` are lists of strings in Phase 16. Structured risk
objects, severities, owners, or due dates are future project-management scope.

### 4. Human Approval Gate

The operator reviews proposals before child Tickets are written:

- View root Ticket, proposed children, role routes, inspection policy, rules
  refs, risks, and open questions.
- Edit child title/body/role/priority/inspection policy before approval.
- Remove unwanted children.
- Reject the proposal with feedback.
- Approve the proposal to create child Tickets under the configured tickets
  root.

On approval:

- Each child Ticket gets `parent_ticket` set to the root Ticket id.
- Each child Ticket records `assigner: mayor` or equivalent provenance.
- Child Tickets remain runtime data under the tickets root.
- Role routing may assign children according to Phase 14 behavior.
- Inspector policy may be attached according to Phase 15 behavior.
- The root Ticket history records which child Ticket ids were created.

No Phase 16 path may commit Tickets to git or create external GitHub artifacts.

### 5. Mayor Prompt Contract

Mayor prompts should include:

- Root Ticket id/title/body/state/priority.
- Current Ticket conversation summary.
- Known role labels and eligible Citizen summaries.
- Current inspection policy options.
- `rules_refs` and a plain instruction that the Mayor may run `af read` or
  `af plan` itself when useful.
- The structured proposal reply contract.

Babs must not load full SOP contents into the prompt. The Mayor Citizen is
responsible for invoking `af` under the convention in `BAB-1108`.

If the Mayor reply cannot be parsed or violates policy, Babs persists a failure
event and leaves the root Ticket on the Billboard for human action.

### 6. UI

Add a proposal review surface:

- Billboard/root Ticket shows "Ask Mayor" or "Proposal pending" state.
- Proposal page/panel renders child Tickets as editable rows/cards.
- A compact graph/tree view shows root -> proposed children.
- Each child shows assignee role, inspector policy, priority, and validation
  errors.
- Approve/reject/edit controls use semantic icons and match the existing
  light-theme Babs UI.
- Proposal history remains visible in the Ticket chat/history stream.

The graph is a product aid, not the data model. Ticket files and history JSONL
remain authoritative.

## Out of Scope

- Automatic proposal approval without a human gate.
- Mayor election, Mayor councils, or conflict resolution between Mayors.
- Babs-side parsing of Alfred SOP documents.
- Cross-machine Mayor operation from Phase 17.
- Creating GitHub issues, PRs, branches, or commits from Mayor proposals.
- Long-term learning of which proposal strategies perform best.
- Full project management features such as estimates, capacity planning, or
  dependency scheduling beyond parent/child Tickets.

## Implementation Slices

Phase 16 should be delivered in small reviewed PRs:

1. **16.1 Mayor policy and proposal schema**
   - Add Mayor metadata validation.
   - Add proposal artifact parser/validator fixtures.
   - Preserve normal Billboard behavior for Tickets without Mayor metadata.

2. **16.2 Mayor selection and prompt assembly**
   - Select the default/pinned Mayor Citizen.
   - Build redacted Mayor prompts with role summaries and opaque rule refs.
   - Add parser-failure and policy-violation tests.

3. **16.3 Proposal review UI**
   - Render proposal child list and graph/tree preview.
   - Support edit/remove/reject/approve controls with icons.
   - Add LiveView tests for validation errors and approval flow.

4. **16.4 Child Ticket creation and routing**
   - Write approved child Tickets under the configured tickets root.
   - Persist root history events for created children.
   - Trigger Phase 14 role routing where requested.
   - Preserve Phase 15 inspection metadata on children.
   - Add BDD/E2E for mission -> proposal -> approve -> child Tickets.

## Acceptance Criteria

- A Mayor Citizen can be marked eligible without changing ordinary Citizen
  lifecycle behavior.
- A mission Ticket can opt into Mayor proposal mode through metadata.
- Babs passes `rules_refs` to the Mayor as opaque references and does not parse
  Alfred documents.
- A Mayor can return a structured proposal with child Tickets, roles,
  inspection policy, risks, and questions.
- Invalid or unparseable Mayor output never creates child Tickets.
- The operator can review, edit, remove, reject, and approve proposed children.
- Approved children are written under the configured tickets root with
  `parent_ticket` set to the root Ticket id.
- Role routing and inspection metadata are preserved for approved child Tickets.
- The UI shows a readable proposal list and root-to-children graph/tree preview.
- BDD/E2E coverage proves one human-approved Mayor proposal flow.
- No raw secrets, private hostnames, private IPs, local checkout paths, runtime
  Ticket data, or generated proposal data are published in docs, PR body,
  comments, or fixtures.

## Validation Plan

Each implementation CHG under Phase 16 should include focused tests first, then
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
- Implementation CHGs should update `BAB-1002` vocabulary if Mayor wording
  needs to mention rule refs, proposal artifacts, or graph previews.
- Each implementation CHG must follow `BAB-1503` / `COR-1616`.
- GitHub PRs must use the correct project GitHub identity and follow
  `COR-1612` + `COR-1615` review loops.
- Maximum five GitHub Codex review rounds per PR unless the operator explicitly
  extends the loop.

## Open Questions

None for the PRP. Implementation CHGs may still choose whether the proposal is
stored as a separate `proposal` Ticket or as proposal events attached to the
root Ticket, provided the operator review and child-creation behavior remains
the same.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-07 | Initial Phase 16 PRP for Mayor rule-guided proposals | Codex |
| 2026-05-07 | Trinity R1 fast-review passed GLM and DeepSeek; folded advisories for roadmap heading, BAB-1002 dependency, child inspector policy precedence, risks/questions schema, and allowed_roles example clarity | Codex |
