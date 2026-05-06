# PRP-2217: Phase 7-12 M3 Ticket Billboard System

**Applies to:** BAB project
**Last updated:** 2026-05-06
**Last reviewed:** 2026-05-06
**Status:** Approved

---

## What Is It?

This PRP designs the full M3 ticket/billboard system across roadmap Phases
7-12. It is a single architecture contract for the filesystem-first Ticket
flywheel, but it is intentionally executed as multiple small PRs.

The M3 system introduces:

- The configured tickets root as the Billboard and Ticket source of truth.
- Strict Ticket markdown/frontmatter schema validation.
- Append-only Ticket history JSONL.
- Serialized per-ticket writes through `:babs_citizens`.
- A `bb ticket` CLI/API surface for Citizens and the operator.
- `/tickets` and `/tickets/<id>` browser UI.
- Assignment from Ticket to Citizen terminal prompt injection.
- The five-state Ticket lifecycle from `BAB-1111`.
- Human Inspector approval/reject UI for V0-M.
- Cross-Citizen comments that are persisted and injected to all assignees.

M3 does not add Mayor, autonomous ticket decomposition, role-based automatic
routing, read-only federation, mobile/PWA polish, or external Discord/Telegram
connectors. Those stay in later phases.

## Why

Phase 6 completes V0-S: Babs can run several Citizens, create them, navigate
between them, and manage lifecycle from the browser. The missing flywheel is
coordination. Today the operator can talk to each Citizen terminal, but there is
no durable shared work object that Citizens can read, update, route, and audit.

`BAB-1111` already decides the coordination primitive: Ticket files plus history
JSONL. Phase 7-12 turns that ADR into a usable V0-M system. Designing all six
phases together matters because assignment, state transitions, approval, and
cross-Citizen comments all depend on the same schema and writer semantics.

This PRP keeps the implementation disciplined:

- one source of truth: files in the configured tickets root, not SQLite
- one write path: per-ticket writer, not ad hoc file edits from several places
- one browser mental model: Billboard list, Ticket detail, Citizen assignment
- one citizen mental model: `bb ticket ...`
- one validation story: unit tests, LiveView tests, browser-harness BDD, E2E

## Preconditions

- Phase 6 must be merged and running from `main`.
- Phase 6.5 manual ticket dogfood is useful but not a gate for the current
  delivery. The operator explicitly chose direct Phase 7-12 implementation on
  2026-05-06.
- `BAB-1111` remains the architectural source for Ticket semantics.
- `BAB-1106` remains the browser terminal byte-stream contract.
- `BAB-1110` remains the OTP app boundary: ticket runtime code that does not
  require Phoenix belongs in `:babs_citizens`.

## Principles

1. **Filesystem first.** Ticket markdown and history JSONL are authoritative.
   SQLite may later hold a derived `tickets_index`, but M3 must work correctly
   without SQLite ticket tables.
2. **Human-editable but validated.** Operators can inspect and edit files, but
   Babs refuses malformed Ticket changes instead of silently accepting drift.
3. **Serialized writes.** Babs-owned writes go through a per-ticket writer. This
   prevents torn frontmatter updates and interleaved comments.
4. **Small vertical PRs.** M3 is designed together but implemented in reviewable
   slices. Each slice must have its own tests, BDD when browser behavior
   changes, local validation, Trinity review, and GitHub Codex review loop.
5. **Citizen-visible CLI before autonomy.** Citizens receive `bb ticket` as a
   stable command surface before Mayor/role automation exists.
6. **No hidden prompts.** Assignment/comment injection must be visible in the
   target Citizen terminal and persisted in Ticket history.
7. **Operator remains Inspector in V0-M.** Approval and rejection are explicit
   user actions. Auto-inspector Citizens start in Phase 15, not M3.

## Proposed Execution Slices

M3 should be delivered as four PRs:

| Slice | Roadmap phases | Result |
|---|---:|---|
| PR A | Phase 7 | Ticket storage core, schema validation, writer, minimal CLI/API |
| PR B | Phase 8 | Read-only `/tickets` UI and live refresh |
| PR C | Phase 9-10 | Assignment, prompt injection, five-state machine |
| PR D | Phase 11-12 | Approval/reject UI and cross-Citizen comments |

