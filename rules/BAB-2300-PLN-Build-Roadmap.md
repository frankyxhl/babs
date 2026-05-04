# PLN-2300: Build Roadmap (v0.1 → v1.0)

**Applies to:** BAB project
**Last updated:** 2026-05-04
**Last reviewed:** 2026-05-04
**Status:** Active
**Replaces:** Earlier 5-phase roadmap (Discord/Telegram + cross-machine A2A)
**Sources:** v0.1 design session 2026-05-03; Trinity Review `BAB-1006`

---

## What Is It?

The master roadmap of Babs from Phase 0 (PTY validation) through Phase 16 (V0-L complete: Mayor + federation). Replaces the earlier 5-phase plan in full.

Two stages:
- **Bootstrap** (Phase 0-1): manually built by human in terminal `claude code`. ~2-5 weeks.
- **Flywheel** (Phase 2-16): every phase is built BY a Citizen AI INSIDE the running Babs (the user is in browser only). ~16-30 weeks (per Trinity 2× multiplier).

Phase 0 has its own PRP (`BAB-2200`). Optional Phase 0a has its own PRP (`BAB-2202`). Optional Phase 0b has its own PRP (`BAB-2203`). Optional Phase 0c has its own PRP (`BAB-2205`). Phase 1 has its own PRP (`BAB-2201`). Phases 2-16 are documented in this roadmap as concise sections; each will become a Ticket once the ticket system is online (Phase 7+) and that Ticket becomes the de facto PRP for that phase's work.

---

## Milestone Map

| Milestone | Phases | Definition |
|-----------|--------|------------|
| **M0** | 0, optional 0a/0b/0c | PTY substrate validated; optional browser manager console, full-window terminal mode, and browser test harness available for easier hardline operation |
| **M1** | 1 | **Flywheel ignited** — single Citizen running in browser, can edit Babs and survive reload |
| **M2** | 2-6 | **V0-S complete** — multi-citizen browser console with persistence; manual coordination |
| **M2.5** | 6.5 | Manual ticket dogfood validation (Trinity-mandated) |
| **M3** | 7-12 | **V0-M complete** — filesystem-first ticket-driven multi-agent system |
| **M4** | 13-16 | **V0-L complete** — Mayor + Inspector autonomy; PWA + read-only federation |

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
**Built by**: human (last manual phase)

🔥 **FLYWHEEL IGNITES at end of Phase 1** 🔥

---

## Stage 2: Flywheel (Citizens Build Babs)

> From here, every phase is a task given to a Citizen via BabsWeb browser. The user is PM + reviewer. Estimates assume single-Citizen sequential work; multi-Citizen parallelism (from Phase 5) reduces wall-clock time.

### Phase 2 — Transcript JSONL Persistence

**Scope**: Every byte that flows through `Hardline.Pane` is appended to `<cwd>/transcript.jsonl`, for example `workspaces/clare/transcript.jsonl`. On browser reload, last N lines replayed to xterm.js for context.
**Acceptance**: Close browser tab, re-open: see most recent 200 lines of transcript; tab restart is byte-loss-free
**Note**: This phase is the first chicken-and-egg test for the flywheel — clare modifies the file (`Hardline.Pane`) that captures her own bytes. Per `BAB-1110`, tmux survives the reload; new Pane reattaches.
**Estimate**: 3-5 days

### Phase 3 — SQLite Citizens Table + Auto-Respawn

**Scope**: `priv/repo/migrations/` + `Babs.Citizens.Repo`; `citizens` table fields: `slug`, `display_name`, `cwd`, `cli`, `cli_args`, `status` (`:running`/`:stopped`/`:failed`), `created_at`, `metadata` (JSONB), `role` (nullable), `is_mayor` (bool, default false). On Babs boot, scan SQLite + reattach.
**Reserved fields** for V0-L: `role`, `is_mayor`, `metadata` declared but not written by v0.1 logic.
**Acceptance**: Restart Babs node; clare auto-respawns from SQLite; cwd preserved
**Estimate**: 4-6 days

### Phase 4 — NewCitizenLive Spawn UI

**Scope**: `/citizens/new` form (slug + display name + CLI radio: claude/codex/droid/pi/gh copilot + cwd field + optional env block). Submit → write `citizens/citizen-<slug>.toml` + SQLite row + start citizen + redirect to `/citizens/<slug>`.
**Acceptance**: Spawn a new non-seed citizen via UI; it reaches interactive prompt; SQLite row + citizen TOML exist; transcript starts persisting
**Estimate**: 4-6 days

### Phase 5 — Multi-Citizen Index + Tab Navigation

**Scope**: `/citizens` index page (list all citizens with status badges); tab navigation between active citizens; ≥3 concurrent hardlines without PTY fd leak (verified via `lsof`).
**Acceptance**: Spawn clare / dylan / one additional citizen simultaneously; each in own tab; 30 min concurrent run, fd count stable
**Estimate**: 3-5 days

### Phase 6 — Stop / Start / Restart UI

