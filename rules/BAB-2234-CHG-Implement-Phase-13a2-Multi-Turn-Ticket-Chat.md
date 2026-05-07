# CHG-2234: Implement Phase 13a2 Multi Turn Ticket Chat

**Applies to:** BAB project
**Last updated:** 2026-05-07
**Last reviewed:** 2026-05-07
**Status:** Completed
**Date:** 2026-05-07
**Requested by:** Operator
**Priority:** High
**Change Type:** Normal

---

## What

Implement the second Phase 13a delivery slice: make Tickets behave as durable
multi-turn chat sessions.

This CHG adds the Ticket turn/message/attempt event model described in
`BAB-2232`, a reader/reducer for rendering ordered chat rows plus delivery
status, a provider-neutral prompt assembler for follow-up turns, and a
light-theme Ticket detail chat UI that uses the Tailwind foundation from
`BAB-2233`.

This CHG deliberately does **not** implement direct CLI provider execution,
provider-session SQLite persistence, or lazy tmux attach. Those remain in
13a.3/13a.4.

## Why

The current Ticket detail page still feels like a rough one-shot comment log:
operator comments are stored and injected, but the model and UI do not clearly
represent turn 1, turn 2, per-Citizen delivery state, captured replies, or
legacy comments without turn ids.

Phase 13a needs this model before direct CLI work starts. Direct provider
sessions need stable `turn_id`, `message_id`, and `attempt_id` values so later
backends can resume the right provider conversation and correlate replies to the
right Ticket turn. The operator also needs the browser detail page to feel like
a compact messaging tool, not a raw history dump.

## Impact Analysis

- **Systems affected:** `apps/babs_citizens` Ticket API/Writer/History reader
  helpers, `apps/babs` Ticket detail LiveView, Ticket LiveView tests,
  Ticket unit tests, `BAB-2232`, `BAB-2300`, and the discussion tracker.
- **Runtime impact:** Ticket history JSONL gains additive fields/events. Legacy
  `comment` rows without `turn_id` remain valid and render normally. Existing
  markdown Ticket files remain the metadata/body source of truth.
- **User impact:** Ticket detail becomes a chat-style collaboration page with
  visible per-turn delivery/capture statuses and a follow-up composer. Existing
  comments and reply captures should continue to appear.
- **Compatibility:** all new events append through
  `Babs.Citizens.Tickets.Writer`; no second history writer is introduced.
- **Rollback plan:** revert the new Ticket turn modules/events, restore legacy
  `comment_ticket` event generation and Ticket detail rendering, and remove the
  associated tests/docs. No database migration is part of this CHG.
- **Privacy/security:** prompt assembly and rendered chat must not expose local
  absolute paths, private IPs, tokens, raw provider transcripts, or unredacted
  provider errors.

## Implementation Plan

1. Add a Ticket id helper for sortable Babs ids:
   `turn_<yyyymmddhhmmss>_<random>`, `msg_<yyyymmddhhmmss>_<random>`, and
   `attempt_<yyyymmddhhmmss>_<random>`. The timestamp is UTC second precision
   and the suffix is cryptographically random, lower-case base32/base36-safe,
   fixed width, and URL/log friendly. Do not add a new ULID dependency in this
   CHG. Fixture-test the exact format and sort behavior for controlled
   timestamps.
2. Extend `Babs.Citizens.Tickets.Writer.comment/4` so user/operator comments
   create a new turn when no `turn_id` is supplied:
   - visible `comment` with `message_id` and `turn_id`;
   - `turn_created`;
   - per-assignee `turn_delivery_attempted` with `status: "queued"` and
     `backend: "hardline"`;
   - new `turn_delivered` or `turn_delivery_failed` events emitted alongside
     the existing legacy delivery events, using the same `attempt_id`.
   The `busy` status from `BAB-2232` is deferred until 13a.3 introduces the
   per-Citizen execution serialization layer.
3. Allow captured Citizen replies to pass a `turn_id`/`attempt_id` through
   `Api.comment_ticket(..., notify_assignees: false)` so reply capture can
   append a visible comment plus `turn_reply_captured` without renotifying
   assignees.
4. Preserve legacy behavior:
   - comments without `turn_id` or `message_id` remain readable;
   - existing `comment_notification_*`, `injected`, and `injection_failed`
     events can still be displayed in the raw history panel;
   - terminal tickets still reject comments.
