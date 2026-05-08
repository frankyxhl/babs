# PLN-2300: Build Roadmap (v0.1 → v1.0)

**Applies to:** BAB project
**Last updated:** 2026-05-07
**Last reviewed:** 2026-05-07
**Status:** Active
**Replaces:** Earlier 5-phase roadmap (Discord/Telegram + cross-machine A2A)
**Sources:** v0.1 design session 2026-05-03; Trinity Review `BAB-1006`

---

## What Is It?

The master roadmap of Babs from Phase 0 (PTY validation) through Phase 17 (V0-L complete: Mayor + federation). Replaces the earlier 5-phase plan in full.

Two stages:
- **Bootstrap** (Phase 0-1): manually built by human in terminal `claude code`. ~2-5 weeks.
- **Flywheel** (Phase 2-17): every phase is built BY a Citizen AI INSIDE the running Babs (the user is in browser only). ~24-38 weeks (per Trinity 2× multiplier).

Phase 0 has its own PRP (`BAB-2200`). Optional Phase 0a has its own PRP (`BAB-2202`). Optional Phase 0b has its own PRP (`BAB-2203`). Optional Phase 0c has its own PRP (`BAB-2205`). Phase 1 has its own PRP (`BAB-2201`). Phases 2-17 are documented in this roadmap as concise sections; each will become a Ticket once the ticket system is online (Phase 7+) and that Ticket becomes the de facto PRP for that phase's work. Phase 13a has its own PRP (`BAB-2232`) because it changes the Ticket conversation and Citizen execution model before role automation begins. Phase 13f has its own PRP (`BAB-2241`) for the provider runtime contract, Phase 14 has its own PRP (`BAB-2242`) for multi-role Citizen routing, Phase 15 has its own PRP (`BAB-2243`) for Inspector Council auto-approval, Phase 16 has its own PRP (`BAB-2244`) for Mayor rule-guided proposals, and Phase 17 has its own PRP (`BAB-2245`) for mobile and federated control.

---

## Milestone Map

| Milestone | Phases | Definition |
|-----------|--------|------------|
| **M0** | 0, optional 0a/0b/0c | PTY substrate validated; optional browser manager console, full-window terminal mode, and browser test harness available for easier hardline operation |
| **M1** | 1 | **Flywheel ignited** — single Citizen running in browser, can edit Babs and survive reload |
| **M2** | 2-6 | **V0-S complete** — multi-citizen browser console with persistence; manual coordination |
| **M2.5** | 6.5 | Manual ticket dogfood validation (waived as gate; retained as reference) |
| **M3** | 7-12a | **V0-M complete** — filesystem-first ticket-driven multi-agent system with reliable hardline delivery and AI CLI reply capture |
| **M4** | 13, 13a, 14-17 | **V0-L complete** — imported tmux attach; multi-turn Ticket sessions; Mayor + Inspector autonomy; mobile + federated control |

---

## Stage 1: Bootstrap (Manual Build)

### Phase 0 — Hardline PTY Spike

**Doc**: `BAB-2200` (full PRP, drafted)
**Output**: `spikes/hardline/` sub-mix-project; CHG entries on `BAB-1103`, `BAB-1106`, and `BAB-1110`
**Acceptance**: 24-48h soak + chaos kill + 30-min Channel render no dropped bytes; **detach + reattach scenario** validates that erlexec ports can attach to pre-existing tmux sessions without byte loss (per `BAB-1110` and Trinity findings)
**Estimate**: 3-5 days
**Built by**: human

### Phase 0a — Hardline Manager Console Spike

**Doc**: `BAB-2202` (implemented)
**Output**: `spikes/hardline/` web spike upgraded from one-pane validation page to one browser console that can create, list, switch between, and explicitly stop multiple Babs-managed tmux-backed hardlines using one web port.
**Acceptance**: Passed on 2026-05-04. Browser at `http://100.x.y.z:4010/` can create two `babs-hardline-*` sessions, switch between them without creating new tmux sessions, refresh/restart without changing session ID / pane PID for existing sessions, stop one session without touching unmanaged tmux sessions, and reattach existing managed sessions after web server restart.
**Estimate**: 1-2 days
**Built by**: human
**Gate status**: Optional but recommended usability spike. It does **not** replace Phase 0's official 24h+ validation and does **not** by itself authorize Phase 1 SEED.

### Phase 0b — Hardline Full-Window Mode Spike

**Doc**: `BAB-2203` (implemented), `BAB-2204` CHG (implemented)
**Output**: `spikes/hardline/` manager UI gains `Open Full` controls and `/?session=<slug>&full=1`, a separate browser-window mode where one managed hardline fills the viewport.
**Acceptance**: Passed on 2026-05-04. Full-window mode reuses an existing `pane:<slug>` session, does not create or kill tmux sessions, hides manager chrome, preserves resize through `:exec.winsz/3`, and shows visible errors for missing sessions.
**Estimate**: <1 day
**Built by**: human
**Gate status**: Optional browser usability spike. It does **not** replace Phase 0's official 24h+ validation and does **not** by itself authorize Phase 1 SEED.

### Phase 0c — Hardline Browser Test Harness

