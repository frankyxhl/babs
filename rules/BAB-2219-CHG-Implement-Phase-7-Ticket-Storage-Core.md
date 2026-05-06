# CHG-2219: Implement Phase 7 Ticket Storage Core

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

Implement Phase 7 from `BAB-2217` and the PR A slice from `BAB-2218`:

- Add a configurable Ticket data root through `BABS_TICKETS_ROOT` /
  `:babs_citizens, :tickets_root`.
- Default the development Ticket root to gitignored `<BABS_ROOT>/var/tickets`.
- Add `Babs.Citizens.Tickets` runtime modules for strict Ticket parsing,
  rendering, ID allocation, history JSONL, read-only store operations,
  serialized writes, typed errors, and a public API boundary.
- Add a minimal command surface for create/list/show Ticket operations.
- Keep Ticket markdown plus history JSONL as the source of truth.
- Keep SQLite out of the Phase 7 Ticket data path.
- Keep runtime Ticket data out of git.

This CHG does not add `/tickets` browser UI, file watching, assignment,
terminal injection, full state-machine controls, approval/reject flows, or
cross-Citizen live notifications. Those remain Phase 8-12 work.

Authority references for this CHG are `BAB-2217`, `BAB-2218`, `BAB-1111`,
`BAB-1110`, `BAB-1002`, and `BAB-1503`.

## Why

Phase 6 gives the operator durable browser control over Citizens, but there is
still no durable shared work object. Phase 7 creates that source of truth before
any UI or assignment behavior is layered on top.

The important Phase 7 property is correctness under human-editable files and
concurrent Babs-owned writes. If the file format, history log, ID allocator, or
writer semantics are loose, later phases will build assignment and approval on
state that can drift or corrupt.

## Impact Analysis

- **Systems affected:** `:babs_citizens` runtime configuration, application
  supervision, new `Babs.Citizens.Tickets` modules, Mix command tasks or the
  smallest feasible `bb ticket` command path, shared `config/runtime.exs`,
  ExUnit coverage, Gate A, roadmap and tracker docs.
- **Data affected:** Runtime files under the configured Ticket root:
  `T-YYYY-MM-DD-NNN.md` plus `T-YYYY-MM-DD-NNN.history.jsonl`. The default
  development root stays under gitignored `var/tickets`.
- **Security/privacy:** User-facing and logged errors must redact host-specific
  paths, env maps, tokens, private network details, and raw low-level IO
  exceptions. Public PR text must not include private IPs, local absolute paths,
  or machine-specific secrets.
- **UX impact:** Phase 7 may expose only a CLI/Mix command surface. Browser
  behavior should not change in this slice.
- **Rollback plan:** Revert the Phase 7 implementation commit. Existing
  Citizen SQLite rows, TOML files, workspaces, transcripts, and browser routes
  remain compatible because Ticket runtime data is isolated under the
  configured Ticket root.

## Implementation Plan

1. **RED: Ticket root configuration**
   - Add tests for config precedence:
     - per-call keyword opts override runtime/application config.
     - `BABS_TICKETS_ROOT` is wired in `config/runtime.exs` so it overrides
       compile-time/default application config at boot.
     - explicit `:babs_citizens, :tickets_root` is honored when no per-call
       override is supplied.
     - default development root resolves under `<BABS_ROOT>/var/tickets`.
   - Keep test roots isolated under temporary directories.
   - Ensure the default `var/` path is already gitignored and no generated
     Ticket fixtures are committed.
   - Create the configured Ticket root on first write with `File.mkdir_p/1`.
   - Runtime code resolves per-call keyword override first, then
     `Application.get_env(:babs_citizens, :tickets_root)`, then the default
     under the configured Babs root. `config/runtime.exs` is responsible for
     translating `BABS_TICKETS_ROOT` into Application env at boot, matching the
     existing `workspace_root` pattern.
   - Treat nil, empty, and whitespace-only Ticket root values as unset.
2. **RED: Ticket markdown parser and serializer**
   - Add strict frontmatter parse tests for the `BAB-1111` schema:
     `id`, `type`, `state`, `assigner`, `assignees`, `assignee_role`,
     `inspector`, `priority`, `parent_ticket`, `created_at`, `updated_at`,
     and `metadata`.
   - Enforce file stem and frontmatter `id` match.
   - Enforce first Markdown H1 title and non-empty body.
   - Reject unknown top-level frontmatter keys.
   - Preserve extensibility only through `metadata`.
   - Enforce that `assignees: []` requires `state: open` unless the Ticket is
     `cancelled`.
   - Surface unknown assignees as warnings in Phase 7 rather than hard errors,
     because assignment validation begins in Phase 9.
   - Add `{:yaml_elixir, "~> 2.12"}` unless implementation proves a smaller
     already-installed parser is available. The package is a maintained
     Elixir-facing YAML parser, has no NIF boundary, and keeps Phase 7 away
     from ad hoc YAML parsing.
