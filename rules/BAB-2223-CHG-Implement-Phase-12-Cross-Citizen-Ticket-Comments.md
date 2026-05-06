# CHG-2223: Implement Phase 12 Cross-Citizen Ticket Comments

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

Implement Phase 12 from `BAB-2217` / `BAB-2218`: cross-Citizen Ticket
comments, with Ticket history as the authoritative communication surface and
terminal notifications as mirrors only.

This slice adds:

- A Citizen-facing `bb ticket comment <id> "..."` command bridge.
- Live delivery for `comment_ticket/3` instead of Phase 7's deferred delivery.
- Ticket detail comment form with semantic icon and accessible label.
- Comment notification mirrors to all current assignees, including the author
  when the author is an assignee.
- Runtime environment support so Babs-owned tmux sessions can find `bb` and
  identify their Citizen slug.
- Unit, LiveView, browser-harness BDD, coverage, Trinity, and PR review
  validation for the comment loop.

`Api.comment_ticket/3` is the public boundary used by web and command code;
`Writer.comment/4` remains the internal per-Ticket serialized mutation.

This CHG intentionally does not implement the final ADR-complete Unix-domain
socket `bb` transport. It adds a small tracked development bridge for
`bb ticket comment` so Phase 12 can complete the M3 flywheel now while keeping
the public command shape aligned with `BAB-1111`.

Authority references for this CHG are `BAB-2217`, `BAB-2218`, `BAB-2222`,
`BAB-1111`, `BAB-1104`, `BAB-1106`, and `BAB-1503`.

## Why

Phase 11 completes the operator approval loop, but Citizens still cannot
coordinate through the Billboard from their own terminal with the intended
`bb ticket comment` mental model. Phase 12 closes M3 by making Ticket history
the shared communication surface:

1. A Citizen comments from their terminal.
2. The comment is persisted to `.history.jsonl` first.
3. The Ticket detail history updates through the existing watcher path.
4. All assigned Citizens receive a terminal notification mirror.
5. Delivery failures are advisory and do not roll back the comment.

After this slice, the V0-M flywheel is usable end to end: create or receive a
Ticket, assign it, observe Citizen work, exchange comments through history,
request changes or approve, and close the Ticket.

## Impact Analysis

- **Systems affected:** `:babs_citizens` Ticket writer/API/Injector/Runner,
  temporary `bb` bridge, `mix babs.ticket.comment`, `/tickets/<id>` LiveView,
  browser BDD tests, roadmap/tracker docs.
- **Data affected:** Runtime Ticket history JSONL under the configured tickets
  root. No Ticket runtime data is committed to git.
- **SQLite affected:** Citizen lookup/status only through existing
  Catalog/Lifecycle boundaries. No Ticket tables are added.
- **Runtime behavior:** Comment history is durable before notification
  mirrors. Stopped assigned Citizens may be auto-started through the same
  Injector prepare boundary as assignment and rejection feedback.
- **Security/privacy:** Comment text is runtime user/Citizen content. Babs must
  not persist env maps, tokens, socket tokens, private URLs, host-local paths, or
  raw lifecycle errors in public PR text, browser flashes, or Ticket history.
- **Rollback plan:** Revert this PR. Existing `comment` history events remain
  readable because Phase 7 already supported storage-only comments. The `bb`
  bridge disappears, but stored Ticket history remains valid.

## Implementation Plan

1. RED: Add Runner tests for Babs-owned tmux runtime environment:
   - `BABS_ROOT` points at the app root used by Babs.
   - `BABS_CITIZEN_SLUG` is set to the Citizen slug.
   - `BABS_TICKETS_ROOT` is forwarded when configured.
   - `PATH` includes `<BABS_ROOT>/bin` ahead of the existing path so `bb` is
     available inside Citizen terminals.
   Existing Citizen-defined env remains supported and must not override the
   slug/root values.
2. GREEN: Extend `Babs.Citizens.Runner.new_session_args/1` with the runtime env
   above. `BABS_ROOT` is derived from
   `Application.get_env(:babs_citizens, :root, File.cwd!())`, matching existing
   project-root resolution. `BABS_TICKETS_ROOT` is derived from the configured
   tickets root when present. Keep values host-local at runtime only; do not
   write them to public PR text or docs with absolute paths.
   Citizen-defined env vars must be emitted first and Babs-owned env vars
   emitted last in the tmux `-e` argument list, so the Babs-owned
   `BABS_ROOT`, `BABS_CITIZEN_SLUG`, `BABS_TICKETS_ROOT`, and `PATH` values
   cannot be overridden by TOML env entries. Because tmux `-e` does not expand
   `$PATH`, construct `PATH` as the literal string
   `<BABS_ROOT>/bin:<existing PATH>` using the current process environment.