**Doc**: `BAB-2205` (implemented), `BAB-2206` CHG (completed)
**Output**: `spikes/hardline/` browser manager JavaScript is refactored out of inline HTML into testable static modules; JS/DOM tests and Playwright BDD-style E2E tests cover create/select/type/full/refresh/stop and missing-session workflows.
**Acceptance**: Passed on 2026-05-04. `index.html` loads testable static modules under `priv/static/js/`; `npm run test:js` passed with 9 tests; `npm run test:e2e` passed with 10 Playwright DOM/E2E tests; `mise exec -- mix test` passed with 59 tests, 0 failures. E2E uses isolated `babs-e2e-*` tmux prefixes and cleans up temporary sessions.
**Estimate**: 1-2 days
**Built by**: human
**Gate status**: Optional test-hardening/refactor phase. It does **not** replace Phase 0's official 24h+ validation and does **not** by itself authorize Phase 1 SEED.

### Phase 1 — V0-S0 SEED (Flywheel Ignition)

**Doc**: `BAB-2201` (full PRP, drafted)
**Output**: Mix umbrella with `:babs` and `:babs_citizens` apps; **two AI seed Citizens** (`clare` running `claude`, `dylan` running `codex` — validates multi-CLI works at SEED time, not deferred) plus deterministic `sentinel` (`/bin/zsh`) for Gate A; minimal LiveView terminal at `/citizens/<slug>`; Channel re-registration; tmux detach + reattach; multi-CLI configs at `citizens/citizen-<slug>.toml`; `Babs.DevReloader` in `:babs` for `:babs_citizens` reload (per `BAB-1110`); restricted keyboard set; PubSub chunk payloads ≤4KB (per `BAB-1106`)
**Acceptance**: **Flywheel Test (Gate A scripted + Gate B dogfood)** — Gate A is `mix babs.gate_a`, a machine-verifiable sentinel reload test (sentinel survives `:babs_citizens` reload with tmux session and pane PID intact); Gate B is the human dogfood test (clare implements Phase 2 entirely from browser, closes all terminals first). Both gates must pass.
**Estimate**: 14-21 days (Trinity 2× multiplier from naive 7-10)
**Built by**: human

🔥 **FLYWHEEL IGNITES at end of Phase 1** 🔥

### Phase 1a — Flywheel Hardening

**Doc**: `BAB-2207` CHG
**Output**: Explicit coverage gates for `:babs_citizens` and `:babs`; browser terminal JavaScript extracted from `TerminalLive` into static modules with Node unit tests; browser-harness BDD scenarios cover connect/type/reload/resize/missing-citizen workflows; `/citizens/<slug>` terminal UX aligns with useful Phase 0b full-window behavior; `BABS_HTTP_IP` restores local-only dev default with explicit Tailscale opt-in.
**Acceptance**: `mix test --cover` passes at `:babs_citizens` 80% and `:babs` 70%; `npm run test:js`, `npm run test:bdd`, preserved `npm run test:e2e`, `mix babs.gate_a`, and Alfred validation pass; billboard/ticket automation remains deferred.
**Estimate**: 1-2 days
**Built by**: human (last manual hardening phase before continuing Citizen-built product phases)

---

## Stage 2: Flywheel (Citizens Build Babs)

> From here, every phase is a task given to a Citizen via BabsWeb browser. The user is PM + reviewer. Estimates assume single-Citizen sequential work; multi-Citizen parallelism (from Phase 5) reduces wall-clock time.

### Phase 2 — Transcript JSONL Persistence

**Doc**: `BAB-2208` PRP
**Scope**: Every byte that flows through `Hardline.Pane` is appended to `<cwd>/transcript.jsonl`, for example `workspaces/clare/transcript.jsonl`. On browser reload, last N lines replayed to xterm.js for context.
**Acceptance**: Close browser tab, re-open: see most recent 200 lines of transcript; tab restart is byte-loss-free
**Note**: This phase is the first chicken-and-egg test for the flywheel — clare modifies the file (`Hardline.Pane`) that captures her own bytes. Per `BAB-1110`, tmux survives the reload; new Pane reattaches.
**Current status**: Implemented in PR #8. Babs writes `input` and `output` byte records to `<cwd>/transcript.jsonl`; browser reconnect replays bounded, slug-filtered transcript output before falling back to `tmux capture-pane`.
**Estimate**: 3-5 days

### Phase 2a — Configurable Workspace Root

**Doc**: `BAB-2209` PRP
**Scope**: Separate Babs application root from Citizen workspace storage root. Add `BABS_WORKSPACE_ROOT` / `:babs_citizens, :workspace_root`; resolve relative citizen `cwd` values under that workspace root while preserving absolute `cwd` overrides.
**Acceptance**: Default dev behavior still resolves seeds to `<BABS_ROOT>/workspaces/<slug>`; setting `BABS_WORKSPACE_ROOT=<workspace-root>` moves seed workspaces and transcripts outside the repo checkout; Gate A and browser-harness BDD still pass.
**Current status**: Implemented in PR #10. Seed TOML `cwd` values are now `<slug>` and resolve under configurable `workspace_root`; custom workspace-root BDD passed.
**Estimate**: 1-2 days

### Phase 3 — SQLite Citizens Table + Auto-Respawn

**Doc**: `BAB-2210` PRP
**Scope**: `priv/repo/migrations/` + `Babs.Citizens.Repo`; `citizens` table records durable Citizen identity/config/status, including `id`, `slug`, `display_name`, `description`, resolved absolute `cwd`, `cli`, `cli_args`, `env`, string `status` (`running`/`stopped`/`failed`), `metadata`, `role`, `is_mayor`, `last_error`, and Ecto timestamps. `BAB-2210` is authoritative for the exact schema and import semantics. On Babs boot, import seed TOML into SQLite, then scan all SQLite rows and reattach/respawn as appropriate.
**Reserved fields** for V0-L: `role`, `is_mayor`, `metadata` declared but not written by v0.1 logic.
**Acceptance**: Restart Babs node; clare auto-respawns from SQLite; cwd preserved
**Current status**: Implemented and merged in PR #11. Local validation passed: Ecto migrate/rollback/migrate, ExUnit/coverage (`:babs_citizens` 84.26%, `:babs` 78.00%), browser-harness BDD with SQLite registry scenario, Playwright smoke, Gate A, and Alfred validation.
**Estimate**: 4-6 days

