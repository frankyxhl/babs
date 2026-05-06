# CHG-2226: Implement Phase 12a Relay Reliability

**Applies to:** BAB project
**Last updated:** 2026-05-06
**Last reviewed:** 2026-05-06
**Status:** Approved
**Date:** 2026-05-06
**Requested by:** Operator
**Priority:** High
**Change Type:** Normal

---

## What

Implement Phase 12a from `BAB-2224`: make Ticket-to-Citizen delivery reliable
enough for dogfood by combining safer system prompt delivery, Ticket chat
polish, and AI CLI reply capture.

This CHG covers the full Phase 12a implementation surface, but the local
working tree already contains a partial dogfood implementation that must be
validated rather than blindly expanded.

### Already-started local work to preserve if validated

1. **Adaptive/system delivery foundation**
   - System-delivered Ticket prompts use a distinct injection path from manual
     browser typing.
   - The current simple AI CLI auto-submit path is treated as partial work, not
     as the final Phase 12a adaptive-delivery implementation.
   - Transcript writes are flushed after system injection so tests and replay
     observe delivered prompts deterministically.
2. **Ticket dogfood UI polish**
   - `/tickets/new` lets the operator create Tickets from the browser.
   - Ticket comments render as a chat-style stream with a compact send action.
   - Ticket detail/index CSS interpolation remains LiveView-safe.

Current partial file set:

- `apps/babs_citizens/lib/babs_citizens/hardline/pane.ex`
- `apps/babs_citizens/lib/babs_citizens/runner.ex`
- `apps/babs_citizens/lib/babs_citizens/tickets/injector.ex`
- `apps/babs/lib/babs_web/live/new_ticket_live.ex`
- `apps/babs/lib/babs_web/live/ticket_live.ex`
- `apps/babs/lib/babs_web/live/tickets_live.ex`
- related LiveView, BDD, E2E, and unit tests

### New work required before Phase 12a can complete

1. **Full adaptive delivery confirmation loop**
   - Wait until the target AI CLI pane is ready enough to receive input.
   - Paste system prompts through a tmux-buffer-safe path.
   - Poll pane content for a unique Ticket marker or known paste receipt state.
   - Send Enter only after receipt is observed.
   - Retry Enter when the pane remains in an editable pasted-block state.
   - Preserve the existing direct byte path for manual browser input.
2. **AI CLI JSONL reply capture**
   - Add provider-aware, read-only upstream transcript adapters for supported AI
     CLIs where the transcript source can be discovered safely.
   - Match assistant replies to a delivered Ticket turn using Ticket id, Citizen
     slug, and injection time/marker.
   - Append matched replies to Ticket history as durable `comment` events.
   - Ignore stale, unrelated, partial, malformed, or duplicate records.
3. **Dogfood verification**
   - Validate with deterministic unit tests and simulated JSONL fixtures.
   - Keep real-provider dogfood optional when a CLI is unavailable or quota is
     exhausted.

## Why

Phase 12 gave Citizens a durable `bb ticket comment` path, but manual testing
showed two blockers:

- Ticket assignment prompts could be pasted into an AI CLI pane without being
  submitted until the operator manually pressed Enter.
- Citizens can reply in their AI CLI, but Babs does not yet turn matched
  Claude/Codex upstream JSONL replies into Ticket comments automatically.

Phase 12a closes that loop so the Ticket/Billboard surface becomes the durable
conversation record while the terminal remains the execution transport.

## Impact Analysis

- **Systems affected:** `:babs_citizens` Hardline.Pane, Runner, Ticket
  Injector/API/history paths, optional new AI transcript reader modules;
  `:babs` Ticket LiveViews/routes/icons; browser BDD/E2E tests; docs in
  `rules/`.
- **Authority:** `BAB-2224` is the approved Phase 12a PRP and remains the
  acceptance authority. This CHG may clarify execution details but must not
  weaken the PRP acceptance criteria without a follow-up PRP amendment.
- **Data affected:** Ticket history JSONL gains additional `comment` events
  when matched AI CLI replies are captured. Existing Ticket markdown/frontmatter
  schema is unchanged.
- **Compatibility:** Manual browser terminal input remains byte-for-byte direct
  input. Shell Citizens do not receive AI-CLI auto-submit behavior.
