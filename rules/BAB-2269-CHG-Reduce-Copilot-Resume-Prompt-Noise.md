# CHG-2269: Reduce Copilot Resume Prompt Noise

**Applies to:** BAB project
**Last updated:** 2026-05-09
**Last reviewed:** 2026-05-09
**Status:** Approved
**Date:** 2026-05-09
**Requested by:** Operator
**Priority:** Medium
**Change Type:** Bugfix
**Related:** `BAB-2268`

---

## Objective

Reduce repeated Babs protocol text in Copilot CLI provider-session transcripts
after the first direct-CLI turn.

The operator observed that `copilot --resume` history still shows repeated
non-interactive wrapper text for each Ticket follow-up. The direct turn now
captures correctly, but the provider transcript is noisy and hard to read.

## Non-Goals

- No change to direct reply parsing semantics from `BAB-2268`.
- No change to Claude, Codex, Fake, hardline, tmux, or Ticket UI behavior.
- No retroactive cleanup of existing Copilot provider-session history.
- No removal of the initial Copilot start protocol wrapper.

## Contract

- Copilot start turns must keep the full one-line reply protocol wrapper.
- Copilot resume turns must send a compact prompt containing only the latest
  operator message and the required `BABS_REPLY <ticket_id>:` reply marker when
  that latest message can be extracted.
- Copilot resume prompts must not include the repeated "You are running as a
  Babs Citizen..." wrapper or "Original Babs prompt" header.
- If a resume prompt cannot be compacted safely, Babs may fall back to the
  original prompt plus a short one-line reply instruction.
- Ticket reply capture must continue to parse direct Copilot replies correctly.

## Implementation Plan

1. Add RED adapter coverage for Copilot `resume_command/4` prompt construction.
2. Pass `resume?: true` into Copilot resume command prompt construction.
3. Add Copilot resume prompt compaction that extracts `Latest operator message`.
4. Run direct adapter and direct runner tests, plus formatting and validation.

## Acceptance Criteria

- Copilot resume command args include `--resume=<session_id>`.
- Copilot resume prompt contains the latest operator message and current Ticket
  reply marker.
- Copilot resume prompt omits the repeated full non-interactive wrapper.
- Existing Copilot parsing regressions continue to pass.

## Validation Commands

```bash
mise exec -- mix test apps/babs_citizens/test/babs_citizens/direct_cli/adapters_test.exs apps/babs_citizens/test/babs_citizens/direct_cli/runner_test.exs --seed 1
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
af validate --root .
git diff --check
```

## Results

- Implementation:
  - Changed Copilot `resume_command/4` to pass `resume?: true` into prompt
    construction.
  - Kept the full Copilot non-interactive wrapper for start turns.
  - Added a compact Copilot resume prompt that extracts `Latest operator
    message` and sends only that message plus the required one-line
    `BABS_REPLY` marker.
  - Tightened the compaction delimiter to the generated `Reply ... with:`
    trailer followed by the current `BABS_REPLY` marker, so operator text
    containing its own "Reply..." paragraph is preserved.
  - Anchored the delimiter to the final generated trailer at the end of the
    prompt, so operator text that quotes the current Ticket's reply trailer is
    also preserved.
  - Added adapter coverage proving resume prompts omit the repeated full
    wrapper, still include the current Ticket marker, and preserve valid
    operator paragraphs that start with "Reply".
- Validation:
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/direct_cli/adapters_test.exs --seed 1`: pass; 21 tests, 0 failures.
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/direct_cli/adapters_test.exs apps/babs_citizens/test/babs_citizens/direct_cli/runner_test.exs --seed 1`: pass; 41 tests, 0 failures.
  - `mise exec -- mix format --check-formatted`: pass.
  - `mise exec -- mix compile --warnings-as-errors`: pass.
  - `mise exec -- mix test --seed 1`: pass; `babs_citizens` 521 tests, 0 failures; `babs` 137 tests, 0 failures.
  - `af validate --root .`: pass; 179 documents checked, 0 issues found.
  - `git diff --check`: pass.
  - Manual Copilot resume command construction produced a compact prompt with
    only the latest operator message plus the required `BABS_REPLY` marker, and
    parsed the direct Copilot reply successfully.
- Review:
  - GitHub Codex review R1 found one P2 issue: the resume prompt compaction
    delimiter could truncate an operator message containing a paragraph that
    starts with "Reply".
  - Fixed by matching the generated trailer only when it is followed by the
    current Ticket's `BABS_REPLY` marker, and added a regression.
  - GitHub Codex review R2 found one P2 issue: operator text could quote the
    current Ticket's `Reply with:` trailer and still be truncated at the first
    occurrence.
  - Fixed by anchoring compaction to the final generated trailer at the end of
    the prompt, and added a regression.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-09 | Initial Copilot resume prompt noise CHG | Codex |