5. Add a `Babs.Citizens.Tickets.Conversation` reducer that converts append-order
   history into:
   - ordered visible chat messages;
   - delivery attempts keyed by `{turn_id, citizen_slug, attempt_id}`;
   - per-turn summaries for `queued`, `delivered`, `captured`, `failed`, and
   legacy comments.
   Tests must cover same-second ordering, legacy interleaving, retry
   `parent_turn_id`, and replies captured after later status events.
   Retry semantics for this CHG: retrying a failed delivery creates a new
   attempt on the same `turn_id` and records `parent_attempt_id`; replacement
   prompts or substantially changed follow-ups create a new `turn_id` with
   `parent_turn_id`. The first UI slice may render retry controls as disabled or
   placeholder controls until the backend retry action is wired.
6. Add a `Babs.Citizens.Tickets.PromptAssembler` that builds a sanitized
   provider-neutral follow-up prompt from Ticket metadata/body, latest 12
   visible messages, latest operator message, Citizen slug, and the Babs reply
   contract. Fixture-test that local paths/private IPs/tokens/raw transcripts
   are excluded or redacted.
7. Refactor `BabsWeb.TicketLive` to use the 13a.1 stylesheet/classes instead of
   its large inline dark CSS:
   - top summary/state bar or side rail for Ticket metadata/actions;
   - messaging-app-style chat stream;
   - sticky/light composer;
   - icon-bearing retry/open-terminal affordances for failed/direct/lazy status
     placeholders;
   - raw history remains secondary for debugging.
8. Add LiveView tests for:
   - two operator follow-up turns in one Ticket;
   - per-Citizen delivery badges;
   - captured Citizen reply correlated to the right turn;
   - legacy comments still rendered;
   - retry/open-terminal controls present for failed delivery states.
9. Add browser-harness BDD or a documented local smoke for the current CHG
   scope: create Ticket, assign one available Citizen, send a follow-up, render
   the second turn in the same chat, and verify no duplicate comments. If the
   browser-harness authorization gate blocks automation, record the exact
   manual fallback in this CHG's Validation section and the discussion tracker.
10. Run focused tests, full ExUnit, format/compile, asset build, `af validate`,
    `git diff --check`, privacy scan, and Trinity code review before PR.

## Acceptance Criteria

- A Ticket can show at least two operator-to-Citizen turns on the same detail
  page.
- Each new operator message has a stable `turn_id` and `message_id`.
- Delivery attempts are recorded per assignee with stable `attempt_id` and
  backend/status metadata.
- Captured Citizen replies can be correlated to the correct `turn_id` and
  rendered in order without duplicates.
- Legacy comments without turn fields still render normally.
- The Ticket detail UI uses the shared light-theme asset pipeline instead of a
  large inline dark CSS block.
- Prompt assembler fixtures include prior chat context and do not leak private
  local/runtime details.
- Existing Ticket assign/comment/approve/reject workflows continue to pass.

## Implementation Outcome

Implemented locally:

- `Babs.Citizens.Tickets.TurnIds` for sortable `turn_*`, `msg_*`, and
  `attempt_*` ids.
- `Babs.Citizens.Tickets.Conversation` for ordered chat rows, legacy comment
  compatibility, and per-attempt delivery/capture state.
- `Babs.Citizens.Tickets.PromptAssembler` for sanitized follow-up prompts with
  recent Ticket chat context and duplicate-latest-message suppression.
- Additive `turn_*` Writer events emitted through the existing Ticket Writer
  path alongside legacy `comment_notification_*` events.
- Reply capture correlation using `turn_id` and `attempt_id`.
- Ticket detail LiveView moved from inline dark CSS to the shared light-theme
  stylesheet and chat layout from `BAB-2233`.
- LiveView, unit, Playwright, and BDD selector updates for the new chat surface.

## Validation Plan

