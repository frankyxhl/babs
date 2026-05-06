# REF-1002: Naming & Vocabulary

**Applies to:** BAB project
**Last updated:** 2026-05-06
**Last reviewed:** 2026-05-06
**Status:** Active

---

## What Is It?

The project's vocabulary. Defines the meaning of every term that appears in code, documents, and conversations about Babs. New code and docs MUST use these terms with the meanings given here. Disagreements about a term's meaning are resolved by editing this document, not by adopting parallel vocabulary.

---

## ⚠️ v0.1 Scope Notice (2026-05-04 update)

This document was authored under the original 5-phase scope (with Discord/Telegram connectors and cross-node A2A). The v0.1 scope redefinition narrowed Babs significantly. **Read the "v0.1 Vocabulary (Authoritative)" section below first**; it supersedes terms in the legacy sections where they conflict. Terms still valid: `Babs`, `Citizen`, `Hardline` (formerly `Tmux.Core`), `Family Naming`. Terms partially superseded: `Citizen.Server`, `PaneSession`, `ChannelWorker`, `Connector`, `A2A`. Legacy term: `*.bob/` is not used by the current runtime layout; Babs uses `citizens/citizen-<slug>.toml` plus resolved Citizen workspaces under `workspace_root`, defaulting to `<BABS_ROOT>/workspaces/<slug>`. See `BAB-1109` (UI federation only), `BAB-1110` (β + γ), `BAB-1111` (Ticket replaces A2A messaging), `BAB-1112` (multi-CLI).

---

## v0.1 Vocabulary (Authoritative)

These terms reflect the current v0.1 design. They take precedence over legacy sections.

### Hardline

The PTY/byte channel between BEAM and a `tmux` pane. **1:1 with one Citizen execution** (one Citizen = one active Hardline; one Hardline is attached to one tmux pane).

Implemented as `Hardline.Pane` GenServer (in `:babs_citizens` OTP app — see `BAB-1110`). Holds an `erlexec` port. Publishes received bytes to `Phoenix.PubSub` topic `pane:<slug>`; provides `inject/2` for input.

Replaces the old `Tmux.Core` + `PaneSession` split. Origin: *The Matrix* hardline phones (see `BAB-1005`).

### Imported Tmux Session

A tmux pane created outside Babs and explicitly attached through the Phase 13
import UI. Imported sessions default to external ownership: Babs may stream,
inject, persist transcript, detach, and reattach, but it must not kill the
external tmux session. UI should label these Citizens with an `Imported ·
External-owned` style badge and show a `Detach only · tmux stays running`
lifecycle reminder near Stop/Detach controls. See `BAB-1113`.

### Ticket

The unified primitive for representing work in Babs. Each Ticket = one markdown file + one history JSONL file under the configured tickets root:

```
<tickets_root>/T-2026-05-03-001.md
<tickets_root>/T-2026-05-03-001.history.jsonl
```

Ticket has `type` field (`assignment`, `mission`, `proposal`, etc.) and a five-state lifecycle (Open / In Progress / Pending Approval / Closed / Cancelled) plus transition events such as Rejected and Unassigned. See `BAB-1111` for full schema.
The default tickets root is `<BABS_ROOT>/var/tickets`; Ticket files are runtime
data and are not committed by default.

Replaces three earlier separate concepts: Mission, Assignment, Need. The collapse into Ticket is per ServiceNow / Linear / Jira issue-typing precedent.

### Billboard

The configured tickets root itself, viewed as a coordination surface. Tickets with `state: open, assignees: []` are "on the billboard" (unassigned, awaiting pickup or Mayor proposal). Subscription = filesystem watcher (FSEvents on macOS).

There is no separate Billboard data structure — the filesystem is the billboard. See `BAB-1111`.

### Mayor

A special Citizen with `is_mayor: true` (V0-L only — Phase 16 in `BAB-2300`). Reads the Billboard, proposes ticket trees + citizen lists, awaits user approval, writes approved tickets to disk. **Not implemented in v0.1 (V0-S or V0-M)**; SQLite reserved field `is_mayor` is set false in v0.1.

### Inspector

A Citizen with `role: inspector` (V0-L only — Phase 15). Reviews tickets in `Pending Approval` state and decides approve/reject. In v0.1 (V0-S/V0-M), the inspector role is fulfilled by the human user.

### Mission (deprecated as runtime concept; reborn as `Ticket(type=mission)`)

**Do not use "Mission" as an independent term in code or new docs.** The earlier design had Mission as a long-running unit; this is now `Ticket(type=mission)`. Mission as a noun in casual conversation can still mean "a project a Citizen is working on", but that's user-facing language, not a runtime entity.

### Thread (deprecated; replaced by `Ticket(type=assignment)`)

The earlier design tried "Thread" for a unit-of-work; rejected because it collides with OS thread / BEAM scheduler thread terminology. **Do not use "Thread" in code or docs.**