3. RED: Add command tests for `bb ticket comment <id> "body"`:
   - Reads `BABS_ROOT` and runs from any Citizen cwd.
   - Uses `BABS_CITIZEN_SLUG` as the default `by`.
   - Supports an optional `--by <slug>` override for tests/operator use.
   - Stores metacharacter-heavy comment text literally and does not execute
     shell fragments such as `$()`, backticks, semicolons, pipes, or quotes.
   - Prints clear usage for unsupported commands.
4. GREEN: Add a small tracked `bin/bb` bridge that currently supports only
   `ticket comment`. It may shell out to `mix babs.ticket.comment` from
   `BABS_ROOT` for this phase. Full UDS-backed `bb` remains deferred, but the
   command shape must match the ADR.
   The bridge must avoid shell interpolation of the comment body. Implement it
   with argument arrays or equivalent safe process invocation; do not build a
   command string containing user/Citizen comment text. `bin/` is new in this
   repository, so tests must verify `bin/bb` exists and is executable.
5. RED: Update `mix babs.ticket.comment` tests:
   - Accept optional `--by <actor>`.
   - Remove "live delivery is deferred until Phase 12" output.
   - Print whether notification mirrors succeeded or had advisory failures.
6. GREEN: Update `Mix.Tasks.Babs.Ticket.Comment` to pass `by` through to the
   API and display typed/redacted outcomes. This removes the Phase 7
   `delivery: :deferred` user-facing message.
7. RED: Add Writer/API tests for live comments:
   - Nonblank comment persists one `comment` event before notification mirrors.
   - Existing Phase 7 comment events without `ticket_id` remain readable and
     renderable alongside Phase 12 comment events with `ticket_id`.
   - Comments on unassigned open Billboard Tickets persist as history-only
     comments, return `{:comment_notified, []}`, and do not write notification
     attempted/outcome events because there are no targets.
   - Comments are accepted for `open`, `in_progress`, and `pending_approval`
     Tickets and rejected for terminal states.
   - Both the `comment` event and `comment_notification_attempted` event are
     prevalidated before markdown rewrite, preserving the Phase 7
     oversized-comment safety invariant.
   - Oversized comments are rejected before markdown rewrite, leaving the Ticket
     unchanged and without a `comment` history event.
   - Oversized notification-attempt events, for example from a manually valid
     Ticket with many assignees, are rejected before markdown rewrite.
   - `comment_notification_attempted` records all current assignee targets once
     when at least one target exists.
   - `comment_notified` is recorded per successful assignee.
   - `comment_notification_failed` is recorded per failed assignee with redacted
     errors.
   - Partial or total notification failure returns an advisory delivery result
     while preserving the comment and Ticket state.
   - Partial notification failure reports both successes and failures as
     `{:comment_notification_failed, ok_slugs, failures}` where failures are
     `{slug, reason}` tuples.
   - Multi-assignee comments notify Clare and Dylan, including the author when
     `by` is one of the assignees.
   - Concurrent comments on the same Ticket serialize through the per-ticket
     writer and produce valid ordered history without data loss.
   - The author sees their own comment through history by reading the Ticket
     after the write, and exactly one `comment` event is appended.
   - `closed` and `cancelled` Tickets reject comments with a typed
     `{:terminal_ticket, id, state}` error and do not rewrite markdown.
   - Invalid authors are rejected before rewrite. A valid author is `"user"` or
     a valid Citizen slug per `Babs.Citizens.Citizen.Config.valid_slug?/1`.
   - Error rendering covers new `{:invalid_comment_author, value}`,
     `{:terminal_ticket, id, state}`, and comment notification failure delivery
     cases with stable typed/redacted messages.
8. GREEN: Extend `Babs.Citizens.Tickets.Injector`:
   - Add `comment_prompt(ticket, slug, by, body)`.
   - Reuse `prepare/2` and `inject/3` so stopped assigned Citizens auto-start
     before notification mirrors.