- **Operational toggle:** AI reply capture must be disableable without reverting
  all Phase 12a code, using app config/env such as
  `BABS_AI_REPLY_CAPTURE=0`. Delivery and manual Ticket comments continue when
  capture is disabled.
- **Privacy/security:** Fixtures and docs must not contain private IPs, local
  absolute host paths, provider tokens, or raw upstream transcript contents.
  Synthetic fixtures are preferred.
- **Rollback plan:** Revert the Phase 12a code/doc changes. Existing Ticket
  history comments are append-only runtime data; rollback does not rewrite
  runtime Ticket history. If capture causes bad comments before rollback,
  operator can close/reject affected Tickets manually. Capture state must be
  in-memory or explicitly cleared on app restart; rollback must not leave stale
  delivery metadata that can create comments after redeploy.

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| AI CLI JSONL schema changes | Medium | Missed or malformed captures | Defensive parser fixtures, tolerate unknown fields, typed unsupported result |
| System prompt delivery silently fails | Medium | Citizen never sees Ticket work | Full receipt-confirmation loop, visible Ticket/history advisory on failure, LiveView flash on operator-initiated actions |
| Stale JSONL reply matched to wrong Ticket | Medium | Incorrect durable comment | Require Ticket marker + slug + timestamp window; reject unmatched records |
| Duplicate explicit `bb ticket comment` and auto-capture | Medium | Repeated comments | Per-ticket/slug/body hash dedup inside capture window |
| Capture loop consumes CPU | Low | Runtime noise | Bounded polling interval/window; disabled by config in emergencies |
| Capture creates bad comments in dogfood | Low/Medium | Operator cleanup needed | Feature toggle plus append-only history; manual reject/close remediation |

## Implementation Plan

1. **Review and preserve current partial implementation**
   - Keep the already-started system injection path, new Ticket UI, and chat UI
     only if they pass the full Phase 12a validation gates.
   - Refactor rather than expanding ad hoc code if JSONL capture needs shared
     helpers.
2. **Complete adaptive delivery behavior**
   - Keep `Pane.inject/2` manual and asynchronous.
   - Keep `Pane.inject_system/2` synchronous and typed.
   - Implement the full `BAB-2224` adaptive delivery loop for AI CLI system
     prompts: idle/readiness check, tmux-buffer-safe paste, receipt polling,
     Enter-after-receipt, and Enter retry for editable pasted-block states.
   - Ensure shell system injection does not get an accidental Enter.
   - Return typed delivery failures and write visible non-comment advisory
     events to Ticket history when system delivery cannot be confirmed.
   - Add tests for success, not-found, transcript flush, shell-vs-AI behavior,
     receipt polling, Enter retry, and visible delivery failure.
3. **Add upstream AI CLI transcript adapters**
   - Introduce a small behavior/module boundary for transcript discovery and
     parsing.
   - Start with Claude/Codex fixtures; GitHub Copilot can report unsupported
     capture if no safe transcript source is known.
   - Parse line-by-line JSONL defensively and return typed records.
   - If upstream JSONL is unavailable, allow pane-diff fallback only when the
     response can be matched safely to a unique Ticket marker. Otherwise return
     a typed capture-unavailable advisory and do not append a comment.
4. **Add Ticket reply capture service**
   - Persist delivery metadata sufficient to match a later reply to a Ticket
     turn.
   - Poll/read adapter output on a bounded background check: default 5s interval
     for up to 30 minutes per delivered Ticket turn, with shorter intervals
     injected in tests.
   - On capture-window expiry, clear in-memory delivery metadata and record at
     most a non-comment Ticket history advisory event such as
     `ai_reply_capture_expired`; never append an inferred assistant reply after
     the active window expires.
   - Append matched assistant replies through existing Ticket API/write path as
     `comment` events by the Citizen slug.
   - Deduplicate against explicit `bb ticket comment` replies by checking
     per-ticket/slug normalized body hashes inside the active capture window.
   - On app shutdown, restart, feature-toggle disable, or rollback, clear
     capture workers and delivery metadata so stale captures cannot fire after a
     redeploy.
5. **Browser integration**
   - Ensure captured comments update `/tickets/<id>` through the existing
     watcher path and appear in the chat panel.
   - Show non-blocking advisory state when capture is unavailable.
