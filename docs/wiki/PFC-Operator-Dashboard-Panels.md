# PFC-Informed Operator Dashboard Panels

A batch of operator-facing dashboard panels for Babs, ported **in spirit, not in
code** from `prefrontal-cortex` (PFC). Scoped to the **self-evolution flywheel
operated from a phone**: watch Citizens build Babs, give them durable standing
context, and review/approve their code changes — including on mobile.

- **Authoritative plan:** `rules/BAB-2271` (PRP) — `af read BAB-2271`
- **Full comparison + rationale:** `docs/PFC-vs-babs-comparison.md`
- **Build context:** `rules/BAB-2300` (roadmap), `rules/BAB-1503` (phase delivery)

## Why this batch

Babs already has PFC's core (Citizens, terminal/PTY, multi-CLI, Tickets +
Mayor/Inspector autonomy, federation/PWA) **and** the flywheel. The gap is the
operator dashboard breadth that makes the flywheel pleasant to drive from a
phone. These are the cheap, high-leverage panels; heavy PFC machinery
(plugin/extension system, Nerve bus, Diagram/Skill editors, external IM
adapters) is **deferred, not deleted**.

## Phases & issues

Each slice is one Iterwheel Blueprint issue (≈ one PR + tests).

### Phase 1 — Observability · Milestone #1
Mount `Phoenix.LiveDashboard` + Babs telemetry so system/Citizen/Ticket health
is visible (incl. mobile). Replaces PFC's hand-rolled System Monitor.

- #80 Add `phoenix_live_dashboard` + mount `/dev/dashboard` (dev-open, prod token-gated)
- #81 `Babs.Telemetry` metrics module (BEAM/Phoenix/Ecto)
- #82 Custom gauges — Citizens/Hardlines/Tickets
- #83 Docs — dashboard access + prod gating

### Phase 2 — Citizen Knowledge Home · Milestone #2
A browser-editable, file-backed markdown home per Citizen, live-refreshed via a
FileSystem watcher (same pattern as the Ticket watcher). **Files are the source
of truth.**

- #84 `knowledge_root` config + per-Citizen path resolution
- #85 `Babs.Knowledge` core — safe markdown CRUD
- #86 Markdown render + frontmatter parse
- #87 FileSystem watcher → PubSub (mirror Tickets.Watcher)
- #88 Citizen Home read tab on `/citizens/:slug`
- #89 Citizen Home edit mode (save → file → watcher refresh)
- #90 Multi-note support under `notes/`
- #91 Seed default `Readme.md` on spawn
- #92 BDD — browser edit + external-edit-reflects

### Phase 3 — Knowledge → Prompt · Milestone #3
Feed the Citizen's home (Readme/GOAL) into `prompt_assembler` as durable
standing context, with a "preview what gets injected" surface.

- #93 `prompt_assembler` injects standing context
- #94 Selection policy (frontmatter flag / config)
- #95 Size/token bounding + truncation
- #96 "Preview injected context" dry-run API + UI
- #97 Tests — assembly inclusion + preview parity

### Phase 4 — Mobile Diff Review · Milestone #4
A Ticket-bound git diff panel so a `pending_approval` Ticket shows what the
Citizen changed, reviewable + approvable from a phone.

- #98 `Babs.Git` wrapper — workspace-scoped status/branch/log/diff
- #99 Resolve repo/workspace for a Ticket
- #100 Git diff LiveView component
- #101 Wire diff into `ticket_live` for `pending_approval`
- #102 Mobile/responsive styling for diff view
- #103 BDD — view diff + approve from mobile viewport

## Deferred (not deleted)

`Babs.Extension.Registry` (plugin system; the runtime-adapter case is already
solved by `provider_runtime` + `direct_cli/adapter`), `Babs.EventLog` / Nerve
bus, Diagram/Excalidraw editor, Skill editor, Notebook, Glossary, BDD-in-UI,
external IM adapters. Phase 2–4 panels are built so a future registry can absorb
them.
