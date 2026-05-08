# CHG-2259: Implement Phase 16.1 Mayor Policy and Proposal Schema

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

Implement **Phase 16.1: Mayor policy and proposal schema** from `BAB-2244`.

This is the first small PR slice for Phase 16 Mayor rule-guided proposals. It
adds the durable validation foundation only:

- Add a Mayor policy normalizer/validator for Ticket `metadata["mayor"]`.
- Preserve current Billboard behavior when Mayor metadata is missing.
- Validate that Phase 16 Mayor planning is explicitly opt-in through
  `metadata.mayor.mode: "propose"`.
- Require Phase 16 Mayor proposals to remain human-gated through
  `require_human_approval: true`.
- Treat `rules_refs` as opaque strings; Babs validates shape only and does not
  parse Alfred/Babs documents.
- Use concrete Phase 16.1 bounds: at most 10 `rules_refs`, 10
  `allowed_roles`, 10 children, 10 risks, and 10 questions.
- Add a structured Mayor proposal parser/validator for future Mayor replies.
- Validate proposal children for title/body/type/priority/role and Phase 15
  inspection metadata compatibility.
- Add unit tests and fixtures covering valid policies, malformed policies,
  valid proposals, invalid proposals, and no-surprise normal Tickets.

Out of scope:

- Selecting a Mayor Citizen.
- Prompt assembly or external provider calls.
- Persisting proposal events.
- Proposal review UI or graph/tree rendering.
- Approving proposals or writing child Tickets.
- Automatic proposal approval.
- Cross-machine Mayor behavior from Phase 17.

## Why

Phase 16 adds a powerful decomposition loop, so the first implementation slice
must make the data contract explicit before any Citizen is asked to plan work.
The runtime needs to know which root Tickets opted into Mayor planning, which
rule references are safe to pass through, and which proposal payloads are valid
enough to persist or render later.

Doing the policy and schema first keeps later prompt/UI/child-writing slices
small and testable.

## Impact Analysis

- **Systems affected:** Ticket frontmatter metadata validation, new Mayor
  policy/proposal schema modules, Ticket markdown tests.
- **Runtime behavior:** Tickets without Mayor metadata parse and render as
  before; no automatic Mayor work is introduced in this slice.
- **Database:** no migration.
- **Runtime data:** future Tickets may include normalized `metadata.mayor`;
  this CHG must not create child Ticket files or proposal history events.
- **Alfred boundary:** `rules_refs` are opaque strings; Babs must not read or
  parse Alfred SOP bodies.
- **Privacy:** proposal fixtures must not include raw provider logs, private
  hostnames, private IPs, local checkout paths, tokens, or secrets.
- **Rollback:** revert this CHG implementation. Existing Tickets without Mayor
  metadata remain unaffected.

## Implementation Plan

1. **Review this CHG before code**
   - Run Trinity review with available providers.
   - If a provider is temporarily unavailable, record the outage and re-include
     it once it is healthy again.
   - Fold blocking findings before implementation.

2. **RED/GREEN: Mayor policy metadata**
   - Add `Babs.Citizens.Tickets.MayorPolicy`.
   - Normalize both atom and string keys into string-keyed metadata.
   - Accept missing Mayor metadata without rewriting metadata.
   - Validate:
     - `mode` is `"propose"`;
     - `mayor` is `nil` or a valid Citizen slug;
     - `rules_refs` is a bounded list of at most 10 nonblank strings;
     - `max_children` is an integer from 1 through 10;
     - `allowed_roles` is a bounded list of at most 10 normalized role labels;
     - `require_human_approval` is exactly `true`.
   - Integrate validation into `TicketMarkdown.metadata/1` after inspection
     metadata normalization.
   - Add policy unit tests and Ticket markdown round-trip/negative tests.

3. **RED/GREEN: proposal parser and validator**
   - Add `Babs.Citizens.Tickets.MayorProposal`.
   - Parse whole-body JSON and fenced JSON replies.
   - Validate required fields:
     - `proposal_id`, `root_ticket_id`, `summary`, `rules_refs_used`,
       `children`, `risks`, `questions`.
   - Validate `proposal_id` as a non-secret id with a `prop_` prefix and only
     lowercase letters, digits, underscores, or hyphens.
   - Validate `rules_refs_used`, `risks`, and `questions` as lists of at most
     10 nonblank strings each.
   - Validate each child:
     - nonblank `title` and `body`;
     - `type` defaults to or validates as `"assignment"` for Phase 16.1;
     - `priority` defaults to or validates as an existing Ticket priority;
     - `assignee_role` is nil or a normalized allowed role;
     - `metadata.inspection`, when present, normalizes through
       `InspectionPolicy`.
     - compact `inspector` is derived from `metadata.inspection` when omitted:
       `"auto"` for auto inspection and `"user"` for human/missing inspection.
     - explicitly supplied compact `inspector` must not conflict with
       `metadata.inspection`; `"auto"` requires auto inspection metadata, and
       human/missing inspection metadata cannot claim `"auto"`.
   - Reject raw non-map findings, overlarge child lists, and malformed
     `rules_refs_used` / `risks` / `questions`.
   - Add parser/validator unit tests with deterministic fixtures.

