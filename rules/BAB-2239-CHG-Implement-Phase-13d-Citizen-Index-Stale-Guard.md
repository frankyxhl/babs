# CHG-2239: Implement Phase 13d Citizen Index Stale Guard

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

Implement Phase 13d: Citizen Index Stale Guard.

The immediate defect is that `/citizens` still shows stale SQLite-only Citizen
rows after their canonical `citizens/citizen-<slug>.toml` files have been
deleted. Phase 13c correctly hid those rows from Ticket assignment controls,
but the fleet index still reads the full durable SQLite registry through
`StatusSnapshot.list/1`.

Scope:

- Apply the same operator-visible eligibility rule to the normal Citizens index:
  - Include TOML-backed Citizens.
  - Include explicitly imported external Hardline Citizens.
  - Exclude stale SQLite-only Citizens that are neither TOML-backed nor
    imported external sessions.
- Keep existing stale SQLite rows untouched for future lifecycle cleanup work.
- Keep imported external sessions visible because the operator deliberately
  imported them and Babs does not own their tmux lifecycle.
- Add regression coverage for `/citizens` so stale rows do not appear in the
  normal index.

Out of scope:

- Deleting stale SQLite rows.
- Adding a stale-record cleanup UI.
- Changing attach/import inventory behavior.
- Changing direct URL behavior for already-known stale Citizen slugs.

## Why

The operator-facing Citizens index should not imply that a deleted Babs-owned
Citizen is still a normal usable Citizen. Showing a stale row such as `json` on
the index after its TOML definition has been removed creates the same class of
misleading UI that Phase 13c fixed for Ticket assignment.

At the same time, SQLite remains durable runtime state. Hiding stale rows from
the normal fleet index is safer than destructive cleanup because later phases
may still need an audit/cleanup screen.

## Impact Analysis

- **Systems affected:** Citizen status snapshots and Citizens index LiveView
  rendering.
- **Data affected:** None. No migrations and no deletes.
- **Runtime behavior:** Normal `/citizens` hides stale SQLite-only rows.
  TOML-backed Citizens and imported external Citizens remain visible.
- **Risk:** Operators temporarily lose a default index view into stale database
  rows. This is intentional; explicit stale cleanup/reporting can be added as a
  later lifecycle feature.
- **Rollback plan:** Revert the implementation PR. Existing data is unchanged.

## Implementation Plan

1. **Document first**
   - File this CHG as Phase 13d before implementation.

2. **RED tests**
   - Add/adjust status snapshot coverage so configured Citizens and imported
     external Citizens remain visible while stale SQLite-only rows are excluded.
   - Add/adjust Citizens LiveView coverage so `/citizens` does not render a
     stale `citizen-row-<slug>`.
   - Add one focused browser-harness BDD scenario for the exact operator-facing
     `/citizens` stale-row failure mode.

3. **Implementation**
   - Route the normal `StatusSnapshot.list/1` fleet snapshot through
     `Catalog.list_configured_or_imported_citizens/1`.
   - Preserve full-registry visibility as an explicit
     `StatusSnapshot.list(include_stale?: true)` option for internal callers or
     tests that need raw SQLite visibility.

4. **Validation**
   - Focused status snapshot and Citizens LiveView tests.
   - Focused browser-harness BDD scenario:
     `citizens index hides stale sqlite citizen`.
   - `mise exec -- mix format --check-formatted`
   - `mise exec -- mix compile --warnings-as-errors`
   - `mise exec -- mix test`
   - `af validate --root .`
   - `git diff --check`

## Guard Rails

- Do not delete or mutate stale SQLite rows.
- Do not hide imported external Hardline Citizens.
- Do not alter Ticket assignment semantics already delivered in Phase 13c.
- Do not add a broad lifecycle cleanup feature in this CHG.

## Acceptance Criteria

- `/citizens` no longer renders stale SQLite-only rows such as `json` when the
  TOML file is absent.
- TOML-backed Citizens remain visible on `/citizens`.
- Imported external Hardline Citizens remain visible on `/citizens`.
- Existing raw SQLite rows are not deleted.
- Tests cover the normal index behavior.

## Validation Results

- 2026-05-08 `mise exec -- mix format --check-formatted`: pass
- 2026-05-08 focused ExUnit:
  `mise exec -- mix test apps/babs_citizens/test/babs_citizens/status_snapshot_test.exs apps/babs/test/babs_web/live/citizens_live_test.exs`
  - `babs_citizens`: 10 tests, 0 failures
  - `babs`: 9 tests, 0 failures