### Phase 4 — NewCitizenLive Spawn UI

**Doc**: `BAB-2212` PRP; `BAB-2213` CHG
**Scope**: `/citizens/new` form (slug + display name + CLI preset: shell/claude/codex/droid/pi/copilot-cli + cwd field). Submit → write `citizens/citizen-<slug>.toml` + SQLite row + start citizen + redirect to `/citizens/<slug>`. `BAB-2212` owns the implementation plan. Arbitrary env editing is deferred until a secret-storage/redaction design exists.
**Acceptance**: Spawn a new non-seed citizen via UI; it reaches interactive prompt; SQLite row + citizen TOML exist; transcript starts persisting
**Current status**: Implemented and merged in PR #12. Local validation passed, including ExUnit/coverage (`:babs_citizens` 83.24%, `:babs` 77.24%), browser-harness BDD, Playwright smoke, Gate A, Alfred validation, and whitespace check. Trinity fast-review passed on scoped web, citizens-core, and BDD slices after review findings were fixed. GitHub Codex PR review findings were fixed and validation was rerun, including `/citizens/new` route shadowing, cwd symlink-swap revalidation, workspace-root `/` handling, lifecycle exit failure persistence, Gate A detach hang cleanup, and socket-token preservation on create redirect. Per operator review-loop cap, no additional Codex review loop was started after the final targeted socket-token fix.
**Estimate**: 4-6 days

### Phase 5 — Multi-Citizen Index + Tab Navigation

**Doc**: `BAB-2214` PRP; `BAB-2215` CHG
**Scope**: `/citizens` index page (list all citizens with status badges); tab navigation between active citizens; ≥3 concurrent hardlines without PTY fd leak (verified via `lsof`).
**Acceptance**: Spawn or seed at least three Citizens simultaneously; each is reachable through `/citizens` index and terminal tabs; fast fd smoke shows no descriptor leak in short validation. The 30 minute concurrent fd stability run is deferred to Phase 6 or the M2 gate, after stop/start/restart lifecycle controls exist.
**Current status**: Implemented locally on branch `codex/phase-5-prep`; PR review loop is active. `/` redirects to `/citizens`; default terminal pages use compact tab chrome while `?full=1` preserves the pure full-window terminal. Local validation passed on 2026-05-06: ExUnit/coverage (`:babs_citizens` 83.59%, `:babs` 84.10%), browser-harness BDD including the Phase 5 multi-Citizen index/tab/fd scenario, Playwright smoke, Gate A, Alfred validation, and whitespace check. GitHub Codex PR review R1/R2/R3 findings were fixed. The 30 minute fd stability run remains deferred to Phase 6/M2.
**Estimate**: 3-5 days

### Phase 6 — Stop / Start / Restart UI

**Doc**: `BAB-2216` CHG
**Scope**: Browser lifecycle controls on `/citizens` and default terminal pages: stop (`tmux kill-session` + SQLite `stopped` + preserve configured workspace), start (reuse SQLite config/workspace, fresh tmux + erlexec, status `running`), restart (atomic stop + start). Per `BAB-1107` semantics.
**Acceptance**: Stop clare from the browser, start/restart clare from the browser, terminal reconnects, SQLite status is correct, transcript path and workspace files are preserved, stopped Citizens do not auto-start on Babs restart, and running Citizens still auto-respawn/reattach.
**Current status**: Implemented and merged in PR #14. `BAB-2216` CHG was approved on 2026-05-06 after Trinity fast-review with GLM 9.05/10 and DeepSeek 9.0/10. Local validation passed on 2026-05-06: ExUnit/coverage (`:babs_citizens` 83.88%, `:babs` 82.17%), JS tests, browser-harness BDD with the Phase 6 lifecycle scenarios, Playwright smoke, Gate A, Alfred validation, and whitespace check. Trinity implementation review passed on scoped `apps/` review with GLM PASS and DeepSeek PASS; DeepSeek's conditional missing Stop-click test was fixed. GitHub Codex R1 P2 sibling-control race was fixed and R2 reported no major issues.
**Estimate**: 2-4 days

### 🎯 M2 = V0-S complete (~3-5 weeks flywheel time)

### Phase 6.5 — Manual Ticket Dogfood (Trinity-mandated)

**Scope**: Operator manually creates 1-2 ticket markdown files at `<tickets_root>/T-2026-XX-XX-001.md`; manually edits frontmatter to assign to clare; manually injects ticket body as clare's prompt; clare completes work; operator manually flips state to `closed`. **No automation.** Validates that the schema design (per `BAB-1111`) actually works end-to-end before infrastructure is built.
**Why**: Trinity 3/3 reviewers flagged that Phase 7-12 is high-cost ticket infrastructure built without proving the workflow first. This 1-2 day phase validates the workflow.
**Acceptance**: 2 tickets driven through full lifecycle; observed friction informs Phase 7-12 designs
**Current status**: Waived as a gate by operator decision on 2026-05-06. Keep the dogfood procedure as a reference, but proceed directly into continuous Phase 7-12 delivery under `BAB-2217`.
**Estimate**: 1-2 days

