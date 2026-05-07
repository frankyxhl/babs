# CHG-2235: Implement Phase 13a3 Direct CLI Provider Sessions

**Applies to:** BAB project
**Last updated:** 2026-05-07
**Last reviewed:** 2026-05-07
**Status:** Approved
**Date:** 2026-05-07
**Requested by:** Operator
**Priority:** High
**Change Type:** Normal

---

## What

Implement **Phase 13a.3: Direct CLI provider sessions** from `BAB-2232`.

This slice adds an opt-in Ticket delivery backend that can execute supported AI
CLIs non-interactively for Ticket turns, persist provider session identity in
SQLite, capture direct replies into the existing Ticket chat history, and keep
the existing Hardline/tmux path as the default and fallback backend.

Scope:

- Add `ticket_backend = "hardline" | "direct_cli" | "lazy_tmux"` to Citizen
  config and SQLite rows, defaulting to `hardline`.
- Add a `provider_sessions` SQLite table and Ecto schema/context for direct
  provider session metadata.
- Add a direct CLI adapter behavior plus Claude, Codex, and Copilot command /
  output parsers covered by fixture tests.
- Add a supervised direct-execution runner in `:babs_citizens` using erlexec
  without PTY, per-Citizen execution locking, timeout cleanup, bounded output,
  and redaction.
- Route Ticket assignment/comment delivery through a backend boundary:
  `hardline` keeps current behavior; `direct_cli` starts an async direct turn;
  `lazy_tmux` remains recognized but falls back to Hardline until CHG 13a.4.
- Capture direct replies by adapter return value through the existing
  `Babs.Citizens.Tickets.Writer` path as `comment` plus
  `turn_reply_captured`.
- Add deterministic unit, integration, browser-harness BDD, and existing E2E
  coverage. Live provider calls are not required for CI validation; fixtures and
  fake executors prove command construction, parsing, fallback, and UI updates.

Out of scope:

- Replacing Hardline as the default backend.
- Generic background/batch jobs outside Ticket turns.
- Lazy interactive tmux resume polish beyond explicit fallback behavior.
- Live quota-consuming Claude/Codex/Copilot canary runs as mandatory gates.
- Replacing `ecto_sqlite3` / `exqlite`.

## Why

Phase 13a.1 and 13a.2 made the Ticket UI and history model capable of
multi-turn collaboration, but every delivery still requires a live tmux pane.
Some Ticket turns can be completed more cleanly through provider non-interactive
CLI modes. Direct CLI delivery is also the missing piece for proving that a
second Ticket turn can resume the same upstream provider conversation when a
provider exposes a session id.

The change keeps the current interactive workflow intact while adding a durable,
testable execution backend for dormant or automation-friendly Citizens.

## Impact Analysis

- **Systems affected:** `:babs_citizens` Citizen config/import, SQLite
  migrations, Ticket Writer/API, Ticket delivery/reply capture, browser-harness
  BDD, and Ticket detail status rendering.
- **Database:** add `provider_sessions`; add `ticket_backend` to `citizens`.
  Ticket files/history JSONL remain the source of truth for conversation
  content.
- **Runtime process boundary:** add an erlexec non-PTY runner with process group
  cleanup. It must not use unmanaged ad hoc `System.cmd` for provider turns.
- **Privacy:** do not store raw prompts, raw stdout/stderr, tokens, private IPs,
  or absolute local paths in provider session rows, Ticket history, PR body, or
  review packets.
- **Rollback plan:** stop or restart the Babs node to terminate any in-flight
  supervised direct runner processes, verify no Babs-owned direct process group
  remains, revert this CHG's commit/PR, and run Ecto down migrations. Existing
  Tickets continue to render because direct events are additive and legacy
  Hardline events remain valid.

## Implementation Plan

1. **Contract and plan review**
   - Fill this CHG before code.
   - Run Trinity `fast-review` against the CHG/plan and fold blockers.

2. **RED tests for config and persistence**
   - Add config tests for `ticket_backend` defaulting and validation.
   - Add migration/schema tests for `provider_sessions` uniqueness,
     status validation, rollback, safe workspace references, and redaction.

3. **Provider session persistence**
   - Add `Babs.Citizens.ProviderSession` and
     `Babs.Citizens.ProviderSessions`.
   - Store provider, backend, upstream session id, capabilities, safe workspace
     reference/fingerprint, status, last turn, optional in-flight OS pid, and
     redacted last error.

4. **Direct CLI adapter layer**
   - Add `Babs.Citizens.DirectCli.Adapter` behavior.
   - Add adapters for Claude, Codex, and Copilot with tests for:
     command arguments, resume arguments, version/capability fingerprints,
     session id discovery, assistant reply extraction, invalid/expired resume
     errors, output bounds, and redaction.
   - Add a deterministic fake adapter/executor only for tests and BDD.

