# CHG-2218: M3 Phase 7-12 Execution Contract

**Applies to:** BAB project
**Last updated:** 2026-05-06
**Last reviewed:** 2026-05-06
**Status:** Approved

---

## What Is It?

This CHG is the execution contract for implementing the approved M3
Ticket/Billboard plan in `BAB-2217`.

It does not replace the PRP. `BAB-2217` defines the architecture and product
behavior for Phase 7-12. This contract defines how Codex should execute that
plan without repeatedly interrupting the operator for already-decided defaults.

The goal is continuous Phase 7-12 delivery:

- Phase 7: Ticket storage core, configured tickets root, writer, minimal CLI/API
- Phase 8: `/tickets` UI, detail view, filesystem watcher, browser-harness BDD
- Phase 9: assignment, stopped-Citizen auto-start, prompt injection
- Phase 10: Ticket state machine and legal transition controls
- Phase 11: approval/reject UI and feedback flow
- Phase 12: Ticket comments, Billboard history, notification mirrors

Implementation remains split into reviewable PR slices. Continuous delivery does
not mean one unsafe mega-PR.

## Why

The operator wants Phase 7-12 executed as one coherent push rather than
re-litigating direction after every phase. The codebase still needs the existing
Babs quality loop: TDD, BDD where browser behavior changes, coverage, Trinity
review, GitHub Codex review, and clean PRs.

This contract lets both constraints hold:

- Codex may proceed automatically through the M3 slices once each slice meets
  its completion conditions.
- Each slice remains small enough to validate, review, merge, and revert.
- Directional decisions are recorded now so implementation does not pause for
  predictable questions.
- If a real blocker appears, Codex stops and reports the conflict rather than
  silently changing the contract.

## Authority

This contract is subordinate to:

- `BAB-2217` approved PRP for Phase 7-12 M3 Ticket/Billboard System.
- `BAB-1111` Ticket ADR.
- `BAB-1110` two-OTP-app boundary.
- `BAB-1106` Hardline browser terminal byte-stream contract.
- `BAB-1503` phase delivery workflow.
- `BAB-1504` local GitHub Codex PR review loop guidance.
- `COR-1615` / `COR-1612` GitHub Codex PR review loop.

If this contract conflicts with a higher-authority ADR/PRP, stop and update the
documents through a reviewed CHG.

## Operator Defaults

The operator explicitly approved these defaults on 2026-05-06:

- Codex may automatically execute Phase 7-12 slices after this contract is
  approved.
- Codex may create branches, write CHGs/tests/code, run validation, run Trinity
  reviews, push, create PRs as `ryosaeba1985`, monitor GitHub Codex review, fix
  blockers, and continue to the next slice after merge.
- GitHub Codex review loop remains capped at five rounds per PR. If round 5
  still has required changes, stop and summarize.
- Long-running stability validations are deferred unless the operator says time
  is available.
- Runtime data, tmux sessions, tickets, transcripts, and app binary/runtime
  state are outside the repo by design.
- Ticket data root must be configurable and outside the application package
  model. Default for development is gitignored `<BABS_ROOT>/var/tickets`; real
  deployments may set `BABS_TICKETS_ROOT`.
- Test/dogfood Citizens:
  - Clare validates `claude`.
  - Dylan validates `codex`.
  - Flora validates `pi`.
  - Elena validates `gh copilot` / `copilot-cli`.
- If Flora does not exist yet, the first M3 slice that needs full multi-CLI
  validation must add/import `citizens/citizen-flora.toml` and SQLite state for
  `pi`.

## Non-Negotiable Behavior

- Tickets are runtime data and must not be committed by default.
- The configured tickets root is the Billboard.
- Ticket markdown plus history JSONL is the source of truth.
- SQLite may only be a derived index for tickets during M3.
- All Babs-owned Ticket writes go through the per-ticket writer.
- All communication is persisted to Ticket/Billboard history first.
- Terminal injection and notifications are mirrors only; they are not
  authoritative state.