This gives the operator a usable improvement after every PR while keeping the
longer M3 semantics coherent. The delivery goal is still continuous Phase 7-12
execution: finish each slice, pass validation/review, merge, and proceed to the
next slice without reopening the architecture unless tests or review expose a
real defect.

PR C intentionally combines assignment and state machine work even though it is
larger than the other slices. The state machine has limited user value before
assignment can move a Ticket out of the Billboard, and assignment is unsafe
without legal transition checks.

## Ticket Data Model

### Source Files

Each Ticket has two files under the configured tickets root:

```text
<tickets_root>/T-2026-05-06-001.md
<tickets_root>/T-2026-05-06-001.history.jsonl
```

Default tickets root is `<BABS_ROOT>/var/tickets`, which is ignored by git.
Phase 7 should add a `BABS_TICKETS_ROOT` / `:babs_citizens, :tickets_root`
override for tests and operator deployments. Ticket files are runtime data and
must not be committed by default. Exporting or archiving Tickets into git is a
future explicit operator action, not the normal write path.

### Ticket ID

Ticket IDs use date-scoped monotonic IDs:

```text
T-YYYY-MM-DD-NNN
```

Phase 7 owns an allocator that scans the tickets root and issues the next
available ID for the current local date. Tests must cover collision handling and
concurrent creation.

### Frontmatter Schema

Phase 7 implements the `BAB-1111` schema with strict validation:

```yaml
---
id: T-2026-05-06-001
type: assignment
state: open
assigner: user
assignees: []
assignee_role: null
inspector: user
priority: normal
parent_ticket: null
created_at: 2026-05-06T00:00:00Z
updated_at: 2026-05-06T00:00:00Z
metadata: {}
---

# Ticket title

Markdown body.
```

Required values:

- `type`: initially `assignment`; `mission`, `proposal`, and `comment-thread`
  remain schema-reserved but not fully automated in M3.
- `state`: `open`, `in_progress`, `pending_approval`, `closed`, `cancelled`.
  `rejected` is a history event, not a state.
- `assignees`: always a list. Empty list means the Ticket is on the Billboard.
- `priority`: `low`, `normal`, `high`, `urgent`.
- `created_at` and `updated_at`: ISO-8601 strings.
- `metadata`: map only; no secrets.

`updated_at` changes on every Babs-owned mutation that changes Ticket
frontmatter, body, or history. Manual edits are accepted only if their
frontmatter remains valid; the Watcher does not rewrite `updated_at` on behalf
of the operator. The UI may show an advisory when a valid manual edit leaves
`updated_at` stale.

Validation rules:

- File stem and frontmatter `id` must match.
- Title is the first Markdown H1.
- Body must be non-empty after frontmatter.
- `assignees` must reference known Citizen slugs for API assignment from Phase
  9 onward. Phase 7 storage validation may surface unknown slugs as warnings so
  manually drafted Tickets can exist before assignment automation is online.
- A Ticket with `assignees: []` must be `state: open` unless it is cancelled.
- `closed` and `cancelled` are terminal states.
- Unknown frontmatter keys may be preserved only if nested under `metadata`;
  top-level unknown keys are rejected until a CHG extends the schema.

### Error Contract

Ticket APIs must return typed errors that are stable enough for tests, UI, and
CLI handling:

- `{:error, {:not_found, ticket_id}}`
- `{:error, {:invalid_id, value}}`
- `{:error, {:invalid_frontmatter, reason}}`
- `{:error, {:invalid_transition, from, to}}`
- `{:error, {:unknown_citizen, slug}}`
- `{:error, {:citizen_not_running, slug}}`
- `{:error, {:write_conflict, ticket_id}}`
- `{:error, {:redacted_io_error, operation}}`

Browser and CLI messages may translate these errors into user-facing text, but
must not expose env maps, tokens, private network details, or raw host paths.

### History JSONL

Each line is one JSON object:

