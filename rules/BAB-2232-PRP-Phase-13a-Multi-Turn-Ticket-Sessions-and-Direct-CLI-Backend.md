# PRP-2232: Phase 13a Multi-Turn Ticket Sessions and Direct CLI Backend

**Applies to:** BAB project
**Last updated:** 2026-05-07
**Last reviewed:** 2026-05-07
**Status:** Approved
**Date:** 2026-05-07
**Requested by:** Operator
**Priority:** High

---

## What Is It?

Add a Phase 13a milestone between Phase 13 and Phase 14 to make the Ticket
flywheel feel like a real ongoing collaboration surface instead of a one-shot
prompt relay.

Phase 13a has two tightly related goals:

1. **Multi-turn Ticket sessions** - a Ticket detail page becomes a durable chat
   surface where the operator and assigned Citizens can continue a conversation
   over multiple turns, with ordered messages, delivery state, captured replies,
   and retry visibility.
2. **Direct CLI execution backend** - Babs can run supported AI CLIs in
   non-interactive mode for Ticket turns, store each provider session id, and
   resume the same provider conversation on later turns. The existing tmux
   Hardline backend remains the default live/debug backend, and a lazy-tmux path
   can open an interactive tmux session only when needed.

This is an exception to the original "no non-interactive AI workflows" roadmap
anti-goal. The exception is narrow: direct CLI execution is only a Ticket-turn
backend for Babs Citizens. Babs is not becoming a generic batch-job runner.

---

## Problem

Phase 12a made assignment delivery and reply capture much more reliable, but
dogfood exposed two product-level gaps:

- A Ticket currently feels like a single prompt plus a captured answer. The
  operator can add comments, but the model, UI, and reply-capture semantics do
  not yet clearly represent "turn 2", "turn 3", or "continue this same
  conversation".
- Some AI CLI workflows do not need a persistent tmux pane at all times. For
  example, Claude Code, Codex CLI, and GitHub Copilot CLI all expose
  non-interactive prompt modes and some form of session resume. Keeping tmux
  alive for every dormant Citizen is useful for live debugging, but it is not
  always the simplest execution path for a Ticket turn.

The two issues should be solved together. A direct CLI backend needs an explicit
Ticket turn model so it knows what context to send and which provider session id
to resume. A multi-turn Ticket UI benefits from knowing whether the next turn is
being delivered through Hardline, direct CLI, or a lazy interactive session.

## Proposed Solution

### Phase Placement

Add **Phase 13a - Multi-Turn Ticket Sessions + Direct CLI Backend** immediately
after Phase 13 and before Phase 14. This avoids renumbering the accepted
Phase 14-17 roadmap while preserving the operator preference for lettered phases
instead of decimal phases.

### 1. Multi-Turn Ticket Conversation Model

Introduce an explicit turn/message model on top of the existing Ticket history
JSONL. The Ticket markdown file remains the source of truth for Ticket metadata
and body; the history JSONL remains the durable event log.

Required concepts:

- `turn_id`: stable id for each operator-to-Citizen prompt turn.
- `message_id`: stable id for each visible chat row rendered in the Ticket UI.
  A `turn_id` groups one operator prompt plus zero or more reply/status
  messages; every visible message has its own `message_id`.
- `parent_turn_id`: optional link for retries or replacements.
- `attempt_id`: stable id for one delivery attempt to one Citizen.
- `delivery_backend`: `hardline`, `direct_cli`, or `lazy_tmux`.
- `delivery_status`: `queued`, `busy`, `delivered`, `failed`, `captured`,
  `stale`, or `deduplicated`.
- `provider_session_id`: the upstream AI CLI session id when available.

The history file should accept new event names such as:

