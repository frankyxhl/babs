# CHG-2268: Fix Copilot Direct Reply Capture

**Applies to:** BAB project
**Last updated:** 2026-05-09
**Last reviewed:** 2026-05-09
**Status:** Approved
**Date:** 2026-05-09
**Requested by:** Operator
**Priority:** High
**Change Type:** Bugfix
**Related:** `BAB-2230`, `BAB-2248`, `BAB-2250`

---

## Objective

Fix a Copilot direct-CLI reply capture bug where Babs accepts planning or
analysis-shaped provider output as the Citizen's Ticket comment.

The operator observed a Copilot Citizen answering a simple "what is your name?"
Ticket with meta text about how it should reply, instead of a final user-facing
answer. The direct turn completed and was captured, but the captured comment was
not semantically valid.

## Non-Goals

- No provider-wide redesign of the direct CLI runtime.
- No change to Claude, Codex, Fake, hardline, tmux transcript, or JSONL capture
  behavior unless required by shared tests.
- No retroactive mutation of existing runtime Ticket history.
- No new UI redesign for Ticket detail refresh in this slice.

## Contract

- Copilot direct output must prefer a real `BABS_REPLY <ticket_id>:` reply line
  when the provider emits one.
- Inline quoted instructions such as `` `BABS_REPLY <ticket_id>: your response` ``
  must not be captured as a valid reply.
- When Copilot includes analysis before a final reply line, Babs must capture
  only the final reply body, without the `BABS_REPLY` marker and without the
  analysis text.
- If Copilot omits the marker, Babs may accept only a narrow markerless fallback:
  exactly one non-empty line that does not contain `BABS_REPLY`, is not a
  placeholder, and does not look like planning or analysis text.
- If Copilot provides neither a valid final reply line nor a safe markerless
  one-line answer, direct delivery must fail visibly instead of recording the
  analysis text as a Citizen comment.
- Copilot prompts should be tightened so the provider is explicitly told to
  return one final line only.

## Implementation Plan

1. Add RED tests for Copilot direct result parsing:
   - extracts a final `BABS_REPLY` line from noisy output;
   - rejects analysis output that only mentions the marker as an instruction.
2. Tighten the Copilot adapter prompt wrapper and parser.
3. Run focused direct adapter tests and the relevant direct runner tests.
4. Run formatting, validation, and privacy checks.

## Acceptance Criteria

- Copilot parser captures a concise final answer from a valid `BABS_REPLY`
  line.
- Copilot parser captures a concise markerless one-line final answer when
  Copilot ignores the marker instruction.
- Copilot parser rejects the observed planning-text failure mode.
- Existing direct CLI adapter tests continue to pass.
- No private hostnames, local checkout paths, IPs, runtime Ticket payloads,
  tokens, or secrets are published in code, docs, or PR text.

## Validation Commands

```bash
mise exec -- mix test apps/babs_citizens/test/babs_citizens/direct_cli/adapters_test.exs --seed 1
mise exec -- mix test apps/babs_citizens/test/babs_citizens/direct_cli/runner_test.exs --seed 1
mise exec -- mix format --check-formatted
af validate --root .
git diff --check
git diff -U0 | rg -n '^\+.*(100\.[0-9]{1,3}|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|/Users/[^[:space:]]+|api_token|secret|token)' || true
```

## Results

- Implementation:
  - Wrapped Copilot direct prompts with an explicit "one final line" protocol.
  - Changed Copilot direct result parsing to accept only a line-start
    `BABS_REPLY <ticket_id>:` marker.
  - Passed the current Ticket id from the direct runner into the Copilot adapter
    so prompts and parsing cannot be steered by stale quoted markers.
  - Changed Copilot parsing to reject planning text that only quotes the marker
    instruction inline.
  - Added a conservative markerless fallback for Copilot output: accept only one
    non-empty final-answer line with no `BABS_REPLY` token, no placeholder, and
    no planning-shaped prefix.
  - Hardened background reply capture so a missing/unavailable Citizen catalog
    table is ignored instead of crashing capture polling during CI or early
    runtime startup.
- Validation:
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/direct_cli/adapters_test.exs --seed 1`: pass; 18 tests, 0 failures.
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/direct_cli/adapters_test.exs apps/babs_citizens/test/babs_citizens/direct_cli/runner_test.exs --seed 1`: pass; 35 tests, 0 failures.
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/reply_capture_test.exs --seed 1`: pass; 10 tests, 0 failures.
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/mix_tasks_test.exs --seed 193306`: pass; 2 tests, 0 failures.
  - `mise exec -- mix test`: pass; `babs_citizens` 514 tests, 0 failures; `babs` 137 tests, 0 failures.
  - `mise exec -- mix format --check-formatted`: pass.
  - `mise exec -- mix compile --warnings-as-errors`: pass.
  - `af validate --root .`: pass; 178 documents checked, 0 issues found.
  - `git diff --check`: pass.
  - Privacy diff scan for private IP ranges, local paths, and credentials: pass.
- Review:
  - GitHub Codex review R1 found one P2 issue: Copilot prompt wrapping selected
    the first quoted `BABS_REPLY` marker and parsing accepted any Ticket id.
  - Fixed by passing the current Ticket id into command construction and result
    parsing, selecting that id in the wrapper, and rejecting stale-id final
    markers.
  - GitHub Codex review R2 found one P2 issue: the markerless planning guard was
    too broad and rejected ordinary final answers starting with natural prefixes
    such as "This is".
  - Fixed by narrowing the planning-prefix guard and adding a regression for an
    ordinary markerless answer.
  - Live Ticket follow-up found another Copilot JSONL shape where the real
    `assistant.message` is followed by an `assistant.reasoning` event. Fixed the
    Copilot parser to prefer assistant-message content over later reasoning
    content and added a regression for that ordering.
  - A second live follow-up found the executor redactor could make Copilot JSONL
    invalid by replacing numeric metadata under token-like keys with an unquoted
    `[REDACTED]`. Fixed redaction to preserve JSON validity for quoted JSON
    keys and added regressions for redacted Copilot metadata.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-09 | Initial Copilot direct reply capture bugfix CHG | Codex |
