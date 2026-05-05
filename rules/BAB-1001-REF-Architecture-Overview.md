# REF-1001: Architecture Overview

**Applies to:** BAB project
**Last updated:** 2026-05-05
**Last reviewed:** 2026-05-04
**Status:** Active

---

## ⚠️ v0.1 Scope Amendments — Substantial (2026-05-04)

This document was authored under the original 5-phase scope. The v0.1 redefinition narrowed and restructured Babs significantly. **Refer to these documents first**; this doc remains for historical context and architectural pieces still valid (Citizen abstraction, supervision-tree philosophy, BEAM-native intra-node coordination).

| Topic | Authoritative source |
|-------|--------------------|
| OTP application structure (single vs umbrella) | `BAB-1110` (β: two OTP apps) |
| Tmux lifecycle ownership | `BAB-1107` |
| Build phase sequencing | `BAB-2300` (17-phase Bootstrap → Flywheel) |
| Cross-machine A2A scope | `BAB-1109` (UI federation only in v0.1) |
| Coordination primitive | `BAB-1111` (unified Ticket replaces Mission/Assignment) |
| AI CLI choice | `BAB-1112` (multi-CLI from day 1) |
| Vocabulary | `BAB-1002` v0.1 section |
| Naming for `*.bob/` | Legacy/deferred per `BAB-1002`; current runtime uses `citizens/citizen-<slug>.toml` plus resolved Citizen workspaces under `workspace_root` |

The amendments are **substantial** — the build-phase sequencing, OTP application structure, cross-machine model, coordination primitive, and Phase 1 runtime layout have all changed. The doc remains as historical context plus the still-valid pieces (Citizen abstraction, supervision-tree philosophy, BEAM-native intra-node coordination). Legacy `*.bob/` naming below is not the Phase 1 runtime layout. A full rewrite will be done by Babs Citizens themselves post-Phase 1.

---

## What Is It?

The canonical architecture of Babs — the multi-agent Elixir/Phoenix runtime. Captures the OTP supervision tree, the persistence layering, the external boundaries, and the message flow paths. This document is the reference; ADRs (`BAB-11xx`) record the *why* for each consequential choice.

---

## Top-Level Shape

```
Babs OTP release  (CLI: bb)
└─ Babs.Application
   ├─ Babs.Repo                              (ecto_sqlite3 — durable queryable state)
   ├─ Babs.Cluster.Supervisor                (Tailscale node discovery + allowlist)
   │
   ├─ Babs.Citizens.Supervisor (DynamicSupervisor)
   │   └─ Babs.CitizenSupervisor(name)        ← one citizen = one supervised subtree
   │       ├─ Babs.Citizen.Server             (identity, lifecycle, mailbox)
   │       ├─ Hardline.Pane                   (formerly PaneSession; owns erlexec PTY)
   │       ├─ Babs.Citizen.ChannelWorker(N)   (one per Discord/TG channel relay)
   │       └─ Babs.Citizen.TranscriptTailer   (read-only JSONL; incremental tail)
   │
   ├─ Hardline                                (formerly Babs.Tmux.Core; tmux/erlexec boundary)
   │
   ├─ Babs.A2A.Supervisor
   │   ├─ Babs.A2A.Router                     (intra-node: Registry + GenServer.call)
   │   └─ Babs.A2A.HttpEndpoint               (inter-node / non-BEAM: JSON-RPC over Bandit)
   │
   ├─ Babs.Connectors.Supervisor              (Discord/Telegram REST + Gateway)
   │
   └─ BabsWeb.Endpoint
       ├─ LiveView      → state UI (dashboard / status / ops / diagram)
       └─ Channels      → raw PTY byte streams (subscribe `pane:<slug>` PubSub topic published by Hardline.Pane — see `BAB-1106` v0.1 amendment; earlier direct-channel wording is REVERSED)
```

---

## Persistence Layering

| Layer | Backend | What lives here | Why |
|-------|---------|-----------------|-----|
| Hot state | **ETS** | `:citizen_status`, `:rate_limit_counters`, `:hot_routing_cache` | Read every 0.5s by dashboard; volatile is fine; survives via re-derivation on restart |
| Durable & queryable | **SQLite via ecto_sqlite3** | `citizen.db` (identities, registry), `relay_config`, `task_history`, `method_cache` | Real query patterns (find by name, list by category); single-writer; Ecto integration |
| External truth | **JSONL files on disk** | Claude/Codex transcripts | The AI CLI writes them; Babs only tails read-only via mtime; external tooling can also read them |

**Explicit rejections:**
- **No DETS** — SQLite covers the durable case better and avoids two persistence APIs
- **No Mnesia** — distributed durability adds fragility without matching the single-writer data model

See **`BAB-1105`** for the full reasoning and the rejected alternatives.

---

## External Boundaries

```
Discord  ⇄ Connectors ⇄ ChannelWorker ⇄ Hardline.Pane ⇄ Hardline ⇄ tmux/PTY
Telegram ⇄ Connectors ─────────────────────────────────────────────┘
Claude/Codex JSONL ──read-only──► TranscriptTailer ──PubSub/ETS──► Web
Browser  LiveView (state UI) + Channel (terminal bytes) ──────────► PubSub `pane:<slug>` ─► Hardline.Pane
Tailscale peers ─────────HTTP JSON-RPC──► A2A.HttpEndpoint
```

**Boundary contracts:**