```json
{"ts":"2026-05-06T00:00:00Z","event":"created","by":"user"}
{"ts":"2026-05-06T00:01:00Z","event":"assigned","by":"user","to":["clare"]}
{"ts":"2026-05-06T00:01:01Z","event":"state_change","by":"system","from":"open","to":"in_progress"}
{"ts":"2026-05-06T00:02:00Z","event":"comment","by":"clare","body":"Working on it."}
```

Required event fields:

- `ts`
- `event`
- `by`

`by` is required for M3 events, including `state_change`. This tightens
`BAB-1111`'s example format so every persisted event has provenance.

Common optional fields:

- `from`, `to`
- `body`
- `ticket_id`
- `injected_to`
- `error`

History is append-only. UI and CLI may render history, but neither may rewrite
old events.

All M3 communication is persisted to Ticket history first. Terminal injection is
an attention/notification mechanism, not a second source of truth. Authors see
their own comments through the same Ticket/Billboard history as everyone else.

## Architecture

### `:babs_citizens`

Add ticket runtime modules under `Babs.Citizens.Tickets`:

- `Ticket`: struct and validation contract.
- `TicketId`: ID parsing, formatting, and allocation.
- `TicketMarkdown`: frontmatter/body parser and serializer.
- `History`: JSONL append/read helpers.
- `Store`: read/list/show operations from the tickets root.
- `Writer`: one GenServer per Ticket ID that serializes mutations.
- `WriterSupervisor`: dynamic supervisor for writers.
- `WriterRegistry`: Registry key by Ticket ID.
- `StateMachine`: legal state transitions and errors.
- `Api`: public boundary used by web, CLI transport, and tests.
- `Injector`: prompt/comment injection through `Hardline.Pane.inject/2`.
- `Watcher`: filesystem watcher that broadcasts ticket changes to PubSub.

The application supervisor gains the writer registry/supervisor and watcher.
Ticket code must not depend on Phoenix LiveView. PubSub is already available in
`:babs_citizens` and can be reused for change notifications.

Writer and Watcher coordination:

- Babs-owned writes go through `Writer` only.
- `Writer` writes frontmatter/body atomically using a temporary file plus rename
  and appends history as a separate append-only operation.
- Phase 7 CHG must choose write ordering for coupled frontmatter/history
  mutations and define startup/lazy-init reconciliation when the last history
  event and frontmatter state disagree after a crash.
- `Writer` publishes a Ticket changed event after durable writes complete.
- `Watcher` handles operator/manual file edits by validating changed Ticket
  files and publishing either `{:ticket_changed, id}` or
  `{:ticket_invalid, path, reason}`.
- Duplicate changed events are acceptable. Consumers must refresh by reading
  the current file state instead of trusting event payloads as authoritative.
- If a manual edit races with a Babs write, the writer must re-read before
  mutation and return `{:error, {:write_conflict, ticket_id}}` when the on-disk
  state changed unexpectedly.

Writer lifecycle:

- Start a per-ticket writer lazily on the first Babs-owned mutation for that
  Ticket.
- Do not start writers for every Ticket during boot or read-only listing.
- Stop idle writers after a bounded timeout once no mutation is in flight.
- Terminal Tickets may still start a writer briefly to reject illegal writes
  with typed errors, but they must not stay resident indefinitely.

### `:babs`

Add web/UI modules:

- `BabsWeb.TicketsLive`: `/tickets` Billboard list.
- `BabsWeb.TicketLive`: `/tickets/<id>` detail page.
- Optional `BabsWeb.TicketPath` helper for URL generation.

The web app calls `Babs.Citizens.Tickets.Api`; it does not mutate files
directly.

### CLI / `bb ticket`

`bb ticket` is the Citizen-facing command surface. The accepted ADR specifies an
escript over a per-user Unix domain socket. Phase 7 should implement the
smallest useful version while keeping room for later commands:

```bash
bb ticket new --type=assignment --title="..." --body="..."
bb ticket list [--state=open] [--assignee=clare]
bb ticket show T-2026-05-06-001
bb ticket comment T-2026-05-06-001 "..."
bb ticket assign T-2026-05-06-001 --to=clare
bb ticket transition T-2026-05-06-001 pending_approval
bb ticket approve T-2026-05-06-001
bb ticket reject T-2026-05-06-001 --feedback="..."
```

