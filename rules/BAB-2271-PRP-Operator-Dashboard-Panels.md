# PRP-2271: Operator Dashboard Panels

**Applies to:** BAB project
**Last updated:** 2026-06-12
**Last reviewed:** 2026-06-12
**Status:** Implemented
**Date:** 2026-05-31
**Requested by:** Operator (@frankyxhl)
**Priority:** P2
**Sources:** Internal design analysis (2026-05-31); inspiration from prior art in existing multi-agent dashboards

---

## What

A post-v0.1 batch of operator-facing dashboard panels for Babs. The design is
**inspired by prior art in existing multi-agent dashboards**, but is a
clean-room, BEAM-native design — no third-party code or detailed internals are
reproduced. The batch is scoped to the **self-evolution flywheel operated from a
phone**: the operator watches AI Citizens build Babs, gives them durable standing
context, and reviews/approves their code changes from a browser — including
mobile.

Four phases, 24 atomic execution slices (each ≈ one PR + tests):

1. **Observability** — mount `Phoenix.LiveDashboard` + Babs telemetry so system
   and Citizen/Ticket health are visible (incl. from mobile).
2. **Citizen Knowledge Home** — a browser-editable, file-backed markdown home per
   Citizen (Readme / Notes), live-refreshed via a FileSystem watcher (same
   pattern as the Ticket watcher).
3. **Knowledge → Prompt** — feed the Citizen's home (Readme/GOAL) into
   `prompt_assembler` as durable standing context, with a "preview what gets
   injected" surface.
4. **Mobile Diff Review** — a Ticket-bound git diff panel so a `pending_approval`
   Ticket shows exactly what the Citizen changed, reviewable + approvable from a
   phone.

This PRP is the authoritative plan. Each slice is filed as an Iterwheel
Blueprint issue (see §Execution Slices) so Citizens can pick them up.

## Why

Babs already implements the core multi-agent runtime (Citizens, terminal/PTY,
multi-CLI, Tickets + Mayor/Inspector autonomy, federation/PWA) and the
**flywheel** (`BAB-2300`: Phases 2-17 were built by Citizens inside the running
Babs). The gap is not the engine — it is the **operator dashboard breadth** that
makes the flywheel pleasant to drive, especially from a phone:

- No system observability surface.
- No place for a Citizen's durable, human-editable standing context
  (only Tickets + transcripts exist today).
- No way to see *what context* a Citizen is actually given for a Ticket turn
  (`prompt_assembler` runs internally, but it is invisible/uneditable).
- No way to review a Citizen's code changes from the browser before approving a
  Ticket (the core "it writes code, I approve from my phone" loop).

These are the cheap, high-leverage panels. Heavier machinery (a general
extension/plugin system, a unified event bus, diagram/skill editors, external IM
adapters) is **explicitly deferred, not deleted** — see §Out of Scope.

## Scope

### Phase 1 — Observability (LiveDashboard)
Mount `Phoenix.LiveDashboard` at a dev-open / prod-token-gated route; wire a
`Babs.Telemetry` metrics module (BEAM + Phoenix + Ecto); add custom gauges for
Citizen status counts, live Hardline panes, and Ticket counts by state. Prefer
the BEAM-native surface over a hand-rolled process monitor.

### Phase 2 — Citizen Knowledge Home
A generic `Babs.Knowledge` context (safe per-Citizen markdown CRUD under a
configurable `knowledge_root`, resolved relative to the Citizen workspace),
markdown render + frontmatter parse, a FileSystem watcher → `Phoenix.PubSub`
mirroring `Tickets.Watcher`, and a Citizen Home tab on `/citizens/:slug` (read +
edit). **Files are the source of truth** (external editor / git can edit them) —
do **not** move this into SQLite.

### Phase 3 — Knowledge → Prompt
Extend `prompt_assembler` to inject a Citizen's standing context (Readme/GOAL)
into Ticket turns, governed by a selection policy (frontmatter flag / config),
bounded by a size/token cap with explicit truncation, and exposed through a
"preview injected context" dry-run API + UI.

### Phase 4 — Mobile Diff Review
A workspace-scoped `Babs.Git` wrapper (`System.cmd`, safe arg handling),
ticket→workspace resolution, a git diff LiveView component wired into
`ticket_live` for `pending_approval`, with responsive/mobile styling, so the
operator can review + approve a Citizen's changes from a phone.

## Execution Slices (atomic — one Iterwheel Blueprint issue each)

> Labels: `stack-type-*` / `stack-area-*` / `stack-size-*` / `stack-risk-*`;
> `blueprint-ready` applied by the bot.