| Boundary | Protocol | Direction | Owner |
|----------|----------|-----------|-------|
| tmux / PTY | erlexec port (PTY mode) | bidirectional bytes | `Hardline` boundary in `:babs_citizens`; `Hardline.Pane` holds the port |
| Discord / Telegram | HTTPS REST + (Discord) Gateway | poll inbound, REST outbound | `Babs.Connectors.*` |
| Browser ⇄ state UI | Phoenix LiveView (WebSocket) | bidirectional, declarative diffs | `BabsWeb.*Live` modules |
| Browser ⇄ terminal | Phoenix Channel (raw bytes) + PubSub `pane:<slug>` | bidirectional, byte streams | `Hardline.Pane` publishes bytes; Channel joins `pane:<slug>` and forwards browser input |
| Inter-node A2A | HTTP JSON-RPC (over Tailscale) | request/response | `Babs.A2A.HttpEndpoint` |
| Intra-node A2A | `GenServer.call` via `Babs.A2A.Router` | direct OTP | Citizens directly |

---

## Message Flow — Discord Inbound

```
1. Discord poller (Connectors)            → fetches new messages
2. ChannelWorker                          → identifies target citizen, formats inject text
3. Hardline.Pane.inject(citizen, text)   → serialized input via Hardline
4. erlexec PTY                            → bytes hit tmux pane → AI CLI
5. AI CLI writes JSONL                    → TranscriptTailer detects mtime, parses delta
6. PubSub broadcast(citizen:<id>:reply)   → ChannelWorker subscribes
7. ChannelWorker                          → POSTs reply to Discord REST API
```

**Backpressure:** `Hardline.Pane` is the single serialization point per citizen. ChannelWorker, web `agent-send`, and A2A delegations all queue at this GenServer's mailbox. The PTY is never accessed directly by anything else.

---

## Message Flow — A2A Delegation

**Intra-node** (same BEAM):
```
Citizen A.delegate("task")
  → Babs.A2A.Router.dispatch(target_id, payload)
  → GenServer.call(via Registry, target_pid, {:a2a, payload})
  → target Citizen.Server enqueues, runs, replies
```

**Inter-node** (across Tailscale):
```
Citizen A.delegate("task")
  → A2A.Router → looks up target node from registry
  → POST /a2a (JSON-RPC) over Tailscale to peer's Babs.A2A.HttpEndpoint
  → peer dispatches locally as above
```

See **`BAB-1104`** for why HTTP JSON-RPC remains the inter-node primary (not `:erpc`).

---

## Concurrency Model — Why a Subtree per Citizen

Each Citizen is a **supervised subtree**, not a single GenServer:

- `Citizen.Server` — identity, mailbox, lifecycle
- `Hardline.Pane` — owns the PTY attachment; crashes restart only the pane attachment, not the citizen
- `ChannelWorker(N)` — one per relay channel; isolated failure domains (Discord auth flaking ≠ pane dying)
- `TranscriptTailer` — read-only file tail; restartable independently

**Why not a single GenServer per citizen?** Mixing PTY ownership, channel polling, and transcript reading in one process means one bug crashes everything. The subtree gives each concern its own crash boundary while keeping the citizen identity cohesive at the supervisor.

See **`BAB-1102`**.

---

## What Babs Does *Not* Do

- **Not an AI CLI** — Babs hosts AI CLIs (Claude, Codex, etc.) running inside tmux panes. It speaks to them via PTY bytes and reads their JSONL output.
- **Not a workflow engine** — that is Alfred (`af`). Babs runs the citizens; Alfred tells each citizen which SOP to follow.
- **Not a distributed compute framework** — A2A is light coordination, not a job queue or map-reduce. Cross-node is HTTP JSON-RPC explicitly (see `BAB-1104`).

---

## Build Phases

Babs is a from-scratch project. The build is sequenced to surface high-risk bets early. Each phase has its own PRP under `BAB-22xx`; the overall sequencing lives in `BAB-2300` (Build Roadmap PLN).

- **Phase 0** — PTY stability spike (`BAB-1502` SOP, `BAB-2200` PRP). Run before any production code is written. Validates erlexec PTY attach against the production-blocking risk in `BAB-1103`.
- **Phase 1** — V0-S0 SEED (`BAB-2201`): two OTP apps (`:babs`, `:babs_citizens`), `Hardline.Pane`, browser terminal at `/citizens/<slug>`, TOML seed configs, and Flywheel Gates A/B.
- **Phase 2+** — See `BAB-2300` for the current 17-phase roadmap. The old Phase 2-4 sequence below the v0.1 decision point is superseded.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial version — captures the architecture decided in the design discussion | Claude Code |
| 2026-05-03 | Drop migration framing; reframe Phase plan as from-scratch build phases | Claude Code |
| 2026-05-03 | Normalize Status metadata to `Active`; supersession context remains in the v0.1 banner | Codex |
| 2026-05-04 | Trinity review follow-up: align PubSub topic to authoritative `pane:<slug>` terminology | Codex |
| 2026-05-04 | Trinity review fix: mark `*.bob/` as legacy/deferred in the v0.1 amendments banner and point Phase 1 to `citizens/citizen-<slug>.toml` plus `workspaces/<slug>/` | Codex |
| 2026-05-04 | Trinity review fix: replace implementation-facing legacy `PaneSession`/`Tmux.Core`/direct-Channel wording with `Hardline.Pane`, `Hardline`, and PubSub `pane:<slug>` semantics | Codex |
| 2026-05-05 | Phase 2a: clarify that Citizen workspace paths are resolved under configurable `workspace_root`, with repo-local `workspaces/<slug>/` only the default resolved path | Codex |
