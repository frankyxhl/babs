# PRP-2271: PFC-Informed Operator Dashboard Panels

**Applies to:** BAB project
**Last updated:** 2026-05-31
**Last reviewed:** 2026-05-31
**Status:** Draft
**Date:** 2026-05-31
**Requested by:** Operator (@frankyxhl)
**Priority:** P2
**Sources:** `docs/PFC-vs-babs-comparison.md`; `prefrontal-cortex` feature surface analysis (2026-05-31)

---

## What

A post-v0.1 batch of operator-facing dashboard panels for Babs, ported in spirit
(not in code) from `prefrontal-cortex` (PFC). The batch is scoped to the
**self-evolution flywheel operated from a phone**: the operator watches AI
Citizens build Babs, gives them durable standing context, and reviews/approves
their code changes from a browser — including mobile.

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

Babs already implements PFC's core (Citizens, terminal/PTY, multi-CLI, Tickets +
Mayor/Inspector autonomy, federation/PWA) and the **flywheel** (`BAB-2300`:
Phases 2-17 were built by Citizens inside the running Babs). The gap vs PFC is
not the engine — it is the **operator dashboard breadth** that makes the
flywheel pleasant to drive, especially from a phone:

- No system observability surface (PFC has a System Monitor; Babs has none).
- No place for a Citizen's durable, human-editable standing context
  (PFC's `*.bob/` home with Readme/GOAL/Notes; Babs has only Tickets + transcripts).
- No way to see *what context* a Citizen is actually given for a Ticket turn
  (Babs has `prompt_assembler` internally, but it is invisible/uneditable).
- No way to review a Citizen's code changes from the browser before approving a
  Ticket (the core "it writes code, I approve from my phone" loop).

These are deliberately the **cheap, high-leverage** PFC panels. Heavy PFC
machinery (extension/snippet plugin system, Nerve message bus, Diagram editor,
Skill editor, external IM adapters) is **explicitly deferred, not deleted** —
see §Out of Scope.

## Scope

### Phase 1 — Observability (LiveDashboard)
Mount `Phoenix.LiveDashboard` at a dev-open / prod-token-gated route; wire a
`Babs.Telemetry` metrics module (BEAM + Phoenix + Ecto); add custom gauges for
Citizen status counts, live Hardline panes, and Ticket counts by state. Prefer
the BEAM-native surface over re-implementing PFC's `ps`-parsing monitor.

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

> Issue numbers backfilled after creation. Labels: `stack-type-*` / `stack-area-*`
> / `stack-size-*` / `stack-risk-*`; `blueprint-ready` applied by the bot.

| Slice | Title | Size | Risk | Issue |
|------|-------|------|------|-------|
| 1.1 | Add `phoenix_live_dashboard` dep + mount `/dev/dashboard` (dev-open, prod token-gated) | S | low | #80 |
| 1.2 | `Babs.Telemetry` metrics module (BEAM/Phoenix/Ecto) | S | low | #81 |
| 1.3 | Custom telemetry gauges — Citizens/Hardlines/Tickets | M | med | #82 |
| 1.4 | Document dashboard access + prod gating | XS | low | #83 |
| 2.1 | `knowledge_root` config + per-Citizen home path resolution | S | med | #84 |
| 2.2 | `Babs.Knowledge` core — safe list/read/write markdown | M | med | #85 |
| 2.3 | Markdown render + frontmatter parse for knowledge files | S | low | #86 |
| 2.4 | FileSystem watcher for `knowledge_root` → PubSub (mirror Tickets.Watcher) | S | med | #87 |
| 2.5 | Citizen Home read tab on `/citizens/:slug` (rendered Readme) | M | med | #88 |
| 2.6 | Citizen Home edit mode (save → file → watcher refresh) | M | med | #89 |
| 2.7 | Multi-note support under `notes/` (list + pick) | M | low | #90 |
| 2.8 | Seed default `Readme.md` on Citizen spawn | S | low | #91 |
| 2.9 | BDD — edit home in browser; external edit reflects in UI | M | med | #92 |
| 3.1 | `prompt_assembler` injects Citizen standing-context (Readme/GOAL) | M | high | #93 |
| 3.2 | Standing-context selection policy (frontmatter flag / config) | S | med | #94 |
| 3.3 | Size/token bounding + truncation for injected context | S | med | #95 |
| 3.4 | "Preview injected context" dry-run API + UI | M | med | #96 |
| 3.5 | Tests — assembly includes home; preview matches actual injection | S | med | #97 |
| 4.1 | `Babs.Git` wrapper — workspace-scoped status/branch/log/diff | M | med | #98 |
| 4.2 | Resolve repo/workspace for a Ticket (Citizen → cwd) | S | med | #99 |
| 4.3 | Git diff LiveView component | M | med | #100 |
| 4.4 | Wire diff into `ticket_live` for `pending_approval` review | M | med | #101 |
| 4.5 | Mobile/responsive styling for diff view | S | low | #102 |
| 4.6 | BDD — view Ticket diff + approve from mobile viewport | M | med | #103 |

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

- **Extension / plugin system** (PFC `extension_packages` runtime bundle loading).
  The runtime-adapter case is already solved BEAM-native by
  `provider_runtime` + `direct_cli/adapter`. A general `Babs.Extension.Registry`
  (umbrella apps + behaviour + LiveView component registry) is a future milestone;
  **Phase 2-4 panels must be built so a future registry can absorb them** (no
  hard-wiring that blocks extraction).
- **Nerve unified message bus** + external IM adapters (Discord/Telegram) —
  remains a `BAB-2300` anti-goal. A unified `Babs.EventLog` + replay may be
  considered independently later.
- Diagram/Excalidraw editor, Skill editor, Notebook, Glossary, BDD-in-UI panel,
  Component Inspector (Electron-bound), Chrome web-extension distribution.

## References / Dependencies

- `docs/PFC-vs-babs-comparison.md` — full PFC↔Babs feature matrix + rationale.
- `BAB-1503` — Phase Delivery Workflow (each slice follows it).
- `BAB-2100` — Workflow Routing.
- `BAB-1001` / `BAB-1106` — architecture + LiveView/Channel boundaries.
- `Tickets.Watcher` — the FileSystem-watcher pattern Phase 2 mirrors.
- `prompt_assembler` / `injector` — the assembly path Phase 3 extends.
- `BAB-2300` §Anti-Goals — the deferral boundary this PRP respects.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-31 | Initial draft — 4-phase, 24-slice PFC-informed operator dashboard batch | Claude Code |