4. **REFACTOR**
   - Keep Mayor policy validation separate from proposal validation.
   - Reuse existing `Roles`, `Citizen.Config`, `TicketId`, and
     `InspectionPolicy` helpers instead of duplicating validation rules.
   - Keep error terms nested and stable enough for UI mapping in Phase 16.3.

5. **Validation**
   - Run focused Mayor policy/proposal/Ticket markdown tests.
   - Run `mix format --check-formatted`.
   - Run `mix compile --warnings-as-errors`.
   - Run `mix test --max-cases 1`.
   - Run full `mix test`.
   - Run exported coverage gate.
   - Run `af validate --root .`.
   - Run `git diff --check`.
   - Run added-line privacy scan.

6. **Review and PR**
   - Run Trinity implementation review with available providers.
   - Create the PR with `gh` as `ryosaeba1985`.
   - Follow `COR-1615` / `COR-1612` GitHub Codex loop, max five review rounds.

## Acceptance Criteria

- Tickets without `metadata.mayor` parse/render as before and stay normal
  Billboard Tickets.
- `metadata.mayor.mode: "propose"` normalizes with opaque `rules_refs`,
  bounded `max_children`, bounded `allowed_roles`, optional pinned Mayor slug,
  and mandatory `require_human_approval: true`.
- Invalid Mayor metadata fails Ticket parsing with a nested
  `{:mayor_policy, reason}` frontmatter error.
- Mayor proposal JSON can be parsed from whole-body JSON and fenced JSON.
- Valid proposals normalize child defaults and child inspection metadata.
- Valid proposals derive compact child `inspector` values from child
  `metadata.inspection`, and conflicting compact inspector values are rejected.
- Invalid proposals never produce child Ticket files, external GitHub artifacts,
  or provider-visible side effects.
- Unit tests cover valid and invalid policy/proposal cases.
- No raw secrets, private hostnames, private IPs, local checkout paths, or
  generated runtime proposal data are published in docs, PR body, comments, or
  fixtures.

## Validation Commands

```bash
mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/mayor_policy_test.exs apps/babs_citizens/test/babs_citizens/tickets/mayor_proposal_test.exs apps/babs_citizens/test/babs_citizens/tickets/ticket_markdown_test.exs
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test --max-cases 1
mise exec -- mix test
mise exec -- mix test --cover --export-coverage phase16_1 && mise exec -- mix cmd mix test.coverage
af validate --root .
git diff --check
git diff -U0 | rg -n '^\+.*(100\.[0-9]{1,3}|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|/Users/[^[:space:]]+|api_token|secret|token)' || true
```

## Results

- 2026-05-08 Trinity CHG review:
  - Trinity packet:
    `.trinity/reviews/20260508-190051-rules-BAB-2259-CHG-Implement-Phase-16-1-Mayor-Policy-and-Proposal-Schema.md`.
  - GLM PASS at 9.10/10 with no blocking findings.
  - DeepSeek was temporarily skipped because the provider was service-down at
    the time of CHG review; it was re-enabled once healthy for implementation
    review.
  - Folded advisories for concrete list/size bounds, compact child `inspector`
    derivation/conflict behavior, and stricter `proposal_id`, `risks`, and
    `questions` validation.
- 2026-05-08 implementation:
  - Added `Babs.Citizens.Tickets.MayorPolicy` for `metadata.mayor`
    normalization and validation.
  - Added `Babs.Citizens.Tickets.MayorProposal` for whole-body and fenced JSON
    proposal parsing, child validation, role limits, inspection metadata
    normalization, and compact inspector derivation/conflict checks.
  - Integrated Mayor metadata normalization into `TicketMarkdown` after
    inspection metadata normalization.
  - Enforced Mayor metadata on `mission` Tickets only.
  - Folded GLM implementation-review advisories for compact inspector edge
    tests and mission-only Mayor metadata.
  - Folded DeepSeek implementation-review advisory so invalid
    `allowed_roles` parser options fail instead of silently disabling role
    gating.
  - Added focused tests for Mayor policy, Mayor proposal payloads, and Ticket
    markdown Mayor metadata round trips/errors.
