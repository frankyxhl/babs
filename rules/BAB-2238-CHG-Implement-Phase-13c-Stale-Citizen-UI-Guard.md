# CHG-2238: Implement Phase 13c Stale Citizen UI Guard

**Applies to:** BAB project
**Last updated:** 2026-05-08
**Last reviewed:** 2026-05-08
**Status:** Approved
**Date:** 2026-05-08
**Requested by:** Operator
**Priority:** High
**Change Type:** Normal

---

## What

Implement Phase 13c: Stale Citizen UI Guard.

The immediate defect is that the browser UI still exposes a SQLite-only
Citizen record after its canonical `citizens/citizen-<slug>.toml` file has been
deleted. In the observed case, `citizen-json.toml` had been deleted, but the
durable SQLite row for `json` remained visible and assignable in the Ticket UI.
The operator assigned a Ticket to `json`, which caused accidental direct-cli
delivery and a later `execution_busy` failure.

Scope:

- Define a UI-safe Citizen eligibility rule:
  - Include TOML-backed Citizens.
  - Include explicitly imported external Hardline Citizens.
  - Exclude stale SQLite-only Citizens that are neither TOML-backed nor
    imported external sessions.
- Apply that eligibility rule to Ticket assignment options so stale records
  cannot be selected accidentally.
- Keep existing Tickets readable. If a Ticket is already assigned to a stale
  Citizen, show it as an unknown/stale assignee warning rather than treating
  the row as valid.
- Add regression coverage for the stale SQLite-only assignment option at the
  catalog, LiveView, and focused browser-harness BDD layers.

Out of scope for this CHG:

- Destructive deletion of stale SQLite rows.
- New schema fields for Citizen source/provenance.
- Full lifecycle cleanup UX for stale records.
- Queueing direct-cli messages while a Citizen is busy.

## Why

The UI must reflect the runtime truth closely enough that the operator cannot
easily choose an invalid target. SQLite is durable runtime state, but for normal
Babs-owned Citizens the TOML file is still the canonical editable definition. A
deleted TOML file should not leave a normal Citizen looking usable in Ticket
assignment controls.

Imported external tmux sessions are a deliberate exception: they may be valid
without TOML because the operator explicitly imported them from the UI and Babs
does not own their lifecycle. This CHG keeps that exception while filtering
ordinary stale rows.

## Impact Analysis

- **Systems affected:** Ticket detail LiveView assignment options, Citizen
  catalog read helpers, Ticket detail warning behavior, and focused LiveView /
  catalog tests.
- **Data affected:** No migration. Existing SQLite rows and Ticket history
  remain unchanged.
- **Runtime behavior:** Deleted TOML-backed Citizens disappear from new Ticket
  assignment choices. Existing Tickets assigned to those slugs remain visible
  and should display an unknown assignee warning.
- **Risk:** If a valid non-imported Citizen exists only in SQLite, it will no
  longer be assignable from the Ticket UI. That is intentional for now because
  current canonical Babs-owned Citizens should have TOML definitions.
- **Rollback plan:** Revert the implementation PR. Existing data is unchanged.

## Implementation Plan

1. **Document first**
   - File this CHG as Phase 13c before continuing implementation.
   - Move status to `Approved` after Trinity plan review approval.

2. **RED tests**
   - Add a LiveView regression test where `clare` is TOML-backed and `json` is
     SQLite-only. The Ticket assignment UI must show `clare` and hide `json`.
   - Add explicit coverage that an imported external Hardline Citizen remains
     assignable even when it is not TOML-backed.
   - Add/adjust catalog tests for the eligibility helper if needed.
   - Add a focused browser-harness BDD scenario for the observed operator
     failure mode: a UI-created Citizen leaves a SQLite row after its TOML is
     deleted, and the Ticket detail page must not offer it as an assignment
     target.
   - Verify an existing Ticket assigned to stale `json` shows an unknown
     assignee warning.

3. **Implementation**
   - Add a catalog read helper for UI-valid Citizens:
     TOML-backed records plus imported external records.
   - Use this helper in Ticket assignment option generation.
   - Do not delete stale records in this CHG.

4. **Validation**
   - Focused LiveView/catalog tests.
   - `mise exec -- mix format --check-formatted`
   - `mise exec -- mix compile --warnings-as-errors`
   - `mise exec -- mix test`
   - `af validate --root .`
   - `git diff --check`