### Phase 7 — Ticket File System Skeleton

**Planning doc**: `BAB-2217` PRP covers the complete Phase 7-12 M3 design and execution slices.
**Execution contract**: `BAB-2218` records approved operator defaults for continuous Phase 7-12 delivery, review-loop caps, runtime data roots, multi-CLI validation citizens, and stop conditions.
**Implementation CHG**: `BAB-2219` is approved and defines the Phase 7 Ticket storage core TDD plan, command-surface bridge decision, validation scope, and review requirements.
**Current status**: Merged in PR #16. The slice uses a documented temporary `mix babs.ticket.*` bridge rather than ADR-complete `bb ticket` over UDS.
**Scope**: configured tickets root, defaulting to gitignored `<BABS_ROOT>/var/tickets`; schema validation (per `BAB-1111` frontmatter); `bb ticket new` minimum CLI target with any temporary `mix babs.ticket.*` bridge disclosed in the Phase 7 PR; per-ticket single-writer GenServer (concurrent-write safety); `T-...history.jsonl` append-only log.
**Acceptance**: Create 5 tickets via `bb ticket new` or an explicitly disclosed temporary `mix babs.ticket.*` bridge; `git status` clean except intended source changes; concurrent writes from 2 processes do not corrupt files (test in code)
**Estimate**: 4-6 days

### Phase 8 — Ticket Index UI + Render

**Implementation CHG**: `BAB-2220` defines the Phase 8 Ticket UI, detail render, watcher, icon, BDD, and validation plan.
**Current status**: Merged in PR #17.
**Scope**: `/tickets` list page (grouped by state); `/tickets/<id>` view (frontmatter table + markdown body + history timeline); filesystem watcher (FSEvents on macOS) drives live UI updates.
**Acceptance**: Browse all tickets; click one, see full content; manually edit ticket file in editor → UI updates within 1s
**Estimate**: 5-7 days

### Phase 9 — Ticket → Citizen Assignment

**Implementation CHG**: `BAB-2221` is approved and owns PR C for Phase 9 assignment plus Phase 10 state-machine work.
**Current status**: Merged in PR #18.
**Scope**: UI button "Assign to clare" → ticket `assignees` field updated → ticket body **injected as clare's initial prompt** via `Hardline.Pane.inject/2`; state transitions to `in_progress`; history event written.
**Acceptance**: Create T-001 = "Add health check endpoint"; assign to clare; clare's terminal receives the body as input and starts working
**Estimate**: 4-6 days

### Phase 10 — Ticket State Machine

**Implementation CHG**: `BAB-2221` owns the Phase 10 implementation together with Phase 9 as PR C.
**Current status**: Merged in PR #18.
**Scope**: Open / In Progress / Pending Approval / Closed / Cancelled plus Rejected and Unassigned transition events. Each transition writes to `.history.jsonl`. UI shows state badge. Illegal transitions are rejected with error message.
**Acceptance**: All paths walkable: Open → In Progress → Pending Approval → Closed; Reject from Pending Approval returns to In Progress with feedback comment in history; Cancel terminates from any non-closed state
**Estimate**: 3-5 days

### Phase 11 — Approval UI (Inspector = User in V0-M)

**Implementation CHG**: `BAB-2222` defines the Phase 11 approval/reject UI,
feedback injection, temporary Mix bridge commands, BDD, validation, and review
plan.
**Current status**: Merged in PR #19.
**Scope**: Pending Approval tickets show "Approve" / "Reject" buttons. Reject requires feedback using an inline feedback form in the first implementation; modal polish is deferred. Approve transitions to Closed; Reject transitions back to In Progress with feedback comment injected into assignee's hardline.
**Acceptance**: clare submits T-001 to Pending Approval; user rejects with feedback "missing docs"; clare receives feedback in terminal and continues; clare resubmits; user approves; ticket Closed
**Estimate**: 2-4 days

### Phase 12 — Cross-Citizen Ticket Comments

**Implementation CHG**: `BAB-2223` defines the Phase 12 `bb ticket comment`,
Ticket detail comment form, notification mirrors, BDD, validation, and review
plan.
**Current status**: Merged in PR #20.
**Scope**: `bb ticket comment <id> "..."` shell command (used by Citizens). Comment appended to `.history.jsonl`. Ticket/Billboard history is the authoritative communication surface for all participants, including the author; terminal notifications may mirror history but are not authoritative.
**Acceptance**: T-001 assigned to clare + dylan; clare `bb ticket comment T-001 "Backend done"`; clare and dylan both see the persisted comment in Ticket/Billboard history within 1s
**Estimate**: 3-5 days

### Phase 12a — PFC-Informed Hardline Relay Reliability

**Planning doc**: `BAB-2224` PRP
**Implementation CHG**: `BAB-2226`
**Current status**: Implemented locally with final validation passing. ExUnit
225 `:babs_citizens` tests and 72 `:babs` tests pass; clean coverage is
`:babs_citizens` 81.35% and `:babs` 87.34%; JS tests, browser-harness BDD,
Playwright E2E, Gate A, Alfred validation, format, compile, and whitespace
checks pass.
**Scope**: Borrow the reliable mechanics from `prefrontal-cortex` without
copying its Discord relay architecture. System-delivered Ticket prompts use
adaptive paste/submit confirmation for AI CLIs instead of raw bytes plus a
guessed Enter. Claude/Codex replies are read from their upstream AI CLI JSONL
transcripts when available, matched to the Ticket turn, and persisted back to
Ticket history as Citizen comments. Pane capture remains diagnostic/fallback;
Ticket/Billboard history remains authoritative.
**Acceptance**: Assigning a Ticket to Clare/Dylan submits without a manual
Enter; a matched AI CLI reply is captured into `.history.jsonl` as a Citizen
comment; `/tickets/<id>` chat updates through the watcher path; stale or
unmatched JSONL never creates a comment.
**Estimate**: 4-7 days

