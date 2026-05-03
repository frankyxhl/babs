# ADR-1111: Ticket as Universal Coordination Primitive

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Accepted
**Implementation gate:** Full implementation gated to V0-M / Phase 7+; see `BAB-2300`

---

## What Is It?

The decision to represent **all** work in Babs (project-level needs, citizen-execution units, mayor proposals, public-billboard items) as a single filesystem-first primitive called a **Ticket** — a markdown file with YAML frontmatter, accompanied by an append-only history JSONL — discriminated by a `type` field (`assignment` / `mission` / `proposal` / etc.). Replaces the earlier separate concepts of Mission, Assignment, and Need with one unified primitive in the manner of Linear / Jira issue typing.

---

## Context

The 2026-05-03 design session iterated through several models for representing work in Babs:

1. Initial: Citizen-as-context, with implicit messaging
2. Refined: Citizen + Mission (long) + Thread (per-context-of-work)
3. Refined: Citizen + Mission + Assignment (sub-mission unit)
4. Refined: + Mayor (orchestrator) + Billboard (need pool)
5. Final: **Ticket** as universal primitive replacing Mission + Assignment + Need

The "Ticket-everything" simplification collapses three previously separate concepts (high-level project, citizen-execution-unit, public need) into one filesystem-first primitive with a `type` discriminator field. This pattern is identical to Linear / Jira issue typing (Epic / Story / Task / Subtask) — proven at scale.

## Decision

**Adopt Ticket as the universal coordination primitive of Babs.**

### Schema

Each Ticket is **two files** with the same stem:

```
tickets/T-2026-05-03-001.md         # the ticket itself
tickets/T-2026-05-03-001.history.jsonl  # append-only event log
```

Ticket file = YAML frontmatter + Markdown body:

```markdown
---
id: T-2026-05-03-001
type: assignment        # assignment | mission | proposal | comment-thread | ...
state: open             # open | in_progress | pending_approval | closed | cancelled
assigner: user          # user | mayor | <citizen-name>
assignees: [alex]       # list (always); v0.1 typically has 1 entry; multi-assignee supported from Phase 12
assignee_role: null     # nullable; for role-based routing
inspector: user         # who approves
priority: normal        # low | normal | high | urgent
parent_ticket: null     # nullable; for ticket trees (mission → assignments)
created_at: 2026-05-03T14:30:00Z
metadata: {}            # type-specific extension dict
---

# Ticket title here

Markdown body. The Citizen's initial prompt when assigned.
```

**Note on `assignees`**: List form even when only one citizen is assigned. Empty list `[]` means "on the billboard" (unassigned). Multi-assignee semantics (per `BAB-2300` Phase 12) means a comment broadcasts to all listed citizens' hardlines.

History file = JSON-Lines, one event per row:

```jsonl
{"ts":"2026-05-03T14:30:00Z","event":"created","by":"user"}
{"ts":"2026-05-03T14:35:00Z","event":"assigned","by":"user","to":"alex"}
{"ts":"2026-05-03T14:35:01Z","event":"state_change","from":"open","to":"in_progress"}
{"ts":"2026-05-03T15:12:00Z","event":"comment","by":"alex","body":"Working on it..."}
```

### Lifecycle States

```
open ─────► in_progress ─────► pending_approval ─────► closed
  │             ▲     ▲                │
  │             │     └── rejected ────┘
  │             │
  └── cancelled └── (assignee voluntarily releases)
```

States:
- `open` — created, not yet assigned to a citizen
- `in_progress` — assigned + accepted; Hardline open; AI working
- `pending_approval` — Citizen submitted; awaiting inspector decision
- `closed` — terminal: approved
- `cancelled` — terminal: aborted before completion
- `rejected` — transition event (NOT a state); when fired, ticket goes back to `in_progress` with feedback in history

### Type Field (extensible)

Initial v0.1 (Phase 7):
- `assignment` — a citizen does one unit of work; opens one Hardline

Future:
- `mission` (V0-L) — parent ticket with `parent_ticket: null`; spawns child assignments
- `proposal` (V0-L) — Mayor's draft of mission decomposition awaiting user approval
- `comment-thread` — long-running discussion attached to another ticket

### Billboard = Filesystem

There is no separate "billboard data structure". The `tickets/` directory IS the billboard. Tickets in `state: open, assignee: null` are "on the billboard" (unassigned, awaiting pickup or proposal). UI subscribes via filesystem watcher (FSEvents on macOS, inotify on Linux).

### Concurrent Write Strategy

Two writers (Babs core + a Citizen via `bb` CLI; or two Citizens commenting simultaneously) cannot directly write to the same ticket file — torn writes destroy data.

**Strategy: per-ticket single-writer GenServer.**