6. **Validation**
   - `mix format --check-formatted`
   - `mix compile --warnings-as-errors`
   - `mix test --cover` with coverage preserved or improved against the Phase
     12 baseline: `:babs_citizens >= 83.0%` and `:babs >= 85.0%`.
   - `npm run test:js` if browser JavaScript changes.
   - `npm run test:bdd`
   - `npm run test:e2e`
   - `mix babs.gate_a`
   - `git diff --check`
   - Privacy scan for private IPs, local paths, and tokens.
7. **Review and PR**
   - Trinity implementation fast-review with GLM and DeepSeek.
   - Create PR using `gh` as `ryosaeba1985`.
   - Follow Alfred `COR-1615`/`COR-1612` for GitHub Codex review loop, capped at
     five rounds unless the operator explicitly extends it.

## TDD Plan

| Boundary | RED | GREEN | REFACTOR |
|----------|-----|-------|----------|
| System delivery | Failing unit tests for tmux-buffer paste, receipt polling, Enter-after-receipt, Enter retry, shell no-extra-Enter, and transcript flush | Implement adaptive delivery under `Pane.inject_system/2` while preserving manual `Pane.inject/2` | Extract delivery helpers and fakeable tmux/pane operations for deterministic tests |
| Transcript adapters | Failing fixture tests for Claude/Codex assistant records, malformed lines, partial lines, and unsupported providers | Implement read-only parser/discovery modules | Extract shared JSONL line validation and provider record normalization |
| Reply matching | Failing tests for Ticket id/slug/timestamp match, stale reply rejection, and unrelated reply rejection | Implement matcher with explicit delivery metadata | Reduce matcher coupling to Ticket structs and adapter record shapes |
| Capture service | Failing tests for bounded polling, disabled toggle, comment append, duplicate suppression, and missing transcript advisory | Implement capture worker/service through existing Ticket API | Isolate timer/polling dependencies for deterministic tests |
| Pane-diff fallback | Failing tests for safe unique marker match and unsafe ambiguous match | Implement fallback only for uniquely matched Ticket marker output | Keep fallback optional behind adapter result, not mixed into JSONL parser |
| Browser chat update | Failing LiveView/BDD/E2E assertions that captured comments appear through watcher path | Reuse Ticket history watcher and chat panel | Keep UI independent of capture internals |

## PRP Slice Mapping

| `BAB-2224` slice | Covered here by |
|------------------|-----------------|
| CHG 12a.1 Adaptive Delivery | Already-started system delivery foundation plus the full adaptive delivery loop in Implementation Plan step 2 |
| CHG 12a.2 JSONL Capture | Implementation Plan steps 3-4 and TDD adapter/matcher/capture boundaries |
| CHG 12a.3 Dogfood Polish | Ticket new/chat UI preservation, browser integration, and validation gates |

## Acceptance Criteria

- Assigning a Ticket to a Claude/Codex Citizen submits the system prompt without
  a manual Enter.
- Shell Citizens do not receive an unintended extra Enter from system delivery.
- A matched AI CLI JSONL assistant reply becomes a durable Ticket `comment` by
  the Citizen slug.
- Stale, malformed, unrelated, partial, or duplicate JSONL records do not create
  comments.
- `/tickets/<id>` chat updates through the existing watcher path when a captured
  reply is appended.
- New Ticket creation and chat-style comments are covered by LiveView,
  browser-harness BDD, and E2E tests.
- Coverage gates, BDD, E2E, Gate A, Trinity review, GitHub Codex review loop,
  and privacy checks pass before merge.

## Review Plan

- Plan review: Trinity `fast-review` with GLM and DeepSeek before continuing
  beyond already-started local implementation.
- Implementation review: Trinity `fast-review` on the implementation diff.
- PR review: GitHub Codex loop per `COR-1615`, current-head matched and capped
  at five rounds.

## Review Results

- R1 `.trinity/reviews/20260506-203455-rules-BAB-2226-CHG-Implement-Phase-12a-Relay-Reliability.md`:
  GLM returned FIX at 8.4/10; DeepSeek returned PASS at 9.0/10. Findings were
  folded into the CHG.
- R2 `.trinity/reviews/20260506-204302-rules-BAB-2226-CHG-Implement-Phase-12a-Relay-Reliability.md`:
  GLM returned FIX at 8.9/10; DeepSeek timed out. GLM findings were folded into
  the CHG.
