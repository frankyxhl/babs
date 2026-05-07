# CHG-2230: Elena Copilot Reply Capture BDD Coverage

**Applies to:** BAB project
**Last updated:** 2026-05-07
**Last reviewed:** 2026-05-07
**Status:** Completed
**Date:** 2026-05-07
**Requested by:** Frank
**Priority:** Medium
**Change Type:** Normal

---

## What

Add test coverage for Elena/Copilot Ticket reply capture:

- ExUnit coverage for direct `copilot` JSONL transcript discovery and capture.
- Browser-harness BDD coverage that creates a Ticket in the browser, writes a
  Copilot-style `events.jsonl` assistant reply, invokes the real reply capture
  path, and verifies the Ticket chat shows Elena's captured reply.
- Fix BDD seed CLI detection to check `copilot` for Elena instead of legacy
  `gh`.

## Why

Elena was switched from legacy `gh copilot` to direct `copilot`, and Copilot
reply capture was added to the parser. The existing BDD suite covered Ticket
creation and chat rendering separately, but did not exercise the Copilot JSONL
capture path into Ticket chat.

## Impact Analysis

- **Systems affected:** Browser-harness BDD tests and `:babs_citizens` reply
  capture tests.
- **Runtime behavior:** No production behavior changes intended.
- **Risk:** BDD must remain hermetic and avoid real model/network dependency.
- **Rollback plan:** Remove the new BDD scenario and ExUnit additions.

## Implementation Plan

1. Add failing BDD/ExUnit expectations for direct Copilot/Elena capture.
2. Fix BDD Elena CLI detection from `gh` to `copilot`.
3. Add a BDD helper that runs `ReplyCapture.capture_once/2` with a temporary
   Copilot transcript path and no Babs application startup.
4. Run focused ExUnit and browser-harness BDD with an isolated Chrome CDP
   profile to avoid repeated remote-debugging prompts.

## Implementation Outcome

- Added direct `copilot` transcript discovery coverage in
  `AiTranscriptsTest`.
- Added Elena/direct-Copilot reply capture coverage in `ReplyCaptureTest`.
- Added browser-harness BDD scenario:
  `ticket new form captures Elena Copilot JSONL reply`.
  The scenario creates a Ticket through `/tickets/new`, writes a temporary
  Copilot `events.jsonl`, invokes the real `ReplyCapture.capture_once/2` path,
  and verifies the Ticket chat shows Elena's captured message.
- Updated BDD seed CLI detection so Elena checks `copilot` instead of legacy
  `gh`.

## Browser-Harness Authorization Note

For unattended BDD, use browser-harness Way 2 instead of the everyday Chrome
profile:

1. Launch a separate Chrome instance with `--remote-debugging-address=127.0.0.1`,
   `--remote-debugging-port=<port>`, and a non-default `--user-data-dir`.
2. Run BDD with `BU_CDP_URL=http://127.0.0.1:<port> npm run test:bdd`.

This avoids Chrome 144+ repeated "Allow remote debugging" popups. The normal
Way 1 checkbox is sticky per profile, but the per-attach popup can still
reappear depending on Chrome/browser-harness daemon state.

## Validation

- `python3 -m py_compile test/browser/bdd/babs_steps.py test/browser/bdd/run.py`
- `mise exec -- mix test apps/babs_citizens/test/babs_citizens/ai_transcripts_test.exs apps/babs_citizens/test/babs_citizens/tickets/reply_capture_test.exs`
  - 16 tests, 0 failures
- Isolated Chrome profile browser-harness run:
  `BU_NAME=babs-bdd BU_CDP_URL=http://127.0.0.1:9335 npm run test:bdd`
  - `BDD PASS`

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-07 | Initial version | Codex |
| 2026-05-07 | Completed direct Copilot ExUnit and Elena JSONL BDD coverage | Codex |