9. GREEN: Update `Writer.comment/4`:
   - Audit all callers of `Writer.comment/4` and `Api.comment_ticket/3`
     including API tests, Mix task, LiveView handler, and browser BDD helpers.
   - Validate comment body and `by`.
   - `by` defaults to `"user"` for browser/operator paths, uses
     `BABS_CITIZEN_SLUG` through `bb` for Citizen terminal paths, and accepts
     only `"user"` or a valid Citizen slug. Invalid values return
     `{:invalid_comment_author, value}`. Import or alias
     `Babs.Citizens.Citizen.Config` directly for `valid_slug?/1`; this
     validation does not need an opts-injected callback.
   - Reject comments on terminal states (`closed`, `cancelled`) with
     `{:terminal_ticket, id, state}`.
   - Read and conflict-check the Ticket through the per-ticket writer.
   - Update `comment_event` to accept the Ticket id and include `ticket_id` in
     newly appended comment events.
   - Generate and prevalidate the `comment` event and
     `comment_notification_attempted` event before rewriting markdown. For
     zero-target comments, prevalidate and append only the `comment` event.
   - Write markdown with updated `updated_at`, append `comment` first, then
     `comment_notification_attempted` when targets exist, then attempt
     notification mirrors.
   - Append per-assignee success/failure advisory events after notification
     attempts.
   - Return `{:ok, %{ticket: ticket, delivery: {:comment_notified, slugs}}}` on
     full success and `{:ok, %{ticket: ticket, delivery:
     {:comment_notification_failed, ok_slugs, failures}}}` on advisory
     failures. This preserves partial-success information for Mix and LiveView
     warnings.
10. RED: Add LiveView tests for `/tickets/<id>`:
    - Comment form appears for valid Tickets that are not terminal.
    - The submit button has a semantic icon and accessible label.
    - Blank comment is rejected in the browser/server path.
    - Valid comment appends to history and appears in the timeline.
    - A pre-Phase-12 comment event without `ticket_id` still renders.
    - Notification advisory failures show a warning flash without hiding the
      stored comment.
11. GREEN: Add Ticket detail comment form:
    - Use an existing or new semantic icon such as `message-square`. If the
      chosen icon does not exist in `BabsWeb.Icon`, add it with tests.
    - Use the existing async action guard so comments cannot double-submit.
    - Flash typed/redacted errors only.
    - Preserve socket-token behavior.
    - The existing file watcher must refresh `/tickets/<id>` after comment
      writes. BDD must verify history visibility through the browser rather
      than trusting the submit response alone.
12. RED/GREEN: Add browser-harness BDD for Phase 12:
    - Create two shell Citizens, Clare and Dylan equivalents in the isolated BDD
      environment.
    - Create a Ticket assigned to both.
    - Verify the Citizen terminal has `BABS_ROOT`, `BABS_CITIZEN_SLUG`, and
      `<BABS_ROOT>/bin` on `PATH` before invoking the bridge. The preferred BDD
      assertion is behavioral: after invoking `bb`, read Ticket history and
      assert `by` equals the Citizen slug from `BABS_CITIZEN_SLUG`; the helper
      may also echo `BABS_ROOT` and `PATH` in the shell Citizen pane when useful
      for diagnosis.
    - Run `bb ticket comment <id> "Backend done"` from one Citizen terminal.
    - Verify `/tickets/<id>` history shows the comment within 1s.
    - Verify both assigned Citizen terminals receive the notification mirror.
13. REFACTOR: Extract shared delivery helpers only when duplication between
    rejection feedback and comment notification becomes harder to read than the
    explicit functions. Use a concrete gate: extract only if either comment
    delivery or rejection feedback delivery exceeds 35 lines after formatting,
    or if the same delivery-result fold appears in three places. Keep the Ticket
    boundary local and avoid broad abstractions unless they remove real
    complexity.
14. GREEN: Update docs with implementation facts, validation results, review
    results, PR results, and Phase 12/M3 status.

## History Event Semantics

Phase 12 comment history uses these events:

- `comment`: `ts`, `event`, `by`, `ticket_id`, `body`
- `comment_notification_attempted`: `ts`, `event`, `by`, `ticket_id`,
  `injected_to`, `kind`
- `comment_notified`: `ts`, `event`, `by`, `ticket_id`, `injected_to`, `kind`
- `comment_notification_failed`: `ts`, `event`, `by`, `ticket_id`,
  `injected_to`, `kind`, `error`

