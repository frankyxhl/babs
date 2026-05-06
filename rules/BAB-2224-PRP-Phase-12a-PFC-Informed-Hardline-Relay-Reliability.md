# PRP-2224: Phase 12a PFC-Informed Hardline Relay Reliability

**Applies to:** BAB project
**Last updated:** 2026-05-06
**Last reviewed:** 2026-05-06
**Status:** Approved
**Date:** 2026-05-06
**Requested by:** Operator
**Priority:** High

---

## What

Add a Phase 12a milestone, immediately after Phase 12, that borrows the proven
relay mechanics from
`prefrontal-cortex` without copying its Discord-centric architecture.

Phase 12a makes Babs' Ticket-to-Citizen loop reliable enough for sustained
dogfooding:

1. System-delivered Ticket prompts are pasted and submitted to AI CLIs with an
   adaptive confirmation loop instead of a raw "write bytes plus Enter" guess.
2. Claude/Codex replies are read from their upstream AI CLI JSONL transcripts
   when available, then written back into Ticket history as durable comments.
3. Terminal pane capture remains a diagnostic and fallback path, not the
   primary response source.
4. Ticket/Billboard history remains the authoritative communication surface.

## Why

Phase 12 gives Citizens a durable `bb ticket comment` path, but dogfood showed
two friction points:

- AI CLI prompts can be pasted into the terminal but not submitted until a human
  presses Enter.
- Babs currently asks Citizens to call `bb ticket comment` explicitly, but it
  does not yet observe Claude/Codex's own structured reply stream and convert
  replies back into Ticket history.

`prefrontal-cortex` solved similar problems by using adaptive tmux paste
submission and AI CLI JSONL response extraction. Babs should adopt those
mechanics while keeping its own boundaries: local Tickets, Phoenix UI, OTP
supervision, and no Discord/Telegram adapter in v0.1.

## Scope

### 1. Adaptive System Prompt Delivery

- Add a delivery adapter for system prompts sent by Ticket assignment,
  rejection feedback, and comment notifications.
- For AI CLI citizens (`claude`, `codex`, and later provider-specific
  adapters), prefer tmux buffer paste plus confirmation:
  - wait until the CLI appears idle enough to receive input;
  - paste through a tmux buffer or equivalent paste-safe path;
  - poll pane content for receipt indicators such as pasted-text markers or a
    unique prompt marker;
  - send Enter only after receipt is observed;
  - retry Enter when the pane still shows an editable pasted block.
- Keep manual browser keyboard input as direct PTY bytes.
- Keep deterministic shell citizens on the simpler path unless a test requires
  the adaptive delivery path.
- Return typed failures so Ticket history can distinguish "stored but mirror
  delivery failed" from "stored and injected".

### 2. AI CLI JSONL Reply Capture

- Add read-only transcript adapters for supported AI CLIs.
- Discover the active upstream JSONL transcript for a Citizen without writing
  to the upstream transcript files.
- Match replies to a Ticket delivery using a stable turn marker, Ticket id, and
  injection timestamp.
- Convert matched assistant replies into `comment` history events with `by`
  set to the Citizen slug.
- Ignore malformed, partial, stale, or unrelated JSONL records.
- Fall back to pane-diff extraction only when JSONL is unavailable and the
  response can be matched safely.

### 3. Ticket Chat Integration

- Ensure automatically captured Citizen replies appear in the Ticket detail
  chat panel through the existing Ticket watcher path.
- Avoid duplicate comments when a Citizen both replies normally and explicitly
  runs `bb ticket comment`.
- Preserve Ticket history as the single durable coordination record.

### 4. Tests And Validation

- Unit tests for adaptive delivery state transitions using fake tmux/pane
  functions.
- Unit tests for Claude/Codex JSONL fixture parsing and stale-response guards.
- Writer/API tests proving captured replies append valid `comment` events and
  never rewrite Ticket markdown on parser failure.
