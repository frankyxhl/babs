# CHG-2256: Implement Phase 15.2 Inspector Selection and Prompts

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

Implement **Phase 15.2: inspector selection and prompt assembly** from
`BAB-2243`.

This is the second small PR slice for Phase 15 Inspector Council
auto-approval. Phase 15.1 added policy validation and durable inspection event
constructors. Phase 15.2 selects eligible Inspector Citizens and builds a
redacted, auditable prompt for each selected inspector.

Scope:

- Add an `InspectorSelector` service that selects Citizens from a Ticket's
  normalized `metadata.inspection` policy.
- Support explicit `citizens` and role-based `roles` selection.
- Exclude current assignees by default unless `allow_self_inspection` is true.
- Exclude failed, stale SQLite-only, busy, and imported external Citizens that
  cannot receive Ticket execution. In this slice, "stale SQLite-only" means a
  Citizen row that is present in SQLite but is neither backed by a current
  configured TOML file nor marked as an executable imported external session.
- Keep deterministic tie-breaking:
  - explicit Citizens first, in policy order;
  - then role-matched Citizens by least-recent inspection assignment;
  - then slug order.
- Enforce `max_inspectors` and return a clear human-action error when no
  eligible inspector exists.
- Add an inspection prompt assembler that includes Ticket metadata, body,
  recent visible conversation, selected inspector identity, and the structured
  decision contract.
- "Recent visible conversation" means human/Citizen-authored chat messages and
  captured replies derived from the existing `Conversation` model, not internal
  system/audit events such as assignments, transitions, or inspection event
  maps.
- Reuse the existing prompt redaction behavior so prompts do not expose local
  paths, private IPs, hostnames, env maps, tokens, secrets, or raw provider
  transcripts.
- Add a request helper that appends `inspection_requested` plus
  `inspection_prompt_delivered` history events through the existing
  per-ticket Writer without parsing decisions or changing Ticket state.
- Keep `mode: human` and missing inspection metadata on the existing Phase 11
  human approval path.

Out of scope:

- Parsing inspector replies. That is Phase 15.3.
- Quorum reduction and automatic state transitions. That is Phase 15.3.
- UI, BDD, and E2E inspection panels. That is Phase 15.4.
- New database tables or migrations.
- Remote-node inspection or federated Citizen selection.

## Why

Phase 15 cannot safely auto-approve work until Babs can first answer two
auditable questions: who was asked to inspect, and exactly what prompt they saw.
This slice adds that foundation without allowing any Citizen reply to mutate
Ticket approval state.

Separating selection/prompting from reply parsing keeps the blast radius small:
operator-visible history can show that an inspection was requested and which
Citizens were prompted, while all actual decisions still require later Phase
15.3 logic.

## Impact Analysis

- **Systems affected:** Citizen catalog querying, Ticket policy execution,
  Ticket prompt assembly, Ticket history append path, focused Ticket tests.
- **Runtime behavior:** Tickets with `metadata.inspection.mode: auto` can have
  inspectors selected and prompts assembled/appended to history. They do not
  auto-approve, auto-reject, or transition state in this slice.
- **Human path:** Tickets without inspection metadata or with `mode: human`
  continue to use the existing human approval behavior.
- **Database:** no schema change.
- **Runtime data:** selected inspector lists and prompt-delivery attempts are
  appended to Ticket history only. Ticket markdown remains the state source of
  truth.
- **Privacy:** prompt fixtures and PR/docs must not include private hostnames,
  private IPs, local checkout paths, env maps, tokens, secrets, or raw provider
  transcripts.
- **Rollback:** revert this CHG implementation. Existing Tickets remain valid
  because Phase 15.1 policy metadata and history events are additive.

## Implementation Plan

1. **Review this CHG before code**
   - Run Trinity `fast-review` against this CHG.
   - Fold blockers and update status before implementation.

2. **RED: add inspector selector tests**
   - Explicit Citizens are selected in policy order.
   - Role-matched Citizens are selected by least-recent inspection assignment,
     then slug.
   - Current assignees are excluded unless `allow_self_inspection` is true.
   - Cover `allow_self_inspection` for both explicit Citizen and role-matched
     selection paths; the flag gates self-exclusion for all candidate sources.
   - Failed, stale SQLite-only, busy, and external non-executable Citizens are
     excluded.
   - Missing eligible inspectors returns a clear error that callers can route
     to human action.