```jsonl
{"ts":"2026-05-07T10:00:00Z","event":"comment","ticket_id":"T-...","message_id":"msg_...","turn_id":"turn_...","by":"user","body":"..."}
{"ts":"2026-05-07T10:00:00Z","event":"turn_created","ticket_id":"T-...","turn_id":"turn_...","prompt_message_id":"msg_...","by":"user","to":["clare","dylan"]}
{"ts":"2026-05-07T10:00:01Z","event":"turn_delivery_attempted","ticket_id":"T-...","turn_id":"turn_...","attempt_id":"attempt_...","to":"clare","backend":"hardline","status":"queued"}
{"ts":"2026-05-07T10:00:02Z","event":"turn_execution_started","ticket_id":"T-...","turn_id":"turn_...","attempt_id":"attempt_...","to":"clare","backend":"hardline"}
{"ts":"2026-05-07T10:00:03Z","event":"turn_delivered","ticket_id":"T-...","turn_id":"turn_...","attempt_id":"attempt_...","to":"clare","backend":"hardline"}
{"ts":"2026-05-07T10:01:00Z","event":"comment","ticket_id":"T-...","message_id":"msg_...","turn_id":"turn_...","by":"clare","body":"..."}
{"ts":"2026-05-07T10:01:00Z","event":"turn_reply_captured","ticket_id":"T-...","turn_id":"turn_...","attempt_id":"attempt_...","by":"clare","message_id":"msg_..."}
```

Visible chat rows remain `comment` events for backward compatibility. `turn_*`
events are operational correlation/status events. CHG 13a.1 must update all
Ticket chat readers to join `comment` and `turn_*` events by `turn_id` /
`message_id` from the first implementation slice; it must not leave the UI
filtering only legacy comments without status context. Legacy comments without a
`turn_id` still render normally.

All `turn_*` events must be appended through the existing per-ticket
`Babs.Citizens.Tickets.Writer` path. Phase 13a must not introduce a second
history writer for turn metadata.

Delivery status is per recipient attempt, not only per turn. The reducer key is
`{turn_id, citizen_slug, attempt_id}` so one multi-Citizen turn can show Clare
delivered, Dylan failed, and Elena queued without collapsing those states.

`parent_turn_id` is reserved for retry/replacement chains. Normal follow-up
operator prompts are new sibling turns in the same Ticket. Multi-Citizen replies
to the same prompt share the same `turn_id` and have distinct `message_id`
values.

Ordering is JSONL append order from the per-ticket Writer. `ts` is display and
audit metadata, not the sole ordering authority. Tests must cover same-second
events, retry chains, and replies captured after later status events.

Initial CHG scope implements `queued`, `delivered`, `captured`, and `failed`.
`busy` is used when per-Citizen serialization rejects a concurrent turn instead
of queueing it. `stale` and `deduplicated` are reserved statuses for
post-dogfood refinement unless the implementation needs them to avoid duplicate
replies.

Minimum status/event table:

| State | Required event |
|---|---|
| queued | `turn_delivery_attempted` with `status: "queued"` |
| actively executing | `turn_execution_started` |
| provider accepted delivery | `turn_delivered` |
| provider/runner failed | `turn_delivery_failed` |
| reply persisted | visible `comment` plus `turn_reply_captured` |
| rejected by serialization | `turn_delivery_attempted` with `status: "busy"` |

Use sortable, machine-independent Babs-generated ids for `turn_id`,
`message_id`, and `attempt_id`: prefer UUIDv7-compatible or ULID-style ids if an
existing dependency supports them, otherwise use an equivalent timestamp plus
cryptographically random suffix. The CHG must fixture-test the exact chosen
format.

### 2. Ticket Detail Chat UI

Replace the current rough comments layout with a proper light-theme,
messaging-app-style chat surface. The target feel is closer to a compact
business messaging tool than to a raw operations log: messages are easy to scan
as a conversation, while delivery/capture metadata remains visible but secondary.

- ordered message stream with left/right or role-distinguished rows for user,
  Citizen, and system/status messages;
- each row shows author, timestamp, backend/status badge, and readable body
  formatting without turning every status field into a separate line;
- sticky composer for the operator;
- visible pending/delivered/failed/captured states per turn;
- retry action for failed delivery;
- "open terminal" / "open full" affordance when a direct or lazy backend needs
  interactive inspection;
- icon-bearing buttons consistent with the existing Citizen and Hardline UI.

The UI must keep Ticket history authoritative. Terminal notifications and AI CLI
transcripts remain mirrors or capture sources, not the source of truth.