The `kind` field must be the literal string `"ticket_comment"`.
Notification events use the comment author as `by`, matching the Phase 11
rejection feedback convention.
`comment` is appended first. Phase 12 adds `ticket_id` to the existing Phase 7
`comment` event type; previously persisted Phase 7 comment events may not have
that field and must remain readable/renderable. `comment_notification_attempted`
is appended after `comment` and before terminal injection when at least one
target exists. Its `injected_to` value is the list of all current assignee
slugs. Delivery outcome events are per assignee and use list-form `injected_to`
containing the single target slug, matching the Phase 9 and Phase 11
conventions. When a Ticket has no assignees, Babs appends only `comment`, treats
notification as a no-op success, and returns `{:comment_notified, []}`.

Comment notification prompt:

```text
[Babs Ticket T-YYYY-MM-DD-NNN comment]
State: <state>
Assignee: <slug>
From: <by>

<body>

This comment is persisted in Ticket history. Continue coordination through `bb ticket comment`.
```

The prompt is generated once per recipient. `Assignee` is the individual
recipient slug for that notification mirror, not the full assignee list.

## Validation Plan

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`
- `mise exec -- mix test --cover --export-coverage phase12`
- `mise exec -- mix cmd mix test.coverage`
- `npm run test:js`
- `npm run test:bdd`
- `npm run test:e2e`
- `mise exec -- mix babs.gate_a`
- `af validate --root .`
- `git diff --check`
- Privacy scan for public PR text and changed files.

Coverage thresholds remain the current umbrella thresholds from `BAB-2218`:
`:babs_citizens` must stay at or above 80% and `:babs` must stay at or above
75%. `mix test.coverage` is the coverage summary command already used by the
current project validation flow.

Optional or conditional validation:

- Multi-CLI manual smoke against Clare, Dylan, Flora, and Elena when their
  credentials and local CLIs are available. Missing or stopped seed Citizens
  should skip the smoke rather than fail this slice.

## Review Plan

- Plan review: Trinity fast-review using GLM and DeepSeek.
- Implementation review: Trinity fast-review using GLM and DeepSeek on the
  implementation diff.
- PR review: GitHub Codex review loop per `COR-1615`, capped at five rounds by
  `BAB-2218`.

## Review Results

- R1 `.trinity/reviews/20260506-162953-rules-BAB-2223-CHG-Implement-Phase-12-Cross-Citizen-Ticket-Comments.md`:
  DeepSeek PASS with blockers and GLM failed before review because the local
  droid command required `--auto medium`. Fixed local Trinity GLM config, then
  folded DeepSeek blockers on unassigned comment behavior, `by` validation,
  terminal-state rejection, author-history unit coverage, explicit event
  ordering, oversized-comment regression, root derivation, watcher refresh, and
  coverage thresholds.
- R2 `.trinity/reviews/20260506-164015-rules-BAB-2223-CHG-Implement-Phase-12-Cross-Citizen-Ticket-Comments.md`:
  GLM PASS and DeepSeek PASS with non-blocking findings. Folded notes on
  `comment.ticket_id` schema evolution, safe `bb` bridge invocation, new
  `bin/` executable expectations, icon addition, tmux env ordering, and
  coverage command wording.
- R3 `.trinity/reviews/20260506-164950-rules-BAB-2223-CHG-Implement-Phase-12-Cross-Citizen-Ticket-Comments.md`:
  GLM PASS and DeepSeek PASS with two plan blockers. Folded explicit partial
  notification success/failure delivery shape, notification event `by`
  provenance, author validation wiring, `comment_event` signature change,
  browser-harness `bb` env setup, concrete refactor gate, Error module coverage,
  literal PATH construction, concurrent comment test coverage, and removal of
  the Phase 7 deferred-delivery message.
- R4 `.trinity/reviews/20260506-165816-rules-BAB-2223-CHG-Implement-Phase-12-Cross-Citizen-Ticket-Comments.md`:
  GLM PASS and DeepSeek PASS with no blockers. Folded remaining non-blocking
  advisories on legacy comment rendering, `bb` shell-metacharacter tests, BDD
  env verification, caller audit, per-recipient prompt wording, pending-approval
  comment acceptance, and notification-attempt prevalidation coverage.

## Implementation Results

Implemented locally on `codex/m3-phase-12-ticket-comments`.

Implemented:

- Babs-owned tmux runtime env injection for `BABS_ROOT`,
  `BABS_CITIZEN_SLUG`, optional `BABS_TICKETS_ROOT`, and a `PATH` prefixed with
  `<BABS_ROOT>/bin`.
- Tracked `bin/bb` bridge for `bb ticket comment <id> "body" [--by actor]`
  with argument-array invocation of `mix babs.ticket.comment`.
- `mix babs.ticket.comment` `--by` support and live delivery result output.
- `Injector.comment_prompt/4` and history-first comment notification mirrors to
  all current assignees.
- `Writer.comment/4` validation for body, author, terminal states, event
  prevalidation, durable comment history, attempted notification events,
  per-assignee success/failure advisory events, and partial failure delivery
  results.
- Ticket detail comment form with `message-square` icon, async action guard,
  blank-body validation, timeline rendering, and advisory failure flash.
- Unit, LiveView, browser-harness BDD, and Playwright E2E coverage for the
  comment loop.

Local validation passed on 2026-05-06:

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`: `:babs_citizens` 194 tests, `:babs` 62 tests.
- `mise exec -- mix test --cover --export-coverage phase12`
- `mise exec -- mix cmd mix test.coverage`: `:babs_citizens` 83.11%,
  `:babs` 85.69%.