- Assignment to a stopped Citizen auto-starts the Citizen before injection.
- Start/injection failure creates typed errors and persisted advisory history
  where appropriate.
- Every M3 browser action button must include a relevant semantic icon and
  follow the existing `/citizens` and Hardline manager console operations style.
  Icon-only dense controls require accessible labels or tooltips.
- Public PR text must not include private IPs, local absolute paths, tokens, or
  machine-specific secrets.
- GitHub-visible writes must use `gh` authenticated as `ryosaeba1985`.

## Execution Slices

### PR A: Phase 7 Ticket Storage Core

Scope:

- Add `BABS_TICKETS_ROOT` / `:babs_citizens, :tickets_root`.
- Default development tickets root to `<BABS_ROOT>/var/tickets`.
- Ensure `var/` and runtime ticket data remain gitignored.
- Add `Babs.Citizens.Tickets` parser, serializer, ID allocator, store, history,
  writer registry/supervisor, API, and typed errors.
- Add minimal CLI/API surface:
  - `bb ticket new`
  - `bb ticket list`
  - `bb ticket show`
- If the full UDS-backed `bb` is too large, a temporary `mix babs.ticket.*`
  bridge may ship only when the PR documents the deviation and keeps the
  internal API compatible with the final CLI.
- Storage-only comments may exist if they write exactly one `comment` event and
  print that live delivery is deferred.

Tests:

- Parser/render round trip.
- Strict frontmatter validation.
- Unknown assignee warning behavior before Phase 9.
- ID allocation/collision/concurrency.
- History append/read.
- Writer serialization and write conflict.
- Config precedence for tickets root.
- Redacted error messages.
- No runtime ticket files dirtied in repo.