CHG 13a.1 must add a light-theme kitchen-sink page before the production Ticket
chat view is finalized. The kitchen sink should live at `/dev/kitchen-sink` in
dev/test and should render representative components, Ticket chat states,
buttons with icons, status badges, validation errors, empty states, and
terminal-in-light-shell examples. See `BAB-1004` for the detailed UI contract.
Operator review found the first inline-CSS kitchen-sink spike visually weak, so
CHG 13a.1 must correct the foundation before more Ticket polish: install the
Phoenix Tailwind CSS pipeline, define Babs theme tokens, move shared UI styling
out of inline LiveView CSS, and then rebuild the kitchen sink against that
system. The accepted reference stack is Tailwind UI Application UI for layout
patterns, shadcn/ui neutral tokens for light-theme discipline, Petal Components
for Phoenix/HEEx implementation style, and Tremor only for dense dashboard
inspiration. Do not adopt daisyUI default themes for the Babs product shell.

Ticket detail should keep Ticket status and routing context visible outside the
message stream. Use a top summary bar and/or side rail for state, priority,
assignees, inspector, delivery summary, latest captured reply, and action
buttons. The chat column should carry the conversation; the surrounding chrome
should carry operational state.

OpenHanako is useful as an external reference, but not as a stack template. The
parts worth borrowing for Phase 13a+ are product shape rather than specific
implementation:

- keep each Citizen self-contained and easy to back up, similar to an
  agent-as-folder mental model;
- make asynchronous collaboration first-class: Ticket chat is the visible
  conversation, while future attachments/notes can become a Babs equivalent of a
  per-agent desk;
- keep background work independent from the active browser view, matching the
  Hub idea where heartbeat, scheduling, and routing continue outside the current
  chat session;
- design plugin/page/widget/theme contracts early enough that future operator
  surfaces can reuse shared UI tokens instead of inventing one-off screens;
- treat file/media artifacts as registered session resources, not raw local
  paths embedded in chat.

Do not import OpenHanako's Node/Electron/runtime choices into Phase 13a. Babs
remains an Elixir/Phoenix/Ecto application; OpenHanako's use of
`better-sqlite3` is appropriate for its Node stack but not a reason to add a
second database access path here.

### 3. Prompt Assembly For Follow-Up Turns

Add a prompt assembler that builds a provider-neutral follow-up prompt from:

- Ticket id, title, state, assignees, acceptance criteria, and current body;
- the recent N Ticket chat messages;
- the latest operator message;
- the required Babs reply contract for the chosen backend;
- the Citizen slug and role context.

The assembler must be fixture-tested. It must not leak local paths, private IPs,
tokens, or raw upstream transcript records.

Default context window: include the latest 12 visible chat messages, with a
Citizen-level configuration override in a later CHG if dogfood shows the default
is too short or too noisy.

### 4. Direct CLI Execution Backend

Add an execution backend abstraction beside the existing Hardline path.

Initial backend values:

| Backend | Meaning |
|---|---|
| `hardline` | Existing tmux + erlexec + browser terminal path. Default for current Citizens. |
| `direct_cli` | Non-interactive provider CLI execution for a Ticket turn. No persistent tmux required. |
| `lazy_tmux` | Start direct, then open or resume an interactive tmux Hardline only when the operator needs a live terminal. |

Provider adapters should expose a small behavior:

```elixir
start_turn(citizen, turn) :: {:ok, result} | {:error, reason}
resume_turn(citizen, provider_session_id, turn) :: {:ok, result} | {:error, reason}
discover_session(result, artifacts) :: {:ok, provider_session_id} | :unknown
```

`artifacts` means sanitized command stdout/stderr plus provider-specific
transcript/session-state candidates discovered by the adapter. If
`discover_session/2` returns `:unknown`, Babs must record the direct attempt as
non-resumable and use the configured Hardline fallback for future turns rather
than silently treating the session as resumable.

The behavior above is the logical adapter contract; CHG 13a.2 decides whether
callbacks block inside a supervised runner task/process or are represented as
messages to a runner GenServer. Long-running provider work must not block the
Ticket Writer.

The first supported direct providers should be:

| Provider | Direct command shape | Session evidence |
|---|---|---|
| Claude Code | `claude -p` with `--session-id` or `--resume` | CLI supports explicit session ids and resume semantics. |
| Codex CLI | `codex exec --json` and `codex exec resume <id>` | JSONL/stdout includes a session/thread id in current local testing. |
| GitHub Copilot CLI | `copilot -p --output-format json` with `--resume` or `--connect` | Session state is recorded under Copilot's session-state data and emits a session id. |