- 2026-05-08 validation:
  - Focused Mayor policy/proposal/Ticket markdown suite passed: 21 tests.
  - `mise exec -- mix format --check-formatted` passed.
  - `mise exec -- mix compile --warnings-as-errors` passed.
  - `mise exec -- mix test --max-cases 1` passed: `babs_citizens` 447 tests,
    `babs` 97 tests.
  - `mise exec -- mix test` passed: `babs_citizens` 447 tests, `babs` 97 tests.
  - Coverage passed: `babs_citizens` 85.50%, `babs` 88.92%.
  - `af validate --root .` passed: 168 documents checked, 0 issues.
  - `git diff --check` passed.
  - Added-line privacy scan passed for private IPs, local checkout paths,
    tokens, and secrets.
- 2026-05-08 Trinity implementation review:
  - Final Trinity packet:
    `.trinity/reviews/20260508-193844-Phase-16.1-mayor-policy-proposal-schema-final-post-advisory-diff`.
  - GLM PASS and DeepSeek PASS with no blocking findings.
  - Remaining advisories are minor follow-ups: duplicated private helpers,
    cosmetic error wording, and defensive fallback branches without direct
    tests.
- 2026-05-08 Codex PR review R1:
  - Codex found one P2 issue: proposal list fields documented as required
    could be omitted and defaulted to empty lists.
  - Fixed `MayorProposal` so all top-level required fields return
    `{:missing_field, key}` when absent, including `proposal_id`,
    `root_ticket_id`, `summary`, `children`, `rules_refs_used`, `risks`, and
    `questions`.
  - Explicit empty lists remain valid for list fields that allow empty values;
    an empty `children` list still returns `:empty_children`.
  - Folded the DeepSeek implementation-review advisory to make missing
    `children` consistent with the other required top-level fields.
  - Added regression tests for the missing-field cases.
  - Focused Mayor policy/proposal/Ticket markdown suite passed: 21 tests.
  - `mise exec -- mix format --check-formatted` passed.
  - `mise exec -- mix compile --warnings-as-errors` passed.
  - `mise exec -- mix test --max-cases 1` passed with a fresh temporary test
    directory: `babs_citizens` 447 tests, `babs` 97 tests.
  - `mise exec -- mix test` passed with a fresh temporary test directory:
    `babs_citizens` 447 tests, `babs` 97 tests.
  - Coverage passed after the R1 fix: `babs_citizens` 85.52%, `babs` 88.92%.
  - Final Trinity R1-fix implementation review packet:
    `.trinity/reviews/20260508-195708-Phase-16.1-final-Codex-R1-required-field-consistency-fix`.
  - GLM PASS and DeepSeek PASS with no blocking findings.
- 2026-05-08 Codex PR review R2:
  - Codex found one P2 issue: fenced JSON extraction could match Markdown code
    fences inside a JSON string before parsing the proposal object.
  - Fixed proposal parsing so whole-body JSON is decoded first; fenced fallback
    now extracts only an outer fence delimited by standalone fence lines.
  - Added regression tests for whole-body JSON and fenced JSON where a child
    body contains a Markdown code fence.
  - Focused Mayor policy/proposal/Ticket markdown suite passed: 23 tests.
  - `mise exec -- mix format --check-formatted` passed.
  - `mise exec -- mix compile --warnings-as-errors` passed.
  - `mise exec -- mix test --max-cases 1` passed with a fresh temporary test
    directory: `babs_citizens` 449 tests, `babs` 97 tests.
  - `mise exec -- mix test` passed with a fresh temporary test directory:
    `babs_citizens` 449 tests, `babs` 97 tests.
  - Coverage passed after the R2 fix: `babs_citizens` 85.51%, `babs` 88.92%.
  - Final Trinity R2-fix implementation review packet:
    `.trinity/reviews/20260508-200541-Phase-16.1-final-Codex-R2-fenced-JSON-parsing-fix`.
  - GLM PASS and DeepSeek PASS with no blocking findings.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Fix Codex R2 fenced JSON parsing finding and update validation | Codex |
| 2026-05-08 | Fix Codex R1 required proposal-list-field finding and update validation | Codex |
| 2026-05-08 | Record final GLM and DeepSeek implementation PASS/PASS | Codex |
| 2026-05-08 | Fold DeepSeek parser-option advisory and update final validation | Codex |
| 2026-05-08 | Implement Mayor policy/proposal schema and record validation | Codex |
| 2026-05-08 | Mark Approved after GLM CHG review PASS and fold advisories | Codex |
| 2026-05-08 | Initial Phase 16.1 Mayor policy and proposal schema CHG | Codex |