### 🎯 M3 = V0-M complete (~7-11 weeks flywheel time)

### Phase 13 — Imported Tmux Session Attach

**Planning doc**: `BAB-2225` PRP; `BAB-1113` ADR
**Implementation CHG**: `BAB-2227`
**Current status**: Implemented locally with final validation passing alongside
Phase 12a. Browser-harness BDD and Playwright E2E both cover imported external
tmux attach, terminal input, Detach, and proof that the external tmux session
stays alive.
**Scope**: Browser-driven import/attach workflow for tmux panes that already
exist outside Babs. Imported sessions default to external ownership: Babs can
stream, inject, persist transcript, detach, and reattach, but Stop/Detach does
not kill the external tmux session. UI shows an explicit `Imported ·
External-owned` style badge wherever lifecycle controls are available.
**Acceptance**: Create a tmux session outside Babs, attach it to an existing
stopped/detached Citizen from the browser, use the normal terminal and Ticket
injection paths, detach without killing the external tmux session, and reattach
after Babs restart when the tmux target still exists.
**Estimate**: 4-7 days

### Phase 13a — Multi-Turn Ticket Sessions + Direct CLI Backend

**Planning doc**: `BAB-2232` PRP
**Current status**: Implemented and merged through the 13a implementation
slices. CHG 13a.1 (`BAB-2233`) completed the Tailwind UI foundation and
kitchen-sink correction. CHG 13a.2 (`BAB-2234`) completed the multi-turn Ticket
model, prompt assembler, turn/attempt events, and light-theme Ticket detail
chat. CHG 13a.3 (`BAB-2235`) completed direct CLI provider sessions. CHG 13a.4
(`BAB-2236`) completed direct backend UI controls. Follow-up CHGs `BAB-2237`
through `BAB-2240` completed compact resumable direct prompts, stale Citizen UI
guards, and the first GitHub Actions CI gate.
**Scope**: Make Ticket detail pages true multi-turn conversation surfaces and
add a direct CLI execution backend for Ticket turns. Phase 13a.1 also introduces
a light-theme `/dev/kitchen-sink` page so Ticket chat and shared UI components
can be reviewed before production polish lands. After operator review rejected
the first ad-hoc palette, Phase 13a.1 must install the Phoenix Tailwind CSS
pipeline, define Babs theme tokens, and rebuild the kitchen sink against shared
component styling before polishing the production Ticket detail UI. Ticket
history remains the
authoritative communication record. Existing tmux Hardline execution remains
the default live/debug backend; direct CLI is an additive backend for providers
with non-interactive prompt and resume support. A conservative lazy-tmux path may
open a live terminal only when the operator needs interactive inspection. Phase
13a explicitly does not replace Ecto/SQLite with `better-sqlite3`; Babs keeps
`ecto_sqlite3` / `exqlite` for runtime persistence.
**Acceptance**: A Ticket supports at least two operator-to-Citizen turns in the
same chat UI; the second turn resumes the same provider session where supported;
captured replies are correlated to the correct turn without duplicates; direct
CLI can complete a Ticket turn without a persistent tmux pane; the operator can
still open a Hardline when needed; direct CLI process lifecycle and per-Citizen
execution serialization are covered by tests; existing Hardline assignment,
reply capture, restart, and imported tmux validations still pass.
**Estimate**: 10-16 days

### Phase 13f — Provider Runtime Contract

**Planning doc**: `BAB-2241` PRP
**Current status**: Approved PRP after Trinity fast-review with GLM and
DeepSeek PASS. Phase 13f.1 implementation CHG is `BAB-2246`; the public
provider inventory reference is `BAB-2247`; Phase 13f.2 implementation CHG is
`BAB-2248`; Phase 13f.3 implementation CHG is `BAB-2249`; Phase 13f.4
implementation CHG is `BAB-2250`.
**Scope**: Formalize the provider runtime contract before Phase 14-17 automation
depends on provider-specific launch, resume, parsing, and capability behavior.
The OpenClaw wrapping research is used as architecture inspiration only; Babs
keeps the Elixir/Phoenix/Ecto runtime and extracts a Babs-native contract for
command building, environment policy, prompt/input mode, session id discovery,
reply parsing, capability flags, timeout/cancellation behavior, redaction, and
interactive Hardline attachment.
**Acceptance**: Each supported provider/backend has an explicit capability map;
direct CLI results can be represented with one normalized result shape; Hardline
and imported Hardline expose capabilities without changing ownership semantics;
at least one direct CLI Ticket turn and one Hardline Ticket turn remain covered
after migration.
**Estimate**: 4-8 days

### Phase 14 — Citizen Roles

