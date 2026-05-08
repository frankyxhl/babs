# CHG-2248: Implement Phase 13f.2 Direct CLI Normalized Result

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

Implement **Phase 13f.2: Direct CLI adapter normalized result shape** from
`BAB-2241`.

This slice migrates direct CLI adapter success results toward the provider
runtime result contract created in `BAB-2246`, while preserving current Ticket
turn behavior.

Scope:

- Add a small provider runtime result module for direct CLI result maps.
- The result constructor takes `provider` as a required argument from each
  adapter's `provider/0` callback.
- Make Claude, Codex, Copilot, and Fake direct CLI adapters return normalized
  success maps with:
  - `status: :ok`
  - `provider`
  - `backend: "direct_cli"`
  - `provider_session_id`
  - `reply`
  - `diagnostics`
  - `capabilities`
  - `raw_artifact_refs`
  - compatibility `text`
- `text` and `reply` hold the same value in this slice; `text` is a
  compatibility alias until existing call sites fully migrate.
- `capabilities` comes from the adapter/result caller when provided, defaulting
  to `%{"direct" => true}`.
- Successful direct CLI diagnostics use `%{redacted: true, summary: nil}` so
  the shape remains stable for Phase 13f.4 diagnostics standardization.
- Preserve existing caller compatibility by keeping `text` and
  `provider_session_id` available until later call sites move fully to
  `reply`.
- Update the direct runner to prefer `reply` while still accepting `text`.
- Add regression tests for Claude, Codex, Copilot, Fake, and direct runner
  Ticket reply persistence.

Out of scope:

- Changing direct CLI command construction.
- Changing provider session table schema or Ticket history schema.
- Changing Hardline/tmux capability mapping. That is Phase 13f.3.
- Standardizing failed/timeout/cancelled diagnostics across all providers.
  That remains Phase 13f.4.
- Live quota-consuming provider canaries.
- Browser UI changes.

## Why

`BAB-2246` made provider capabilities inspectable, but direct CLI adapter
success maps still use the pre-contract shape where reply text is only `text`
and backend/status/diagnostics/raw-artifact fields are implicit. Phase 14-17
automation should consume direct provider outcomes through one stable result
shape before role routing, inspector councils, Mayor proposals, and federation
depend on provider-specific behavior.

This CHG keeps the migration low-risk by preserving existing keys and runtime
behavior while adding the normalized fields.

## Impact Analysis

- **Systems affected:** `:babs_citizens` direct CLI adapter parse results and
  direct runner reply persistence.
- **Runtime behavior:** no intended user-visible behavior change; existing
  direct CLI Ticket turns should keep writing the same visible comments and
  provider session rows.
- **Database:** no migrations.
- **Tests:** adapter unit tests and direct runner tests expand to cover the
  normalized fields and compatibility keys.
- **Privacy:** normalized result maps must keep `raw_artifact_refs` empty for
  direct CLI providers and must not store raw stdout/stderr, prompts, private
  hostnames/IPs, local paths, or credentials.
- **Rollback:** revert the CHG commit. Since this slice is additive to result
  maps and preserves legacy keys, rollback should not affect existing data.

## Implementation Plan

1. **Review this CHG before code**
   - Run Trinity `fast-review` against this CHG and fold blockers.

2. **Add result helper**
   - Add `Babs.Citizens.ProviderRuntime.Result`.
   - Provide a constructor for successful direct CLI results with required
     `provider` and `reply` arguments.
   - Include `reply` and compatibility `text`.
   - Include adapter-provided `capabilities`, defaulting to
     `%{"direct" => true}`.
   - Include `diagnostics: %{redacted: true, summary: nil}` and
     `raw_artifact_refs: []` for direct CLI rows.

3. **Migrate direct adapters**
   - Update Claude, Codex, Copilot, and Fake `parse_result/2` success paths to
     use the result helper.
   - Preserve `{:error, reason}` parse failures in this slice so existing
     runner fallback behavior remains unchanged.

4. **Preserve runner behavior**
   - Update direct runner reply persistence to prefer `reply`, falling back to
     `text`.
   - Keep provider session update behavior compatible with existing
     `provider_session_id` and `capabilities` fields.

5. **Add tests**
   - Adapter tests assert normalized fields and legacy compatibility fields for
     each provider.
   - Runner tests prove a direct CLI Ticket turn still persists the visible
     reply comment.
   - Existing runner tests that execute Fake stdout fixtures should validate
     the migration naturally once Fake `parse_result/2` returns normalized
     results; extend those tests only where needed instead of duplicating large
     fixtures.
   - Privacy tests assert direct normalized results use empty
     `raw_artifact_refs` and redacted diagnostics.