The transport endpoint is internal and local-only. If UDS listener details prove
too large for PR A, PR A may ship `mix babs.ticket.*` tasks plus the internal
API, but `bb ticket` must exist before Phase 9 assignment is considered done.
Any deviation from the ADR must be recorded as a PRP review finding or CHG, and
the Phase 7 PR must state whether it implements ADR-complete `bb ticket` or a
temporary `mix babs.ticket.*` bridge.

Minimum Phase 7 CLI subset:

- `bb ticket new`
- `bb ticket list`
- `bb ticket show`

`bb ticket comment` may exist in Phase 7 only as storage-only history append. If
it ships before Phase 12 real-time UI/notification delivery, it must print an
explicit advisory that the comment was stored and live delivery is not available
yet.

## Phase Details

### Phase 7: Ticket File System Skeleton

Scope:

- Create strict Ticket parser/serializer.
- Create Ticket ID allocator.
- Create append-only history JSONL helpers.
- Create per-ticket `Writer`.
- Add public `Tickets.Api` for create/list/show and storage-only comment
  basics.
- Add minimal command surface for operator/Citizen use.
- Ensure concurrent writes cannot corrupt a Ticket.

Acceptance:

- Create five Tickets through the API/CLI.
- List and show Tickets without Phoenix.
- Concurrent create/comment attempts serialize and produce valid files.
- A Phase 7 comment appends one `comment` history event only; live UI delivery
  and notification mirrors remain Phase 12.
- Invalid frontmatter is rejected with typed errors.
- `af validate --root .` still passes with generated test fixtures excluded.
- No SQLite ticket table is required.

Unit tests:

- frontmatter parse/render round trip
- malformed frontmatter/body errors
- ID parsing/allocation/collision
- history append/read
- writer serialization
- root path config
- no env/secret leakage in errors

BDD:

- Optional browser-harness only if Phase 7 exposes browser-visible behavior.
  Otherwise Phase 7 is mostly unit/integration tests.

### Phase 8: Ticket Index UI and Render

Scope:

- Add `/tickets` list page.
- Add `/tickets/<id>` detail page.
- Render frontmatter, Markdown body, and history timeline.
- Add filesystem watcher live refresh.
- Link `/citizens` to `/tickets` and `/tickets` to `/citizens`.

Acceptance:

- Operator can browse all Tickets grouped by state.
- Operator can open a Ticket detail page and inspect body/history.
- Manual file edit updates UI within one second.
- Malformed Ticket files are visible as errors, not silently hidden.
- Billboard is the subset `state: open` and `assignees: []`.

LiveView tests:

- list grouping and ordering
- detail render
- invalid Ticket render
- live refresh message updates list/detail
- socket-token behavior remains unaffected for terminal routes

Browser-harness BDD:

- create a Ticket file manually, open `/tickets`, verify it appears
- edit the file externally, verify UI updates
- open Ticket detail and verify history timeline

### Phase 9: Ticket to Citizen Assignment

Scope:

- Add assign action from UI and CLI.
- Validate target Citizen exists and can be started/recovered.
- Transition `open -> in_progress`.
- Inject a structured prompt into the assigned Citizen terminal.
- Record assignment and injection events in history.

Prompt injection shape:

```text
[Babs Ticket T-2026-05-06-001 assigned]
Title: ...
Path: <tickets_root>/T-2026-05-06-001.md

<Ticket body>

Please acknowledge the assignment and work in this terminal. Use `bb ticket comment T-... "..."` for durable updates.
```

Acceptance:

- Assigning a Billboard Ticket to Clare removes it from Billboard.
- Clare's terminal receives the Ticket prompt.
- Ticket state becomes `in_progress`.
- History records assignment, state change, and injection.
- If the Citizen is stopped, assignment starts it using Phase 6 lifecycle
  behavior before injection. If start fails, assignment returns a typed error
  and records an advisory event instead of silently dropping the assignment.