**Scope**: Buttons in citizen detail view: stop (`tmux kill-session` + SQLite `:stopped` + preserve configured workspace), start (reuse config/workspace, fresh tmux + erlexec, status `:running`), restart (atomic stop + start). Per `BAB-1107` semantics.
**Acceptance**: Stop clare → restart clare; transcript continues with `:reattached` event in history; AI CLI starts fresh but workspace files are intact
**Estimate**: 2-4 days

### 🎯 M2 = V0-S complete (~3-5 weeks flywheel time)

### Phase 6.5 — Manual Ticket Dogfood (Trinity-mandated)

**Scope**: Operator manually creates 1-2 ticket markdown files at `tickets/T-2026-XX-XX-001.md`; manually edits frontmatter to assign to clare; manually injects ticket body as clare's prompt; clare completes work; operator manually flips state to `closed`. **No automation.** Validates that the schema design (per `BAB-1111`) actually works end-to-end before infrastructure is built.
**Why**: Trinity 3/3 reviewers flagged that Phase 7-12 is high-cost ticket infrastructure built without proving the workflow first. This 1-2 day phase validates the workflow.
**Acceptance**: 2 tickets driven through full lifecycle; observed friction informs Phase 7-12 designs
**Estimate**: 1-2 days

### Phase 7 — Ticket File System Skeleton

**Scope**: `tickets/` directory; schema validation (per `BAB-1111` frontmatter); `mix bb.ticket.new` task; per-ticket single-writer GenServer (concurrent-write safety); `T-...history.jsonl` append-only log.
**Acceptance**: Create 5 tickets via mix task; `git status` clean (atomic write); concurrent writes from 2 processes do not corrupt files (test in code)
**Estimate**: 4-6 days

### Phase 8 — Ticket Index UI + Render

**Scope**: `/tickets` list page (grouped by state); `/tickets/<id>` view (frontmatter table + markdown body + history timeline); filesystem watcher (FSEvents on macOS) drives live UI updates.
**Acceptance**: Browse all tickets; click one, see full content; manually edit ticket file in editor → UI updates within 1s
**Estimate**: 5-7 days

### Phase 9 — Ticket → Citizen Assignment

**Scope**: UI button "Assign to clare" → ticket `assignee` field updated → ticket body **injected as clare's initial prompt** (via `bb` CLI write to clare's stdin); state transitions to `in_progress`; history event written.
**Acceptance**: Create T-001 = "Add health check endpoint"; assign to clare; clare's terminal receives the body as input and starts working
**Estimate**: 4-6 days

### Phase 10 — Ticket 6-State Machine

**Scope**: Open / In Progress / Pending Approval / Closed / Cancelled + Rejected transition. Each transition writes to `.history.jsonl`. UI shows state badge. Illegal transitions are rejected with error message.
**Acceptance**: All paths walkable: Open → In Progress → Pending Approval → Closed; Reject from Pending Approval returns to In Progress with feedback comment in history; Cancel terminates from any non-closed state
**Estimate**: 3-5 days

### Phase 11 — Approval UI (Inspector = User in V0-M)

**Scope**: Pending Approval tickets show "Approve" / "Reject" buttons. Reject requires feedback (modal). Approve transitions to Closed; Reject transitions back to In Progress with feedback comment injected into assignee's hardline.
**Acceptance**: clare submits T-001 to Pending Approval; user rejects with feedback "missing docs"; clare receives feedback in terminal and continues; clare resubmits; user approves; ticket Closed
**Estimate**: 2-4 days

### Phase 12 — Cross-Citizen Ticket Comments

**Scope**: `bb ticket comment <id> "..."` shell command (used by Citizens). Comment appended to `.history.jsonl`. All Citizens listed as `assignees` (multi-assignee allowed) receive the comment via PubSub injection into their hardline.
**Acceptance**: T-001 assigned to clare + dylan; clare `bb ticket comment T-001 "Backend done"`; dylan's terminal sees the message within 1s
**Estimate**: 3-5 days

### 🎯 M3 = V0-M complete (~4-7 weeks flywheel time)

### Phase 13 — Citizen Roles

**Scope**: `citizens.role` SQLite field (was reserved in Phase 3) becomes user-settable. UI shows role; `/citizens/new` form has role field. Tickets can specify `assignee_role` instead of named `assignee`. Babs picks an idle Citizen of that role (round-robin).
**Acceptance**: Create T-002 with `assignee_role: developer`; Babs auto-routes to first idle developer-role citizen
**Estimate**: 3-5 days

### Phase 14 — Inspector Role (Auto-Approval)

**Scope**: Dedicated Citizen with `role: inspector`. SOP: "When a ticket reaches Pending Approval, read the body + acceptance criteria + assignee's last comments; decide approve or reject with reasoning". Inspector becomes the default `inspector` for new tickets. User can override.
**Acceptance**: T-003 reaches Pending Approval; inspector citizen wakes up (notified via PubSub on state change), reads ticket, writes approve/reject decision; user can intervene
**Estimate**: 7-10 days (LLM protocol design)

### Phase 15 — Mayor Citizen (research-grade)