3. **RED/GREEN: Ticket struct and typed errors**
   - Add `Babs.Citizens.Tickets.Ticket` for normalized Ticket data.
   - Add stable typed errors matching `BAB-2217`, including:
     `:not_found`, `:invalid_id`, `:invalid_frontmatter`,
     `:unknown_citizen`, `:write_conflict`, and redacted IO errors.
   - Defer Phase 9+ errors such as `:invalid_transition` and
     `:citizen_not_running`; Phase 7 does not implement assignment, terminal
     injection, or the state machine.
   - Keep browser/CLI-ready error rendering separate from low-level errors.
4. **RED/GREEN: Ticket ID allocation**
   - Implement date-scoped IDs in the form `T-YYYY-MM-DD-NNN`.
   - Use the Babs node's server-local date for the `YYYY-MM-DD` component so
     file names match the operator's local browsing model. Tests should inject
     the date instead of depending on wall-clock time.
   - Scan the configured root for existing IDs and allocate the next ID for the
     current server-local date.
   - Prevent new-ticket TOCTOU races with an atomic exclusive file-claim loop
     before the per-ticket writer takes over.
   - Cover malformed IDs, collisions, and concurrent create attempts.
   - Do not require a database sequence for Phase 7.
5. **RED/GREEN: History JSONL**
   - Add append/read helpers for one JSON object per line.
   - Require `ts`, `event`, and `by` for every event.
   - Keep event rows compact and validate encoded events before append. Babs
     does not rely on OS-level concurrent append atomicity for Babs-owned
     writes; Citizens and commands route through the same per-ticket writer.
   - Ensure create writes exactly one `created` event.
   - If storage-only comments ship in Phase 7, ensure each comment writes
     exactly one `comment` event and emits a live-delivery-deferred advisory.
   - Reject malformed history rows with typed errors on read.
6. **RED/GREEN: Store read/list/show**
   - Add read-only operations that list valid Tickets and surface invalid files
     as typed warnings/errors without crashing callers.
   - Support list filters that are needed by the minimum command surface:
     state and assignee where practical.
   - Sort Tickets deterministically by `updated_at` descending, then Ticket ID
     descending, unless later review requires a different order.
7. **RED/GREEN: Per-ticket writer**
   - Add `WriterRegistry`, `WriterSupervisor`, and `Writer` under
     `Babs.Citizens.Tickets`.
   - Start writers lazily for Babs-owned mutations.
   - Serialize same-ticket mutations while allowing different Tickets to
     proceed independently.
   - Write markdown atomically using a temporary file plus rename.
   - Use a Babs-owned temp-file naming convention:
     `.<ticket_id>.<unique>.babs.md.tmp`. This is intentionally distinguishable
     from common editor temp files such as `.swp` and `~` suffixes.
   - Append history only after the markdown write needed for the same mutation
     is durable.
   - This intentionally chooses markdown-first, history-second ordering:
     markdown is the primary artifact, and a future explicit repair command can
     reconstruct or audit history from markdown state, while Phase 7 treats
     incomplete crash states as invalid rather than guessing.
   - This file-write ordering does not weaken `BAB-2218`'s "history first"
     communication rule. That rule means all communication is persisted to
     history before any terminal notification mirror; history-only events such
     as comments write history directly without requiring a markdown mutation.
   - Set `updated_at` on every Babs-owned mutation that changes Ticket
     frontmatter, body, or history.
   - Re-read before mutation and return `{:error, {:write_conflict, id}}` when
     the on-disk Ticket changed unexpectedly.
   - Define crash reconciliation for Phase 7:
     - markdown exists but history is missing: read as invalid/incomplete until
       a future explicit repair command exists.
     - history contains a `created` row but markdown is missing: read as invalid
       orphan history and do not recreate markdown implicitly.
   - Clean up stale writer temp files on writer start when they match Babs'
     temp-file naming convention.
   - Use temporary writer children so crashed lazy writers are not
     automatically resurrected without a new mutation.
8. **GREEN: Public API**
   - Add `Babs.Citizens.Tickets.Api` as the boundary for web, CLI, and tests.
   - Minimum API:
     - `create_ticket(attrs, opts \\ [])`
     - `list_tickets(opts \\ [])`
     - `show_ticket(id, opts \\ [])`
     - optional `comment_ticket(id, attrs, opts \\ [])` only if storage-only
       comment is small and explicitly documented.
   - If `comment_ticket/3` ships, `attrs` requires `:body` and accepts optional
     `:by`; missing `:by` defaults to `"user"` for operator-originated calls.
   - Return stable `{:ok, ...}` / `{:error, ...}` tuples.