Provider command support must be version-gated with canary tests or adapter
fixture tests. If a provider shape changes, Babs should fall back to Hardline
rather than silently losing a reply.

Implementation order should be provider-by-provider, not all-or-nothing. Start
with the provider whose session-id semantics are strongest in the local
environment, then add the remaining providers behind explicit fixture/canary
checks. Phase 13a is not complete until Claude, Codex, and Copilot are each
either supported directly or marked Hardline-only with an explicit fallback test
and UI indication.

Direct CLI execution must not use ad hoc unmanaged `System.cmd` calls. The CHG
must introduce a supervised direct-execution runner in `:babs_citizens` that can
track a Babs-owned OS process id/process group, enforce timeouts, terminate or
cancel it, record running state, and perform a boot-time sweep of stale
Babs-owned direct executions. Reusing `erlexec` without PTY mode is acceptable
if it gives stronger process-group cleanup than a plain command spawn.

Direct execution is serial per Citizen. At most one active execution may exist
for a Citizen across `direct_cli`, `hardline`, and `lazy_tmux`. Rapid follow-up
turns for the same Citizen must be queued with visible `queued` status or
rejected with a visible `busy` error; they must never start concurrent provider
processes against the same workspace or provider session.

Direct reply capture is part of the backend contract. A successful direct
adapter returns a sanitized assistant reply payload plus optional provider
session metadata. The Writer then appends:

1. a visible `comment` event with `turn_id`, `message_id`, `by`, and redacted
   `body`;
2. a `turn_reply_captured` event that references the same `message_id` and
   attempt.

Raw stdout/stderr and provider transcript snippets must be bounded, redacted,
and discarded or stored only as safe metadata before anything reaches Ticket
history or the browser UI.

If a stored `provider_session_id` is rejected, expired, or missing at resume
time, Babs must append a visible resume-failure status, mark that provider
session non-resumable, and use the configured fallback. The default fallback is
Hardline delivery; starting a fresh direct provider session must be a visible
new attempt rather than silently overwriting the old session row.

If the current direct attempt produced a sanitized assistant reply but
`discover_session/2` returned `:unknown`, Babs still captures the current reply
and marks only future turns as non-resumable. If the current attempt produced no
safe reply, the current turn follows the fallback path.

Direct subprocess environments must be built from the Citizen's resolved config
and launch profile. Do not inherit the full Babs server environment by default.
The CHG must define env allowlist/override behavior, stdin policy,
non-interactive approval flags, command-argument construction, output size
limits, and redaction fixtures for provider stdout/stderr.

### 5. Provider Session Persistence

Persist provider session metadata in the existing SQLite database. The preferred
first implementation is a new table, not a blob in `citizens.metadata`, because
session lookup is likely to become queryable.

Proposed table:

| Field | Notes |
|---|---|
| `id` | Babs-generated row id. |
| `citizen_slug` | String slug. Prefer a real FK to `citizens.slug` because the current table has a unique slug index; if migration constraints make that risky, document slug-stability semantics in the CHG. |
| `ticket_id` | String Ticket id such as `T-2026-05-07-001`; do not use an integer id. |
| `provider` | `claude`, `codex`, `copilot`, etc. |
| `backend` | Configured backend: `direct_cli`, `hardline`, or `lazy_tmux`. Lazy-tmux rows keep `lazy_tmux`; attempt events record whether the current phase used direct execution or Hardline. |
| `provider_session_id` | Nullable upstream session/thread id. Null means direct execution is non-resumable until discovery succeeds. |
| `provider_cli_version` | Captured version string or capability fingerprint used by canary/fallback logic. |
| `capabilities` | Safe JSON map such as `%{"direct" => true, "resume" => true}`. |
| `workspace_ref` | Citizen workspace reference such as slug/root key, not a private absolute path. |
| `cwd_fingerprint` | Optional safe fingerprint for detecting workspace drift without storing local absolute paths. |
| `status` | `active`, `non_resumable`, `closed`, or `failed`. |
| `last_turn_id` | Last Babs turn id delivered through this session. |
| `os_pid` / `os_pgid` | Nullable direct runner process metadata for in-flight cleanup only. |
| `started_at` | Nullable direct runner start timestamp for stale-process sweeps. |
| `last_error` | Redacted last provider/session error. |
| `created_at` / `updated_at` | Ecto timestamps. |
| `metadata` | Provider-specific safe metadata only. |