- Browser-harness BDD for assignment -> auto-submit -> captured reply -> Ticket
  chat update, with real AI CLI scenarios skipped when the CLI is unavailable.
- Playwright E2E for Ticket chat updates from a simulated captured reply.
- Coverage gates remain at least as high as Phase 12.

## Out Of Scope

- Copying the `prefrontal-cortex` Discord relay architecture.
- Adding Discord, Telegram, Slack, or external chat adapters.
- Direct model API calls.
- Replacing Ticket history JSONL with SQLite or upstream AI CLI JSONL.
- Full Inspector automation from Phase 15 and Mayor automation from Phase 16.
- A fully ADR-complete Unix-domain-socket `bb` transport. Phase 12a may improve
  the command bridge, but UDS remains a separate CHG unless explicitly approved.

## Acceptance Criteria

- Assigning a Ticket to a Claude/Codex Citizen submits the prompt without the
  operator pressing Enter.
- If the AI CLI writes a matched assistant response to its upstream JSONL,
  Babs appends that response to the Ticket history as a Citizen comment.
- The Ticket detail chat panel shows the captured Citizen reply without a page
  reload.
- When JSONL capture is unavailable, Babs reports a typed advisory failure and
  does not create an unrelated or stale comment.
- All new behavior is covered by unit, BDD, and E2E tests.
- No private IPs, local absolute paths, tokens, provider credentials, or raw
  upstream transcript contents are added to repository docs, commits, PR text,
  or fixtures.

## Review Results

- R1 `.trinity/reviews/20260506-200953-rules`: GLM found stale phase-reference
  blockers; DeepSeek passed with advisories.
- R2 `.trinity/reviews/20260506-201548-rules`: GLM and DeepSeek passed with
  advisories; advisories were folded in.
- R3 `.trinity/reviews/20260506-202119-rules`: GLM and DeepSeek passed with
  advisories; final wording/timeline advisories were folded in.
- R4 `.trinity/reviews/20260506-202633-rules`: GLM and DeepSeek passed with no
  blockers. Remaining notes were non-blocking process/wording advisories.

## Implementation Slices

1. **CHG 12a.1: Adaptive Delivery**
   - Introduce delivery behavior and fakeable tmux operations.
   - Use adaptive delivery for system Ticket prompts to AI CLIs.
   - Validate with unit tests and BDD transcript assertions.

2. **CHG 12a.2: JSONL Capture**
   - Add provider-specific read-only transcript discovery and parsing.
   - Add matched reply capture into Ticket history.
   - Validate with fixtures, writer tests, and browser-harness BDD.

3. **CHG 12a.3: Dogfood Polish**
   - Deduplicate explicit `bb ticket comment` versus auto-captured replies.
   - Improve Ticket chat status/error messaging.
   - Run real Clare/Dylan/Elena dogfood where provider CLIs are available.

## References

- `BAB-1001` Architecture Overview
- `BAB-1002` Naming and Vocabulary
- `BAB-1003` Glossary of Boundaries, especially AI CLI JSONL transcripts
- `BAB-1105` Persistence - ETS + SQLite + JSONL Only
- `BAB-1111` Ticket as Universal Coordination Primitive
- `BAB-2223` Phase 12 Cross-Citizen Ticket Comments
- `prefrontal-cortex` reference mechanics:
  `citizens/tmux.bob/tmux_core.py` for adaptive tmux paste/submit and
  `citizens/relay.bob/workspace/core/task_manager/response.py` for AI CLI
  JSONL response extraction

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-06 | Draft Phase 12a PFC-informed adaptive delivery and JSONL capture PRP | Codex |
| 2026-05-06 | Fold Trinity R2 advisories: update Mayor/Inspector phase references and add concrete PFC mechanic references | Codex |
| 2026-05-06 | Fold Trinity R3 wording advisory by spelling out Inspector and Mayor phase references | Codex |
| 2026-05-06 | Mark approved after Trinity R4 GLM/DeepSeek PASS with no blockers and operator authorization to continue Phase 12a/13 under SOP gates | Codex |
