# CHG-2237: Implement Phase 13b Direct CLI Resumable Prompt Compaction

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

Implement Phase 13b: Direct CLI resumable prompt compaction.

Scope:

- For `direct_cli` Ticket comment turns that have an active resumable provider
  session, send a compact prompt instead of re-sending Ticket body and recent
  visible chat history.
- The compact prompt contains only:
  - Ticket id.
  - The latest operator message.
  - The required reply protocol: `BABS_REPLY <ticket_id>: ...`.
- The compact prompt deliberately omits the Citizen identity/runtime preamble
  and Ticket state/header wrapper because the resumed provider session already
  carries that context from the initial turn.
- Keep full-context prompts for:
  - Initial Ticket assignment / first direct turn.
  - Direct turns without an active `provider_session_id`.
  - Non-resumable provider sessions.
  - Direct CLI fallback paths after session lookup or resume failure.
  - Reject feedback / approval feedback and other explicit state-transition
    prompts.
- Preserve existing hardline prompt behavior. Hardline terminals still need
  explicit context because tmux state is not a structured resumable provider
  session.
- Keep provider session reuse unchanged for Claude, Codex, Copilot, and Fake
  adapters.

Out of scope:

- Summarization memory.
- Token accounting UI.
- Editing Ticket body/title and broadcasting body diffs to existing sessions.
- Changing provider adapter command syntax beyond choosing compact vs full
  prompt.

## Why

Phase 13a.3/13a.4 made direct CLI sessions resumable, but follow-up comments
still include Ticket body plus up to 12 recent visible messages. That is
conservative, but redundant when the provider session is already resumed.

The operator observed this during manual dogfood: the second message included
the first message and prior context. This wastes tokens and can make the model
over-focus on old content. For providers with reliable resume support, the
session should carry conversational memory; Babs only needs to deliver the new
operator message and reply protocol.

## Impact Analysis

- **Systems affected:** Ticket prompt assembly, direct CLI runner/session
  selection, Ticket writer direct-comment delivery, unit tests, and
  browser-harness BDD for multi-turn direct conversations.
- **Data:** no migration. Existing `provider_sessions` rows remain valid.
- **Runtime:** direct CLI comments after the first turn become smaller. First
  turn behavior is intentionally unchanged.
- **Provider compatibility:** compact prompt is only valid when Babs is using an
  active provider session with a non-empty `provider_session_id`; otherwise
  Babs falls back to the existing full prompt.
- **Privacy:** compact prompts further reduce repeated local context exposure.
  Validation artifacts must not publish private hostnames, private IPs, local
  checkout paths, tokens, or live provider raw output.
- **Rollback plan:** revert this CHG's implementation PR. Existing Tickets and
  provider sessions remain compatible because the change only affects future
  prompt text selection.

## Implementation Plan

1. **Plan review**
   - Fill this CHG before code.
   - Review the plan with Trinity `fast-review` and fold blockers.

2. **RED tests**
   - Add `PromptAssembler` unit tests showing compact prompts include the latest
     operator message and reply protocol but exclude Ticket body and previous
     chat messages.
   - Add direct runner/writer tests proving a resumed direct comment uses the
     compact prompt when the active session has a `provider_session_id`.
   - Add regression coverage proving the first direct assignment still uses full
     Ticket context.
   - Add BDD coverage for a deterministic direct Citizen where the fake direct
     executor records the prompt sent to the provider and the second Ticket
     comment does not resend the first comment or Ticket body, while the same
     provider session is reused.

3. **Implementation**
   - Add a compact prompt builder to `Babs.Citizens.Tickets.PromptAssembler`.
   - Teach direct comment delivery to choose compact prompt only when an active
     resumable provider session exists for `{citizen_slug, ticket_id, provider,
     direct_cli}`. Make this selection in the direct delivery path before
     prompt assembly, not inside hardline prompt code.
   - Reuse `PromptAssembler` sanitization for the compact latest-message body;
     never pass raw operator text directly to provider commands.
   - Keep full prompt for initial assignment, non-resumable sessions, missing
     sessions, feedback prompts, and hardline.
   - Avoid duplicating provider adapter resolution rules; use existing direct
     CLI adapter/session helpers where practical.

4. **REFACTOR**
   - Keep compact/full prompt selection isolated near direct delivery so
     hardline and feedback paths remain simple.
   - Preserve current public APIs unless a small private helper makes tests
     materially clearer.

5. **Validation**
   - Run focused Elixir unit tests for prompt assembly, direct runner/session
     prompt choice, and Ticket writer direct comments.
   - Run focused browser-harness BDD for direct multi-turn compact prompts.
   - Run formatting, compile, full test, coverage, JS/E2E where applicable,
     `af validate`, `git diff --check`, and privacy scan before PR.

## Acceptance Criteria