Do not store raw prompts, raw assistant output, tokens, or private machine paths
in this table. Durable conversation content stays in Ticket history. If an
absolute cwd is needed for execution, derive it at runtime from the Citizen row
and workspace config rather than persisting it in provider session rows.

This table is the authoritative lookup location for provider session identity.
History events may denormalize `provider_session_id` for audit/debugging, but
resume lookups should go through the session table.

Expected lookup constraints:

- unique active session key for `{citizen_slug, ticket_id, provider, backend}`
  when `status in ('active', 'non_resumable')`;
- index on `{citizen_slug, status}` for lifecycle cleanup;
- index on `{ticket_id, citizen_slug}` for Ticket detail status rendering;
- migration, rollback, and uniqueness tests must be part of CHG 13a.2.

### 6. Lazy Tmux Semantics

`lazy_tmux` is additive and should be conservative:

- dormant Citizens may prefer direct CLI for Ticket turns;
- operator can still open a terminal for a Citizen when debugging is needed;
- if the provider can resume interactively by session id, Babs should pass that
  id to the tmux launch command;
- if interactive resume is unavailable, Babs opens a fresh Hardline with a clear
  UI note that the direct CLI session cannot be attached interactively;
- if a direct CLI turn is still running when the operator requests an
  interactive terminal, the default behavior is attach-after-completion: show
  that the direct turn is in progress, offer an explicit cancel action, and open
  the terminal after the direct runner has finished or been cancelled;
- if a queued direct turn exists for the same Citizen, lazy-tmux attach must
  preserve queue ordering or explicitly cancel/retry the queued turn with a
  visible history event;
- the one-Citizen-one-Hardline invariant remains intact.

### 7. Database Driver Decision: Do Not Adopt better-sqlite3 In This Phase

The operator asked whether Babs should switch to
`WiseLibs/better-sqlite3`.

Research summary:

- `better-sqlite3` is a strong SQLite library for Node.js. Its README describes
  a synchronous API, transaction support, high performance, worker-thread
  support, and WAL guidance.
- Node's built-in `node:sqlite` now exposes `DatabaseSync`, but the Node docs
  still mark the module as release-candidate stability as of Node 26 docs.
- Babs's runtime database is not Node-based. It is Elixir Ecto using
  `ecto_sqlite3`, which depends on the Elixir SQLite library `exqlite`.

Decision for Phase 13a:

- Keep `ecto_sqlite3` / `exqlite` as the Babs runtime database stack.
- Do not introduce a Node sidecar or `better-sqlite3` just to access the same
  SQLite file from JavaScript.
- Allow a future Node-only utility or browser-test helper to use
  `better-sqlite3` only if it is read-only against the runtime database or uses
  an isolated test database. It must never write the runtime SQLite file or
  bypass Ecto migrations.
- Consider a separate dependency-refresh CHG to update `ecto_sqlite3` from the
  current `~> 0.22.0` line to the latest compatible Hex release, with migration
  and rollback validation.

Reasoning: adopting `better-sqlite3` for the Elixir runtime would add a second
language boundary, a native Node addon, a second SQL access layer, and lock
coordination risk without replacing Ecto migrations or schemas. The expected
Phase 13a bottleneck is conversation/session semantics, not SQLite driver
performance.

### 8. Tests And Validation

Required test coverage:

- Unit tests for Ticket turn event parsing, ordering, and backward compatibility
  with legacy `comment` events.
- Unit tests for legacy comment interleaving with new turn-grouped comments,
  same-second timestamps, retry chains, and out-of-order reply capture.
- Unit tests for prompt assembler fixtures.
- Unit tests for provider session persistence, uniqueness, migration rollback,
  and redaction.
- Adapter fixture tests for Claude, Codex, and Copilot direct CLI JSON/output
  shapes.
- Adapter tests proving resume commands receive the stored
  `provider_session_id` and that invalid/expired session ids produce the
  configured fallback event.
- Redaction and output-limit tests for direct provider stdout/stderr before
  assistant replies reach Ticket history or UI.
- Environment-construction tests proving direct subprocesses use Citizen config
  and launch-profile policy rather than inheriting the full Babs server env.
