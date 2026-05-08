# CHG-2255: Implement Phase 15.1 Inspection Policy and Events

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

Implement **Phase 15.1: inspection policy and events** from `BAB-2243`.

This is the first small PR slice for Phase 15 Inspector Council
auto-approval. It adds the durable policy and history-event foundation only;
it does not yet ask Citizens to inspect work.

Scope:

- Add an inspection policy normalizer/validator for
  `ticket.metadata["inspection"]`; `inspection` is a nested key under the
  existing Ticket `metadata` map, not a new top-level frontmatter key.
- Include the Phase 15 `BAB-1002` Inspector vocabulary update so it describes
  policy-driven Citizen Inspector Councils selected by slug and/or roles, not
  only a singular `role: inspector`.
- Preserve current human approval behavior when inspection metadata is missing
  or set to `mode: human`.
- Support the Phase 15 reserved policy shape:
  `mode`, `strategy`, `roles`, `citizens`, `quorum`, `max_inspectors`, and
  `allow_self_inspection`.
- Validate only the behavior implemented in this slice:
  - `mode`: `human` or `auto`
  - `strategy`: `single` or `council`
  - `quorum`: `all_pass` only
  - role and Citizen lists must be normalized, bounded, and duplicate-free
  - `max_inspectors` must be an integer from 1 through 10; default is 3
- Add inspection history event helpers for:
  - `inspection_requested`
  - `inspection_prompt_delivered` as an event-map constructor only; actual
    prompt delivery remains Phase 15.2
  - `inspection_decision`
  - `inspection_failed`
  - `inspection_completed`
- Ensure generated events are JSON-serializable, redaction-friendly, and
  appendable through the existing per-ticket Writer.
- Ensure generated events satisfy `History.validate_appendable/2`, including
  non-empty string `ts`, `event`, and `by` keys.
- Use normalized `"error"` string values for `inspection_failed` events, not raw
  provider output or exception structs.
- Generate inspection ids with a non-secret `insp_...` helper that uses time and
  `System.unique_integer([:positive, :monotonic])`; no local paths, hostnames,
  or provider data.
- Update Ticket markdown parse/render tests so inspection metadata round-trips.
- Update docs with validation results and review outcomes.

Out of scope:

- Inspector Citizen selection. That is Phase 15.2.
- Prompt assembly or prompt delivery to inspectors. That is Phase 15.2.
- Structured inspector reply capture, decision parsing, and quorum reduction.
  That is Phase 15.3.
- UI, BDD, and E2E inspection panels. That is Phase 15.4.
- Any automatic state transition caused by inspection.
- GitHub PR review automation.
- New database tables or migrations.

## Why

Phase 15 needs to reduce the operator approval bottleneck, but automatic
inspection must be auditable and conservative. The first safe step is to make
inspection policy explicit and make the durable event vocabulary testable before
any Citizen is allowed to approve or reject a Ticket.

Without this slice, later inspection selection and quorum code would have to
invent policy defaults and history event shapes at the same time as provider
execution. That would make the first automatic approval PR too large and too
risky.

## Impact Analysis

- **Systems affected:** Ticket metadata validation, Ticket markdown
  parse/render, Ticket history event helpers, Ticket writer tests, docs.
- **Runtime behavior:** existing Tickets without inspection metadata must behave
  exactly as before. No Ticket should auto-approve or auto-reject in this slice.
- **Database:** no schema change.
- **Runtime data:** existing metadata keys must be preserved. Invalid
  `metadata.inspection` shapes should produce clear parse/create errors instead
  of being silently accepted. Inspection policy errors should be nested under
  `{:invalid_frontmatter, {:inspection_policy, reason}}`.
- **Privacy:** policy and event helpers must not include local paths, hostnames,
  private IPs, environment maps, tokens, or raw provider transcripts.
- **Rollback:** revert this CHG implementation. Existing Tickets without
  inspection metadata remain compatible.

## Implementation Plan

1. **Review this CHG before code**
   - Run Trinity `fast-review` against this CHG.
   - Fold blockers and update status before implementation.

2. **RED: add policy tests**
   - Add unit tests for default human policy when metadata is missing.
   - Add tests for valid auto single and auto council policies.
   - Add rejection tests for unsupported quorum, invalid mode/strategy,
     invalid role labels, invalid Citizen slugs, invalid `max_inspectors`, and
     non-boolean `allow_self_inspection`.

3. **GREEN: implement policy module**
   - Add a small `Babs.Citizens.Tickets.InspectionPolicy` module.
   - Normalize role labels through the existing role normalizer.
   - Validate Citizen slugs syntactically through existing slug rules where
     available; existence checks against the live Citizen catalog are deferred
     to Phase 15.2 inspector selection.
   - Enforce `max_inspectors` as integer 1..10 with default 3.
   - Preserve unrelated Ticket metadata.
   - Keep defaults explicit and serializable.

