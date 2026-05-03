# REF-1002: Naming & Vocabulary

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Active

---

## What Is It?

The project's vocabulary. Defines the meaning of every term that appears in code, documents, and conversations about Babs. New code and docs MUST use these terms with the meanings given here. Disagreements about a term's meaning are resolved by editing this document, not by adopting parallel vocabulary.

---

## The Names

### Babs

The project itself. Named after **Barbara Gordon's** canonical Bat-Family nickname. Barbara — operating from the Clocktower as Oracle in DC continuity — coordinates intelligence and communications for a team of agents. That role maps directly to what this runtime does: host multiple citizens, route messages between them and their external surfaces, and coordinate agent-to-agent (A2A) work.

**Why "Babs" and not "Oracle":** Oracle is a registered trademark (Oracle Corp.). Babs is the same character, the same role, no conflict. See **`BAB-1101`**.

**CLI**: `bb`.

### Bobs (`*.bob/`)

A directory naming convention this project adopts: each citizen lives in `<name>.bob/`, e.g. `relay.bob/`, `dashboard.bob/`. The phonetic pun with **Babs** is intentional — **"Babs takes care of the Bobs"**. The runtime hosts a population of named, individually-supervised citizens.

### Citizen

A single AI-CLI-bearing identity hosted by Babs. Each citizen has:
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
| `.bob/` directory | "agent dir", "bot dir" | Project convention; the pun matters. |
| PaneSession | "PTY worker", "terminal process" | PaneSession is the role; PTY is the mechanism. |
| Tmux.Core | "tmux wrapper", "erlexec module" | There is exactly one; name it definitively. |
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
