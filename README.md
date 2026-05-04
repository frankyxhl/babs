<p align="center">
  <h1 align="center">Babs</h1>
  <p align="center"><strong>Multi-Agent Communications & Coordination Hub</strong></p>
</p>

---

## What is Babs?

Babs is a multi-agent runtime that hosts citizens, relays messages across Web/tmux first and later Discord/Telegram, and coordinates agent work on a single BEAM node or across a Tailscale mesh. Phase 1 uses `citizens/citizen-<slug>.toml` for seed configuration and `workspaces/<slug>/` for working files; the earlier `*.bob/` directory convention is legacy/deferred.

Built from scratch on Elixir 1.19 / OTP 28 / Phoenix 1.8, with `erlexec` for PTY, LiveView for state UI (with React for complex widgets), and xterm.js for browser terminal rendering.

## Babs and Alfred

Babs pairs with [Alfred](https://github.com/frankyxhl/alfred) (`af`) — the same ecosystem for AI agent operations:

- **Alfred (`af`)** — per-agent runbook: SOPs, workflow checklists, document lifecycle
- **Babs (`bb`)** — multi-agent runtime: citizen lifecycle, message relay, A2A coordination

Both are named after Bat-Family support roles. Alfred Pennyworth keeps the runbook for one Batman; Babs (Barbara Gordon) coordinates the whole Bat-Family from her clocktower. The phonetic resonance with the legacy `*.bob/` idea remains part of the naming history, but it is not the Phase 1 runtime layout.

## Status

Pre-development. Architecture and design decisions live in `rules/` (Alfred PRJ documents, prefix `BAB`).

```bash
af list --root .                  # list all BAB documents
af read BAB-1001                  # Architecture Overview
af guide --root .                 # workflow routing
```

## License

TBD