## Guard Rails

- Do not delete stale SQLite rows in this CHG.
- Do not add schema fields or migrations for provenance in this CHG.
- Do not hide or rewrite existing Ticket history. Existing stale assignments
  must stay readable and surface warnings.
- Treat imported external Hardline Citizens as the only SQLite-only exception
  because the operator explicitly imported them and Babs does not own their
  tmux lifecycle.

## Acceptance Criteria

- `json` no longer appears as a Ticket assignment option when
  `citizen-json.toml` is absent and the row is only present in SQLite.
- TOML-backed Citizens such as `clare`, `dylan`, and `elena` remain assignable
  when their records exist.
- Imported external Hardline Citizens remain eligible despite not being
  TOML-backed.
- Existing Tickets assigned to stale slugs remain readable and surface a
  warning instead of silently presenting stale data as valid.
- No runtime data is destructively removed.

## Validation Results

- 2026-05-08 `mise exec -- mix test apps/babs/test/babs_web/live/tickets_live_test.exs apps/babs_citizens/test/babs_citizens/catalog_test.exs`
  - `babs_citizens`: 9 tests, 0 failures
  - `babs`: 17 tests, 0 failures
- 2026-05-08 `mise exec -- mix format --check-formatted`: pass
- 2026-05-08 `mise exec -- mix compile --warnings-as-errors`: pass
- 2026-05-08 `mise exec -- mix test`
  - `babs_citizens`: 323 tests, 0 failures
  - `babs`: 81 tests, 0 failures
- 2026-05-08 `npm run test:js`: 15 tests, 0 failures
- 2026-05-08 `npm run test:e2e`: 12 passed, 1 skipped
- 2026-05-08 isolated Chrome browser-harness:
  `BU_CDP_URL=http://127.0.0.1:9224 BABS_BDD_SCENARIO="ticket assignment hides stale sqlite citizen" npm run test:bdd`
  - Scenario passed; BDD PASS
- 2026-05-08 `af validate --root .`: 146 documents checked, 0 issues found
- 2026-05-08 `git diff --check`: pass
- 2026-05-08 post-review cleanup validation after removing unused public helper:
  - `mise exec -- mix test apps/babs/test/babs_web/live/tickets_live_test.exs apps/babs_citizens/test/babs_citizens/catalog_test.exs`
    - `babs_citizens`: 9 tests, 0 failures
    - `babs`: 17 tests, 0 failures
  - `mise exec -- mix compile --warnings-as-errors`: pass
  - `mise exec -- mix format --check-formatted`: pass
  - `af validate --root .`: 146 documents checked, 0 issues found
  - `git diff --check`: pass

## Review Results

- 2026-05-08 Trinity fast-review of this CHG: GLM PASS, DeepSeek PASS.
- Review packet:
  `.trinity/reviews/20260508-023213-rules-BAB-2238-CHG-Implement-Phase-13c-Stale-Citizen-UI-Guard.md`
- Non-blocking advisories folded into this document:
  imported-external regression coverage, guard rails, and ADR reference.
- 2026-05-08 Trinity fast-review of the implementation diff: GLM PASS,
  DeepSeek PASS.
- 2026-05-08 Trinity fast-review of the final implementation diff after
  advisory cleanup: GLM PASS, DeepSeek PASS.
- Final implementation review packet:
  `.trinity/reviews/20260508-024738-Phase-13c-stale-Citizen-UI-guard-final-diff`
- Deferred non-blocking implementation advisories:
  TOML parse-error visibility, optional public helper docs if new helpers grow,
  and future stale-Citizen lifecycle/status UX beyond Ticket assignment.

## References

- `BAB-2237` Phase 13b Direct CLI Resumable Prompt Compaction
- `BAB-1113` Imported Tmux Session Attach
- `BAB-2227` Phase 13 Imported Tmux Session Attach
- `BAB-1112` Multi-AI-CLI Citizen Configuration
- `BAB-1105` Persistence - ETS + SQLite + JSONL Only

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial version | — |
| 2026-05-08 | Fill Phase 13c stale Citizen UI guard proposal | Codex |
| 2026-05-08 | Mark approved after Trinity review and add guard rails | Codex |
| 2026-05-08 | Record implementation validation results | Codex |
| 2026-05-08 | Record final Trinity implementation review | Codex |
