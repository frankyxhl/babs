# CHG-2250: Implement Phase 13f.4 Provider Diagnostics and Redaction

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

Implement **Phase 13f.4: Provider diagnostics and redaction** from `BAB-2241`.

This slice standardizes public-safe, operator-visible diagnostics for direct
provider failures without changing execution behavior.

Scope:

- Add a provider runtime diagnostics helper that converts provider failure
  reasons into a normalized, redacted map.
- Add direct provider failure result helpers that expose:
  - `status: :failed | :timeout | :cancelled | :unsupported`
  - `provider`
  - `backend: "direct_cli"`
  - `provider_session_id`
  - `reply: nil`
  - `text: nil`
  - `diagnostics`
  - `capabilities`
  - `raw_artifact_refs: []`
- Result `status` remains an atom for Elixir callers. Diagnostics `category`
  remains a string for public maps. The mapping is:
  `:failed -> "failed"`, `:timeout -> "timeout"`,
  `:cancelled -> "cancelled"`, and `:unsupported -> "unsupported"`.
- `raw_included: false` is intentionally explicit so future debug-only or
  operator-private diagnostics modes cannot accidentally look equivalent to the
  public-safe default.
- Use the same diagnostics summary for direct runner failure events and
  `provider_sessions.last_error`.
- Preserve existing direct runner fallback behavior.
- Add privacy tests for local paths, private-network values, configured secret
  values, raw stdout/stderr, and provider parse failures.

Out of scope:

- Changing provider command construction.
- Changing direct CLI success result behavior from Phase 13f.2.
- Changing Hardline/tmux lifecycle behavior.
- Changing Ticket schemas or provider session schemas.
- Browser UI changes.
- Live provider canaries.

## Why

Phase 13f.1 made provider capabilities inspectable, Phase 13f.2 normalized
direct provider success results, and Phase 13f.3 surfaced Hardline capability
data. Provider failure handling is still spread across runner event builders,
`ProviderSessions.mark_failed/2`, executor errors, parser errors, and ad hoc
redaction calls.

Phase 14-17 automation will route, inspect, approve, plan, and remotely expose
Citizen failures. Those phases need one public-safe diagnostic shape so failure
summaries can be shown to operators and persisted without leaking local paths,
private network values, raw provider output, prompts, or credentials.

## Impact Analysis

- **Systems affected:** `:babs_citizens` provider runtime result helpers,
  direct CLI runner failure persistence/events, and direct CLI failure tests.
- **Runtime behavior:** direct provider failures should still fall back to
  Hardline exactly as before where fallback is enabled.
- **Database:** no migrations; existing `provider_sessions.last_error` remains a
  string, but the source summary becomes standardized.
- **Tests:** add deterministic unit tests for diagnostics and focused direct
  runner failure tests.
- **Privacy:** diagnostics must not expose raw stdout/stderr, raw prompts,
  configured secret values, local checkout paths, private hostnames/IPs, or
  credentials.
- **Rollback:** revert the CHG commit. Since this slice only changes failure
  summaries and preserves fallback semantics, rollback should not affect
  existing runtime data or tmux sessions.

## Implementation Plan

1. **Review this CHG before code**
   - Run Trinity `fast-review` against this CHG and fold blockers.

2. **Add diagnostics helper**
   - Add `Babs.Citizens.ProviderRuntime.Diagnostics`.
   - Provide a function that accepts a failure reason plus redaction opts and
     returns a map shaped like:

     ```elixir
     %{
       redacted: true,
       summary: "...",
       category: "timeout" | "failed" | "unsupported" | "cancelled",
       raw_included: false
     }
     ```

   - The summary must be bounded and redacted with
     `Babs.Citizens.DirectCli.Redactor.redact_text/2`.
   - Configured secret values mean `CitizenConfig.env` values whose names are
     returned by `Babs.Citizens.DirectCli.Env.secret_names/1`, plus those values
     returned by `Babs.Citizens.DirectCli.Env.secret_values/1`.

3. **Extend result helper**
   - Add a direct failure helper to `Babs.Citizens.ProviderRuntime.Result`.
   - Keep `raw_artifact_refs: []`.
   - Keep compatibility `text: nil` for failure results.