- Integration test for direct CLI failure or provider-shape mismatch falling
  back to Hardline delivery without losing the Ticket reply.
- Process-lifecycle tests for direct CLI timeout/cancel/owner-exit cleanup using
  a fake or deterministic long-running command.
- Restart/sweep test for an in-flight direct execution row and fake process.
- Concurrency tests proving two turns for the same Citizen cannot run provider
  processes at the same time and instead become ordered `queued` / `busy`
  outcomes.
- Writer/API tests for multi-turn comments, retries, delivery failures, and
  captured replies.
- LiveView tests for chat rendering, composer submit, retry, status badges, and
  icon controls.
- Asset-pipeline tests or build validation proving Tailwind-generated CSS is
  available to the kitchen-sink route and production LiveViews.
- Kitchen-sink route tests or browser-harness smoke that cover light-theme
  contrast, representative components, icon-bearing controls, and Ticket chat
  state examples.
- Browser-harness BDD for:
  - create Ticket;
  - assign to Elena or another available Citizen;
  - capture first reply;
  - send follow-up in the same Ticket;
  - capture second reply into the same ordered chat;
  - verify no duplicate comments.
- Preserve existing validation: ExUnit coverage gates, JS tests, Playwright or
  browser E2E smoke where still applicable, Gate A, Alfred validation,
  whitespace check, and privacy scan.

### 9. Implementation Slices

1. **CHG 13a.1: Tailwind UI foundation and kitchen sink (`BAB-2233`)**
   - Status: completed locally.
   - Install and validate the Phoenix Tailwind CSS asset pipeline.
   - Define Babs theme tokens and reusable UI component classes.
   - Replace the current inline kitchen-sink spike with a Tailwind-backed
     `/dev/kitchen-sink` light-theme component/state preview.
   - Add unit, build, LiveView, and browser-harness smoke coverage for the UI
     foundation.

2. **CHG 13a.2: Multi-turn Ticket model and chat UI**
   - Status: completed locally via `BAB-2234`.
   - Add turn events and parser compatibility.
   - Add prompt assembler.
   - Refine Ticket detail UI into a proper chat surface using the 13a.1 UI
     foundation.
   - Add unit, LiveView, and browser-harness BDD coverage for two-turn Tickets.
   - Gate with a manual or browser-harness two-turn smoke test using one
     available Citizen before direct CLI work starts.

3. **CHG 13a.3: Direct CLI provider sessions**
   - Status: next slice.
   - Add execution backend behavior and provider adapters.
   - Add supervised direct-execution runner with process cleanup and
     per-Citizen execution locking.
   - Add provider session SQLite table and tests.
   - Implement direct Claude/Codex/Copilot canary/fixture support.
   - Keep Hardline fallback.

4. **CHG 13a.4: Lazy tmux and dogfood polish**
   - Add lazy terminal-open path where provider resume supports it.
   - Add UI affordances for switching between direct and live terminal
     inspection.
   - Dogfood Clare/Dylan/Elena through at least two multi-turn Tickets.

## Out Of Scope

- Replacing the existing Hardline backend.
- Generic queue/batch-job scheduling outside Ticket turns.
- Storing Ticket source-of-truth data in SQLite.
- Replacing Ecto with `better-sqlite3`.
- Inspector automation from Phase 15 or Mayor automation from Phase 16.
- External chat adapters such as Discord, Telegram, Slack, or Matrix.
- Cross-machine writable Ticket federation.

## Acceptance Criteria

- A Ticket can hold at least two operator-to-Citizen turns in the same browser
  detail page.
- The second turn includes prior Ticket context and resumes the same provider
  conversation where the provider supports session ids.
- Captured Citizen replies are correlated to the correct `turn_id` and rendered
  in order without duplicates.
- The operator can see delivery/capture status for each turn.
- A direct CLI Citizen can complete a Ticket turn without a persistent tmux
  session.
- Direct CLI resume is observable in tests by asserting the stored
  `provider_session_id` is passed to the provider resume command where supported.
- Direct CLI turns cannot orphan unmanaged Babs-owned provider processes during
  timeout/cancel/owner-exit scenarios covered by tests.
- Two turns for the same Citizen cannot run concurrently against the same
  workspace or provider session.
- Direct provider stdout/stderr and subprocess env handling are redacted,
  bounded, and covered by tests before replies reach Ticket history or UI.
