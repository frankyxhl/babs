# CHG-2260: Implement Phase 16.2 Mayor Selection and Prompt Assembly

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

Implement **Phase 16.2: Mayor selection and prompt assembly** from `BAB-2244`.

This is the second small PR slice for Phase 16 Mayor rule-guided proposals. It
does not dispatch a provider turn, persist proposal artifacts, create child
Tickets, or add proposal review UI. It adds the pure preparation layer that
later slices can call safely:

- Select a Mayor Citizen for a mission Ticket that already opted into
  `metadata.mayor.mode: "propose"`.
- Support pinned Mayor selection through `metadata.mayor.mayor`.
- Support deterministic default Mayor selection for one active Mayor rollout.
- Exclude imported external-owned Citizens from automatic default Mayor
  selection; pinned selection remains explicit operator intent and still
  requires Mayor eligibility.
- Build a redacted Mayor prompt that contains Ticket context, recent
  conversation context, role/citizen summaries, inspection options, opaque
  `rules_refs`, and the structured proposal reply contract.
- Keep Alfred/Babs boundary intact: Babs passes `rules_refs` and tells the
  Mayor it may run `af read` / `af plan`; Babs must not load SOP bodies.
- Add a no-side-effect reply parser entrypoint that validates Mayor replies
  against the selected policy bounds before any persistence or child creation
  exists.

Out of scope:

- Marking Citizens as Mayor through UI.
- Provider dispatch or hardline/direct-CLI injection.
- Persisting proposal success/failure events.
- Proposal review UI.
- Approving/rejecting proposals.
- Writing child Tickets.
- Mayor election, councils, or multi-Mayor conflict resolution.

## Why

Phase 16.1 made the Mayor policy/proposal data contract explicit. The next
step is to prepare a Mayor request without creating side effects. This gives
future UI and execution slices a tested boundary:

- Ticket metadata decides whether Mayor planning is allowed.
- Mayor selection is deterministic and auditable.
- Prompt content is intentionally redacted and bounded.
- Rule references remain opaque and operator-visible.
- Invalid Mayor replies are rejected before persistence or child creation.

## Impact Analysis

- **Systems affected:** Ticket Mayor policy usage, Citizen catalog reads,
  prompt assembly, proposal reply parsing tests.
- **Runtime behavior:** No automatic Mayor work starts in this slice. Existing
  Tickets without Mayor metadata remain normal Billboard Tickets.
- **Database:** no migration. Existing `citizens.is_mayor`, `roles`, and
  `metadata` fields are read only.
- **Runtime data:** no Ticket files, history events, provider sessions, or
  child Tickets are written by this slice.
- **Alfred boundary:** `rules_refs` remain opaque strings. Babs must not call
  `af read` or embed SOP contents in the prompt.
- **Privacy:** prompts and fixtures must not include private hostnames, private
  IPs, local checkout paths, raw provider logs, tokens, or secrets.
- **Rollback plan:** revert this CHG implementation. Phase 16.1 schema modules
  remain safe and unused by runtime automation.

## Implementation Plan

1. **Review this CHG before code**
   - Run Trinity review with GLM and DeepSeek.
   - Fold blocking findings before implementation.

2. **RED/GREEN: Mayor selection**
   - Add `Babs.Citizens.Tickets.MayorSelector`.
   - Accept a normalized Mayor policy map from `MayorPolicy.from_metadata/1`.
   - Select a pinned Mayor when `policy["mayor"]` is present:
     - slug must exist;
     - Citizen must have `is_mayor: true`;
     - Citizen must not be `failed`;
     - Citizen must have a normalized role of `mayor` or `planner`.
   - Select a default Mayor when `policy["mayor"]` is nil:
     - scan configured/imported Citizens deterministically by slug;
     - if multiple eligible default Mayors exist, choose the first eligible
       Citizen by ascending slug for this one-active-Mayor rollout;
     - require the same eligibility rules;
     - exclude imported external-owned Citizens from automatic default
       selection.
   - Return stable nested error terms for missing policy, missing Mayor,
     ineligible Mayor, failed Mayor, and no default Mayor.
   - Add unit tests for pinned/default/external/failed/non-Mayor cases,
     including AND-condition cases proving `is_mayor`, status, and role all
     matter.

