# ADR-1100: Adopt Elixir + Phoenix

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Accepted

---

## What Is It?

The foundational decision of the Babs project: build the multi-agent runtime on **Elixir 1.19 / OTP 28 / Phoenix 1.8**, from scratch, freely using Hex packages.

---

## Context

Babs is a from-scratch project. It is informed by the design experience of `prefrontal-cortex` (a prior Python implementation of a similar concept) but inherits no code, no data, and no operational footprint. The decision is *which platform to build on*, not *what to migrate from*.

The runtime needs:

- **Per-citizen supervision** with isolated crash boundaries (one citizen's PTY death must not affect others)
- **Real-time bidirectional streams** at multiple scales: high-frequency PTY bytes (xterm.js terminal), medium-frequency state updates (dashboard), low-frequency A2A coordination
- **PTY interaction** with `tmux attach`-style sessions hosting AI CLIs
- **Cross-machine A2A** over a Tailscale mesh
- **Hot updates** to running citizens without dropping in-flight work
- **A web dashboard** that handles many independent state streams without imperative DOM management

The realistic platform candidates: Elixir/OTP, Go, Rust+tokio, Node.js, Python. Each was considered against the requirements above.

---

## Decision

1. **Build on Elixir 1.19 / OTP 28 / Phoenix 1.8.**
2. **Use Hex packages freely** where they replace work that would otherwise be hand-rolled. No "zero external dependency" rule.
3. **Initial dependency set** (decision-time): `phoenix`, `phoenix_live_view`, `bandit`, `ecto_sqlite3`, `erlexec` (PTY — see `BAB-1103`), `jason` for JSON, plus a Discord/Telegram client library or hand-rolled HTTP+JSON.
4. **Boundaries that remain hand-rolled**: the JSONL transcript parsing logic (because each AI CLI's schema is its own contract — see `BAB-1003`) and the project-specific A2A payload schema.
5. **Frontend**: Phoenix LiveView is the default (server-rendered state UI); React components embed via LiveView hooks for complex interactions; xterm.js handles browser terminal rendering. See `BAB-1106`.

---

## Consequences

**Positive:**

- BEAM supervision trees give per-citizen crash isolation natively
- Phoenix LiveView eliminates a whole category of frontend state-sync bugs
- Hot code reload on the BEAM enables in-place updates of running citizens
- Native distributed primitives (Registry, PubSub, `:pg`) for intra-node coordination
- A2A over Erlang processes is microseconds, not network round-trips

**Negative:**

- Elixir is less ubiquitous than Python or JavaScript — onboarding cost
- C++ toolchain required for `erlexec` build (Xcode CLI tools / build-essential)
- BEAM, OTP, Phoenix all need to be installed and managed (asdf or Homebrew)

---

## Rejected Alternatives

### Alt 1 — Python (with modern stacks: aiohttp, FastAPI, Celery)

Mature ecosystem, ubiquitous in AI tooling.

**Rejected because:** the underlying concurrency model (CPython threads + GIL) doesn't give per-citizen supervision without running multiple processes with manual restart logic. Per-pane crash isolation under load is the architectural backbone of this system, and Python forces it to be hand-rolled at the OS-process level.

### Alt 2 — Go or Rust + tokio

Goroutines / async tasks; mature web stacks (`echo`/`gin` for Go, `axum`/`actix` for Rust).

**Rejected because:** neither offers BEAM's per-process supervision-tree-with-restart-strategies, hot code reload, or native distribution. The specific concurrency model that fits "many independent citizens, each with its own crash boundary, hot-upgradable" is OTP. Choosing Go or Rust would mean choosing a more popular ecosystem at the cost of the runtime model that's the actual reason to pick a platform.

### Alt 3 — Node.js / TypeScript backend

Single language across frontend and backend; good async I/O.

**Rejected because:** single-threaded event loop without process supervision. Worker threads are coarse and not a substitute for BEAM processes. The unhandled-exception story (whole process dies) doesn't compose with "many independent citizens".

### Alt 4 — Elixir but stdlib-only (no Phoenix, no Hex deps)

Skip Phoenix and write Channels / LiveView equivalents directly on `:gen_tcp` / `:cowboy`.

**Rejected because:** the entire reason Phoenix exists is to avoid hand-rolling those layers. Reproducing Phoenix in stdlib Elixir would create the same maintenance burden we're explicitly choosing the BEAM ecosystem to avoid.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial version — captures the from-scratch platform decision | Claude Code |