- R3 `.trinity/reviews/20260506-205903-rules-BAB-2226-CHG-Implement-Phase-12a-Relay-Reliability.md`:
  GLM returned PASS at 9.28/10; DeepSeek returned FIX at 8.5/10 with one
  blocker. The blocker was folded into the CHG by making the full `BAB-2224`
  adaptive delivery loop mandatory.
- R4 `.trinity/reviews/20260506-210441-rules-BAB-2226-CHG-Implement-Phase-12a-Relay-Reliability.md`:
  GLM returned PASS at 9.2/10 and DeepSeek returned PASS at 9.0/10. No blockers
  remain.
- Implementation follow-up R2 `.trinity/reviews/20260506-234257-Phase-12a-13-PR-21-R1-fixes-plus-terminal-keyboard-parity-and-Gate-A-isolation`:
  GLM PASS and DeepSeek PASS with no blockers for the PR #21 R1 fixes, terminal
  keyboard parity, transcript/restart fixes, and Gate A isolation. Non-blocking
  advisories were cleaned up by removing stale JS paste helper code, documenting
  Gate A env mutation, and covering UTF-8 C1 terminal-control filtering.
- Implementation follow-up R3 `.trinity/reviews/20260507-012721-Phase-12a-13-PR-21-R5-fixes`:
  GLM PASS and DeepSeek PASS with no blockers for the final PR #21 R5 fixes.
  Remaining observations were informational/non-blocking.
- Implementation follow-up R4 `.trinity/reviews/20260507-020009-Phase-12a-13-final-stable-pane-and-terminal-focus-fixes`:
  GLM PASS and DeepSeek PASS with no blockers for the final stable pane-id
  attach submission and browser terminal focus recovery fixes.
- Implementation follow-up R5 `.trinity/reviews/20260507-020800-Phase-12a-13-final-terminal-focus-followup`:
  GLM PASS and DeepSeek PASS with no blockers after the terminal focus recovery
  advisory hardening.

## Implementation Results

- Added adaptive system delivery through the Hardline pane path, including
  tmux-buffer paste, AI-CLI submit behavior, deterministic transcript flush, and
  visible advisory events when delivery cannot be confirmed.
- Added read-only Claude/Codex transcript parsing helpers and a bounded
  `ReplyCapture` worker. GitHub Copilot remains an explicit unsupported
  transcript source for now. Missing transcript files remain pending so fresh
  CLI turns keep polling until a reply appears or the capture window expires.
  Successful assignment, Ticket comment notification, and rejection feedback
  injections each register a capture turn so follow-up AI replies can become
  durable Ticket comments.
- Added `/tickets/new`, chat-style Ticket comments, send-icon controls, and
  LiveView/BDD/E2E coverage for browser-created Tickets and captured Citizen
  replies.
- Added a configurable `Pane.inject_system/2` delivery timeout while keeping the
  default at 5 seconds.
- Restored browser-terminal keyboard parity with the hardline spike by allowing
  xterm-compatible Ctrl/Alt/function-key/modified-arrow/bracketed-paste input,
  while filtering unsafe controls and xterm-generated terminal response
  sequences that can pollute shell command lines.
- Tightened terminal input filtering so embedded terminal-response sequences are
  rejected before they can be injected into tmux command lines.
- Suppressed comment notification-attempt history when `notify_assignees: false`
  is used for captured AI replies or other explicitly storage-only comments.
- Matched the browser terminal startup behavior to hardline by enabling
  macOS Option-as-Meta, keeping terminal-owned shortcuts focused in xterm, and
  refitting when the terminal container changes size.
- Added terminal focus recovery after `Escape` and other terminal-owned keys so
  common browser-extension focus theft is repaired when the page can observe the
  key event. Extensions that consume `Escape` before page JavaScript, such as
  Vimium, still require an operator-side site exclusion for full terminal
  parity.
- Prefer the live tmux pane snapshot on channel join, with transcript replay as
  a fallback, so browser reconnects after `:babs_citizens` reload show the
  current terminal screen rather than a stale transcript replay.
- Made supervised Hardline pane shutdown detach its tmux attach client, leaving
  the detached tmux session alive without accumulating orphan attach clients.