4. **Use diagnostics in direct runner failure paths**
   - Convert direct execution/parse errors into diagnostics summaries before
     writing `turn_delivery_failed`, `turn_reply_capture_failed`, and
     `provider_sessions.last_error`.
   - Preserve current fallback behavior and event names.
   - Do not store raw artifacts in Ticket history or provider session rows.

5. **Add tests**
   - Diagnostics unit tests for timeout, unsupported, exit-status artifacts,
     parse failures, and configured secret value redaction.
   - Direct runner tests proving failed provider sessions and Ticket failure
     events use redacted diagnostics summaries.
   - Regression tests proving direct fallback still occurs.

6. **Validate and review**
   - Run focused tests first.
   - Run the applicable local validation stack.
   - Run Trinity implementation `fast-review`.
   - Open PR with `gh` as `ryosaeba1985` and follow `COR-1615`/`COR-1612`.

## Acceptance Criteria

- Direct provider failure diagnostics use one normalized map shape.
- Failure summaries are bounded and redacted.
- Timeout, unsupported, cancelled, exit-status, and parse-failure reasons map to
  stable categories/statuses.
- Direct runner failure events and `provider_sessions.last_error` use the same
  redacted diagnostic summary.
- Existing direct-to-Hardline fallback behavior remains unchanged.
- No raw stdout/stderr, prompts, credentials, configured secret values, private
  hostnames/IPs, local paths, or raw artifact locators are exposed in
  diagnostics, fixtures, docs, PR body, or review packets.

## Validation Plan

Focused:

```bash
mise exec -- mix test apps/babs_citizens/test/babs_citizens/provider_runtime apps/babs_citizens/test/babs_citizens/direct_cli/runner_test.exs apps/babs_citizens/test/babs_citizens/provider_sessions_repo_test.exs
```

Standard local gates:

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
    `.trinity/reviews/20260508-101919-Phase-13f.4-Provider-diagnostics-and-redaction-CHG`
  - GLM PASS and DeepSeek PASS.
  - Folded advisories for status/category mapping, `raw_included: false`
    intent, exact redactor module/function, and configured secret definition.
- 2026-05-08 implementation review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-103836-Phase-13f.4-Provider-diagnostics-and-redaction-final-diff-after-advisory-folds`
  - GLM PASS and DeepSeek PASS.
  - No blocking issues found; remaining notes are non-blocking polish.
- 2026-05-08 implementation:
  - Added `Babs.Citizens.ProviderRuntime.Diagnostics`.
  - Added normalized `Result.direct_failure/3`.
  - Updated direct runner failure events and `provider_sessions.last_error` to
    use shared redacted diagnostic summaries.
  - Folded Trinity implementation advisory by routing
    `ProviderSessions.mark_non_resumable/3` through the same diagnostic
    summary helper.
  - Folded Trinity final-review privacy advisory by redacting before final
    output bounding in diagnostics summaries.
  - Added focused diagnostics, result, provider-session, and direct-runner
    privacy tests.
- 2026-05-08 local validation:
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/provider_runtime apps/babs_citizens/test/babs_citizens/direct_cli/runner_test.exs apps/babs_citizens/test/babs_citizens/provider_sessions_repo_test.exs`
    passed: 46 tests, 0 failures.
  - `mise exec -- mix format --check-formatted` passed.
  - `mise exec -- mix compile --warnings-as-errors` passed.
  - `mise exec -- mix test` passed: 435 tests, 0 failures.
  - `af validate --root .` passed: 159 documents checked, 0 issues found.
  - `git diff --check` passed.
  - Changed-file privacy scan found no real private host/IP/path/token values;
    only synthetic test secret fixtures were present.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial Phase 13f.4 implementation CHG | Codex |
| 2026-05-08 | Trinity fast-review passed GLM and DeepSeek; folded diagnostics shape and redaction-source clarifications | Codex |
| 2026-05-08 | Implemented provider diagnostics and local validation results | Codex |
| 2026-05-08 | Folded Trinity implementation advisory for non-resumable session diagnostics | Codex |
| 2026-05-08 | Folded Trinity final-review advisory for redaction-before-bounding order | Codex |
| 2026-05-08 | Trinity final implementation review passed GLM and DeepSeek | Codex |
