# ADR-1102: Citizen as Supervised Subtree, Not a Single GenServer

**Applies to:** BAB project
**Last updated:** 2026-05-04
**Last reviewed:** 2026-05-04
**Status:** Accepted

---

## ⚠️ v0.1 Amendments (2026-05-03)

The core decision (citizen = supervised subtree, not a single GenServer) **stands**. Amendments:

1. **OTP application housing**: This subtree now lives in the `:babs_citizens` OTP app, not the main `:babs` web app. See `BAB-1110` (β + γ live-reload-safety).
2. **`Tmux.Core` is replaced by `Hardline.Pane`** (see `BAB-1005` naming history, `BAB-1110`). Functionally similar; renamed.
3. **`ChannelWorker` is removed from v0.1** — no Discord/Telegram connectors per `BAB-1109`. Cross-citizen coordination happens via Tickets per `BAB-1111`.
4. **`Hardline.Pane` does NOT hold Channel PIDs** — it publishes to `Phoenix.PubSub` topic `pane:<slug>`; Channels subscribe on connect. See `BAB-1106` revision and `BAB-1110`.
5. **Restart strategy `:rest_for_one` retained** as documented.
6. **Known issues to fix during post-Phase-1 rewrite**: (a) line ~52 syntax error `Registry.lookup({:via, ...})` should be `Registry.lookup(Babs.Registry, citizen_name)`; (b) `Babs.CitizenSupervisor` typo should be `Babs.Citizen.Supervisor`; (c) Registry naming drift (`Babs.Registry` vs `Babs.Citizens.Registry`) needs unification.

A full rewrite will be done by Babs Citizens themselves post-Phase 1.

---

## What Is It?

Each citizen (`*.bob/`) is implemented as a **supervised subtree of multiple processes**, not a single GenServer. The subtree contains: `Citizen.Server` (identity/lifecycle), `PaneSession` (PTY ownership), `ChannelWorker(N)` (one per relay channel), `TranscriptTailer` (read-only JSONL tail).

---

## Context

A citizen does many distinct jobs:

| Concern | Cadence | Failure mode |
|---|---|---|
| Identity, A2A mailbox, status reporting | continuous | rare; bug in core logic |
| PTY ownership + `tmux send-keys` serialization | bursty | erlexec port crash, tmux pane death |
| Discord/Telegram channel polling | every 1-3s per channel | Discord auth flake, network blip, rate limit |
| Tailing JSONL transcripts | event-driven (mtime) | malformed JSONL line, file truncation |

A naive design would put all of these in **one GenServer per citizen**. The simplicity is appealing: one PID per citizen, one mailbox, one piece of state.

The problem: these concerns have **independent failure domains**. Discord auth flaking should not crash the PTY session. A malformed JSONL line should not lose pending A2A work. An erlexec port crash should not kill the relay channels watching this citizen.

Putting them in one process means any one bug crashes everything in the citizen. Restart strategy can't be tuned per concern.

---

## Decision

A citizen is a **subtree** rooted at `CitizenSupervisor`:

```
CitizenSupervisor(name)             ← :rest_for_one strategy
├── Citizen.Server                  (identity, lifecycle, A2A mailbox)
├── Citizen.PaneSession             (owns erlexec PTY)
├── Citizen.ChannelWorker(N)        (one per Discord/TG channel relay)
└── Citizen.TranscriptTailer        (read-only JSONL tail)
```

**Restart strategy: `:rest_for_one`.** Order matters:
- `Citizen.Server` first — if it dies, restart everything (it owns identity)
- `PaneSession` next — if it dies, kill ChannelWorkers and Tailer too (they depend on a working PTY)
- `ChannelWorker`s and `TranscriptTailer` last — independent of each other; either can die without affecting the others, except they share the supervisor restart counter

**Citizen Registration:** Each subtree registers itself in a `Registry` keyed by citizen name. A2A delegation does `Registry.lookup({:via, Babs.Registry, citizen_name})` → resolves to the `Citizen.Server` PID.

**Naming Convention:** `Babs.Citizen.Server`, `Babs.Citizen.PaneSession`, `Babs.Citizen.ChannelWorker`, `Babs.Citizen.TranscriptTailer`. The `Babs.CitizenSupervisor` is the dynamic supervisor under `Babs.Citizens.Supervisor`.

---

## Consequences

**Positive:**
- Each concern has its own crash boundary. Discord rate-limit retries don't touch PTY state.
- PaneSession can be restarted without losing A2A mailbox state in `Citizen.Server`.
- ChannelWorker(N) means adding/removing relay channels is just supervisor child management.
- TranscriptTailer can crash on a malformed line and restart from last known offset.
- Code stays focused: each module has one job.

**Negative:**
- More processes per citizen (4+ vs 1). Memory cost per citizen is higher (a few KB extra; negligible at the scales we run — tens of citizens, not thousands).
- More inter-process messaging within a citizen. Mostly resolved by direct `GenServer.call` between known siblings.
- More moving parts to reason about during debugging. Mitigated by the restart strategy being explicit and logged.

---

## Rejected Alternatives

### Alt 1 — One GenServer per citizen (the naive design)

Put PTY, channels, transcript, identity all in one `Citizen.Worker` process.

**Rejected because:**
- Mixing failure domains: a bug in JSONL parsing crashes the PTY attachment
- Restart explodes the entire citizen state on any crash
- Single mailbox bottleneck: a slow Discord poll blocks A2A delivery
- Hard to test concerns in isolation

### Alt 2 — One supervisor per *concern type*, citizens as flat IDs

E.g., `PaneSessions.Supervisor` holds all panes; `ChannelWorkers.Supervisor` holds all channel workers across all citizens. Citizens identified only by an ID.

**Rejected because:**
- Citizen-level lifecycle becomes implicit (kill the citizen = sweep multiple supervisors)
- A2A registration has no clear owner
- Doesn't model the real concept: a citizen is a coherent thing with multiple parts, not an ID-tagged tuple of unrelated processes

### Alt 3 — Each citizen = an OTP application

Use `Application.start/2` for each citizen, giving it its own application supervision and config.

**Rejected because:**
- Applications are heavy; they're meant for top-level releases, not runtime entities
- Supervisor strategy options are richer than application strategies
- Adding/removing citizens at runtime is a `DynamicSupervisor` pattern, which doesn't compose well with applications

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial version — codifies the subtree-per-citizen pattern | Claude Code |
| 2026-05-03 | Normalize Status metadata to `Accepted`; v0.1 amendments remain authoritative in the banner | Codex |
| 2026-05-04 | Trinity review follow-up: align PubSub topic to authoritative `pane:<slug>` terminology | Codex |