9. **Command bridge**
   - Prefer ADR-complete `bb ticket new/list/show` if it fits this PR safely.
   - If Unix-domain-socket `bb` is too large for PR A, ship temporary Mix tasks
     such as `mix babs.ticket.new`, `mix babs.ticket.list`, and
     `mix babs.ticket.show`, document the deviation in this CHG and PR body,
     and keep the internal API compatible with the final `bb` command surface.
   - Commands must print useful output without leaking host-specific paths or
     secrets.
10. **Docs and validation**
    - Update roadmap/tracker docs with real implementation and validation
      results.
    - Record whether Phase 7 shipped ADR-complete `bb` or the temporary Mix
      bridge.
    - Do not add browser-harness BDD unless browser-visible behavior changes.

## Validation Plan

Required local validation for Phase 7:

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`
- `mise exec -- mix test --cover`
- coverage remains above gates:
  `:babs_citizens >= 80%` and `:babs >= 75%`
- `mise exec -- mix babs.gate_a`
- `af validate --root .`
- `git diff --check`
- privacy/runtime scan with `rg` for private IPs, host-specific paths,
  generated Ticket files, and obvious secrets

Test fixtures must use isolated temporary Ticket roots and must not write under
the repo's default `var/tickets`; `af validate --root .` should never need to
parse generated runtime Ticket files from normal test runs.

`BAB-2218` sets the Phase 7 coverage target at `:babs >= 75%`; the current
`apps/babs/mix.exs` threshold is lower and remains a minimum enforcement
setting until a separate coverage-gate CHG changes it. Phase 7 validation should
report actual coverage against the stricter contract target.

Browser validation is not required for Phase 7 unless this PR changes browser
JavaScript or browser-visible behavior. `npm run test:js`, `npm run test:bdd`,
and `npm run test:e2e` remain Phase 8+ gates or regression gates if the Phase 7
implementation unexpectedly touches browser code.

## Local Implementation Results

Implemented locally on branch `codex/m3-phase-7-ticket-core` on 2026-05-06:

- Added `BABS_TICKETS_ROOT` runtime wiring and
  `Babs.Citizens.Tickets.Config`.
- Added `yaml_elixir` for YAML frontmatter parsing.
- Added `Babs.Citizens.Tickets.Ticket`, `TicketId`, `TicketMarkdown`,
  `History`, `Store`, `Writer`, `WriterSupervisor`, `Api`, and redacted
  `Error` rendering.
- Added lazy per-root/per-ticket writer processes supervised under
  `:babs_citizens`. Registry keys include the configured Ticket root plus
  Ticket ID so tests and future isolated roots cannot cross-wire writers.
- Added atomic exclusive ID claim before create, markdown temp-file rename,
  history JSONL append, stale temp cleanup, write-conflict detection, and
  storage-only comments with `delivery: :deferred`.
- Added temporary Phase 7 Mix command bridge:
  - `mix babs.ticket.new`
  - `mix babs.ticket.list`
  - `mix babs.ticket.show`
  - `mix babs.ticket.comment`
- Deferred ADR-complete `bb ticket` over Unix-domain socket. The internal API
  and command shapes remain aligned with the planned `bb ticket` surface.
- Hardened `Babs.DevReloader` to restart `:babs_citizens` with
  `Application.ensure_all_started/1`, so reload tests restore dependent
  applications after a stop/start cycle.
- Addressed Trinity implementation review findings before PR by adding
  ref-tagged writer idle timeouts, pre-write Ticket validation, non-raising
  Ticket root creation in `TicketId.claim_next/2`, sequence exhaustion at 999,
  and empty-claim cleanup on failed create.
- Addressed GitHub Codex R1 by validating storage-only comment history events
  before rewriting Ticket markdown, preventing failed oversized comments from
  advancing `updated_at` without a matching history event.
- Addressed GitHub Codex R2 by rejecting `T-YYYY-MM-DD-000` in
  `TicketId.parse/1`; Ticket sequences are strictly `001` through `999`.

Local validation passed:

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test` — 157 `:babs_citizens` tests and 51 `:babs` tests
  passed.
- `mise exec -- mix test --cover` — `:babs_citizens` 82.56% and `:babs`
  81.49%.