- The first direct assignment prompt still contains full Ticket context.
- A follow-up direct CLI comment with an active `provider_session_id` sends a
  compact prompt containing only the latest operator message plus reply
  protocol.
- The compact prompt does not include Ticket body or previous chat messages.
- Provider session reuse still works; the second direct turn uses the same
  provider session id.
- Hardline, feedback, and missing/non-resumable session paths continue to use
  full-context behavior.
- BDD covers the dogfood scenario that motivated this CHG.

## Validation Plan

Planned commands:

```bash
mise exec -- mix test \
  apps/babs_citizens/test/babs_citizens/tickets/prompt_assembler_test.exs \
  apps/babs_citizens/test/babs_citizens/direct_cli/runner_test.exs
BU_CDP_URL=http://127.0.0.1:9333 \
  BABS_BDD_SCENARIO="direct cli compact prompt" \
  BABS_HTTP_PORT=4109 \
  BABS_BROWSER_BASE_URL=http://127.0.0.1:4109 \
  npm run test:bdd
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
mise exec -- mix test --cover --export-coverage phase13b
mise exec -- mix cmd mix test.coverage
npm run test:js
npm run test:e2e
af validate --root .
git diff --check
```

Final results:

- Focused RED/GREEN suite:
  `mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/prompt_assembler_test.exs apps/babs_citizens/test/babs_citizens/direct_cli/runner_test.exs`:
  22 tests, 0 failures.
- `python3 -m py_compile test/browser/bdd/babs_steps.py
  test/browser/bdd/run.py`: passed.
- Focused browser-harness BDD `direct cli compact prompt`: passed.
- `mise exec -- mix format --check-formatted`: passed.
- `mise exec -- mix compile --warnings-as-errors`: passed.
- `mise exec -- mix test`: 402 tests, 0 failures.
- Coverage export/report:
  - `mise exec -- mix test --cover --export-coverage phase13b`: 402 tests,
    0 failures.
  - `mise exec -- mix cmd mix test.coverage`: passed with `:babs_citizens`
    83.52% total and `:babs` 88.50% total.
- `npm run test:js`: 15 tests, 0 failures.
- `npm run test:e2e`: 13 tests total, 12 passed, 1 skipped.
- `af validate --root .`: 145 documents checked, 0 issues found.
- `git diff --check`: passed.
- Diff privacy scan for private network address, hostnames, local checkout
  path, GitHub tokens, and OpenAI-style API keys: no matches in the current
  diff.

## Review Results

- Trinity fast-review R1: GLM PASS 9.0/10; DeepSeek PASS. Folded advisory
  clarifications for compact prompt wrapper omission, direct-delivery insertion
  point, sanitizer reuse, BDD prompt capture mechanism, and concrete
  `af validate --root .` command.
- Trinity implementation fast-review R1: GLM PASS 9.0/10; DeepSeek PASS.
  Advisory coverage for non-resumable or empty-session fallback was resolved by
  adding regression coverage. The same check exposed a stale provider-session
  id being carried into fresh direct starts for `non_resumable` rows; the runner
  now passes provider-session ids only to true active resumable turns.
- Trinity final implementation fast-review R2:
  `.trinity/reviews/20260508-014845-Phase-13b-final-implementation-diff`.
  GLM PASS; DeepSeek PASS. No blocking issues. Remaining advisory notes were
  limited to possible future DRY consolidation of resumable-session checks and
  stricter test-only JSONL parsing.
- GitHub Codex PR review R1 on commit `095dcfa6d9`: P2 finding that compact
  direct prompts were also used by `DirectRunner` hardline fallback after a
  direct resume/execution failure. Fixed by threading a separate full
  `fallback_prompt` for direct comments and adding a regression test proving
  tmux fallback receives full Ticket context.
- Trinity post-Codex-fix fast-review R3:
  `.trinity/reviews/20260508-015951-Phase-13b-post-Codex-review-fix-diff`.
  GLM PASS; DeepSeek PASS. No blocking issues.

## References

- `BAB-2232` Phase 13a Multi-Turn Ticket Sessions and Direct CLI Backend PRP
- `BAB-2235` Phase 13a.3 Direct CLI Provider Sessions CHG
- `BAB-2236` Phase 13a.4 Direct Backend UI Controls CHG
- `BAB-1112` Multi-AI-CLI Citizen Configuration ADR
- `BAB-1503` Babs Phase Delivery Workflow adapter

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial version | — |
| 2026-05-08 | Fill Phase 13b contract for resumable direct prompt compaction | Codex |
| 2026-05-08 | Fold Trinity fast-review R1 advisory clarifications | Codex |
| 2026-05-08 | Record implementation validation results | Codex |
| 2026-05-08 | Add fallback regression coverage and final validation results | Codex |
| 2026-05-08 | Record final Trinity implementation review pass | Codex |
| 2026-05-08 | Resolve GitHub Codex P2 hardline fallback finding | Codex |