- `npm run test:js`: 8 tests.
- `npm run test:bdd`: PASS, including `ticket comment notifies assigned
  citizen`.
- `npm run test:e2e`: 5 passed, 2 optional seed CLI checks skipped, including
  `ticket detail stores operator comments from the browser`.
- `mise exec -- mix babs.gate_a`
- `af validate --root .`
- `git diff --check`
- Privacy scan over changed and new files.
- Real `bin/bb` smoke with an isolated tickets root confirmed
  `BABS_CITIZEN_SLUG` becomes the persisted comment author.

Trinity implementation review passed:

- R1 `.trinity/reviews/20260506-174129-BAB-2223-phase-12-implementation`:
  GLM PASS and DeepSeek PASS with non-blocking advisories. Fixed the low-cost
  advisories by adding a stable `:empty_body` error message and explicit
  oversized `comment_notification_attempted` prewrite coverage.
- R2 `.trinity/reviews/20260506-175133-BAB-2223-phase-12-implementation-r2-final`:
  GLM PASS and DeepSeek PASS. DeepSeek noted non-blocking LiveView coverage gaps
  for notification advisory failure flash and legacy comment rendering.
- R3 `.trinity/reviews/20260506-175943-BAB-2223-phase-12-implementation-r3-final-after-liveview-coverage`:
  DeepSeek PASS after the LiveView coverage fixes. GLM failed due provider
  execution error, not a review finding.
- R4 `.trinity/reviews/20260506-182204-apps-babs-test-babs_web-live-tickets_live_test.exs`:
  Scoped GLM retry PASS for the final LiveView coverage diff.
- Parser-fix scoped review
  `.trinity/reviews/20260506-184509-apps-babs_citizens-lib-mix-tasks-babs.ticket.comment.ex`:
  GLM PASS and DeepSeek PASS after PR #20 Codex R1 found that option-looking
  comment bodies such as `"--by"` were parsed as flags. The fix preserves
  `--by` before the Ticket id, supports `--by` after the body, and treats
  option-looking text after the Ticket id as literal comment body.

## Acceptance

- `bb ticket comment <id> "Backend done"` from a Citizen terminal persists a
  `comment` history event with the Citizen as `by`.
- `/tickets/<id>` renders the comment in the history timeline within 1s.
- All current assignees receive a terminal notification mirror, including the
  author when the author is assigned.
- Stopped assigned Citizens are auto-started before notification mirrors.
- Missing or failed notification targets create redacted advisory history and do
  not roll back the comment.
- The Ticket detail comment form can add comments with icon-labeled controls.
- All required validation passes before PR.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-06 | Draft Phase 12 cross-Citizen Ticket comments implementation contract | Codex |
| 2026-05-06 | Fold Trinity R1 blockers and R2 implementation advisories | Codex |
| 2026-05-06 | Fold Trinity R3 blockers and implementation advisories | Codex |
| 2026-05-06 | Fold Trinity R4 non-blocking advisories | Codex |
| 2026-05-06 | Mark approved after Trinity R4 GLM and DeepSeek PASS | Codex |
| 2026-05-06 | Record local implementation and validation results | Codex |
| 2026-05-06 | Fold implementation review advisories and record Trinity PASS results | Codex |
| 2026-05-06 | Record PR #20 Codex R1 option-looking comment body parser fix | Codex |
