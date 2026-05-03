# PRP-2202: Phase 2 — A2A + SQLite Registry + First End-to-End Citizen

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Draft
**Depends on:** Phase 1 (`BAB-2201`) — supervision skeleton in place

---

## What Is It?

The phase that makes Babs *useful in isolation*: an operator can run two real citizens locally, they can talk to each other via A2A, transcripts are tailed live, and the citizen registry is durable. Still no Web, still no Connectors. The exit criterion is a live demo of two `*.bob/` citizens delegating tasks via `Babs.A2A.Router` from `iex`.

---

## Problem

Phase 1 produced an OTP skeleton with a single naked PaneSession. To validate the rest of the architecture (`BAB-1001` supervision tree, `BAB-1104` A2A split, `BAB-1105` persistence layering), we need the SQLite registry, the full Citizen subtree (with TranscriptTailer), and the A2A path — both same-node and via `A2A.HttpEndpoint`.

Doing this before Connectors means we surface integration bugs (A2A request/response semantics, transcript parsing edge cases, registry concurrency) without external network noise.

---

## Proposed Solution

### Scope

Adds to the Phase 1 skeleton:

```
lib/babs/
├── repo.ex                     (Ecto repo, ecto_sqlite3 backend)
├── schema/
│   ├── citizen.ex              (Ecto schema for citizens table)
│   └── task_history.ex         (Ecto schema for A2A audit log)
├── citizens/
│   ├── supervisor.ex           (DynamicSupervisor; replaces Phase 1's bare DynamicSupervisor)
│   └── registry.ex             (Registry-backed lookup; reads SQLite citizens table on boot)
├── citizen/
│   └── transcript_tailer.ex    (NEW: tails JSONL via File.stream! + position tracking)
├── a2a/
│   ├── router.ex               (intra-node: GenServer.call via Registry; inter-node: HTTP)
│   ├── http_endpoint.ex        (Bandit-served /a2a JSON-RPC endpoint)
│   └── http_client.ex          (Req or HTTPoison or stdlib for outbound A2A POST)
└── pubsub.ex                   (Phoenix.PubSub setup; not Phoenix Web yet — just the lib)

priv/repo/migrations/
├── 20260504_create_citizens.exs
├── 20260504_create_task_history.exs
└── ...
```

### Citizen.Server becomes real

Phase 1's stub gains:
- An A2A inbox (mailbox handles `{:a2a, payload}` calls from `Router`)
- Status state machine: `:idle | :typing | :waiting | :paused | :dead` (per `BAB-1004` state vocabulary)
- Status broadcasting to PubSub topic `citizen:#{name}:status` on transitions
- A method dispatch table for A2A: `ping`, plus citizen-specific methods registered at start

### TranscriptTailer

- Watches a path (configured per citizen) using `:file.read_file_info/1` mtime polling at 500ms (no fs_inotify dependency for v1)
- Reads new bytes via `File.stream!` from a tracked offset
- Parses JSONL lines into events; tolerant of partial lines and unknown fields
- Publishes parsed events to PubSub topic `citizen:#{name}:transcript`

### A2A — both transports

- `A2A.Router.dispatch(target_name, payload)`:
  1. `Registry.lookup({:via, Babs.Registry, target_name})`
  2. If found locally → `GenServer.call(pid, {:a2a, payload}, timeout)`
  3. If found in remote-host metadata → `A2A.HttpClient.post(host, target_name, payload, timeout)`
- `A2A.HttpEndpoint`: Bandit on configurable port (default 9001); routes `POST /a2a` to local `Router.dispatch/2` after JSON parse
- Audit: every dispatch logged to `task_history` SQLite table (timestamp, source, target, method, status, latency_ms)

### Out of scope for Phase 2

- Connectors (Discord, Telegram) — Phase 3
- Web — Phase 4
- ChannelWorker — Phase 3
- Tailscale node-discovery — start with `host` field hardcoded in citizens table; Tailscale auto-discovery is a Phase 5+ refinement
- A2A streaming — request/response only; streaming is a future ADR

### Acceptance

Phase 2 is done when:

- `mix ecto.migrate` creates the schema; `mix run priv/repo/seeds.exs` populates two test citizens
- `iex -S mix` brings up Babs.Application; both citizens auto-start
- `Babs.A2A.Router.dispatch("relay", %{"method" => "ping"})` returns `{:ok, %{"pong" => true}}` synchronously
- One real Claude CLI is running in tmux; `relay` citizen's TranscriptTailer publishes parsed events visible via `Phoenix.PubSub.subscribe(Babs.PubSub, "citizen:relay:transcript")` + `flush()`
- Two `iex` sessions on the same machine, both running Babs on different ports, can A2A each other via the `A2A.HttpClient` path (cross-process even on same host)
- Test suite covers Router happy-path + remote-failure + TranscriptTailer parsing + Citizen.Server status transitions

### Implementation Plan

1. Add deps: `:ecto_sqlite3`, `:phoenix_pubsub`, `:bandit`, `:req` (or stdlib HTTP)
2. Ecto schema + migrations for `citizens`, `task_history`
3. `Babs.Repo` setup, included in Application supervision
4. `Citizens.Supervisor` (DynamicSupervisor) reads citizens table on boot, starts subtrees
5. `Citizens.Registry` for name-to-pid lookup
6. Flesh out `Citizen.Server` (A2A inbox, status FSM, PubSub broadcasts)
7. `TranscriptTailer` (mtime polling + JSONL parser)
8. `A2A.Router`, `A2A.HttpEndpoint`, `A2A.HttpClient`
9. Seed data: two citizens (`relay.bob`, `summary.bob`) for local development
10. Integration test: end-to-end A2A across HTTP boundary + transcript tailing

---

## Open Questions

- **Mtime polling vs `:file_system` library**: 500ms polling adds latency budget; a real fs-watch dep gets us sub-50ms. **Default**: polling for v1 (zero new deps); upgrade if Phase 4 dashboard shows transcript lag.
- **A2A timeout**: how long does `Router.dispatch` wait by default? **Default**: 30s for synchronous calls; 5s for `ping` health checks; configurable per-call.
- **Handling host field for remote A2A**: how does Babs know which other host runs which citizen? **Default**: hardcoded `host` column in citizens table (operator-managed); Tailscale node auto-discovery deferred.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial draft | Claude Code |