- The operator can open an interactive Hardline only when needed, without
  breaking the one-Citizen-one-Hardline invariant.
- Existing Hardline Citizens still pass assignment, comment, reply-capture,
  restart, and imported tmux attach validations.
- The PRP records that `better-sqlite3` is not adopted for the Elixir runtime in
  this phase.
- Unit, BDD, E2E, coverage, Alfred validation, Trinity review, and GitHub Codex
  review-loop requirements from `BAB-1503` remain mandatory.

## Resolved Design Points

1. Visible chat rows remain `comment` events. `turn_*` events carry delivery and
   correlation metadata. Ticket chat readers must join both event families.
2. Provider support is implemented incrementally. The first provider should be
   the one with the strongest locally verified session-id semantics, and the
   phase is not complete until Claude, Codex, and Copilot have direct support or
   explicit Hardline-only fallback tests.
3. Direct provider replies are captured by adapter return values, not by pane
   scraping, then appended as redacted `comment` events plus
   `turn_reply_captured` metadata through the Writer.
4. Delivery state is per recipient attempt: `{turn_id, citizen_slug,
   attempt_id}`.
5. Lazy terminal attach defaults to attach-after-completion while a direct turn
   is running.
6. Ticket chat should use a compact messaging-app style on the light-first Babs
   theme, not the previous dark operations-log style.
7. Phase 13a.1 adds a dev/test kitchen-sink route before the production Ticket
   chat polish lands.

## Open Questions

None before CHG 13a.1. CHG documents may still make implementation-level choices
inside the resolved light-theme messaging-app direction.

## Review Unit

- **Workflow:** COR-1602 Multi Model Parallel Review.
- **Decision mechanism:** COR-1613 Council Review.
- **Initial reviewers:** Trinity GLM and DeepSeek. Trinity wrapper attempts for
  Gemini timed out because the provider refused ignored prompt paths, so Gemini
  was consulted directly against normal `rules/` paths. Claude and Codex were
  also consulted directly because the current local Trinity wrapper does not
  expose them as providers.
- **Threshold:** no blocking PRP issues from GLM and DeepSeek after advisory
  fold-in; direct Gemini/Claude/Codex blocking findings must be folded in or
  explicitly deferred.
- **Artifact:** this PRP plus the `BAB-2300` roadmap diff.

## Review Results

- R1 Trinity `.trinity/reviews/20260507-102150-BAB-2232-Phase-13a-PRP-roadmap-database-driver-decision`:
  GLM PASS, DeepSeek PASS, Gemini timed out on ignored prompt path. Advisories
  folded in.
- R2 Trinity `tmp/trinity-reviews/20260507-102937-BAB-2232-Phase-13a-PRP-R2-after-advisory-fixes`:
  GLM PASS, DeepSeek PASS, Gemini timed out again. Advisories folded in.
- Direct Gemini review: FIX on orphan-process and per-Citizen concurrency risks.
  Findings folded in.
- Direct Claude review: FIX on direct reply capture, message ids, resume
  invalidation, stdout/env redaction, indexes, legacy tests, and lazy-tmux
  default behavior. Findings folded in.
- Direct Codex review: FIX on visible message schema, per-recipient status,
  ordering, cwd privacy, session uniqueness, environment safety,
  `better-sqlite3` future allowance, and estimate. Findings folded in.
- R3 Trinity `.trinity/reviews/20260507-104321-BAB-2232-Phase-13a-PRP-R3-after-Gemini-Claude-Codex-fixes`:
  GLM PASS and DeepSeek PASS with implementation-level advisories only.
  Low-risk clarifications were folded in.
- Operator UI review after the first kitchen-sink spike rejected the ad-hoc
  inline-CSS palette. Phase 13a.1 now starts with a Tailwind-backed design-system
  correction before production Ticket chat polish.
- R4 Trinity plan review for `BAB-2233`:
  `.trinity/reviews/20260507-120935-BAB-2233-Phase-13a.1-Tailwind-UI-correction-CHG-R2-after-scope-split-and-kitchen-sink-404-test`
  returned GLM PASS and DeepSeek PASS after folding the R1 scope-split and
  disabled-route-test blockers. Phase 13a.1 implementation is approved as the
  Tailwind UI foundation slice.