### Citizen (refined for v0.1)

Same as legacy section, but: a Citizen now has at most ONE active Hardline (= one tmux session) at a time in v0.1 (serial execution); multiple parallel Tickets per Citizen is deferred to v0.2+. Each Citizen has:
- A TOML config at `citizens/citizen-<slug>.toml` declaring `id`, `slug`, `cli`, `cli_args`, `cwd`, `env`, optional `role` (see `BAB-1112`)
- A workspace directory at the resolved `cwd`; relative TOML `cwd` values resolve under `workspace_root`, which defaults to `<BABS_ROOT>/workspaces`
- A SQLite `citizens` row with `slug`, `cwd`, `cli`, `status`, `role` (nullable), `is_mayor`, `metadata` starting in Phase 3
- A supervised subtree in `:babs_citizens` OTP app

### Two OTP Apps: `:babs` and `:babs_citizens`

`:babs` = Phoenix web app (Endpoint, LiveView, Channels, BabsWeb). `:babs_citizens` = Citizen lifecycle (DynamicSupervisor, Hardline.Pane, tmux ownership). They reload independently for live-reload-safety. See `BAB-1110`.

### Multi-CLI

Babs is AI-CLI-agnostic from day 1. Supported CLIs: `claude`, `codex`, `droid`, `pi`, `gh copilot`, plus future. Per-citizen `citizens/citizen-<slug>.toml` declares `cli` + `cli_args` + `env`. See `BAB-1112`.

Seed names are:
- `clare` = Claude Code (`citizens/citizen-clare.toml`, `cwd = "clare"`)
- `dylan` = Codex (`citizens/citizen-dylan.toml`, `cwd = "dylan"`)
- `sentinel` = deterministic `/bin/zsh` reload-validation citizen (`citizens/citizen-sentinel.toml`, `cwd = "sentinel"`)

Post-Phase-1 experimental seed:
- `elena` = GitHub Copilot CLI (`citizens/citizen-elena.toml`, `cwd = "elena"`) for validating `gh copilot` as a hosted Citizen CLI. Elena is not part of the Phase 1 flywheel gate.

### Babs ↔ Alfred Boundary

Babs runs Citizens; Alfred (`af`) provides SOPs. Babs does NOT parse SOPs — Citizens themselves invoke `af` directly inside their tmux pane. Convention only. See `BAB-1108`.

---

## Legacy Vocabulary (some terms below are partially superseded; see notice above)



### Babs

The project itself. Named after **Barbara Gordon's** canonical Bat-Family nickname. Barbara — operating from the Clocktower as Oracle in DC continuity — coordinates intelligence and communications for a team of agents. That role maps directly to what this runtime does: host multiple citizens, route messages between them and their external surfaces, and coordinate agent-to-agent (A2A) work.

**Why "Babs" and not "Oracle":** Oracle is a registered trademark (Oracle Corp.). Babs is the same character, the same role, no conflict. See **`BAB-1101`**.

**CLI**: `bb`.

### Bobs (`*.bob/`)

Legacy/deferred directory naming convention. Earlier drafts placed each citizen in `<name>.bob/`, e.g. `relay.bob/`, `dashboard.bob/`. The current runtime does **not** use this layout; it uses `citizens/citizen-<slug>.toml` for config and resolved `workspace_root/<slug>/` directories for working files by default. Do not introduce new docs or code using `*.bob/` unless a later ADR deliberately reactivates the convention.

### Citizen

A single AI-CLI-bearing identity hosted by Babs. This legacy section describes the older layout; for Phase 1 use the authoritative v0.1 section above. In older drafts each citizen had:
- A name (e.g. `dashboard`, `relay`, `transcript`)
- A directory at `citizens/<name>.bob/` with its config, skills, transcripts
- A tmux session running its AI CLI (Claude / Codex / etc.)
- A supervised subtree in the OTP graph (see `BAB-1102`)
- An A2A address (intra-node Registry key + cross-node URL)

A citizen is **not** an Erlang process. It is a *concept* implemented by a subtree of processes (`Citizen.Server` + `PaneSession` + `ChannelWorker(s)` + `TranscriptTailer`). When you say "the dashboard citizen", you mean that whole subtree plus its tmux session plus its transcripts on disk.

### CitizenSupervisor

The supervisor at the root of one citizen's subtree. One per citizen. Restarts strategy: `:rest_for_one` (so PaneSession crash doesn't lose ChannelWorker state, but Server crash takes down the whole subtree).

### Citizen.Server

A GenServer holding citizen identity, lifecycle state, and the inbound mailbox for A2A. Does NOT own the PTY; that is PaneSession's job.

### PaneSession

The GenServer that owns the citizen's `erlexec` PTY port. Single-writer for `tmux send-keys`. Provides `inject/2`, `read_recent/1`, `resize/2`. All terminal-byte and inject traffic goes through it; nothing else touches the PTY.