5. **Supervised direct runner and locks**
   - Add a supervised runner/task boundary in `:babs_citizens`.
   - Use erlexec without PTY, process groups, timeout handling, and explicit
     cleanup.
   - Add a per-Citizen execution lock shared by direct, Hardline, and
     recognized `lazy_tmux` delivery paths so two turns for one Citizen cannot
     execute concurrently.
   - Choose `busy` as the first implementation's concurrent-turn outcome:
     same-Citizen delivery attempts that cannot acquire the lock append
     `turn_delivery_attempted` with `status: "busy"` and do not queue hidden
     provider work.
   - Add boot-time stale in-flight row cleanup or failure marking.

6. **Ticket delivery integration**
   - Introduce a small delivery boundary used by assignment, rejection feedback,
     and comments.
   - Keep `hardline` behavior equivalent to current behavior.
   - For `direct_cli`, append queued/started/delivered/failed/captured turn
     events through `Writer`, then return to the LiveView without blocking on
     the provider.
   - On non-resumable or provider-shape failure, append visible direct failure
     status and fall back to Hardline with a separate visible attempt.

7. **UI and BDD coverage**
   - Ensure Ticket detail renders direct backend/status/provider session
     metadata in the existing chat/status affordances.
   - Add browser-harness BDD that creates a Ticket in the browser, drives a
     deterministic direct provider reply into the same Ticket, and observes the
     ordered chat update without duplicate comments.

8. **Validation and review**
   - Run applicable Babs validation stack.
   - Record exact results below.
   - Run Trinity implementation `fast-review`, fold blockers, then open PR with
     `gh` as `ryosaeba1985` and follow `COR-1615`/`COR-1612`.

## Acceptance Criteria

- `ticket_backend` defaults to `hardline`; unsupported backend values are
  rejected before runtime.
- `provider_sessions` is migrated, indexed, and tested; it never stores raw
  prompts, raw provider output, tokens, or absolute local paths.
- `provider_sessions` has verifiable indexes for the unique active session key
  `{citizen_slug, ticket_id, provider, backend}`, `{citizen_slug, status}`, and
  `{ticket_id, citizen_slug}`.
- Claude, Codex, and Copilot direct command/resume/output parsers are covered by
  fixture tests against the locally installed command shapes:
  - Claude Code `2.1.132`: `claude -p`, `--session-id`, `--resume`.
  - Codex CLI `0.128.0`: `codex exec --json`, `codex exec resume`.
  - GitHub Copilot CLI `1.0.42`: `copilot -p`, `--output-format json`,
    `--resume`.
- A direct CLI Ticket turn can complete without a persistent tmux pane in tests.
- A second turn reuses the stored `provider_session_id` when the adapter reports
  resumable capability.
- Direct provider replies are appended as visible chat comments plus
  `turn_reply_captured` events through the Writer path.
- Provider failure, invalid resume, no session id, timeout, and output overflow
  create visible failure/fallback events without losing the operator message.
- Provider stdout/stderr is bounded before parsing or persistence; the first
  implementation limit is 64 KiB per stream unless tests prove a smaller
  adapter-specific limit is needed. Redaction covers secret/token assignments,
  common local absolute paths, private/Tailscale IPs, and configured
  `secret-env-vars` names.
- Per-Citizen locking prevents concurrent provider processes or concurrent
  Hardline/direct delivery for the same Citizen.
- Existing Hardline Ticket assignment/comment/reply-capture BDD and E2E tests
  still pass.

## Validation Plan

- Unit:
  - Citizen config and CitizenRecord `ticket_backend` defaults/validation.
  - Provider session changesets, queries, status transitions, unique active key,
    rollback, and redaction.
  - Direct CLI env allowlist, command builders, output parser fixtures, output
    truncation, and secret/path redaction.
  - Direct runner timeout/cancel/owner-exit cleanup with fake commands.
  - Delivery fallback and per-Citizen lock behavior.
- Integration:
  - Writer/API assignment and comment delivery for `hardline`, `direct_cli`,
    direct failure fallback, and same-Citizen concurrency.
  - Reply capture correlation keeps `turn_id` and `attempt_id`.
- Browser:
  - Browser-harness BDD creates a Ticket, runs deterministic direct provider
    reply, and verifies ordered chat/status without duplicates.
  - Existing browser-harness BDD and Playwright E2E remain green.
- Coverage:
  - Preserve existing app coverage thresholds from the previous slice:
    `:babs_citizens` >= 80%, `:babs` >= 70%.

Planned commands:

```bash
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
mise exec -- mix test --cover --export-coverage phase13a3
mise exec -- mix cmd mix test.coverage
npm run test:js
npm run test:e2e
BU_CDP_URL=http://127.0.0.1:9333 \
  BABS_BDD_SCENARIO="direct cli fake" \
  BABS_HTTP_PORT=4107 \
  BABS_BROWSER_BASE_URL=http://127.0.0.1:4107 \
  npm run test:bdd
mise exec -- mix babs.gate_a
af validate --root <repo-root>
git diff --check
```

Final results:

- `mise exec -- mix format --check-formatted`: passed.
- `mise exec -- mix compile --warnings-as-errors`: passed.
- Focused direct CLI runner suite after round-5 review fix: 9 tests,
  0 failures.
- Focused direct/Ticket provider-delivery suite after round-5 review fix:
  59 tests, 0 failures.