4. **RED/GREEN: integrate Ticket markdown validation**
   - Validate `metadata["inspection"]` during Ticket parse/create.
   - Round-trip normalized inspection metadata through render/parse.
   - Preserve old `metadata: {}` and arbitrary non-inspection metadata.

5. **RED/GREEN: add event helper tests**
   - Add event builder tests for required keys, JSON serializability, and
     allowed decision values.
   - Assert each generated event passes `History.validate_appendable/2`.
   - Add at least one negative `History.validate_appendable/2` assertion so the
     appendable contract is actively tested.
   - Cover parse-failure/unparseable decisions as `inspection_failed` event
     data, not state transitions.
   - Assert `inspection_failed` uses a normalized `"error"` string key.

6. **GREEN: implement event helpers**
   - Add `Babs.Citizens.Tickets.InspectionEvents` or similarly scoped helper.
   - Reuse existing timestamp/id conventions where practical.
   - Keep events appendable through `Api.append_ticket_events/3`.
   - Keep `inspection_prompt_delivered` as a tested public constructor only; no
     runtime code path should call it before Phase 15.2 prompt delivery.

7. **Regression checks**
   - Existing human approve/reject tests remain green.
   - Existing Ticket markdown and writer tests remain green.
   - No browser UI changes are expected in this slice.

8. **Review and PR**
   - Run local validation.
   - Run Trinity implementation `fast-review`.
   - Publish PR with `gh` as `ryosaeba1985`.
   - Follow `COR-1615` / `COR-1612` GitHub Codex loop, max five review rounds.

## Acceptance Criteria

- Tickets without `metadata.inspection` parse and render as before and default
  to human inspection policy in code.
- `metadata.inspection.mode: human` preserves existing Phase 11 human approval
  behavior.
- Valid auto single/council policies normalize deterministically.
- Unsupported or malformed inspection policy values fail with clear
  `{:invalid_frontmatter, {:inspection_policy, reason}}` errors.
- Inspection event helpers generate JSON-serializable events with stable
  required keys.
- Inspection events can be appended to a Ticket history file through the
  existing Writer path.
- `BAB-1002` Inspector vocabulary reflects policy-driven Inspector Councils and
  multi-role Citizen selection.
- Existing approve/reject behavior and tests are unchanged.
- No automatic inspector selection, prompt delivery, quorum decision, or UI is
  implemented in this slice.

## Validation Plan

Focused:

```bash
mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/inspection_policy_test.exs
mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/inspection_events_test.exs
mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/ticket_markdown_test.exs
mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/api_writer_store_test.exs
```

Standard local gates:

```bash
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
mise exec -- mix test --cover --export-coverage phase15_1 && mise exec -- mix cmd mix test.coverage
af validate --root .
git diff --check
```

Browser gates are not expected for this slice because there are no UI changes.
If runtime code unexpectedly touches web behavior, add focused BDD/E2E before
PR.

## Review Plan

- Trinity `fast-review` on this CHG before implementation.
- Trinity `fast-review` on the implementation diff before PR.
- Follow the `BAB-1503` / `COR-1616` contract-first delivery workflow.
- GitHub Codex review loop on the PR, capped at five rounds.
- Use `gh` authenticated as `ryosaeba1985` for public GitHub writes.

## Results

- 2026-05-08 CHG review R1:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-134407-rules-BAB-2255-CHG-Implement-Phase-15-1-Inspection-Policy-and-Events.md`.
  - Synthesis recorded GLM PASS and DeepSeek PASS; raw DeepSeek flagged a
    blocker requiring the Phase 15 Inspector vocabulary update from `BAB-2243`.
  - Folded blocker and advisories for `BAB-1002` vocabulary, nested
    `metadata.inspection` scope, `max_inspectors` bounds, prompt-delivered event
    helper scope, inspection error taxonomy, appendable history validation,
    normalized `inspection_failed.error`, and `inspection_id` generation.
- 2026-05-08 CHG review R2:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-134941-rules-BAB-2255-CHG-Implement-Phase-15-1-Inspection-Policy-and-Events.md`.
  - GLM PASS and DeepSeek PASS; no blocking findings remain.
  - Folded implementation advisories for syntactic-only Citizen slug
    validation, explicit `System.unique_integer([:positive, :monotonic])`
    inspection id generation, negative `History.validate_appendable/2` testing,
    and constructor-only `inspection_prompt_delivered` scope.
- 2026-05-08 implementation:
  - Added `Babs.Citizens.Tickets.InspectionPolicy` for default human policy,
    explicit auto policy normalization, nested policy errors, bounded role and
    Citizen lists, syntactic Citizen slug validation, and `max_inspectors`
    bounds.
  - Added `Babs.Citizens.Tickets.InspectionEvents` constructors for requested,
    prompt-delivered, decision, failed, and completed events.
  - Integrated `metadata.inspection` validation into Ticket markdown parse and
    render round trips while preserving Tickets without inspection metadata.
  - Added focused policy, event, markdown, and writer/API append tests.
