# PRP-2201: Phase 1 — Core Supervision Skeleton

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Draft
**Depends on:** Phase 0 (`BAB-2200`) passes — Method A or Method B selected

---

## What Is It?

The first production phase. Build the OTP plumbing: `Babs.Application` + `Babs.Tmux.Core` + `Babs.Citizen.PaneSession` + a minimal `Babs.Citizen.Server`. **No web. No Connectors. No A2A. No SQLite.** The "UI" is `iex`. Exit criterion: an operator can manually start a citizen subtree, attach it to an existing tmux session, write bytes to it, and read bytes back.

---

## Problem

Phase 1 exists to validate the supervision tree shape (`BAB-1102`) and the PTY ownership pattern (`BAB-1103`) **in isolation** — without the noise of Connectors / A2A / Web complicating crash diagnostics. If supervision strategy is wrong, every later phase suffers; finding out at Phase 4 (when a dashboard pixel reveals a misbehaving restart) is expensive.

This phase also produces the Mix project skeleton that all later phases build on.

---

## Proposed Solution

### Scope

```
babs/
├── mix.exs
├── config/
│   ├── config.exs
│   ├── dev.exs
│   └── prod.exs
├── lib/
│   ├── babs/
│   │   ├── application.ex       (root supervisor, minimal children)
│   │   ├── tmux/
│   │   │   └── core.ex          (the only erlexec/tmux boundary)
│   │   ├── citizen/
│   │   │   ├── server.ex        (identity + lifecycle stub)
│   │   │   └── pane_session.ex  (owns erlexec PTY, serializes inject)
│   │   └── citizen_supervisor.ex (rest_for_one)
│   └── babs.ex                  (top-level API: start_citizen/1, etc.)
└── test/
    └── babs/
        ├── tmux/core_test.exs
        └── citizen/pane_session_test.exs
```

### Behaviors required

- `Babs.Tmux.Core.attach(session_name, opts)` — start an erlexec PTY port to `tmux attach-session -t <session>`; return `{:ok, port}` or typed error
- `Babs.Tmux.Core.send_keys(session_name, payload)` — for non-PTY tmux operations (still routes through Tmux.Core to keep the boundary single)
- `Babs.Tmux.Core.capture_pane(session_name)` — for non-PTY reads (used by Method B fallback; available even in Method A)
- `Babs.Citizen.PaneSession.start_link(name)` — attach to tmux session named `name`, become single-writer for it
- `PaneSession.inject(name, bytes)` — serialized write to the PTY
- `PaneSession.resize(name, {cols, rows})` — pty_resize call
- `PaneSession` monitors any caller that registers itself as an output listener; pushes `{:pty_output, bytes}` to listeners
- `Babs.CitizenSupervisor.start_link(name)` — `:rest_for_one` strategy with `Citizen.Server` + `PaneSession` as children

### Out of scope for Phase 1

- Connectors (Discord, Telegram) — Phase 3
- A2A (Router, HttpEndpoint) — Phase 2
- Web (BabsWeb.*) — Phase 4
- TranscriptTailer — Phase 2 (needs a real citizen with a real transcript file)
- ChannelWorker — Phase 3
- SQLite registry — Phase 2
- Citizen.Server's full lifecycle / mailbox — Phase 2 makes it real; Phase 1 is just a name+supervised marker

### Acceptance

Phase 1 is done when, in `iex -S mix`:

```elixir
# Op has manually started a tmux session named "test"
iex> Babs.start_citizen("test")
{:ok, _pid}

iex> Babs.Citizen.PaneSession.inject("test", "hello\n")
:ok

# bytes appear in the tmux pane (verified manually via tmux attach in another terminal)

iex> Babs.Citizen.PaneSession.subscribe_output("test", self())
:ok

iex> flush()
{:pty_output, "hello\n"}
:ok
```

And:

- Killing the PaneSession (`Process.exit(pid, :kill)`) → supervisor restarts it; the citizen is reachable again
- Killing the citizen subtree's `Citizen.Server` → supervisor restarts the whole subtree
- Test suite (`mix test`) passes for `Tmux.Core` and `PaneSession` core paths

### Implementation Plan

1. `mix new babs --sup`
2. Add deps: `:erlexec`, `:jason` (for Phase 2 prep)
3. Implement `Tmux.Core` thinly around erlexec
4. Implement `PaneSession` GenServer
5. Implement `Citizen.Server` stub (just registers a name, holds metadata)
6. Implement `CitizenSupervisor` with `:rest_for_one`
7. Wire `Babs.Application` to a `DynamicSupervisor` for `CitizenSupervisor` instances
8. Top-level `Babs.start_citizen/1` API
9. Tests: Tmux.Core attach/detach, PaneSession serialization (concurrent inject calls produce serialized output), subtree restart behavior

---

## Open Questions

- **Logging**: `Logger` defaults are fine for Phase 1; no structured logging until there's a dashboard to consume it. **Default**: stick with `Logger.info/warning/error` and revisit in Phase 4.
- **Config schema**: where do citizen names + tmux session names come from in Phase 1 (no SQLite yet)? **Default**: a hardcoded list in `config/dev.exs` for development; Phase 2 introduces SQLite-backed registry.
- **Method-A-vs-B branching**: does PaneSession's implementation include both code paths from the start, or only the one selected by Phase 0? **Default**: only the selected one. Building the unused path is YAGNI; the fallback decision is binary.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial draft | Claude Code |
