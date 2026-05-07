# CHG-2231: Fix Copilot Compact Paste System Injection

**Applies to:** BAB project
**Last updated:** 2026-05-07
**Last reviewed:** 2026-05-07
**Status:** Completed
**Date:** 2026-05-07
**Requested by:** Frank
**Priority:** High
**Change Type:** Normal

---

## What

Fix Ticket prompt injection into GitHub Copilot CLI when Copilot renders long
paste input as a compact `[Paste #N - ... lines]` block.

## Why

Manual testing reported `Ticket prompt could not be injected into elena`. The
Elena tmux pane showed `[Paste #1 - 21 lines]`, proving the prompt reached
Copilot but Babs' receipt check did not recognize Copilot's compact paste UI as
successful delivery. Babs then recorded `injection_failed` and left the prompt
unsubmitted in the Copilot input area.

## Impact Analysis

- **Systems affected:** AI CLI system-prompt delivery for Ticket assignment,
  Ticket comments, and rejection feedback.
- **Runtime behavior:** Long Copilot prompts should be treated as received when
  the compact paste block appears, then submitted with Enter.
- **Risk:** Treating a compact paste block as receipt could be too broad if a
  pane already has an unrelated compact paste pending. The condition remains
  scoped to the active delivery flow immediately after Babs calls tmux paste.
- **Rollback plan:** Revert `SystemDelivery` and test changes.

## Implementation Plan

1. Add failing `SystemDelivery` unit coverage for Copilot-style compact paste
   receipt.
2. Recognize `[Paste #` as an editable compact paste block.
3. Treat compact paste UI as delivery receipt when the explicit Ticket marker is
   hidden by the AI CLI.
4. Validate with focused tests, full ExUnit, and a runtime Elena injection
   smoke.

## Implementation Outcome

- Added a regression test for Copilot compact paste receipt handling.
- Updated `Babs.Citizens.Hardline.SystemDelivery` to accept Copilot's
  `[Paste #N - ... lines]` editable block as proof that the paste reached the
  AI CLI when the explicit ticket marker is hidden.
- Verified runtime injection against Elena with `T-2026-05-07-007`; assignment
  returned `delivery: {:injected, "elena"}` and the Copilot pane submitted the
  prompt instead of leaving it pending.

## Validation

- `mise exec -- mix test apps/babs_citizens/test/babs_citizens/hardline/system_delivery_test.exs apps/babs_citizens/test/babs_citizens/tickets/injector_test.exs apps/babs_citizens/test/babs_citizens/tickets/api_writer_store_test.exs`
  - 44 tests, 0 failures
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`
  - `babs_citizens`: 251 tests, 0 failures
  - `babs`: 75 tests, 0 failures
- `af validate --root .`
  - 138 documents checked, 0 issues found
- `git diff --check`

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-07 | Initial version | Codex |
| 2026-05-07 | Completed compact paste fix and validation | Codex |