- 2026-05-08 local validation:
  - Focused tests passed:
    `mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/inspection_policy_test.exs apps/babs_citizens/test/babs_citizens/tickets/inspection_events_test.exs apps/babs_citizens/test/babs_citizens/tickets/ticket_markdown_test.exs apps/babs_citizens/test/babs_citizens/tickets/api_writer_store_test.exs`
    with 64 tests after post-review validation hardening.
  - `mise exec -- mix format --check-formatted` passed.
  - `mise exec -- mix compile --warnings-as-errors` passed.
  - `mise exec -- mix test` passed: 396 `:babs_citizens` tests and 88 `:babs`
    tests.
  - `mise exec -- mix test --cover --export-coverage phase15_1 && mise exec -- mix cmd mix test.coverage`
    passed: `:babs_citizens` 84.50%, `:babs` 89.27%.
  - Browser BDD/E2E gates were not run because this slice has no UI or browser
    behavior changes.
- 2026-05-08 implementation review R1:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-140249-Phase-15.1-inspection-policy-events-implementation-diff`.
  - GLM PASS and DeepSeek PASS; no blocking findings.
  - Folded non-blocking advisories by removing runtime atom conversion,
    validating decision findings as maps, requiring non-empty decision summary,
    and adding negative constructor validation tests.
- 2026-05-08 implementation review R2:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-140903-Phase-15.1-inspection-policy-events-implementation-diff`.
  - GLM PASS and DeepSeek PASS; no blocking findings.
  - Remaining notes are non-blocking implementation guidance for later phases.
- 2026-05-08 GitHub Codex review R1:
  - Fixed P2 privacy bug: `inspection_failed` no longer stores
    `Error.message/1` fallback output for unknown provider failures. Unknown
    reasons are normalized to `Inspection failed`; known timeout/unparseable
    classes use short redacted strings.
  - Added regression coverage proving raw provider-shaped data is not persisted
    in `inspection_failed.error`.
  - Focused event/API tests passed with 53 tests.
  - Full ExUnit and stable exported coverage gates passed after the fix.
- 2026-05-08 GitHub Codex review R2:
  - Fixed P3 inspection id generation bug: `InspectionEvents.new_id/2` now
    formats arbitrary `DateTime` structs via Unix seconds instead of
    `DateTime.shift_zone!/2`, avoiding timezone database failures for non-UTC
    named zones.
  - Added non-UTC DateTime regression coverage.
  - Post-fix validation passed: focused event tests with 14 tests,
    `mix format --check-formatted`, `mix compile --warnings-as-errors`, full
    `mix test` with 397 `:babs_citizens` tests and 88 `:babs` tests, exported
    coverage at `:babs_citizens` 84.52% and `:babs` 89.27%, `af validate`,
    `git diff --check`, and added-line privacy scan.
- 2026-05-08 GitHub CI after R2:
  - Fixed CI-only test isolation failure in `ReattachScannerTest` by moving it
    onto `RepoCase`, so tests that exercise `Catalog`/Repo initialize and clean
    the SQLite schema even when CI runs `mix test --max-cases 1` from an empty
    database.
  - Validation passed: focused `ReattachScannerTest`, CI-equivalent
    `mix test --max-cases 1`, default full `mix test`, exported coverage,
    `af validate`, `git diff --check`, and added-line privacy scan.
- 2026-05-08 GitHub Codex review R3:
  - Fixed P2 audit correctness bug: `inspection_requested` now rejects empty
    inspector lists and blank inspector values, preventing persisted audit
    events that claim an inspection was requested with no deliverable prompt.
  - Added regression coverage for both empty and blank inspector routing fields.
  - Post-fix validation passed: focused event tests with 14 tests,
    CI-equivalent `mix test --max-cases 1`, default full `mix test`, exported
    coverage at `:babs_citizens` 84.55% and `:babs` 89.27%.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial Phase 15.1 inspection policy/events CHG | Codex |
| 2026-05-08 | Fold Trinity CHG review blocker/advisories for Inspector vocabulary, nested metadata, bounds, event id/error contracts, and appendable validation | Codex |
| 2026-05-08 | Mark Approved after Trinity R2 GLM and DeepSeek PASS; fold remaining implementation advisories | Codex |
| 2026-05-08 | Implement inspection policy/events foundation and record local validation | Codex |
| 2026-05-08 | Fold Trinity implementation R1 advisories and rerun focused/full validation | Codex |
| 2026-05-08 | Trinity implementation R2 passed GLM and DeepSeek | Codex |
| 2026-05-08 | Fixed GitHub Codex R1 P2 for redacted inspection failure reasons | Codex |
| 2026-05-08 | Fixed GitHub Codex R2 P3 for non-UTC inspection id timestamps | Codex |
| 2026-05-08 | Fixed GitHub CI test isolation for ReattachScannerTest under max-cases 1 | Codex |
| 2026-05-08 | Fixed GitHub Codex R3 P2 for empty inspector request events | Codex |