**Planning doc**: `BAB-2242` PRP
**Current status**: Approved PRP after Trinity fast-review with GLM and
DeepSeek PASS. Phase 14.1 implementation CHG is `BAB-2251`; Phase 14.2
implementation CHG is `BAB-2252`; Phase 14.3 implementation CHG is `BAB-2253`;
Phase 14.4 implementation CHG is `BAB-2254`.
**Scope**: Replace the earlier single-role plan with canonical multi-role
Citizen routing. Add normalized `roles` while preserving legacy `role`
compatibility, expose role badges and multi-role controls in the UI, and route
Tickets with existing `assignee_role` to any eligible Citizen whose role list
matches.
**Acceptance**: Create a Citizen with roles including `developer` and
`inspector`; create a Ticket with `assignee_role: developer`; Babs auto-routes
to that Citizen even when `developer` is not the first role; legacy single-role
Citizens still import and route correctly.
**Estimate**: 5-8 days

### Phase 15 — Inspector Council (Auto-Approval)

**Planning doc**: `BAB-2243` PRP
**Current status**: Approved PRP after Trinity fast-review with GLM and
DeepSeek PASS. Phase 15.1 execution CHG `BAB-2255` drafts the inspection
policy and event-foundation slice.
**Scope**: Replace the earlier single-inspector plan with Ticket-level
inspection policy and an Inspector Council. The human operator remains the
default inspector; Tickets can explicitly opt into automatic inspection by one
or more eligible Citizens selected by slug and/or Phase 14 roles. Inspector
decisions are persisted to Ticket history, parsed as approve/reject/needs
changes, and reduced by an initial conservative `all_pass` quorum.
**Acceptance**: A Ticket in `pending_approval` can be auto-approved by a
role-selected inspector Citizen; a rejected/needs-changes decision returns the
Ticket to `in_progress` with feedback; a two-Citizen council can approve only
when both inspectors approve; human override remains available.
**Estimate**: 10-14 days (LLM protocol and quorum design)

### Phase 16 — Mayor Rule-Guided Proposals (research-grade)

**Planning doc**: `BAB-2244` PRP
**Current status**: Approved PRP after Trinity fast-review with GLM and
DeepSeek PASS.
**Scope**: Add a Mayor Citizen that creates human-reviewed proposal artifacts
for mission Tickets on the Billboard. Root Tickets opt into proposal mode
through metadata, including opaque Alfred/Babs rule references. Babs does not
parse Alfred SOPs; it passes `rules_refs` to the Mayor, persists a structured
proposal, renders an editable child-ticket preview and graph/tree, and only
writes child Tickets after human approval.
**Acceptance**: User creates a mission Ticket with Mayor proposal metadata;
Mayor returns a structured proposal with child Tickets, roles, inspection
policy, risks, and questions; user removes or edits one child, approves the
proposal, and Babs writes the remaining child Tickets under the configured
tickets root with role routing metadata preserved.
**Estimate**: 18-26 days (LLM protocol, proposal UI, and rule-reference design)

### Phase 17 — Mobile and Federated Control

**Planning doc**: `BAB-2245` PRP
**Current status**: Approved PRP after Trinity R2 fast-review with GLM and
DeepSeek PASS.
**Scope**: Build the mobile and federation product layer. Add configurable node
identity and peer nodes, start with real-time remote reads, make Babs usable as
an installable mobile/PWA on the Tailscale network, and add explicitly
configured remote write/control paths guarded by per-node and per-Citizen
capabilities. Remote state remains local to each node; there is no distributed
Ticket database or cross-node Citizen-to-Citizen A2A.
**Acceptance**: A phone can operate a local Babs node through the mobile UI; a
local Babs node can mount a configured peer and receive live remote Ticket and
Citizen updates; a configured remote control action succeeds; a read-only peer
or read-only Citizen override denies the same action with visible UI/API
feedback.
**Estimate**: 18-28 days

### 🎯 M4 = V0-L complete (~12-18 weeks flywheel time)

---

## Total Timeline (with Trinity Realism Multiplier)

| Stage | Optimistic | Realistic (×2) |
|-------|-----------|---------------|
| Phase 0 (manual) | 3-4 days | 4-6 days |
| Phase 1 (manual) | 7-10 days | 14-21 days |
| Phase 2-6 (V0-S flywheel) | 16-25 days | 32-50 days |
| Phase 6.5 (dogfood, waived as gate) | 0 days | 0 days |
| Phase 7-12 (V0-M flywheel) | 21-33 days | 42-66 days |
| Phase 12a (relay reliability) | 4-7 days | 8-14 days |
| Phase 13 (imported tmux attach) | 4-7 days | 8-14 days |
| Phase 13a (multi-turn direct CLI) | 10-16 days | 20-32 days |
| Phase 13f (provider runtime contract) | 4-8 days | 8-16 days |
| Phase 14-15 (V0-L early) | 15-22 days | 30-44 days |
| Phase 16 (Mayor) | 18-26 days | 36-52 days |
| Phase 17 (Mobile/Federation) | 18-28 days | 36-56 days |
| **Total** | **~120-186 days (~17-27 weeks)** | **~238-371 days (~34-53 weeks, 8-13 months)** |

**Be honest**: The realistic column is the operating estimate. Plan for 8-13 months of total elapsed time, with ~2-5 weeks of human-only effort and the rest as flywheel reviewing.

---

## Flywheel Acceleration

Per the design intent (and Trinity confirmation), velocity increases as more capabilities come online:

| Stage | Speedup factor | Why |
|-------|----------------|-----|
| Phase 2-6 | 1× | Single citizen, sequential work |
| Phase 7-9 | 1.5× | Multi-citizen, can split frontend / backend in parallel |
| Phase 10-12 | 2× | Tickets-create-tickets meta-loop |
| Phase 12a-13 | 2× | Reliable delivery/reply capture plus imported tmux attach reduce manual intervention and context loss |
| Phase 13a | 2.5× | Multi-turn Ticket sessions and provider session ids reduce manual re-prompt/reopen-terminal loops before role automation |
| Phase 14-15 | 3× | Inspector automation removes user-as-bottleneck |
| Phase 16-17 | 5× | Mayor self-plans the roadmap; user becomes director only |