| Slice | Title | Size | Risk | Issue | Status |
|------|-------|------|------|-------|--------|
| 1.1 | Add `phoenix_live_dashboard` dep + mount `/dev/dashboard` (dev-open, prod token-gated) | S | low | #80 | Done (#105) |
| 1.2 | `Babs.Telemetry` metrics module (BEAM/Phoenix/Ecto) | S | low | #81 | Done (#107) |
| 1.3 | Custom telemetry gauges — Citizens/Hardlines/Tickets | M | med | #82 | Done (#108) |
| 1.4 | Document dashboard access + prod gating | XS | low | #83 | Done on merge |
| 2.1 | `knowledge_root` config + per-Citizen home path resolution | S | med | #84 | Done (#110) |
| 2.2 | `Babs.Knowledge` core — safe list/read/write markdown | M | med | #85 | Done (#111) |
| 2.3 | Markdown render + frontmatter parse for knowledge files | S | low | #86 | Done (#112) |
| 2.4 | FileSystem watcher for `knowledge_root` → PubSub (mirror Tickets.Watcher) | S | med | #87 | Done (#113) |
| 2.5 | Citizen Home read tab on `/citizens/:slug` (rendered Readme) | M | med | #88 | Done (#114) |
| 2.6 | Citizen Home edit mode (save → file → watcher refresh) | M | med | #89 | Done (#116) |
| 2.7 | Multi-note support under `notes/` (list + pick) | M | low | #90 | Done (#126) |
| 2.8 | Seed default `Readme.md` on Citizen spawn | S | low | #91 | Done (#117) |
| 2.9 | BDD — edit home in browser; external edit reflects in UI | M | med | #92 | Done (#127) |
| 3.1 | `prompt_assembler` injects Citizen standing-context (Readme/GOAL) | M | high | #93 | Done (#118) |
| 3.2 | Standing-context selection policy (frontmatter flag / config) | S | med | #94 | Done (#128) |
| 3.3 | Size/token bounding + truncation for injected context | S | med | #95 | Done (#129) |
| 3.4 | "Preview injected context" dry-run API + UI | M | med | #96 | Done (#130) |
| 3.5 | Tests — assembly includes home; preview matches actual injection | S | med | #97 | Done (folded into #128–#130 test suites) |
| 4.1 | `Babs.Git` wrapper — workspace-scoped status/branch/log/diff | M | med | #98 | Done (#119) |
| 4.2 | Resolve repo/workspace for a Ticket (Citizen → cwd) | S | med | #99 | Done (#121) |
| 4.3 | Git diff LiveView component | M | med | #100 | Done (#122) |
| 4.4 | Wire diff into `ticket_live` for `pending_approval` review | M | med | #101 | Done (#123) |
| 4.5 | Mobile/responsive styling for diff view | S | low | #102 | Done (#124) |
| 4.6 | BDD — view Ticket diff + approve from mobile viewport | M | med | #103 | Done (#125) |

## Acceptance (per phase)

- **P1**: `/dev/dashboard` renders LiveDashboard; custom Babs metrics (Citizens by
  status, live panes, Tickets by state) are visible; prod route requires the
  socket token; dev route open. Validation: `mix test`, manual smoke.
- **P2**: Open `/citizens/<slug>`, see a rendered Readme; edit + save in the
  browser → file on disk updates; edit the file in an external editor → UI
  refreshes within ~1s via the watcher. Validation: unit + LiveView tests + BDD.
- **P3**: A Ticket turn's assembled prompt includes the Citizen's standing
  context, bounded by the cap; the "preview" surface matches what is actually
  injected. Validation: `prompt_assembler` tests + preview/actual parity test.
- **P4**: A `pending_approval` Ticket shows the Citizen's git diff; the operator
  can review and approve from a mobile-width viewport. Validation: `Babs.Git`
  unit tests + BDD at mobile viewport.

Each slice's own issue carries its concrete, checkbox-level acceptance criteria.

## Out of Scope (deferred, not deleted)

- **Extension / plugin system.** The runtime-adapter case is already solved
  BEAM-native by `provider_runtime` + `direct_cli/adapter`. A general
  `Babs.Extension.Registry` (umbrella apps + behaviour + LiveView component
  registry) is a future milestone; **Phase 2-4 panels must be built so a future
  registry can absorb them** (no hard-wiring that blocks extraction).
- **Unified message bus** + external IM adapters (Discord/Telegram) — remains a
  `BAB-2300` anti-goal. A unified `Babs.EventLog` + replay may be considered
  independently later.
- Diagram editor, Skill editor, Notebook, Glossary, BDD-in-UI panel, browser
  web-extension distribution.

## References / Dependencies

- `BAB-1503` — Phase Delivery Workflow (each slice follows it).
- `BAB-2100` — Workflow Routing.
- `BAB-1001` / `BAB-1106` — architecture + LiveView/Channel boundaries.
- `Tickets.Watcher` — the FileSystem-watcher pattern Phase 2 mirrors.
- `prompt_assembler` / `injector` — the assembly path Phase 3 extends.
- `BAB-2300` §Anti-Goals — the deferral boundary this PRP respects.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-31 | Note Phase 1 Observability slice completion through dashboard access documentation | Codex |
| 2026-05-31 | Initial draft — 4-phase, 24-slice operator dashboard batch | Claude Code |
| 2026-06-12 | Mark all Phase 2-4 slices Done with merged PR references (#110-#130; #97 tests folded into #128-#130); Status Draft → Implemented | Claude Code |