**Scope**: Citizen with `is_mayor: true`. Listens for tickets with `assignee: null` (the billboard). Outputs proposal: `bb propose <root-ticket> --children "T-A: BA work; T-B: Developer work; ..."`. Proposal becomes draft tickets in a special state; UI shows them awaiting user approval. User can edit/cull/approve. On approve, drafts are written to `tickets/` and routed to citizens by role.
**Acceptance**: User creates T-100 = "Build a hello world site" (no assignee). Mayor proposes 4 children. User removes one ("designer"), approves rest. 3 children auto-routed to citizens by role. All 3 progress through the lifecycle.
**Estimate**: 14-21 days (LLM protocol research)

### Phase 16 — PWA + Mobile + Read-Only Federation

**Scope**: PWA manifest + service worker for installable browser app; mobile-responsive breakpoints; read-only federation API (per `BAB-1109`) — Tailscale-connected Babs nodes expose `/api/v1/tickets`, `/api/v1/citizens`, `/api/v1/citizens/<name>/transcript`; remote nodes mount as `remote://<peer>/...` namespace in UI.
**Acceptance**: Install PWA on iPhone; view desktop's running citizens. Configure laptop Babs to peer with desktop Babs; laptop's UI shows desktop tickets read-only.
**Estimate**: 14-21 days

### 🎯 M4 = V0-L complete (~6-9 weeks flywheel time)

---

## Total Timeline (with Trinity Realism Multiplier)

| Stage | Optimistic | Realistic (×2) |
|-------|-----------|---------------|
| Phase 0 (manual) | 3-4 days | 4-6 days |
| Phase 1 (manual) | 7-10 days | 14-21 days |
| Phase 2-6 (V0-S flywheel) | 16-25 days | 32-50 days |
| Phase 6.5 (dogfood) | 1-2 days | 2-3 days |
| Phase 7-12 (V0-M flywheel) | 21-33 days | 42-66 days |
| Phase 13-14 (V0-L early) | 10-15 days | 20-30 days |
| Phase 15 (Mayor) | 14-21 days | 28-42 days |
| Phase 16 (Polish) | 14-21 days | 28-42 days |
| **Total** | **~90-130 days (~13-19 weeks)** | **~170-260 days (~24-37 weeks, 6-9 months)** |

**Be honest**: The realistic column is the operating estimate. Plan for 6-9 months of total elapsed time, with ~2-5 weeks of human-only effort and the rest as flywheel reviewing.

---

## Flywheel Acceleration

Per the design intent (and Trinity confirmation), velocity increases as more capabilities come online:

| Stage | Speedup factor | Why |
|-------|----------------|-----|
| Phase 2-6 | 1× | Single citizen, sequential work |
| Phase 7-9 | 1.5× | Multi-citizen, can split frontend / backend in parallel |
| Phase 10-12 | 2× | Tickets-create-tickets meta-loop |
| Phase 13-14 | 3× | Inspector automation removes user-as-bottleneck |
| Phase 15-16 | 5× | Mayor self-plans the roadmap; user becomes director only |

These are aspirational. Trinity flagged that AI rework cycles + context exhaustion can reduce effective speedup; observed velocity informs whether to invest in V0-L at all or freeze at V0-M.

---

## Anti-Goals (explicit non-roadmap)

- **NO Discord / Telegram / Slack adapters in v0.1.** Removed from earlier scope (D6); deferred indefinitely.
- **NO cross-machine citizen-to-citizen messaging in v0.1.** UI federation is read-only only. See `BAB-1109`.
- **NO support for non-interactive AI workflows (batch jobs).** Babs is for live, interactive citizens. Background jobs are a different design.
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
| 2026-05-03 | Full rewrite from earlier 5-phase plan; new 17-phase (with 6.5) Bootstrap → Flywheel structure; incorporates Trinity review (`BAB-1006`); β + γ (`BAB-1110`); ticket-everything (`BAB-1111`); multi-CLI (`BAB-1112`); v0.1 scope narrowing (`BAB-1109`) | Claude Code |
| 2026-05-03 | Sync Phase 0 output with amended `BAB-1502`; validation now records CHG entries on `BAB-1103`, `BAB-1106`, and `BAB-1110` | Codex |
| 2026-05-04 | Phase 1 cleanup: switch seed names to Clare/Dylan plus Sentinel, move configs to `citizens/citizen-<slug>.toml`, use `Babs.DevReloader`, move transcripts to `<cwd>/transcript.jsonl`, and defer SQLite as Phase 3 authority | Codex |
| 2026-05-04 | Add optional Phase 0a Hardline Manager Console Spike (`BAB-2202`) between Phase 0 and Phase 1; clarify it improves browser operation but does not replace the official Phase 0 full validation gate | Codex |
| 2026-05-04 | Mark Phase 0a implemented after manager console code, tests, Tailscale API smoke, browser smoke, and reattach verification passed | Codex |
| 2026-05-04 | Add optional Phase 0b Hardline Full-Window Mode Spike (`BAB-2203`/`BAB-2204`) after Phase 0a; clarify it is browser-only usability work and not a Phase 0 gate substitute | Codex |
| 2026-05-04 | Mark optional Phase 0c implemented after JS extraction, Node pure-JS tests, Playwright DOM/E2E tests, and ExUnit validation passed | Codex |