- `Hardline.Pane.inject/2` is currently asynchronous. Phase 9 must either add a
  confirmed injection path for assignment/rejection feedback, or record
  `injection_attempted` plus `injection_failed`/advisory events. History must
  not claim confirmed delivery unless the write to the pane is confirmed.

Tests:

- assign legal/illegal state checks
- missing Citizen
- stopped Citizen chosen behavior
- successful prompt injection uses `Pane.inject/2`
- assignment history is durable
- browser UI assign button
- browser-harness assignment flow from `/tickets` to Citizen terminal

### Phase 10: Ticket State Machine

Scope:

- Implement legal transitions:
  - `open -> in_progress`
  - `open -> cancelled`
  - `in_progress -> open` via `unassigned` event when the assignee list becomes
    empty and the Ticket returns to the Billboard
  - `in_progress -> pending_approval`
  - `in_progress -> cancelled`
  - `pending_approval -> closed`
  - `pending_approval -> in_progress` via `rejected` event
  - `pending_approval -> cancelled`
- Removing the last assignee from `pending_approval` is illegal. The operator
  must reject it back to `in_progress` first, then unassign if the Ticket should
  return to the Billboard.
- Reject illegal transitions with typed errors.
- Persist every transition to history.
- Expose UI controls only for legal transitions.

Acceptance:

- All legal paths are test-covered.
- Illegal transitions are rejected at API and UI boundaries.
- History timeline shows transition metadata.
- Closed/cancelled Tickets cannot be mutated except by future explicit reopen
  CHG.
- Removing the last assignee from an `in_progress` Ticket returns it to `open`
  and puts it back on the Billboard.

Tests:

- full transition matrix
- unassign-last-assignee returns `in_progress -> open`
- API transition errors
- UI button availability by state
- history event body for transitions
- BDD walk: open -> in_progress -> pending_approval

### Phase 11: Approval UI

Scope:

- Pending approval Tickets show `Approve` and `Reject`.
- Approve transitions to `closed`.
- Reject requires feedback and transitions to `in_progress` via a `rejected`
  history event.
- Feedback is injected into assigned Citizens.

Acceptance:

- Operator can approve from `/tickets/<id>`.
- Operator can reject with feedback from `/tickets/<id>`.
- Rejection feedback appears in the assigned Citizen terminal.
- History records approval/rejection and injected feedback.
- Inspector remains `user` in V0-M.

Tests:

- approve action
- reject requires feedback
- feedback redaction/safety
- injection failure behavior
- browser-harness approve/reject flow

### Phase 12: Cross-Citizen Ticket Comments

Scope:

- `bb ticket comment <id> "..."`
- UI comment form on Ticket detail.
- Comments append to history.
- Comments append to Ticket history first. The Ticket/Billboard history is the
  communication surface for every participant, including the author.
- Terminal notifications may be sent to assigned Citizens, including the
  author, but those notifications mirror history and are not authoritative.
- Multi-assignee Tickets become operational for comments.

Acceptance:

- A Ticket assigned to Clare and Dylan receives a comment from Clare.
- The comment is appended once to history.
- Dylan sees the comment in Ticket/Billboard history within one second.
- The author sees the same persisted comment in Ticket/Billboard history.
- If one assignee is stopped, the history still records the comment and the UI
  shows delivery failure/advisory for that assignee.

Tests:

- CLI comment
- UI comment
- multi-assignee history visibility and notification mirror behavior
- stopped/missing assignee behavior
- author sees own comment through history without creating a second history row
- browser-harness two-Citizen comment flow

## Browser UX

`/tickets` should be dense and operational:

- state tabs or grouped sections: Billboard, In Progress, Pending Approval,
  Closed, Cancelled
- compact count badges
- sortable or stable ordering by priority, updated time, ID
- visible assignees
- concise error row for malformed files

`/tickets/<id>` should show:

- state badge
- title
- frontmatter summary
- Markdown body
- history timeline
- legal actions only
- assignment controls
- comment box when comments are available

Every Ticket UI action button must include a relevant semantic icon and follow
the existing `/citizens` and Hardline manager console operations style.
Examples:

- create/new Ticket: plus icon
- assign: user-plus or route icon
- approve: check icon
- reject: x or undo icon
- cancel: ban/stop icon
- comment/send: send/message icon
- refresh/retry: rotate/refresh icon