3. **RED/GREEN: Mayor prompt assembly**
   - Extend `Babs.Citizens.Tickets.PromptAssembler` or add a narrow helper that
     builds a Mayor proposal prompt.
   - Reuse the existing `PromptAssembler` sanitization path so Mayor prompt
     redaction cannot drift from Ticket follow-up and inspection prompts.
   - Include only sanitized, bounded context:
     - root Ticket id/title/state/priority/body;
     - recent visible conversation messages;
     - selected Mayor slug;
     - known role labels from policy and available Citizens;
     - eligible Citizen summaries without cwd/env/secrets;
     - inspection policy options;
     - opaque `rules_refs`;
     - structured JSON reply contract from Phase 16.1.
   - Explicitly instruct the Mayor that it may run `af read` / `af plan` for
     referenced rules and that Babs did not embed SOP bodies.
   - Add unit tests proving prompt content is sanitized, bounded, includes
     opaque refs, and excludes local paths/env/secrets.

4. **RED/GREEN: no-side-effect reply validation**
   - Add a small preparation/validation boundary, for example
     `Babs.Citizens.Tickets.MayorPlanner.prepare/2` and
     `MayorPlanner.parse_reply/2`.
   - `prepare(%Ticket{}, keyword())` should combine policy normalization, Mayor
     selection, and prompt assembly without dispatching anything.
   - A missing `metadata.mayor` policy from `MayorPolicy.from_metadata/1`
     should become `{:error, {:mayor_planner, :missing_policy}}`.
   - `parse_reply(raw_reply, policy_map)` should call `MayorProposal.parse/2`
     with keyword opts extracted from the policy map:
     `max_children: policy_map["max_children"]` and
     `allowed_roles: policy_map["allowed_roles"]`.
   - Parser failures and policy violations must return stable errors and must
     not write Ticket files, history, provider sessions, or GitHub artifacts.
   - Add unit tests for invalid JSON, too many children, and disallowed roles.

5. **REFACTOR**
   - Keep selection, prompt assembly, and proposal parsing as separate units.
   - Reuse `Catalog`, `ImportedHardline`, `Roles`, `MayorPolicy`,
     `MayorProposal`, and `Conversation` helpers instead of duplicating rules.
   - Keep this slice side-effect free.

6. **Validation**
   - Run focused Mayor selector/planner/prompt/proposal tests.
   - Run `mix format --check-formatted`.
   - Run `mix compile --warnings-as-errors`.
   - Run `mix test --max-cases 1`.
   - Run full `mix test`.
   - Run exported coverage gate.
   - Run `af validate --root .`.
   - Run `git diff --check`.
   - Run added-line privacy scan.

7. **Review and PR**
   - Run Trinity implementation review with GLM and DeepSeek.
   - Create the PR with `gh` as `ryosaeba1985`.
   - Follow `COR-1615` / `COR-1612` GitHub Codex loop, max five review rounds.

## Acceptance Criteria

- A Ticket without Mayor metadata cannot prepare a Mayor request.
- A mission Ticket with valid Mayor policy can select a pinned eligible Mayor.
- A mission Ticket with valid Mayor policy and no pinned Mayor selects one
  deterministic default Mayor.
- Imported external-owned Citizens are not selected as automatic default
  Mayors.
- Ineligible, failed, or missing pinned Mayor Citizens produce stable errors.
- The Mayor prompt includes opaque `rules_refs`, Ticket context, role/citizen
  summaries, inspection options, and the Phase 16.1 JSON proposal contract.
- The Mayor prompt does not include local paths, private hostnames, private
  IPs, env values, tokens, secrets, or full Alfred SOP bodies.
- Invalid or policy-violating Mayor replies are rejected without side effects.
- Unit tests cover selector, prompt assembly, and parser-failure/policy
  violation cases.

## Validation Commands