- 2026-05-08 focused browser-harness BDD:
  `BU_CDP_URL=http://127.0.0.1:9225 BABS_BDD_SCENARIO="citizens index hides stale sqlite citizen" npm run test:bdd`
  - Scenario passed; BDD PASS
- 2026-05-08 local HTTP check:
  `curl -fsS http://127.0.0.1:4000/citizens | rg -n 'citizen-row-json|>json<|Json' || true`
  - no matching stale `json` row markup
- 2026-05-08 `mise exec -- mix compile --warnings-as-errors`: pass
- 2026-05-08 `mise exec -- mix test`
  - `babs_citizens`: 324 tests, 0 failures
  - `babs`: 82 tests, 0 failures
- 2026-05-08 `npm run test:js`: 15 tests, 0 failures
- 2026-05-08 `npm run test:e2e`: 12 passed, 1 skipped
- 2026-05-08 `af validate --root .`: 147 documents checked, 0 issues found
- 2026-05-08 `git diff --check`: pass
- 2026-05-08 post-Trinity-advisory validation:
  - `mise exec -- mix format --check-formatted`: pass
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/status_snapshot_test.exs apps/babs/test/babs_web/live/citizens_live_test.exs`
    - `babs_citizens`: 10 tests, 0 failures
    - `babs`: 9 tests, 0 failures
  - focused browser-harness BDD:
    `BU_CDP_URL=http://127.0.0.1:9225 BABS_BDD_SCENARIO="citizens index hides stale sqlite citizen" npm run test:bdd`
    - Scenario passed; BDD PASS
  - `mise exec -- mix compile --warnings-as-errors`: pass
  - `mise exec -- mix test`
    - `babs_citizens`: 324 tests, 0 failures
    - `babs`: 82 tests, 0 failures
- 2026-05-08 final post-review validation:
  - `mise exec -- mix format --check-formatted`: pass
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/status_snapshot_test.exs apps/babs/test/babs_web/live/citizens_live_test.exs`
    - `babs_citizens`: 10 tests, 0 failures
    - `babs`: 9 tests, 0 failures
  - focused browser-harness BDD with isolated Chrome CDP:
    `BU_CDP_URL=http://127.0.0.1:9225 BABS_BDD_SCENARIO="citizens index hides stale sqlite citizen" npm run test:bdd`
    - Scenario passed; BDD PASS
  - `mise exec -- mix compile --warnings-as-errors`: pass
  - `mise exec -- mix test`
    - `babs_citizens`: 324 tests, 0 failures
    - `babs`: 82 tests, 0 failures
  - `af validate --root .`: 147 documents checked, 0 issues found
  - `git diff --check`: pass

## Review Results

- 2026-05-08 Trinity fast-review of this CHG: GLM PASS, DeepSeek PASS.
- Review packet:
  `.trinity/reviews/20260508-031202-rules-BAB-2239-CHG-Implement-Phase-13d-Citizen-Index-Stale-Guard.md`
- Non-blocking advisories folded into this document:
  review results section, explicit unit/LiveView coverage scope, and explicit
  `include_stale?: true` internal option.
- Deferred advisories:
  optional `BAB-1107` reference and future cached configured-slug set if the
  1-second Citizens index refresh becomes too filesystem-heavy.
- 2026-05-08 Trinity fast-review of the implementation diff: GLM PASS,
  DeepSeek PASS.
- Implementation review packet:
  `.trinity/reviews/20260508-034612-Phase-13d-Citizen-index-stale-guard-implementation-diff`
- Non-blocking implementation advisories folded in:
  narrower Catalog option forwarding, more precise LiveView assertion, and
  browser BDD positive-case coverage.
- 2026-05-08 final Trinity fast-review of the post-advisory implementation
  diff: GLM PASS, DeepSeek PASS.
- Final implementation review packet:
  `.trinity/reviews/20260508-035555-Phase-13d-Citizen-index-stale-guard-final-diff`

## Deferred Gates

- Stale SQLite cleanup/reporting UI is deferred until a dedicated lifecycle
  cleanup phase.
- Browser-harness BDD for the Citizens index is deferred unless the LiveView
  regression needs broader browser coverage beyond the focused stale-row
  scenario.

## References

- `BAB-2238` Phase 13c Stale Citizen UI Guard
- `BAB-1113` Imported Tmux Session Attach
- `BAB-1105` Persistence - ETS + SQLite + JSONL Only

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial Phase 13d stale Citizens index proposal | Codex |
| 2026-05-08 | Mark approved after Trinity review and clarify test/option scope | Codex |
| 2026-05-08 | Record Phase 13d implementation validation | Codex |
| 2026-05-08 | Record Trinity implementation review and post-review validation | Codex |
| 2026-05-08 | Record final Trinity implementation review | Codex |