- `mise exec -- mix babs.gate_a`
- `af validate --root .` — 115 documents checked, 0 issues.
- `git diff --check`
- Manual command smoke in an isolated temporary Ticket root created five
  Tickets through `mix babs.ticket.new`, listed them with `mix babs.ticket.list`,
  and showed one with `mix babs.ticket.show`.

Browser tests were not run for Phase 7 because this implementation does not
change browser JavaScript or browser-visible behavior.

## Acceptance Criteria

- `BABS_TICKETS_ROOT` and `:babs_citizens, :tickets_root` configure the Ticket
  root, with a gitignored development default under `var/tickets`.
- Creating five Tickets through the Phase 7 command/API path produces valid
  markdown and matching history JSONL files.
- Listing and showing Tickets works without Phoenix.
- Invalid frontmatter is rejected or surfaced with typed errors.
- Unknown assignees are warnings, not hard errors, until Phase 9.
- Concurrent create/comment attempts serialize and leave valid files.
- Babs-owned writes go through the per-ticket writer.
- Runtime Ticket files are not tracked by git and do not dirty the repo.
- Trinity fast-review GLM + DeepSeek passes with no blockers.
- GitHub Codex review loop passes within the five-round cap after the
  implementation PR is opened.

## Open Decisions for This CHG

- The preferred outcome is ADR-complete `bb ticket new/list/show`. The allowed
  fallback is a documented temporary `mix babs.ticket.*` bridge if the UDS
  listener/escript work would make PR A too large.
- Storage-only `comment` can be included only if it remains small and clearly
  prints that live delivery and notification mirrors are deferred to Phase 12.
- Phase 7 does not add Flora or run the full multi-CLI validation matrix because
  no terminal assignment/injection behavior is claimed in PR A.

## Review Results

- R1 `.trinity/reviews/20260506-105308-rules-BAB-2219-CHG-Implement-Phase-7-Ticket-Storage-Core.md`:
  GLM PASS and DeepSeek PASS with no blockers. Folded in non-blocking
  clarifications for Phase 7 error scope, server-local Ticket ID date, explicit
  markdown-first/history-second write ordering, authority references, TDD label
  consistency, new-ticket create-race handling, Ticket root creation/precedence,
  temp-file cleanup, and isolated test fixture roots.
- R2 `.trinity/reviews/20260506-105650-rules-BAB-2219-CHG-Implement-Phase-7-Ticket-Storage-Core.md`:
  GLM PASS and DeepSeek PASS with no blockers. Folded in advisories for
  `config/runtime.exs`, exact Ticket root precedence, `yaml_elixir` dependency
  choice, history append atomicity stance, Babs temp-file naming, optional
  comment attrs, and `BAB-1002` authority.
- R3 `.trinity/reviews/20260506-110113-rules-BAB-2219-CHG-Implement-Phase-7-Ticket-Storage-Core.md`:
  GLM PASS and DeepSeek PASS with no blockers. Folded in final clarifications
  for coverage target wording, exact config precedence, atomic file-claim
  creation, `updated_at` mutation, `updated_at` sort order,
  `assignees: []`/`state: open` invariant, stale temp-file cleanup, and
  compatibility between markdown-first crash ordering and history-first
  communication semantics. Marked CHG approved.
- Implementation R1 `.trinity/reviews/20260506-112237-.`: GLM PASS and
  DeepSeek PASS. Fixed actionable review findings for writer idle timer stale
  messages, API pre-write validation, Ticket ID sequence exhaustion,
  non-raising Ticket root creation, and empty placeholder cleanup after failed
  create.
- GitHub Codex R1 on PR #16 reviewed commit `270a5ddce4` and reported one P2
  finding: oversized comments could rewrite markdown before
  `History.append/3` rejected the event. Fixed by adding
  `History.validate_appendable/2` before markdown rewrite and a regression test.
- GitHub Codex R2 on PR #16 reviewed commit `4de2ec5b5f` and reported one P2
  finding: `T-YYYY-MM-DD-000` was accepted. Fixed by adding a lower-bound check
  in `TicketId.parse/1` and regression coverage.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-06 | Initial Phase 7 Ticket storage core CHG draft | Codex |
| 2026-05-06 | Address Trinity R1 non-blocking findings before implementation | Codex |
| 2026-05-06 | Address Trinity R2 advisories and choose `yaml_elixir` for YAML frontmatter | Codex |
| 2026-05-06 | Mark CHG approved after Trinity R3 PASS and final advisory fold-in | Codex |
| 2026-05-06 | Record local implementation validation and Trinity implementation-review fixes | Codex |
| 2026-05-06 | Record GitHub Codex R1 oversized-comment fix | Codex |
| 2026-05-06 | Record GitHub Codex R2 zero-sequence Ticket ID fix | Codex |