```bash
mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/mayor_selector_test.exs apps/babs_citizens/test/babs_citizens/tickets/mayor_planner_test.exs apps/babs_citizens/test/babs_citizens/tickets/prompt_assembler_test.exs apps/babs_citizens/test/babs_citizens/tickets/mayor_proposal_test.exs
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test --max-cases 1
mise exec -- mix test
mise exec -- mix test --cover --export-coverage phase16_2 && mise exec -- mix cmd mix test.coverage
af validate --root .
git diff --check
git diff -U0 | rg -n '^\+.*(100\.[0-9]{1,3}|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|/Users/[^[:space:]]+|api_token|secret|token)' || true
```

## Results

- 2026-05-08 Trinity CHG review:
  - Trinity packet:
    `.trinity/reviews/20260508-201951-rules-BAB-2260-CHG-Implement-Phase-16.2-Mayor-Selection-and-Prompt-Assembly.md`.
  - GLM PASS at 9.3/10 with no blocking findings.
  - DeepSeek PASS at 9.1/10 with no blocking findings.
  - Folded advisories for explicit `prepare/2` and `parse_reply/2` signatures,
    default Mayor slug tie-breaking, reuse of existing prompt sanitization,
    missing-policy error shape, and AND-condition eligibility tests.
- 2026-05-08 implementation:
  - Added `Babs.Citizens.Tickets.MayorSelector` for pinned/default Mayor
    selection with `is_mayor`, status, mayor/planner role, and external-owned
    default-skip eligibility rules.
  - Added `Babs.Citizens.Tickets.MayorPlanner` as a side-effect-free
    preparation boundary combining Mayor policy, selection, prompt assembly,
    and reply validation.
  - Extended `Babs.Citizens.Tickets.PromptAssembler` with a Mayor proposal
    prompt that reuses existing redaction, includes opaque rule refs, role and
    Citizen summaries, inspection options, and the Phase 16.1 proposal JSON
    contract.
  - Added tests for selector success/failure cases, prompt redaction/content,
    missing policy, invalid JSON, too many children, and disallowed child roles.
  - Folded Trinity implementation advisories by adding
    `CitizenRecord.role_names/1`, reusing it from Mayor/Inspector/Role routing
    surfaces, deferring Citizen catalog reads until after policy validation,
    replacing dynamic atom creation in prompt policy access, and covering
    previously untested error paths.
  - Folded final Trinity prompt advisory by labeling policy-limited roles as
    allowed assignee role labels and listing only `allowed_roles` when present.
- 2026-05-08 validation:
  - Focused Mayor selector/planner/prompt/proposal suite passed: 23 tests.
  - Focused shared-role-helper/router suite passed after advisory folding: 36
    tests.
  - `mise exec -- mix format --check-formatted` passed.
  - `mise exec -- mix compile --warnings-as-errors` passed.
  - `mise exec -- mix test --max-cases 1` passed with a fresh temporary test
    directory: `babs_citizens` 461 tests, `babs` 97 tests.
  - `mise exec -- mix test` passed with a fresh temporary test directory:
    `babs_citizens` 461 tests, `babs` 97 tests.
  - Coverage passed: `babs_citizens` 85.71%, `babs` 88.92%.
  - `af validate --root .` passed: 169 documents checked, 0 issues.
  - `git diff --check` passed.
  - Added-line privacy scan passed for private IPs, local checkout paths,
    private hostnames, tokens, and secrets.
- 2026-05-08 Trinity implementation review:
  - Final Trinity packet:
    `.trinity/reviews/20260508-205129-Phase-16.2-final-post-advisory-implementation-diff`.
  - GLM PASS and DeepSeek PASS with no blocking findings.
  - Remaining advisories are non-blocking style/guard-surface notes.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Record final GLM and DeepSeek implementation PASS/PASS | Codex |
| 2026-05-08 | Fold Trinity implementation advisories and refresh validation | Codex |
| 2026-05-08 | Implement Mayor selector/planner/prompt assembly and record validation | Codex |
| 2026-05-08 | Mark Approved after GLM and DeepSeek CHG review PASS; fold advisories | Codex |
| 2026-05-08 | Initial Phase 16.2 Mayor selection and prompt assembly CHG | Codex |
