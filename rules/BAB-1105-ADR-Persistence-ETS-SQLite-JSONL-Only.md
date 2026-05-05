# ADR-1105: Persistence — ETS + SQLite + JSONL Only

**Applies to:** BAB project
**Last updated:** 2026-05-05
**Last reviewed:** 2026-05-03
**Status:** Accepted

---

## What Is It?

Babs uses exactly three persistence layers: **ETS** (volatile in-memory), **SQLite via ecto_sqlite3** (durable queryable), **JSONL files** (canonical external truth, read-only). DETS and Mnesia are explicitly rejected.

---

## Context

The runtime keeps several distinct kinds of state:

| State | Cadence | Survival need |
|---|---|---|
| Live citizen status, rate-limit counters, hot caches | written every 0.5-2s | volatile fine; re-derive on restart |
| Citizen registry (id, name, A2A URL, skills, host) | written occasionally | must survive restart; ~20-50 entries |
| Relay channel config, task history, method cache | mixed read/write | must survive restart; queryable; potentially thousands of rows |
| AI transcripts (Claude/Codex JSONL output) | append-only by AI CLIs | external truth; Babs only reads |
| Hardline byte transcripts (`<cwd>/transcript.jsonl`) | append-only by Babs | Babs-owned terminal audit/replay log |

Architecture analysis surfaced **four candidate backends**: ETS, DETS, Mnesia, SQLite. Two architecture reviews (DeepSeek, Codex) gave conflicting recommendations:

- DeepSeek: ETS + DETS + ecto_sqlite3 + JSONL (4 layers)
- Codex: ETS + ecto_sqlite3 + JSONL (3 layers; explicit Mnesia + DETS rejection)

---

## Decision

**Three layers. No DETS. No Mnesia.**

### ETS — volatile in-memory

What lives here:
- `:citizen_status` — current state of each citizen (idle / typing / waiting / dead)
- `:rate_limit_counters` — per-channel/per-citizen rate-limit state
- `:hot_routing_cache` — recent A2A target lookups
- `:active_terminal_sockets` — browser terminal connections currently attached

Properties: read every 0.5s by the dashboard's LiveView; write-frequent; survival not required (re-derive from running processes on restart).

Owner: each ETS table has exactly one writer process. Tables that need broad read access are `:public` + `:protected` (read by anyone, write by owner).

### SQLite via ecto_sqlite3 — durable queryable

What lives here:
- `citizens` table (citizen identity registry; Ecto schema)
- `relay_config` (channel routing rules, ai_type, prompt patterns)
- `task_history` (durable A2A task records, audit trail)
- `method_cache` (Notion AI Method DB lookups, see Constitution.md)

Properties: real query patterns (find by name, filter by category, sort by date). Single-writer per table is fine for our scale. Schema migrations via Ecto. Survives restarts trivially.

### JSONL files — append-only file truth

What lives here:
- Claude transcripts at `~/.claude/projects/<project-id>/<session-id>.jsonl`
- Codex transcripts at the equivalent
- Future AI CLI transcripts in their respective conventions
- Babs-owned Hardline byte transcripts at `<citizen cwd>/transcript.jsonl`
  starting in Phase 2

Properties:

- Upstream AI CLI transcripts are written by external tools. Babs only
  **tails** them via `File.stream!` + position tracking. Babs never writes those
  files. Their format is the upstream tool's contract, not ours.
- Babs Hardline byte transcripts are a separate Babs-owned JSONL contract:
  append-only records of terminal input/output bytes used for audit and browser
  replay. They do not replace upstream Claude/Codex transcripts.

Why on disk (not in SQLite): JSONL is already the AI CLI transcript contract,
and byte-level Hardline replay is naturally append-only. Any external tooling
that wants to read these files (now or in the future, in any language) gets them
at face value with no conversion step. We do not fork upstream AI CLI formats;
Babs-owned Hardline transcripts use their own local schema.

### Explicit Rejection — DETS

DETS (Disk Erlang Term Storage) was tempting for the citizen registry: small, persistent, no external server, no migrations.

**Rejected because:**
- SQLite handles the same case better with one less storage API to learn
- DETS has historical reliability concerns (file corruption on hard crash; 2GB size limits on some configurations); SQLite has none of these
- Querying DETS is awkward (`:dets.match/2` matchspecs); SQLite gives us `Ecto.Query`
- Two persistence APIs (DETS + SQLite) is a maintenance tax on a small team

If we had a case where SQLite was wrong (very high-frequency persistent writes that didn't fit a relational schema), DETS would re-enter consideration. We don't have that case.

### Explicit Rejection — Mnesia

Mnesia provides distributed Erlang-native storage with transactions, replication, and OTP integration.

**Rejected because:**
- The data model is single-writer per table (citizen registry is updated by one node; transcripts are read-only). Mnesia's distributed-write coordination is value we don't need.
- Mnesia split-brain recovery is complex; net splits over Tailscale would be a real failure mode if we used it
- We already chose HTTP JSON-RPC for inter-node A2A specifically to *avoid* depending on distributed Erlang health (`BAB-1104`); using Mnesia would re-introduce that dependency
- Schema evolution in Mnesia is harder than `Ecto.Migration`

If Babs grows to need cross-node *replicated* state (e.g., HA failover for the registry), the case to add Mnesia or an external KV store (Redis, etcd) re-opens. Today's scale doesn't justify it.

---

## Consequences

**Positive:**
- One in-memory API (ETS), one durable API (Ecto/SQLite), one read-only file format (JSONL). Easy to teach, easy to reason about.
- SQLite gives full-text search, joins, transactions, migrations — all the SQL toolkit, none of a separate DB server
- JSONL stays as the AI CLI contract; any external tooling that consumes those files works unchanged
- No distributed-storage failure modes; the storage layer is local-only

**Negative:**
- Cross-node state requires explicit replication (e.g., the citizen registry must be propagated by message-passing or HTTP fetch, not by Mnesia magic). We accept the explicitness.
- Some "small persistent state" cases that DETS would have handled in 5 lines need an Ecto schema. The friction is small (one schema file).

---

## Rejected Alternatives

(Captured above as DETS and Mnesia rejections. No additional alternatives considered.)

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial version — three-layer persistence; explicit DETS + Mnesia rejection | Claude Code |
| 2026-05-03 | Drop "replaces Python's citizen.db" / "during migration Phase 1-2" framing | Claude Code |
| 2026-05-05 | Clarify Phase 2 distinction between upstream AI CLI JSONL transcripts, which remain read-only to Babs, and Babs-owned Hardline byte transcripts used for terminal audit/replay | Codex |