3. **GREEN: implement inspector selector**
   - Add `Babs.Citizens.Tickets.InspectorSelector`.
   - Use `InspectionPolicy.from_metadata/1` for policy normalization.
   - Use `Catalog.list_configured_or_imported_citizens/1` by default, with a
     test override for Citizen records.
   - Use existing role normalization from `Catalog.to_config/1` and
     `Babs.Citizens.Roles`.
   - Use existing execution-lock state to exclude busy Citizens.
   - Scan all Ticket history files under the active Ticket root for prior
     `inspection_requested` events to support least-recent role tie-breaking.
     Do not reuse RoleRouter's `assigned`-event tie-breaker.

4. **RED/GREEN: add redacted inspection prompt assembly**
   - Add `PromptAssembler.inspection_prompt/4` or an equivalent small helper
     with a contract equivalent to
     `(ticket, history_or_conversation, inspector_slug, inspection_opts)`.
   - Include Ticket id, title, state, priority, assignees, body, recent visible
     chat messages, selected inspector slug, inspection id, and a fenced JSON
     decision contract.
   - Keep prompt redaction centralized in `PromptAssembler`; if the existing
     sanitizer needs to be reused by the new helper, prefer a private helper in
     the same module rather than exposing a new public sanitizer API.
   - Reuse the existing prompt sanitizer and add regression coverage for local
     paths, private IPs, hostnames, and secret-looking strings.

5. **RED/GREEN: add request helper and history tests**
   - Add a small public API/Writer path to request inspection for a
     `pending_approval` Ticket.
   - Append `inspection_requested` before any prompt-delivered event.
   - Append one `inspection_prompt_delivered` event per selected inspector with
     generated `turn_id` and `attempt_id`.
   - Do not parse replies or change state.
   - Return the selected inspectors and generated prompts so the UI/next phase
     can display/audit them.

6. **Validation**
   - Run focused selector, prompt, and API/Writer tests.
   - Run `mix format --check-formatted`.
   - Run `mix compile --warnings-as-errors`.
   - Run `mix test --max-cases 1` to match GitHub CI ordering.
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

- Existing human approval Tickets remain unchanged.
- Auto inspection policy selects explicit Citizens by slug.
- Auto inspection policy selects role-based Citizens by Phase 14 roles.
- Current assignees are excluded by default and included only when
  `allow_self_inspection` is true, for both explicit and role-based selection.
- Failed, stale, busy, and non-executable imported Citizens are excluded.
- Selection honors `max_inspectors` and deterministic ordering.
- `inspection_requested` is appended before prompt-delivery events.
- Prompt-delivery events include stable `inspection_id`, `turn_id`, and
  `attempt_id` fields.
- Inspection prompts are redacted and fixture-tested.
- No inspector reply parsing, quorum, or automatic state transition exists in
  this slice.

## Validation Commands

```bash
mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/inspector_selector_test.exs
mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/prompt_assembler_test.exs
mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/api_writer_store_test.exs
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test --max-cases 1
mise exec -- mix test
mise exec -- mix test --cover --export-coverage phase15_2 && mise exec -- mix cmd mix test.coverage
af validate --root .
git diff --check
git diff -U0 | rg -n '^\+.*(100\.122|wukong|/Users/frank|api_token|secret|token)'
```

## Results

- 2026-05-08 Trinity CHG review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-145635-rules-BAB-2256-CHG-Implement-Phase-15-2-Inspector-Selection-and-Prompts.md`.
  - GLM PASS and DeepSeek PASS; no blocking findings.
  - Folded advisories for concrete stale SQLite-only meaning, visible chat
    message scope, self-inspection behavior across explicit and role-matched
    paths, all-history `inspection_requested` tie-breaking, prompt helper
    contract, and private sanitizer reuse.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial Phase 15.2 inspector selection and prompt CHG | Codex |
| 2026-05-08 | Mark Approved after Trinity fast-review GLM and DeepSeek PASS; fold non-blocking advisories | Codex |