### ChannelWorker

A GenServer per (citizen × external channel) pair. E.g. the relay citizen has one ChannelWorker per Discord channel it watches. Polls the upstream surface, formats inbound messages, calls `PaneSession.inject/2`, listens for outbound replies via PubSub.

### TranscriptTailer

A GenServer that incrementally tails the citizen's JSONL transcript files (Claude's `~/.claude/projects/.../*.jsonl`, Codex's equivalent). Read-only. Publishes parsed deltas via PubSub for downstream consumers (LiveView dashboard, ChannelWorker reply detection).

### Tmux.Core

The single module/process that wraps `erlexec`. **The only place in the codebase that talks to tmux.** All `tmux send-keys`, `tmux capture-pane`, `tmux list-sessions` go through here. PaneSession holds an erlexec PTY port created by Tmux.Core; routine tmux CLI calls (capture, list) also go through Tmux.Core.

### A2A — Agent-to-Agent

The protocol for one citizen to delegate work to another citizen. **Two transports**:

- **Intra-node**: `Babs.A2A.Router` does Registry lookup → `GenServer.call`. No serialization, native ordering.
- **Inter-node**: HTTP JSON-RPC (`POST /a2a`) over Tailscale.

See **`BAB-1104`**.

### Connector

A module under `Babs.Connectors.*` that bridges Babs to a single external surface (Discord, Telegram, future Slack/Matrix). Owns its own auth, rate limiting, and polling/gateway connection. Hands inbound payloads to ChannelWorkers.

---

## Term Aliases & Anti-Patterns

| Use this term | Not this | Reason |
|---|---|---|
| Citizen | Agent | "Agent" is overloaded — it could mean an AI CLI, a Claude Code agent, a Bat-Family agent. "Citizen" is the project's specific term. |
| `workspace_root/<slug>/` | `.bob/` directory, "agent dir", "bot dir" | Current workspace convention; default resolved path is `<BABS_ROOT>/workspaces/<slug>`, and `.bob/` is legacy/deferred. |
| Hardline.Pane | PaneSession, "PTY worker", "terminal process" | Current v0.1 module for one Citizen's PTY byte channel. |
| Hardline | Tmux.Core, "tmux wrapper", "erlexec module" | Current v0.1 term for the PTY/byte channel boundary. |
| Inter-node A2A | "Cross-machine A2A", "remote A2A" | Tailscale is just the network layer; "node" is the BEAM-correct term. |

---

## Family Naming (Babs ↔ Alfred)

Babs is part of the same fictional family as Alfred (`af`):

- **Alfred Pennyworth** — Bruce Wayne's butler. Keeps the *runbook* for one Batman. → `af` = SOPs, workflow checklists, document lifecycle.
- **Barbara Gordon (Babs)** — Bat-Family communications and coordination hub from the Clocktower. Coordinates *many* agents. → `bb` = citizens, message relay, A2A.

Both tools are deliberately named to read together: `af` runs the playbook for an individual; `bb` runs the population. When documentation says "Babs and Alfred", it means the operational stack for AI agents.

---

## What These Names Are Not

- **Not Marvel.** Babs is DC. Don't conflate with anything from Marvel's continuity.
- **Not literal.** Babs the project does not impersonate Barbara Gordon, communicate with Bruce Wayne, or know about the Clocktower. The name is a metaphor for the *role*, not a costume.
- **Not user-facing branding.** End-users (people Discord-messaging a citizen) don't need to know the project is called "Babs". The name is for developers and operators.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial version — vocabulary, family naming, anti-patterns | Claude Code |
| 2026-05-03 | Drop legacy "inherited from prefrontal-cortex" framing for `.bob/` convention | Claude Code |
| 2026-05-04 | Phase 1 cleanup: mark `*.bob/` as legacy/deferred, define `citizens/citizen-<slug>.toml` + `workspaces/<slug>/`, switch Hardline topic naming to `pane:<slug>`, and record Clare/Dylan/Sentinel seed names | Codex |
| 2026-05-05 | Record Elena as a post-Phase-1 GitHub Copilot CLI experimental seed, separate from Phase 1 gate seeds | Codex |
| 2026-05-04 | Trinity review fix: update anti-pattern table to recommend `Hardline.Pane` and `Hardline` instead of legacy `PaneSession` and `Tmux.Core` terms | Codex |
| 2026-05-05 | Phase 2a: introduce configurable `workspace_root`, migrate seed examples to `cwd = "<slug>"`, and clarify default resolved workspace paths | Codex |
| 2026-05-06 | Normalize Ticket vocabulary to five states plus transition events, `assignees: []` Billboard representation, and gitignored runtime tickets root | Codex |
| 2026-05-06 | Add Imported Tmux Session vocabulary and shift Inspector/Mayor phase references after Phase 13 attach insertion | Codex |