Icon-only dense controls require accessible labels or tooltips.

No landing-page hero. No decorative cards inside cards. Keep the style aligned
with existing `/citizens` operations UI.

## Validation Stack

Every implementation PR must run the applicable subset:

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`
- `mise exec -- mix test --cover`
- `npm run test:js`
- `npm run test:bdd` for browser-harness BDD scenarios
- `npm run test:e2e`
- `mise exec -- mix babs.gate_a`
- `af validate --root .`
- `git diff --check`

Coverage expectations:

- `:babs_citizens >= 80%`
- `:babs >= 75%`
- M3 ticket core modules should target higher local coverage because their data
  mutation surface is shared: parser/writer/state-machine modules should be
  close to exhaustively unit tested.

## BDD Scenarios

The M3 browser-harness suite should eventually include:

1. Billboard list shows manually created open unassigned Ticket.
2. Ticket detail renders body and history.
3. External file edit updates `/tickets` without browser reload.
4. Assign Ticket to Clare from UI and see prompt in Clare's terminal.
5. Clare transitions Ticket to pending approval through CLI or UI.
6. Operator rejects with feedback; Clare receives feedback in terminal.
7. Operator approves; Ticket becomes closed and immutable.
8. Clare comments on a multi-assignee Ticket; Clare and Dylan both see it in
   Ticket/Billboard history.
9. Stopped assignee does not corrupt history; delivery failure is visible.
10. Malformed Ticket file is surfaced in UI and does not crash the page.

Scenario ownership by slice:

| Scenario | Slice |
|---:|---|
| 1, 2, 3, 10 | PR B / Phase 8 |
| 4, 5 | PR C / Phase 9-10 |
| 6, 7 | PR D / Phase 11 |
| 8, 9 | PR D / Phase 12 |

## Security and Privacy

- Ticket files are operator-local runtime data under the configured tickets
  root. They are not committed to git by default. Babs must not write API
  tokens, env maps, socket tokens, private IPs, or local host details into
  Ticket metadata or history automatically.
- Browser errors must use redacted reason strings.
- `bb` transport is local-only. If UDS is implemented, permissions must be
  owner-only. If any HTTP fallback is introduced, it requires a CHG.
- Public PR text must not include private Tailscale IPs or machine-local URLs.

## Rollback

Each PR slice must be independently revertible:

- PR A revert removes Ticket runtime without touching existing Citizen runtime.
- PR B revert removes UI while leaving Ticket files readable by CLI.
- PR C revert disables assignment and state machine controls while leaving
  existing Ticket files valid.
- PR D revert disables approval/comment automation while keeping history
  readable.

Generated Ticket fixtures for tests must live under temporary directories and
must not dirty the real runtime tickets root unless the test explicitly verifies
operator-visible manual files.

## Out of Scope

- Mayor Citizen and proposal generation.
- Role-based auto-routing.
- Inspector Citizen auto-approval.
- External connectors.
- Cross-node write federation.
- Mobile/PWA polish.
- Ticket SQLite source of truth.
- Rich Markdown editor.
- Attachments or binary files.
- Secret storage.

## Operator Decisions

These decisions were made on 2026-05-06 before Phase 7 implementation:

1. Phase 7-12 should be delivered as one continuous M3 goal. Keep reviewable PR
   slices, but continue through Phase 12 without reopening the phase strategy.
2. Phase 6.5 manual dogfood is documented for context but waived as a gate.
3. Assigning a Ticket to a stopped Citizen should auto-start the Citizen before
   injection. Start failure is a typed error with a persisted advisory.
4. All cross-Citizen communication is written to Ticket/Billboard history.
   Authors see their own messages through the same persisted history as other
   participants; terminal delivery is notification only.
5. Tickets are runtime data and must not enter git by default. The default
   tickets root is `<BABS_ROOT>/var/tickets`, with a configurable override.

## Phase 6.5 Manual Dogfood Reference

The waived dogfood would have been:

1. Manually create one or two Ticket markdown files plus history JSONL under the
   tickets root.
2. Manually edit frontmatter from `state: open, assignees: []` to assign Clare
   or Dylan.
3. Manually paste the Ticket body into the Citizen terminal as the initial
   prompt.
4. Let the Citizen work and comment by editing/appending the Ticket history.
5. Manually move the Ticket through `pending_approval` and `closed`, recording
   friction before building automation.

This is still useful as a sanity exercise, but it no longer blocks Phase 7-12
implementation.

## Review Plan

- Review this PRP with Trinity fast-review using GLM and DeepSeek.
- Review unit: `BAB-2217` M3 design contract.
- Workflow: COR-1602 multi-model parallel review.
- Rubric: PRP/design review. Approval requires both reviewers to PASS with no
  blockers.
- Record review directory and decisions in this document before implementation.

## Review Results

- R1 `.trinity/reviews/20260506-084951-rules-BAB-2217-PRP-Phase-7-12-M3-Ticket-Billboard-System.md`:
  GLM found an `in_progress -> open` unassign blocker; DeepSeek timed out at the
  default 600 second limit.
- R2 `.trinity/reviews/20260506-090252-rules-BAB-2217-PRP-Phase-7-12-M3-Ticket-Billboard-System.md`:
  GLM and DeepSeek both returned; blockers were history event naming and
  five-state lifecycle wording.
- R3 `.trinity/reviews/20260506-090855-rules`: full `rules/` scope review found
  one required namespace/vocabulary alignment issue and several advisory
  cross-document drift items.
- R4 `.trinity/reviews/20260506-091352-rules`: GLM PASS and DeepSeek PASS with
  only non-blocking advisories.
- R5 `.trinity/reviews/20260506-091957-rules`: GLM PASS and DeepSeek PASS on the
  final full `rules/` scope after advisory fold-in. Remaining notes are
  implementation-level CHG details, not PRP blockers.
- R6 `.trinity/reviews/20260506-095700-rules`: GLM PASS and DeepSeek PASS after
  operator decisions were recorded. Remaining notes are non-blocking Phase 7+
  CHG details.

## Acceptance Criteria

- `BAB-2217` clearly defines Phase 7-12 scope, architecture, execution slices,
  tests, validation, and out-of-scope boundaries.
- Trinity plan review passes with no blockers.
- Operator decisions for Phase 7-12 are recorded before Phase 7 code starts.
- Phase 7 implementation begins only after this PRP is approved.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-06 | Initial M3 Phase 7-12 Ticket/Billboard PRP draft | Codex |
| 2026-05-06 | Address GLM fast-review blocker by adding `in_progress -> open` unassign transition; clarify typed errors, Writer/Watcher coordination, and ADR-deviation handling | Codex |
| 2026-05-06 | Address Trinity R2 blockers by aligning history event names with `BAB-1111`, using five-state lifecycle wording, and folding review clarifications on writer lifecycle, comments, injection confirmation, and BDD ownership | Codex |
| 2026-05-06 | Address Trinity R3 findings by aligning vocabulary/roadmap/ADR namespace, defining Phase 7 CLI minimums, and flagging write-order recovery for the Phase 7 CHG | Codex |
| 2026-05-06 | Fold Trinity R4 advisories for pending-approval unassign behavior and stale `updated_at` manual-edit advisory | Codex |
| 2026-05-06 | Record Trinity R1-R5 review results; final R5 returned GLM PASS and DeepSeek PASS with no PRP blockers | Codex |
| 2026-05-06 | Record operator decisions: continuous Phase 7-12 delivery, Phase 6.5 waiver, auto-start on assignment, Billboard-history communication, and gitignored runtime Ticket data | Codex |
| 2026-05-06 | Align ADR/roadmap terminology after operator decision: comments are persisted to Billboard history first and terminal notifications are mirrors only | Codex |
| 2026-05-06 | Mark PRP approved after Trinity R6 GLM/DeepSeek PASS with no blockers | Codex |
| 2026-05-06 | Add Ticket UI icon requirement for all action buttons, matching existing operations-console style | Codex |
| 2026-05-06 | Update auto-inspector phase reference after imported tmux attach inserted as Phase 13 | Codex |
