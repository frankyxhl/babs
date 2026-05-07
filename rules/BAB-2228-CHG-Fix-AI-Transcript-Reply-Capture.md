# CHG-2228: Fix AI Transcript Reply Capture

**Applies to:** BAB project
**Last updated:** 2026-05-07
**Last reviewed:** 2026-05-07
**Status:** Completed
**Date:** 2026-05-07
**Requested by:** —
**Priority:** Medium
**Change Type:** Normal

---

## What

Fix the Phase 12a AI reply-capture path so Codex and Copilot CLI Citizens can
write durable Ticket replies through their upstream transcript files instead of
being pushed toward `bb ticket comment` as the primary path.

This change covers:

- Real Codex CLI session JSONL shaped as `response_item` records with nested
  `payload.role` and `payload.content`.
- GitHub Copilot CLI session JSONL under `~/.copilot/session-state/*/events.jsonl`
  shaped as `user.message` and `assistant.message` records.
- A clear `BABS_REPLY <ticket-id>:` marker in injected Ticket prompts so Babs can
  prefer final durable replies over incidental progress chatter.
- ReplyCapture cleanup that stores the comment body without the marker prefix.
- BDD cleanup for temp-runtime seed sessions, preventing test-owned
  `babs-dylan`/`babs-elena` sessions from surviving with temporary workspaces.

## Why

Manual dogfood showed Dylan/Codex still trying to run `bb ticket comment`.
In the observed session, `bb` was not on PATH, then direct `bin/bb` failed under
the Codex sandbox, and Codex stopped at a permission prompt instead of writing a
Ticket comment. The root causes were:

- the prompt still described `bb ticket comment` as the required durable reply
  path;
- Babs's Codex transcript parser did not understand the real Codex JSONL schema;
- Copilot CLI was explicitly reported as unsupported even though current
  Copilot CLI versions persist local session events;
- a BDD temp-runtime seed session could remain as `babs-dylan`, pointing the
  live Dylan pane at a temporary workspace.

Official GitHub documentation confirms Copilot CLI supports non-interactive use
with `-p`, stores session data locally in `~/.copilot/session-state/`, and keeps
configuration/session data under `~/.copilot`.

## Impact Analysis

- **Systems affected:** `Babs.Citizens.AiTranscripts`,
  `Babs.Citizens.Tickets.ReplyCapture`, `Babs.Citizens.Tickets.Injector`,
  seed-Citizen BDD cleanup, and AI CLI classification.
- **Compatibility:** Existing `bb ticket comment` remains available as a
  fallback command. Existing unmarked Claude/Codex transcript replies still
  capture as a best-effort fallback after Babs sees the Ticket prompt.
- **Risk:** Capturing transcript replies remains best-effort because upstream
  CLI JSONL schemas are external contracts. Tests pin the observed Codex and
  Copilot event shapes.
- **Rollback plan:** Revert this CHG's code changes; Ticket prompts will return
  to the Phase 12 `bb`-first behavior.

## Implementation Plan

1. Add RED tests for real Codex `response_item` JSONL and Copilot CLI
   `events.jsonl`.
2. Add RED tests for `BABS_REPLY` prompt text and marker stripping.
3. Extend `AiTranscripts` role/text/timestamp extraction to nested Codex and
   Copilot structures.
4. Discover Copilot CLI transcript paths from `COPILOT_HOME` or
   `~/.copilot/session-state/*/events.jsonl`.
5. Prefer marked assistant replies over incidental first assistant messages.
6. Change Ticket injection prompts to make transcript replies primary and `bb`
   only a fallback.
7. Clean up temp-runtime BDD seed tmux sessions after BDD-owned server teardown.
8. Run focused tests, full ExUnit, formatter, and relevant browser validation.

## Research Notes

- GitHub Copilot CLI quickstart documents `-p` / `-s` for non-interactive
  scripting:
  https://docs.github.com/en/copilot/how-tos/copilot-cli/cli-getting-started
- GitHub Copilot CLI session-data docs say every session is recorded locally and
  session files live under `~/.copilot/session-state/`:
  https://docs.github.com/en/copilot/how-tos/copilot-cli/cli-session-management
- GitHub Copilot CLI config-dir docs list `session-state/`, `session-store.db`,
  logs, settings, and `COPILOT_HOME`:
  https://docs.github.com/en/copilot/how-tos/copilot-cli/cli-configuration
- Babs keeps tmux as the primary substrate per `BAB-1103`; direct CLI hosting
  remains rejected for v0.1 because tmux provides persistence across Babs
  restarts and a human-attachable debugging surface.

## Validation

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors && mise exec -- mix test`
- `mise exec -- mix test --cover --export-coverage ai_reply_capture && mise exec -- mix cmd mix test.coverage`
- `mise exec -- mix babs.gate_a`
- `mise exec -- npm run test:js`
- `mise exec -- npm run test:e2e`
- `BU_CDP_URL=http://127.0.0.1:9223 mise exec -- npm run test:bdd`
- `git diff --check`

Coverage after this change:

- `:babs_citizens`: 81.30%
- `:babs`: 87.55%

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-07 | Initial version | — |
| 2026-05-07 | Completed implementation and validation | Codex |