These are aspirational. Trinity flagged that AI rework cycles + context exhaustion can reduce effective speedup; observed velocity informs whether to invest in V0-L at all or freeze at V0-M.

---

## Anti-Goals (explicit non-roadmap)

- **NO Discord / Telegram / Slack adapters in v0.1.** Removed from earlier scope (D6); deferred indefinitely.
- **NO cross-machine citizen-to-citizen A2A messaging in v0.1.** Remote UI federation starts read-only per `BAB-1109`, and Phase 17 may add explicitly configured remote write/control for the single operator over Tailscale per `BAB-2245`. There is no cross-node Citizen-to-Citizen A2A, no distributed Ticket store, and no public-internet exposure.
- **NO generic non-interactive AI workflows (batch jobs).** Babs is for live, interactive citizens. Phase 13a adds a narrow direct CLI backend for Ticket turns only; background job scheduling remains a different design.
- **NO multi-tenancy / multi-user auth.** Single-operator default; Tailscale network identity is the only auth in v0.1.
- **NO Babs-managed model API quotas / cost tracking** in v0.1. Operator manages provider quotas externally.

---

## Decision Points

The roadmap can be **paused at any milestone**. V0-S, V0-M, V0-L are all defensible stopping points:

- Stop at V0-S → Babs is "multi-AI tab in browser with persistence" (useful but minimal differentiation)
- Stop at V0-M → Babs is "filesystem-first ticket-driven multi-agent system" (the strongest differentiator vs market)
- Stop at V0-L → Babs is "AI city with autonomous orchestration" (research/flagship)