Validation:

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`
- `mise exec -- mix test --cover`
- `mise exec -- mix babs.gate_a`
- `af validate --root .`
- `git diff --check`
- Trinity fast-review GLM + DeepSeek
- GitHub Codex review loop, max five rounds

PR A is storage/core only. `npm run test:js`, `npm run test:bdd`, and
`npm run test:e2e` are not required for PR A unless the implementation changes
browser JavaScript or browser-visible behavior.

Exit condition:

- PR merged.
- Main pulled locally.
- Ticket storage can create/list/show tickets in a gitignored runtime root.

### PR B: Phase 8 Ticket UI and Watcher

Scope:

- Add `/tickets` read-only list.
- Add `/tickets/<id>` detail.
- Link `/citizens` and `/tickets`.
- Render body/history/frontmatter summary.
- Add semantic icons to every action button, including create/open/filter or
  refresh controls when present.
- Add filesystem watcher change notifications.
- Surface invalid Ticket files without crashing UI.
- Preserve socket-token behavior for terminal routes.

Tests:

- LiveView list grouping and ordering.
- Detail render.
- Invalid Ticket render.
- Watcher refresh for manual file edits.
- Browser-harness BDD for list/detail/manual edit refresh.
- Existing Playwright E2E smoke remains passing.

Exit condition:

- Operator can browse runtime tickets from browser and see manual changes
  without page reload.

### PR C: Phase 9-10 Assignment and State Machine

Scope:

- Add UI/API/CLI assignment.
- Assignment and transition controls use semantic icons such as user-plus,
  route, check, undo, ban, and refresh.
- Assigning a stopped Citizen auto-starts it before injection.
- Add confirmed injection or attempted/failed history semantics.
- Implement legal transition matrix:
  - `open -> in_progress`
  - `open -> cancelled`
  - `in_progress -> open` via `unassigned`
  - `in_progress -> pending_approval`
  - `in_progress -> cancelled`
  - `pending_approval -> closed`
  - `pending_approval -> in_progress` via `rejected`
  - `pending_approval -> cancelled`
- Explicitly reject direct unassign from `pending_approval`.
- Show only legal controls in UI.

Tests:

- Full transition matrix.
- Assignment to running Citizen.
- Assignment auto-starts stopped Citizen.
- Start failure advisory.
- Injection attempted/confirmed/failure semantics.
- Browser-harness assignment flow.
- Browser-harness `open -> in_progress -> pending_approval` walk.
- Multi-CLI smoke matrix for Clare, Dylan, Flora, and Elena where credentials
  are available.

Exit condition:

- A Ticket can move from Billboard to a Citizen and through pending approval
  using tested API/UI paths.

### PR D1: Phase 11 Approval UI

Scope:

- Add approval/reject UI.
- Approval, rejection, cancellation, and feedback controls include semantic
  icons and accessible labels.
- Reject requires feedback and moves back to `in_progress`.
- Approve closes Ticket.
- Existing Phase 9-10 cancel behavior remains available; new cancel-time
  notification mirrors are deferred outside Phase 11 unless separately scoped.
- Rejection feedback writes Ticket history first, then mirrors to all current
  assignees; stopped assignees are auto-started when possible.
- Stopped/missing assignee delivery failures are advisory, not history
  corruption.

Tests:

- Approve/reject action tests.
- Reject requires feedback.
- Feedback history and notification mirror.
- Stopped assignee advisory.
- Browser-harness approve/reject flow.

Exit condition:

- Operator can request changes or approve a pending-approval Ticket from the
  browser.

### PR D2: Phase 12 Cross-Citizen Comments

Scope:

- Add `bb ticket comment`.
- Add Ticket detail comment form.
- Comment controls include semantic icons and accessible labels.
- Comment writes history first.
- Ticket/Billboard history is visible to all participants, including author.
- Terminal notifications mirror comments to assignees, including author when
  appropriate, without creating duplicate history rows.
- Stopped/missing assignee delivery failures are advisory, not history
  corruption.

Tests:

- Comment CLI/API/UI.
- Author sees own comment through history.
- Multi-assignee comment visibility for Clare and Dylan.
- Stopped assignee advisory.
- Browser-harness comment flow.

Exit condition:

- M3 flywheel is usable: operator creates or receives a Ticket, assigns it,
  observes Citizen work, requests changes or approves, and Citizens coordinate
  through Ticket history.

## Continuous Validation Matrix

Every implementation PR runs the applicable subset from `BAB-1503`. Minimum
normal validation unless a command does not exist in the repo:

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`
- `mise exec -- mix test --cover`
- `npm run test:js`
- `npm run test:bdd`
- `npm run test:e2e`
- `mise exec -- mix babs.gate_a`
- `af validate --root .`
- `git diff --check`
- privacy/runtime artifact scan with `rg`

Coverage expectations:

- `:babs_citizens >= 80%`
- `:babs >= 75%`
- Ticket parser/writer/state-machine modules should be close to exhaustive
  because they own shared data mutation.

Long validations:

- 24-hour or other long stability runs are deferred manual validations unless
  the operator explicitly makes time available.
- Deferred long validations must be recorded in the PR body and phase document.

## Multi-CLI Validation Matrix

Use these Citizens for M3 dogfood and browser/API smoke:

| Citizen | CLI | Purpose |
|---|---|---|
| Clare | `claude` | Claude Code hosted Citizen |
| Dylan | `codex` | Codex hosted Citizen |
| Flora | `pi` | Pi hosted Citizen |
| Elena | `gh copilot` / `copilot-cli` | GitHub Copilot CLI hosted Citizen |

Rules:

- Do not expose credentials in docs, logs, PR bodies, or review packets.
- If a CLI credential is missing, record the skipped live smoke and keep unit/BDD
  validation using deterministic shell/test doubles.
- If Flora is absent, add her with `cli = "pi"` and `cwd = "flora"` before
  claiming full multi-CLI M3 validation.

## Branch, PR, and Merge Policy

- Use focused branches such as:
  - `codex/m3-phase-7-ticket-core`
  - `codex/m3-phase-8-ticket-ui`
  - `codex/m3-phase-9-10-assignment-state`
  - `codex/m3-phase-11-approval-ui`
  - `codex/m3-phase-12-ticket-comments`