- `mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets`
- `mise exec -- mix test apps/babs/test/babs_web/live/tickets_live_test.exs`
- `mise exec -- mix test apps/babs/test/babs_web`
- `mise exec -- mix assets.build`
- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`
- browser-harness BDD or documented manual two-turn Ticket smoke for the
  current backend
- `af validate --root <repo-root>`
- `git diff --check`
- privacy scan:
  `rg -n "$BABS_PRIVATE_IP_SCAN_PATTERN|BABS_SOCKET_TOKEN[=]|SECRET_KEY_BASE[=]|ANTHROPIC_API_KEY[=]|OPENAI_API_KEY[=]|GITHUB_TOKEN[=]" apps rules config mix.exs test`

## Validation

- `mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/prompt_assembler_test.exs apps/babs_citizens/test/babs_citizens/tickets/api_writer_store_test.exs`: 37 tests, 0 failures.
- `mise exec -- mix test apps/babs/test/babs_web/live/tickets_live_test.exs`: 16 tests, 0 failures.
- `mise exec -- mix test`: `babs_citizens` 262 tests, 0 failures; `babs` 79 tests, 0 failures.
- `mise exec -- mix test --cover --export-coverage phase13`: `babs_citizens` 262 tests, 0 failures; `babs` 79 tests, 0 failures; coverage exported.
- `mise exec -- mix test.coverage` from `apps/babs_citizens`: 82.82% total, above the 80% app threshold.
- `mise exec -- mix test.coverage` from `apps/babs`: 88.26% total, above the 70% app threshold.
- `npm run test:js`: 15 tests, 0 failures.
- `npm run test:e2e`: 13 tests, 0 failures.
- `BU_CDP_URL=http://127.0.0.1:9333 npm run test:bdd`: BDD PASS with isolated Chrome remote debugging. Expected skips remained for externally managed server restart/fd-threshold scenarios and unset `BABS_WORKSPACE_ROOT`; Ticket chat/new-form/Elena-capture/comment scenarios passed.
- `mise exec -- mix assets.build`: passed.
- `mise exec -- mix format --check-formatted`: passed.
- `mise exec -- mix compile --warnings-as-errors`: passed.
- `af validate --root <repo-root>`: 142 documents checked, 0 issues found.
- `git diff --check`: passed.
- Privacy scan for the operator's private Tailscale address and obvious token
  assignments: no matches.
- `mise exec -- mix babs.gate_a`: passed.

Note: `mix test --cover` without `--export-coverage` hit an OTP `:cover` HTML
stylesheet generation issue after successful tests and a printed app coverage
summary. The stable coverage gate for this umbrella is the exported coverage
flow above plus per-app `mix test.coverage`, which passed both configured app
thresholds.

## Plan Review

- R1 Trinity fast-review:
  `.trinity/reviews/20260507-133025-rules-BAB-2234-CHG-Implement-Phase-13a2-Multi-Turn-Ticket-Chat.md`
  - GLM PASS.
  - DeepSeek PASS with non-blocking advisories.
  - Folded advisories: fixed concrete id format, clarified retry semantics,
    clarified new `turn_*` events are emitted alongside legacy delivery events,
    explicitly deferred `busy` to 13a.3, specified browser-harness fallback
    recording location, and made the privacy scan command concrete.

## Code Review

- R1 Trinity implementation fast-review:
  `.trinity/reviews/20260507-140100-BAB-2234-implementation-diff-Phase-13a.2-multi-turn-Ticket-chat`
  - GLM PASS.
  - DeepSeek PASS.
  - Folded advisories: removed dead `TicketLive.styles/0`, avoided repeated
    history reads and repeated conversation reductions during assignee fanout,
    narrowed CGNAT redaction, avoided `inspect/1` sanitizer fallback, and added
    user `notify_assignees: false` behavior coverage.
- R2 Trinity implementation fast-review:
  `.trinity/reviews/20260507-141244-BAB-2234-implementation-diff-R2-after-Trinity-advisory-cleanup`
  - GLM PASS.
  - DeepSeek PASS.
  - Folded advisory: avoid duplicating the latest operator message in assembled
    follow-up prompts.
- R3 Trinity implementation fast-review:
  `.trinity/reviews/20260507-141938-BAB-2234-implementation-diff-R3-after-prompt-de-dup-cleanup`
  - GLM PASS.
  - DeepSeek PASS.
  - Remaining advisories are non-blocking and deferred: optional
    `bubble_class/1` simplification, empty-recipient turn semantics, Linux path
    sanitizer expansion, prompt-read warning observability, and future retry UI
    grouping.
- R4 Trinity implementation fast-review:
  `.trinity/reviews/20260507-182615-Phase-13a.1-13a.2-implementation-diff-R4-after-Trinity-raw-findings`
  - GLM PASS.
  - DeepSeek PASS.
  - Folded raw-review findings and security advisories: removed the no-op
    `bubble_class/1`, removed the duplicate kitchen-sink `live_boot.js` script,
    added prompt-read warning observability, fixed latest-operator-message
    de-duplication when a Citizen reply follows, and expanded prompt
    sanitization for Linux local paths plus space-containing secret values.

## References

- `BAB-1004` UI Design Spec
- `BAB-1503` Phase Delivery Workflow
- `BAB-2232` Phase 13a PRP
- `BAB-2233` Phase 13a.1 Tailwind UI foundation CHG

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-07 | Initial version | — |
| 2026-05-07 | Define Phase 13a.2 multi-turn Ticket model, chat UI, prompt assembler, tests, and deferred direct CLI scope | Codex |
| 2026-05-07 | Record Trinity plan PASS and fold non-blocking GLM/DeepSeek advisories into the implementation plan | Codex |
| 2026-05-07 | Complete implementation, validation, browser-harness fallback note, and Trinity implementation R3 PASS | Codex |