6. **Validate and review**
   - Run focused tests first.
   - Run the applicable local validation stack.
   - Run Trinity implementation `fast-review`.
   - Open PR with `gh` as `ryosaeba1985` and follow `COR-1615`/`COR-1612`.

## Acceptance Criteria

- Claude, Codex, Copilot, and Fake direct CLI successful parse results expose
  the normalized fields from `BAB-2241`.
- Existing callers can still read `result.text` and `result.provider_session_id`.
- Direct runner writes the same visible Ticket reply for direct CLI turns after
  the migration.
- Direct CLI normalized results expose `backend: "direct_cli"`,
  `status: :ok`, `reply`, `diagnostics`, `capabilities`, and
  `raw_artifact_refs: []`.
- In direct CLI normalized success results, `text == reply`.
- Direct adapter parse failures still trigger existing fallback/error handling.
- No raw stdout/stderr, prompts, credentials, private hostnames/IPs, local paths,
  or raw artifact locators are exposed in normalized direct CLI results,
  fixtures, docs, PR body, or review packets.

## Validation Plan

Focused:

```bash
mise exec -- mix test apps/babs_citizens/test/babs_citizens/direct_cli/adapters_test.exs apps/babs_citizens/test/babs_citizens/direct_cli/runner_test.exs
```

Standard local gates for this non-UI slice:

```bash
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
af validate --root .
git diff --check
```

Because this slice does not change browser assets or LiveViews, `npm run
test:js`, `npm run test:e2e`, and `npm run test:bdd` are not required locally
unless implementation scope expands into browser code. The GitHub Actions Test
workflow remains the PR gate.

## Review Plan

- Trinity `fast-review` on this CHG before implementation.
- Trinity `fast-review` on the implementation diff before PR.
- GitHub Codex review loop on the PR, capped at five rounds.
- Use `gh` authenticated as `ryosaeba1985` for public GitHub writes.

## Results

- 2026-05-08 CHG review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-093905-Phase-13f.2-Direct-CLI-normalized-result-CHG`
  - GLM PASS and DeepSeek PASS.
  - Folded advisories for capability source, diagnostics shape, `text`/`reply`
    alias semantics, Fake runner fixture reuse, and provider argument
    requirements.
- 2026-05-08 implementation:
  - Added `Babs.Citizens.ProviderRuntime.Result` with `direct_success/3`.
  - Migrated Claude, Codex, Copilot, and Fake direct CLI adapter success parse
    results to expose normalized fields while preserving `text` and
    `provider_session_id`.
  - Updated direct runner reply persistence to prefer `reply` while retaining
    `text` compatibility.
  - Added provider runtime result tests and adapter normalization assertions.
- 2026-05-08 local validation:
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/provider_runtime/result_test.exs apps/babs_citizens/test/babs_citizens/direct_cli/adapters_test.exs`:
    14 tests, 0 failures.
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/provider_runtime apps/babs_citizens/test/babs_citizens/direct_cli/adapters_test.exs apps/babs_citizens/test/babs_citizens/direct_cli/runner_test.exs`:
    45 tests, 0 failures.
  - `mise exec -- mix format --check-formatted`: pass.
  - `mise exec -- mix compile --warnings-as-errors`: pass.
  - `mise exec -- mix test`: `babs_citizens` 340 tests, 0 failures; `babs`
    82 tests, 0 failures.
  - `af validate --root .`: 156 documents checked, 0 issues found.
  - `git diff --check`: pass.
  - Targeted privacy scan for private host/IP/path patterns in the Phase 13f.2
    docs/code/tests: pass.
- 2026-05-08 implementation review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-094603-Phase-13f.2-Direct-CLI-normalized-result-implementation-diff`
  - GLM PASS and DeepSeek PASS with no blocking findings.
  - Remaining notes were non-blocking cleanup/deprecation-tracking candidates
    for later slices.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial Phase 13f.2 implementation CHG | Codex |
| 2026-05-08 | Trinity fast-review passed GLM and DeepSeek; folded result shape contract clarifications | Codex |
| 2026-05-08 | Record Phase 13f.2 implementation and local validation results | Codex |
| 2026-05-08 | Record Trinity implementation review pass | Codex |