- Made transcript appends immediately visible to external readers and redirected
  terminal restart back to the terminal route so the Phoenix Channel binds to
  the restarted Hardline pane.
- Isolated `mix babs.gate_a` from AI-Citizen autostart so the sentinel gate does
  not attach Clare/Dylan/Elena while validating reload behavior.

## Validation Results

Final local validation for the combined Phase 12a + Phase 13 working tree:

- `mise exec -- mix format --check-formatted`: pass
- `mise exec -- mix compile --warnings-as-errors`: pass
- `mise exec -- mix test`: `:babs_citizens` 235 tests, `:babs` 75 tests, all
  pass
- `mise exec -- mix test --cover --export-coverage phase13` then
  `mise exec -- mix cmd mix test.coverage`: `:babs_citizens` 81.28% and
  `:babs` 87.55%
- `npm run test:js`: 15 tests pass
- `npm run test:bdd`: pass; expected externally managed-server skips remain for
  managed restart/fd-threshold scenarios, and the `BABS_WORKSPACE_ROOT` scenario
  is skipped when that env var is unset
- `npm run test:e2e`: 13 Playwright tests pass, including browser tmux-prefix,
  Ctrl-A, Alt-B, and extension-style `Escape` focus recovery shortcut parity
- `mise exec -- mix babs.gate_a`: pass
- `af validate --root .`: 131 documents checked, 0 issues
- `git diff --check`: pass
- Privacy scan over changed diff: pass

## References

- `BAB-2224` PRP Phase 12a PFC-Informed Hardline Relay Reliability
- `BAB-2223` CHG Phase 12 Cross-Citizen Ticket Comments
- `BAB-1003` Glossary of Boundaries, AI CLI JSONL transcript boundary
- `BAB-1105` Persistence ETS SQLite JSONL Only
- `BAB-1111` Ticket as Universal Coordination Primitive

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-06 | Initial Phase 12a implementation CHG covering adaptive delivery, JSONL reply capture, Ticket chat polish, validation, and review gates | Codex |
| 2026-05-06 | Fold Trinity R1 findings: separate already-started work from new scope, add TDD plan, risk register, PRP slice mapping, capture bounds, dedup strategy, feature toggle, and rollback state cleanup | Codex |
| 2026-05-06 | Fold Trinity R2 GLM findings: clarify PRP authority, pane-diff fallback, coverage floors, capture-window expiry, and capture-state cleanup | Codex |
| 2026-05-06 | Fold Trinity R3 DeepSeek blocker by making the full BAB-2224 adaptive delivery receipt-confirmation loop mandatory for Phase 12a acceptance | Codex |
| 2026-05-06 | Mark approved after Trinity R4 GLM/DeepSeek PASS with no blockers | Codex |
| 2026-05-06 | Record Phase 12a implementation and final local validation results | Codex |
| 2026-05-06 | Fix GitHub Codex R1 P2 by keeping missing transcript files in the retry path | Codex |
| 2026-05-06 | Fix browser-terminal keyboard parity, transcript visibility, restart reconnect race, and Gate A autostart isolation | Codex |
| 2026-05-06 | Record Trinity follow-up PASS and advisory cleanup for PR #21 fixes | Codex |
| 2026-05-06 | Fix GitHub Codex R3 P2 by scheduling reply capture for successful comment and rejection feedback injections | Codex |
| 2026-05-06 | Fix GitHub Codex R4 P2 by rejecting embedded terminal-response sequences before injection | Codex |
| 2026-05-06 | Restore hardline-equivalent browser terminal shortcuts/focus and prefer live tmux snapshots on reconnect | Codex |
| 2026-05-06 | Refresh final validation after terminal shortcut, reconnect, and attach-client cleanup fixes | Codex |
| 2026-05-06 | Fix GitHub Codex R5 P2 by omitting notification-attempt history for storage-only comments | Codex |
| 2026-05-06 | Refresh final validation after R5 fixes; no R6 requested per operator review cap | Codex |
| 2026-05-07 | Record Trinity follow-up R3 PASS for final PR #21 R5 fixes | Codex |
| 2026-05-07 | Add browser terminal focus recovery for extension-stealing `Escape`, refresh validation, and record Trinity R4/R5 PASS | Codex |