Decision criterion: at each milestone, ask "is the additional feature set worth the next phase batch?" If no — V0-M is a perfectly good shipping product.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Add `BAB-2254` Phase 14.4 Role BDD/E2E Hardening CHG | Codex |
| 2026-05-08 | Add `BAB-2253` Phase 14.3 Ticket Role Router CHG | Codex |
| 2026-05-08 | Add `BAB-2252` Phase 14.2 Citizen Role UI CHG | Codex |
| 2026-05-08 | Add `BAB-2251` Phase 14.1 Role Model and Persistence CHG | Codex |
| 2026-05-08 | Add `BAB-2250` Phase 13f.4 Provider Diagnostics and Redaction CHG | Codex |
| 2026-05-08 | Add `BAB-2249` Phase 13f.3 Hardline Capability Mapping CHG | Codex |
| 2026-05-08 | Add `BAB-2248` Phase 13f.2 Direct CLI Normalized Result CHG | Codex |
| 2026-05-08 | Add `BAB-2247` Provider Runtime Inventory reference for Phase 13f.1 | Codex |
| 2026-05-03 | Full rewrite from earlier 5-phase plan; new 17-phase (with 6.5) Bootstrap → Flywheel structure; incorporates Trinity review (`BAB-1006`); β + γ (`BAB-1110`); ticket-everything (`BAB-1111`); multi-CLI (`BAB-1112`); v0.1 scope narrowing (`BAB-1109`) | Claude Code |
| 2026-05-03 | Sync Phase 0 output with amended `BAB-1502`; validation now records CHG entries on `BAB-1103`, `BAB-1106`, and `BAB-1110` | Codex |
| 2026-05-04 | Phase 1 cleanup: switch seed names to Clare/Dylan plus Sentinel, move configs to `citizens/citizen-<slug>.toml`, use `Babs.DevReloader`, move transcripts to `<cwd>/transcript.jsonl`, and defer SQLite as Phase 3 authority | Codex |
| 2026-05-04 | Add optional Phase 0a Hardline Manager Console Spike (`BAB-2202`) between Phase 0 and Phase 1; clarify it improves browser operation but does not replace the official Phase 0 full validation gate | Codex |
| 2026-05-04 | Mark Phase 0a implemented after manager console code, tests, Tailscale API smoke, browser smoke, and reattach verification passed | Codex |
| 2026-05-04 | Add optional Phase 0b Hardline Full-Window Mode Spike (`BAB-2203`/`BAB-2204`) after Phase 0a; clarify it is browser-only usability work and not a Phase 0 gate substitute | Codex |
| 2026-05-04 | Mark optional Phase 0c implemented after JS extraction, Node pure-JS tests, Playwright DOM/E2E tests, and ExUnit validation passed | Codex |
| 2026-05-05 | Add `BAB-2208` as the Phase 2 transcript persistence PRP and record that PR #7 partially implemented write-side transcript logging while replay remains open | Codex |
| 2026-05-05 | Add Phase 2a configurable workspace root (`BAB-2209`) before SQLite so durable Citizen working state is not implicitly tied to the active repo checkout | Codex |
| 2026-05-05 | Mark Phase 3 implemented in branch pending PR after SQLite registry, import/respawn, lifecycle status, BDD, coverage, Gate A, and migration validation passed | Codex |
| 2026-05-05 | Add `BAB-2212` draft PRP for Phase 4 NewCitizenLive spawn UI, defer arbitrary env editing until secret-storage/redaction design exists, and label the GitHub Copilot CLI preset `copilot-cli` | Codex |
| 2026-05-05 | Mark Phase 3 merged in PR #11 and Phase 4 PRP reviewed by Trinity GLM/DeepSeek, ready for CHG | Codex |
| 2026-05-05 | Add draft `BAB-2213` implementation CHG for Phase 4 TDD work | Codex |
| 2026-05-05 | Mark `BAB-2213` reviewed by Trinity GLM/DeepSeek and pending operator approval | Codex |
| 2026-05-05 | Mark `BAB-2213` approved after operator approval to proceed with Phase 4 implementation | Codex |
| 2026-05-05 | Mark Phase 4 implemented locally with validation passed, pending code review and PR | Codex |
| 2026-05-05 | Record full-scope Trinity implementation-review execution blocker for Phase 4 | Codex |
| 2026-05-05 | Mark Phase 4 local validation and scoped Trinity fast-review complete, pending PR | Codex |
| 2026-05-05 | Record GitHub Codex PR review fixes and final validation rerun for Phase 4 | Codex |
| 2026-05-06 | Add `BAB-2216` draft CHG for Phase 6 Stop/Start/Restart UI lifecycle controls | Codex |
| 2026-05-06 | Mark `BAB-2216` approved after Trinity GLM/DeepSeek fast-review PASS | Codex |
| 2026-05-06 | Record local Phase 6 implementation and validation evidence | Codex |
| 2026-05-06 | Record Phase 6 Trinity implementation review pass and Stop-click test fix | Codex |
| 2026-05-06 | Mark Phase 6 merged, add `BAB-2217` M3 planning reference, normalize Ticket lifecycle/assignees/runtime-root wording for Phase 7-15, and record Phase 6.5 gate waiver for continuous Phase 7-12 delivery | Codex |
| 2026-05-06 | Add `BAB-2218` M3 execution contract reference for continuous Phase 7-12 delivery defaults and stop conditions | Codex |
| 2026-05-06 | Mark `BAB-2218` execution contract approved and align Phase 7 acceptance with `bb ticket new` / documented bridge wording | Codex |
| 2026-05-06 | Add `BAB-2219` Phase 7 Ticket storage core implementation CHG reference | Codex |
| 2026-05-06 | Mark `BAB-2219` approved after Trinity R3 GLM/DeepSeek PASS and advisory fold-in | Codex |
| 2026-05-06 | Add Phase 12a (`BAB-2224`) after Phase 12 for PFC-informed adaptive hardline delivery and AI CLI JSONL reply capture | Codex |
| 2026-05-06 | Add Phase 13 imported external tmux session attach (`BAB-2225`/`BAB-1113`) with explicit `Imported · External-owned` lifecycle labeling, shift V0-L role/inspector/mayor/federation phases to 14-17, and update timeline estimates | Codex |
| 2026-05-06 | Fold Trinity R1 findings by splitting Phase 12a into its own timeline row and marking Phase 6.5 waived as 0-day gate cost | Codex |
| 2026-05-06 | Fold Trinity R2 advisories by marking M2.5 waived in the milestone map and clarifying Phase 12a-13 acceleration rationale | Codex |
| 2026-05-06 | Fold Trinity R3 advisory by aligning M3/M4 flywheel-time labels with the timeline table | Codex |
| 2026-05-06 | Add `BAB-2226` Phase 12a implementation CHG reference | Codex |
| 2026-05-06 | Record Phase 12 PR #20 merge, Phase 12a/13 local implementation validation, and `BAB-2227` Phase 13 CHG reference | Codex |
| 2026-05-06 | Record local Phase 7 Ticket storage implementation and temporary Mix command bridge | Codex |
| 2026-05-06 | Record Phase 7 Trinity implementation review pass and post-review fixes | Codex |
| 2026-05-06 | Mark Phase 7 PR #16 merged and add `BAB-2220` Phase 8 Ticket UI and watcher CHG reference | Codex |
| 2026-05-06 | Record local Phase 8 Ticket UI and watcher implementation plus validation pass | Codex |
| 2026-05-06 | Mark Phase 8 PR #17 merged and add `BAB-2221` Phase 9-10 assignment/state-machine CHG reference | Codex |
| 2026-05-06 | Mark `BAB-2221` approved after Trinity R2 GLM/DeepSeek PASS | Codex |
| 2026-05-07 | Add Phase 13a after imported tmux attach for multi-turn Ticket sessions, direct CLI provider sessions, lazy tmux, and the decision not to adopt `better-sqlite3` for the Elixir runtime | Codex |
| 2026-05-07 | Increase Phase 13a estimate after Claude/Codex direct review identified supervised runner, direct reply pipeline, session migration, redaction/env, and lazy-tmux concurrency scope | Codex |
| 2026-05-07 | Align Phase 13a with light-first UI and kitchen-sink route from `BAB-1004` | Codex |
| 2026-05-07 | Add `BAB-2242` Phase 14 PRP and update Phase 14 from single-role to multi-role Citizen routing | Codex |
| 2026-05-07 | Add `BAB-2243` Phase 15 PRP and update Phase 15 from a single inspector role to Inspector Council auto-approval | Codex |
| 2026-05-07 | Add `BAB-2244` Phase 16 PRP and update Mayor scope to human-gated rule-guided proposal planning | Codex |
| 2026-05-07 | Add `BAB-2245` Phase 17 PRP and update federation scope from read-only PWA polish to mobile plus explicitly configured remote control | Codex |
| 2026-05-08 | Add `BAB-2246` Phase 13f.1 implementation CHG for Provider Runtime Contract and inventory | Codex |