- `Babs.Ticket.Writer` is a Registry-keyed GenServer, one process per ticket ID, hosted in **`:babs_citizens` OTP app** (filesystem-only, no web dep)
- All writes (state change, comment, assignment) go through the writer
- Writer serializes mutations and commits to disk atomically (write to `.tmp` + rename)
- History writes are similarly serialized but use append-only fopen mode (concurrent appends to a single file are safe at the OS level for ≤PIPE_BUF bytes; we ensure each event row is small)

### CLI Surface

For citizens to interact with the ticket system from inside their tmux pane:

```bash
bb ticket new --type=assignment --title="..." --body="..."
bb ticket assign T-... --to=alex
bb ticket comment T-... "..."
bb ticket transition T-... pending_approval
bb ticket approve T-...
bb ticket reject T-... --feedback="..."
bb ticket list [--state=open] [--assignee=alex]
bb ticket show T-...
```

### `bb` CLI Transport Specification (v0.1)

The `bb` CLI is a binary in PATH inside Citizen tmux panes. It communicates with the running Babs node:

| Property | Value |
|----------|-------|
| **Implementation** | Elixir escript (`mix escript.build` produces `bb` binary). Built once during Babs install, dropped into a known location (`<repo>/_build/dev/bb` initially; user PATH later). |
| **Transport** | Unix domain socket at `/tmp/babs-<uid>.sock` (per-user). HTTP not used — UDS avoids port conflicts and is loopback-only by OS guarantee. Socket created by `:babs_citizens` `Plug.Cowboy` listener on app start. |
| **Wire format** | JSON request / JSON response. Single round-trip per CLI invocation. |
| **Auth** | None in v0.1 — UDS file permissions (mode 0700, owner-only) are the auth model. Single-operator default. |
| **Endpoint shape** | `POST /api/internal/v1/ticket` with `{action: "new"\|"assign"\|"comment"\|...; ...}` |
| **Error semantics** | Non-zero exit code on any failure; stderr carries human-readable message; stdout carries JSON for `list`/`show` actions only. |
| **Schema versioning** | `Bb-Protocol-Version: 1` header. v0.1 freezes at v1; future versions co-exist behind version negotiation. |

**Implementation gating**: `bb` CLI is built and installed by **Phase 7** (when ticket system goes online). Phase 1-6 do not need `bb`. The transport is specified now to prevent design drift; Phase 7's PRP slots into this spec without renegotiation.

**Phase 1 SEED does NOT include `bb` CLI** — Phase 1 has no tickets. Citizens interact with Babs only through their tmux pane's stdin/stdout (Hardline). Operators interact only through BabsWeb. The `bb` CLI surface emerges in Phase 7+.

## Why Filesystem-First (Not SQLite)

1. **Git as audit log** — every ticket change is `git diff`-able and reviewable
2. **Operator inspection** — `cd tickets/ && grep -l 'state: pending_approval' *.md` works
3. **Zero migration cost** — schema evolves by adding optional frontmatter keys; old tickets remain valid
4. **Aligns with Alfred convention** — Alfred uses markdown PRJ docs; Babs sister project should follow the same philosophy
5. **Backup = `tar`** — no database to dump

SQLite still exists for `citizens` table (auto-respawn requires queryable structured data) and possibly a `tickets_index` table for fast filtering — but **the ticket file is the source of truth**, the SQLite index is a derived view.

## Consequences

- Phase 7 implements the file format + writer + index
- Phase 8 implements the UI (renders frontmatter as table + markdown body + history timeline)
- Phase 9 implements assignment (Ticket body → Citizen prompt injection)
- Phase 10 implements the state machine
- Phase 11 implements approval UI
- Phase 12 implements cross-citizen comment routing
- The full system is gated to **Phase 7+** in `BAB-2300`
- v0.1 SEED (Phase 1) does NOT have tickets; it just has Citizens with terminals

## What This Replaces

- All earlier discussion of `Mission` as a runtime concept — replaced by `Ticket(type=mission)`, deferred to V0-L
- All earlier discussion of `Assignment` as a separate primitive — replaced by `Ticket(type=assignment)`
- All earlier discussion of `Billboard` as a separate data structure — replaced by `tickets/` directory + file watcher
- All earlier discussion of a separate `MessageBus` for cross-citizen comms — replaced by `bb ticket comment`

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial decision; ticket-everything model adopted | Claude Code |
| 2026-05-03 | Trinity 2nd-round fixes: schema `assignee: alex` → `assignees: [alex]` (list form forward-compatible with multi-assignee in Phase 12); added explicit `bb` CLI Transport Specification (Elixir escript over UDS at `/tmp/babs-<uid>.sock`, JSON, mode-0700 auth, gated to Phase 7 implementation); clarified `Babs.Ticket.Writer` lives in `:babs_citizens` OTP app | Claude Code |
| 2026-05-03 | Normalize Status metadata to `Accepted`; move implementation gate into a dedicated metadata field | Codex |