- Commit each slice after local validation and Trinity review pass.
- Push branches and open PRs with `gh` as `ryosaeba1985`.
- PRs should be non-draft unless validation is explicitly incomplete and the
  operator requests draft mode.
- GitHub Codex review loop:
  - Trigger review per `COR-1615`.
  - Compare reviewed commit with current head.
  - Do not treat `eyes` as approval.
  - Do not spam duplicate review requests.
  - Fix P1/P2 or clearly required findings.
  - Rerun relevant validation.
  - Push and repeat.
  - Stop after five rounds if required findings remain.
- After merge, pull `main`, verify status, update trackers if needed, and start
  the next slice.

## Stop Conditions

Codex should stop and ask/report if:

- A slice would violate `BAB-1111`, `BAB-1110`, `BAB-1106`, or this contract.
- Required credentials or CLI binaries are absent and no deterministic fallback
  can preserve the acceptance claim.
- A GitHub Codex review still has required findings after five rounds.
- A validation gate fails for reasons unrelated to the current slice and cannot
  be isolated safely.
- Implementing the slice would require committing runtime Ticket data,
  transcripts, credentials, private IPs, or host-specific paths.
- A destructive git operation would be required.

## Reusable SOP Template Suggestion

This contract pattern should become a reusable SOP for other multi-phase
projects. Suggested SOP title:

`COR-16xx-SOP-Multi-Phase-Execution-Contract.md`

Template:

```markdown
# SOP-16xx: Multi-Phase Execution Contract

## When to Use

- A user wants several phases delivered continuously.
- Directional decisions are known, but implementation still needs safe PR
  slices.
- The agent should proceed without repeated operator interruption unless a real
  blocker appears.

## Contract Sections

1. Authority documents
2. Operator defaults and permissions
3. Non-negotiable product behavior
4. Execution slices and exit conditions
5. Validation matrix
6. External review policy
7. Branch/PR/merge policy
8. Runtime-data/privacy rules
9. Stop conditions
10. Change history

## Rules

- Continuous execution does not mean one mega-PR.
- Every slice must have tests, validation, review, and rollback.
- Open questions become operator decisions before implementation.
- Review-loop caps must be explicit.
- Runtime data must be separated from source unless explicitly approved.
- The agent may continue automatically only while the contract remains true.
```

## Acceptance Criteria

- `BAB-2218` records operator defaults and execution permission for Phase 7-12.
- Contract references `BAB-2217` and does not redefine conflicting product
  architecture.
- Contract defines slice exit conditions, validation matrix, review caps,
  multi-CLI validation citizens, and stop conditions.
- Trinity fast-review GLM + DeepSeek passes with no blockers.
- Phase 7 implementation CHG may begin after this contract is approved.

## Review Results

- R1 `.trinity/reviews/20260506-102449-rules`: GLM found a blocker in the
  `BAB-1111` lifecycle diagram because `pending_approval -> cancelled` was not
  visually explicit. DeepSeek passed with advisories. Fixed by making every
  non-terminal cancellation path explicit in the ADR diagram and by clarifying
  `BAB-1504` / PR A browser-test omissions.
- R2 `.trinity/reviews/20260506-103406-rules`: GLM PASS and DeepSeek PASS with
  no blockers. Remaining findings were advisories and follow-up notes only.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-06 | Initial M3 Phase 7-12 execution contract draft | Codex |
| 2026-05-06 | Address Trinity R1 findings by linking `BAB-1504` and clarifying PR A browser-test omissions | Codex |
| 2026-05-06 | Add M3 UI action-button icon requirement matching existing operations-console style | Codex |
| 2026-05-06 | Mark contract approved after Trinity R2 GLM/DeepSeek PASS with no blockers | Codex |
| 2026-05-06 | Split original PR D into Phase 11 approval UI and Phase 12 cross-Citizen comments slices for reviewable continuous delivery | Codex |