- Focused hardline-lock/direct suite after Trinity advisories: 49 tests,
  0 failures.
- `mise exec -- mix test`: 378 tests, 0 failures.
- Coverage export/report:
  - `mise exec -- mix test --cover --export-coverage phase13a3`: 378 tests,
    0 failures.
  - `mise exec -- mix cmd mix test.coverage`: passed thresholds with
    `:babs_citizens` 81.40% total and `:babs` 87.62% total.
  - Note: direct umbrella `mix test --cover` completed tests and printed a
    passing `:babs_citizens` summary, but this local OTP/Mix environment
    crashed in the Erlang HTML cover writer; the export plus per-app report is
    the stable umbrella coverage path used for this validation.
- `python3 -m py_compile test/browser/bdd/babs_steps.py
  test/browser/bdd/run.py`: passed.
- `npm run test:js`: 15 tests, 0 failures.
- Browser-harness BDD focused scenario with isolated Chrome CDP on local port
  9333: `ticket chat shows direct CLI fake reply` passed.
- `npm run test:e2e`: 13 tests, 0 failures.
- `mise exec -- mix babs.gate_a`: passed.
- `git diff --check`: passed.
- `af validate --root <repo-root>`: 143 documents checked, 0 issues found.
- Diff privacy scan for the operator's private Tailscale IP and local checkout
  path: no matches in the current diff.

## Review Results

- Plan review: Trinity `fast-review` with `COR-1602` / `COR-1609` strict CHG
  rubric passed on 2026-05-07:
  `.trinity/reviews/20260507-191633-rules-BAB-2235-CHG-Implement-Phase-13a3-Direct-CLI-Provider-Sessions.md`.
  GLM PASS at 9.0/10 and DeepSeek PASS at 9.1/10. Advisories on rollback
  cleanup, output bounds, references, busy semantics, lazy-tmux lock wording,
  and provider-session indexes were folded into this CHG before implementation.
- Implementation review: Trinity `fast-review` with `COR-1602` / `COR-1609`
  passed on 2026-05-07:
  `.trinity/reviews/20260507-200233-phase-13a3-direct-cli-provider-sessions`.
  GLM PASS at 9.2/10 and DeepSeek PASS at 9.0/10. Advisory findings on SQL
  status filtering, dynamic atom normalization, hardline lock-contention
  coverage, and default direct execution status coverage were folded before PR.
- GitHub Codex PR review loop: round 1 produced two P1 findings. Fixes for
  `command.cwd` process spawning and fresh direct Claude session-id generation
  were folded with regression tests. Round 2 produced one P1 finding on
  documented Codex JSONL nested text parsing; `params.item.text` and
  `params.delta` regressions were folded. Round 3 produced one P1 finding on
  busy direct turns; direct busy lock contention now records a failed direct
  delivery and returns `{:error, {:execution_busy, slug}}` instead of silently
  dropping the prompt. Round 4 produced one P2 finding on erlexec monitor
  non-zero exit messages; direct execution now handles both `{:status, status}`
  and `{:exit_status, status}` without waiting for timeout. Round 5 produced
  one P1 finding on assignment/rejection feedback bypassing the selected
  backend; direct-cli assignment and rejection prompts now route through the
  direct runner, avoid Hardline pane startup/injection, and have regression
  tests for both entry points.
- Additional Trinity Gemini implementation review ran on 2026-05-07 in
  `.trinity/reviews/20260507-203855-phase-13a3-direct-cli-provider-sessions`.
  It found P1 process timeout cleanup/fallback issues. Direct CLI execution now
  uses erlexec monitor mode with process groups, `kill_group`, explicit timeout
  stop-and-wait cleanup, and Runner-side executor exit capture with fallback
  regression coverage.
- Gemini re-review of the fixed branch was attempted in
  `.trinity/reviews/20260507-205139-phase-13a3-direct-cli-provider-sessions`
  and timed out after 360 seconds due provider capacity/tool-access errors; no
  additional findings were returned.

## References

- `BAB-1001` Architecture Overview
- `BAB-1002` Naming and Vocabulary
- `BAB-1102` Citizen as Supervised Subtree
- `BAB-1105` Persistence - ETS + SQLite + JSONL Only
- `BAB-1107` Babs Owns Tmux Session Lifecycle
- `BAB-1110` Two OTP Apps Plus Tmux Detach
- `BAB-1111` Ticket as Universal Coordination Primitive
- `BAB-1112` Multi AI CLI Citizen Configuration
- `BAB-1113` Imported Tmux Session Attach
- `BAB-1503` Phase Delivery Workflow
- `BAB-2232` Phase 13a Multi-Turn Ticket Sessions and Direct CLI Backend
- `BAB-2233` Phase 13a.1 Tailwind UI Correction
- `BAB-2234` Phase 13a.2 Multi-Turn Ticket Chat

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-07 | Initial version | — |
| 2026-05-07 | Draft 13a.3 direct CLI provider-session implementation contract | Codex |
| 2026-05-07 | Implement direct CLI provider sessions locally and record validation results | Codex |