- `BAB-2234` implementation review R3:
  `.trinity/reviews/20260507-141938-BAB-2234-implementation-diff-R3-after-prompt-de-dup-cleanup`
  returned GLM PASS and DeepSeek PASS after folding earlier implementation
  advisories. Phase 13a.2 is completed locally; next slice is 13a.3 direct CLI
  provider sessions.

## External References Checked

- `WiseLibs/better-sqlite3` README, latest release and feature summary
  (checked 2026-05-07).
- Node.js `node:sqlite` documentation for `DatabaseSync` stability and sync API
  shape (checked 2026-05-07).
- Hex package pages for `ecto_sqlite3` and `exqlite` current package identity and
  release dates (checked 2026-05-07).
- `liliMozi/openhanako` README and plugin guide for agent memory/personality,
  multi-agent chat/delegation, desk/files, Hub background tasks, SessionFile
  sidecars, plugin pages/widgets, and Node/better-sqlite3 stack context (checked
  2026-05-07).
- Tailwind CSS official Phoenix installation guide, Tailwind UI Application UI,
  shadcn/ui components, Petal Components, Tremor, and daisyUI docs for the
  accepted Phase 13a UI correction route (checked 2026-05-07).

## References

- `BAB-1001` Architecture Overview
- `BAB-1002` Naming and Vocabulary
- `BAB-1004` UI Design Spec
- `BAB-1105` Persistence - ETS + SQLite + JSONL Only
- `BAB-1107` Babs Owns Tmux Session Lifecycle
- `BAB-1110` Two OTP Apps Plus Tmux Detach
- `BAB-1111` Ticket as Universal Coordination Primitive
- `BAB-1112` Multi AI CLI Citizen Configuration
- `BAB-1113` Imported Tmux Session Attach
- `BAB-1503` Phase Delivery Workflow
- `BAB-2224` Phase 12a PFC-Informed Hardline Relay Reliability
- `BAB-2225` Phase 13 Imported Tmux Session Attach
- `BAB-2228` Fix AI Transcript Reply Capture
- `BAB-2230` Elena Copilot Reply Capture BDD Coverage
- `BAB-2231` Fix Copilot Compact Paste System Injection

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-07 | Initial version | af CLI |
| 2026-05-07 | Draft Phase 13a scope for multi-turn Ticket sessions, direct CLI provider sessions, lazy tmux, tests, and database-driver decision | Codex |
| 2026-05-07 | Fold Trinity R1 GLM/DeepSeek advisories on event-reader strategy, provider session authority, fallback testing, prompt context size, provider rollout order, and two-turn CHG 13a.1 smoke gate | Codex |
| 2026-05-07 | Fold Trinity R2 GLM/DeepSeek advisories on turn event field shape, Writer authority, id generation, parent-turn semantics, direct-session discovery fallback, lazy-tmux concurrency, and lifecycle ADR references | Codex |
| 2026-05-07 | Fold Gemini direct-review findings on direct CLI orphan-process cleanup, per-Citizen execution serialization, and corresponding lifecycle/concurrency tests | Codex |
| 2026-05-07 | Fold Claude/Codex direct-review findings on visible message schema, per-recipient attempts, direct reply capture pipeline, resume failure, env/output redaction, session indexes, cwd privacy, resume canaries, and lazy-tmux default behavior | Codex |
| 2026-05-07 | Fold R3 GLM/DeepSeek implementation advisories on busy status, event-state table, async adapter semantics, current-turn `discover_session` behavior, lazy backend metadata, and reply-capture references | Codex |
| 2026-05-07 | Resolve UI density toward light-theme messaging-app chat and add Phase 13a.1 kitchen-sink page requirement | Codex |
| 2026-05-07 | Add OpenHanako takeaways as product-shape inspiration while keeping Babs on Elixir/Phoenix/Ecto | Codex |
| 2026-05-07 | Accept Tailwind-backed UI correction route after operator rejected the first inline-CSS kitchen-sink palette | Codex |
| 2026-05-07 | Mark Phase 13a PRP approved and record BAB-2233 Trinity R2 approval for the Tailwind UI foundation slice | Codex |
| 2026-05-07 | Mark CHG 13a.1 and 13a.2 completed locally and set CHG 13a.3 direct CLI provider sessions as the next slice | Codex |
