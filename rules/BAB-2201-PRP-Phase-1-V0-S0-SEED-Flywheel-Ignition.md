# PRP-2201: Phase 1 — V0-S0 SEED (Flywheel Ignition)

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Draft
**Replaces:** Earlier `BAB-2201` Phase 1 "Core Supervision Skeleton" (deleted; that scope assumed old 5-phase plan with Discord/Telegram)
**Depends on:** `BAB-2200` Phase 0 PRP (PTY + detach/reattach validated)
**Implements:** `BAB-1110` (β + γ live-reload-safe), `BAB-1112` (multi-CLI), `BAB-1107` (Babs owns tmux), `BAB-1106` (Channel re-registration)

---

## What Is It?

Phase 1 is the **flywheel ignition phase**. The smallest implementation of Babs that can host its own future development. Once Phase 1 passes acceptance, all subsequent phases (2-16) are implemented by AI Citizens running INSIDE Babs — the user never opens a terminal `claude code` session again to develop Babs.

**This is the only Phase after Phase 0 that is built manually outside of Babs.** Every later phase is built USING the Babs that Phase 1 produces.

---

## Problem

`BAB-2200` validates the PTY substrate. But validation alone doesn't ignite the flywheel — there must be a runnable Babs that:

1. Hosts a Citizen running an arbitrary AI CLI (`claude` / `codex` / `droid` / `pi` / `gh copilot`)
2. Renders the Citizen's terminal in a browser via xterm.js
3. Forwards keyboard input from the browser to the Citizen
4. Survives BabsWeb code reloads without killing the Citizen mid-task
5. Survives BEAM node restarts by reattaching to detached tmux sessions
6. Lets the Citizen edit Babs's own source code, commit, observe live reload, and continue working

If any one of these fails, the flywheel is broken.

---

## Proposed Solution

### Scope

A two-OTP-app Mix umbrella project rooted at `/Users/frank/Projects/babs/`:

```
babs/
├── mix.exs                              (umbrella root)
├── config/
│   ├── config.exs                       (shared)
│   ├── dev.exs
│   └── runtime.exs
├── apps/
│   ├── babs/                            (Phoenix web app — :babs)
│   │   ├── mix.exs                      (deps :babs_citizens via :in_umbrella)
│   │   ├── lib/babs/
│   │   │   ├── application.ex
│   │   │   ├── endpoint.ex
│   │   │   ├── live/
│   │   │   │   └── terminal_live.ex     (single LiveView per citizen)
│   │   │   └── channels/
│   │   │       └── pane_channel.ex      (subscribes pane:<name> via PubSub)
│   │   └── priv/static/
│   │       ├── js/xterm.js              (vendored)
│   │       └── js/xterm-addon-fit.js
│   └── babs_citizens/                   (citizen lifecycle — :babs_citizens)
│       ├── mix.exs
│       └── lib/babs_citizens/
│           ├── application.ex           (DynamicSupervisor + reattach scan on boot)
│           ├── citizen/
│           │   ├── lifecycle.ex         (start/stop/restart, owns tmux)
│           │   ├── config.ex            (parses citizen.toml)
│           │   └── supervisor.ex        (per-citizen subtree)
│           └── hardline/
│               └── pane.ex              (erlexec port + PubSub publisher)
├── alex.bob/                            (default seed citizen)
│   └── citizen.toml                     (cli = "claude", env = ANTHROPIC_API_KEY, ...)
└── ...
```

### Key Design Decisions (each links to its ADR)

1. **Two OTP apps** (β): `:babs` reload doesn't touch `:babs_citizens` → citizens survive. See `BAB-1110`.
2. **Tmux detach + reattach** (γ): All sessions `tmux new-session -d`; on `:babs_citizens` startup, reattach existing `babs-*` sessions. See `BAB-1110`.
3. **Multi-CLI agnostic**: `citizen.toml` declares `cli`, `cli_args`, `env`. `claude`, `codex`, `droid`, `pi`, `gh copilot` all supported day-1 via TOML. See `BAB-1112`.
4. **Babs owns tmux lifecycle**: Babs creates / destroys / reattaches; sessions prefixed `babs-`. See `BAB-1107`.
5. **Hardline.Pane publishes to PubSub**, holds NO Channel PIDs: Channels die on `:babs` reload but PubSub topic survives; Channels re-subscribe on reconnect. See `BAB-1106` revision.
6. **Restricted keyboard set**: printable + Enter + Tab + Ctrl+C/D/Z + arrows + paste. Full fn/cmd combos deferred to Phase 5 polish.

### Spawn Flow (programmatic only in Phase 1; UI in Phase 4)

```elixir
# Phase 1: hardcoded boot of seed citizen "alex" from config.exs
# (no UI spawn; Phase 4 will add NewCitizenLive)

defmodule Babs.Citizens.Application do
  def start(_, _) do
    Supervisor.start_link([
      {Phoenix.PubSub, name: BabsCitizens.PubSub},
      {Babs.Citizens.DynamicSupervisor, []},
      {Babs.Citizens.ReattachScanner, []}
    ], strategy: :one_for_one)
  end
end

defmodule Babs.Citizens.ReattachScanner do
  # On boot:
  # 1. Run `tmux ls` to list sessions; filter `^babs-(.+)$`
  # 2. For each, look up SQLite citizens row (or fall back to citizen.toml)
  # 3. Call Lifecycle.reattach(name) — opens fresh erlexec port to existing session
  # 4. If no sessions exist, read seed_citizens config and spawn defaults
end
```

### The Flywheel Test (acceptance gate)

Phase 1 is **NOT done** until both gates below pass.

**Gate A — Scripted Sentinel Reload Test** (objective, machine-verifiable):

> 1. Start Babs (`mix phx.server`); confirm two seed citizens (`alex` running `claude`, `morgan` running `codex`) reach interactive prompt within 10s
> 2. Inject a sentinel byte sequence into alex's hardline (e.g., `echo "BEFORE_RELOAD_$(date +%s)"`)
> 3. Touch (no-op modify) `apps/babs_citizens/lib/babs_citizens/hardline/pane.ex` to trigger `Babs.Citizens.SourceWatcher` (per `BAB-1110`) → triggers `Application.stop(:babs_citizens)` + `Application.start(:babs_citizens)`
> 4. Wait for ReattachScanner completion (≤5s)
> 5. Inject another sentinel (`echo "AFTER_RELOAD_$(date +%s)"`)
> 6. **PASS** if both sentinels appear in alex's xterm.js view; tmux session ID unchanged; AI CLI process PID unchanged (verify via `tmux list-panes -t babs-alex -F '#{pane_pid}'`)
> 7. **FAIL** if any sentinel is lost, tmux session ID changes, or AI CLI PID changes

**Gate B — Dogfood Flywheel Test** (subjective, AI-competence-bounded):

> 1. With Babs running and Gate A passing, **close all terminal windows**. From this moment, the user is in browser only.
> 2. In alex's terminal (xterm.js in browser), give alex the prompt: "Implement Phase 2 (transcript JSONL persistence) per `BAB-2300`. Edit `apps/babs_citizens/lib/babs_citizens/hardline/pane.ex` to write each PTY byte to `<cwd>/<name>.bob/transcript.jsonl`. Commit when done."
> 3. Watch alex work entirely in browser.
> 4. **PASS** if alex makes the edits, `Babs.Citizens.SourceWatcher` triggers reload, alex survives the reload (per Gate A semantics), alex completes the work without context loss, alex `git commit`s the change.
> 5. **FAIL** if alex dies, or if Gate A semantics fail mid-task.

**Both gates must pass**. Gate A isolates the infrastructure question (does β+γ + SourceWatcher actually work?); Gate B confirms the integrated system is usable end-to-end. If Gate A fails, debug infra without burning AI-CLI tokens. If Gate A passes but Gate B fails, the issue is AI competence or higher-level UX, not the substrate.

### Implementation Plan (sequenced — dependency-correct)

> Reordered after Trinity 2nd-round review: TOML parsing must precede Citizen.Lifecycle (which reads `citizen.toml`); SQLite is Phase 3, so Phase 1 reads citizen.toml directly without DB.

1. **Day 1-2: Mix umbrella scaffold** — `mix new --umbrella`; create `:babs` and `:babs_citizens` apps; verify `mix phx.server` starts both; confirm Phoenix `live_reload` config watches ONLY `apps/babs/lib/**`
2. **Day 2-3: Citizen config — TOML parser** — read `<name>.bob/citizen.toml`; resolve `[env]` interpolations from BEAM node env; validate required fields (`name`, `cli`); produce `%CitizenConfig{}` struct. Required by Day 3-4 below.
3. **Day 3-4: Hardline.Pane (`:babs_citizens`)** — port erlexec port + PubSub publishing logic from Phase 0 spike (`spikes/hardline/`); chunk PubSub publishes to ≤4KB per `BAB-1106`; add input injection method
4. **Day 4-5: Citizen.Lifecycle (`:babs_citizens`)** — `start_citizen(config)` takes `%CitizenConfig{}` (from Day 2-3), creates detached tmux session `babs-<name>`, opens erlexec port with `[env]` injected, spawns Hardline.Pane; `stop_citizen(name)` polite TERM + `tmux kill-session -t babs-<name>`; `restart_citizen(name)` = stop + start
5. **Day 5-6: ReattachScanner (`:babs_citizens`)** — boot-time `tmux ls` + filter `^babs-(.+)$` + read `<name>.bob/citizen.toml` for each (NO SQLite in v0.1 / Phase 1); call `Lifecycle.reattach(config)` for each; write `:reattached` event to in-memory log (Phase 2 adds JSONL); **must complete before DynamicSupervisor accepts spawns** (race fix per Trinity 2nd-round review)
6. **Day 6-7: SourceWatcher (`:babs_citizens`)** — FileSystem watcher on `apps/babs_citizens/lib/**/*.ex`; on change → `mix compile` :babs_citizens → if success, `Application.stop` + `start`; per `BAB-1110` reload mechanism. **Required for Flywheel Gate A.**
7. **Day 7-9: BabsWeb (`:babs`)** — Phoenix endpoint; `TerminalLive` mounts xterm.js; `PaneChannel` subscribes `pane:<name>` PubSub; bytes pushed to xterm.js
8. **Day 9-11: Keyboard forwarding** — xterm.js `onData` → Channel `push` → Hardline.Pane `inject`; restrict to essential keys (printable / Enter / Tab / Ctrl+C/D/Z / arrows / paste); test `Ctrl+C` specifically (erlexec gotcha — buffer 3-5 days here per Trinity findings)
9. **Day 11-13: Live-reload Channel re-registration** — verify `:babs` reload kills Channels but `:babs_citizens` stays; browser auto-reconnects; new Channel re-subscribes PubSub; xterm.js sees flicker only
10. **Day 13-14: Multi-CLI verification** — boot two seed citizens (`alex` running `claude`, `morgan` running `codex`) from `citizens/{alex,morgan}.bob/citizen.toml`; verify both reach interactive prompt; verify env var interpolation correctly injected per-citizen
11. **Day 14-21: Flywheel test (Gates A + B) + bug fixes** — run scripted Gate A first; once green, run dogfood Gate B; iterate on whatever breaks. Both gates must pass.

### Acceptance Criteria

This PRP is "done" when ALL of the following hold:

- [ ] `mix phx.server` starts cleanly with both apps in supervision tree
- [ ] Two seed citizens (`alex` running `claude`, `morgan` running `codex`) boot with valid env vars and reach an interactive prompt within 10s
- [ ] Browser at `http://localhost:4000/citizens/alex` renders alex's terminal; keyboard input reaches AI CLI; AI output renders in xterm.js with correct ANSI colors
- [ ] Editing a file in `apps/babs/lib/` triggers `:babs` reload; alex's xterm.js Channel briefly disconnects then reconnects (≤2s); alex's session is intact (no bytes lost from AI CLI's perspective)
- [ ] Editing a file in `apps/babs_citizens/lib/` triggers `:babs_citizens` reload; alex's tmux session survives (γ); Hardline.Pane respawns; alex's AI CLI continues; brief blindness window ≤5s; **acceptable per `BAB-1110`**
- [ ] Killing the entire BEAM node (Ctrl+C twice in `mix phx.server`); restart `mix phx.server`; ReattachScanner finds existing tmux sessions; alex/morgan reappear in browser without losing AI CLI state
- [ ] **The Flywheel Test passes** (alex implements Phase 2 entirely from browser)

### Output

A CHG entry on this PRP recording flywheel-test pass + a short writeup of any deviations. Phase 2 begins immediately after.

---

## Open Questions

- **Should `morgan` be in default seed citizens?** Default: yes — having two CLIs in seed validates multi-CLI works at SEED time, not deferred.
- **Channel reconnect "flicker" UX** — is the brief disconnect on `:babs` reload acceptable to operator? Default: yes, ≤2s tolerable; UI shows "reconnecting…" badge.
- **Where does `<name>.bob/transcript.jsonl` live?** — In Phase 1, it doesn't exist (Phase 2 adds it). Phase 1 transcripts are in-memory only.
- **What if Phase 0's detach/reattach validation fails?** — Phase 1 cannot start. Hardline ADR `BAB-1103` would need to switch to Method B (polling fallback), and this PRP rewrites accordingly.

---

## Risks (per Trinity Review `BAB-1006`)

1. **Underestimated keyboard fidelity work**: Ctrl+C alone can burn 3-5 days because erlexec may interpret it as a signal vs forward as bytes. Buffer ~3 days in Day 9-11.
2. **Channel PID staleness on `:babs` reload**: Hardline.Pane MUST publish to PubSub (no PID holding) — verify in code review before flywheel test.
3. **Multi-CLI auth**: `gh copilot` requires `gh auth login` state, not env var; Phase 1 may exclude `gh copilot` if auth handling slips. Acceptable.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial draft (replaces deleted old `BAB-2201`); incorporates β + γ + multi-CLI + flywheel test | Claude Code |
| 2026-05-03 | Trinity 2nd-round fixes: split Flywheel Test into Gate A (scripted sentinel) + Gate B (dogfood); reordered Implementation Plan so TOML parsing (Day 2-3) precedes Citizen.Lifecycle (Day 4-5); removed Phase 1 SQLite reference (Phase 1 reads citizen.toml only); added SourceWatcher day (per `BAB-1110` reload mechanism); fixed ReattachScanner-vs-DynamicSupervisor race; added 4KB PubSub chunk constraint reference; clarified two-seed-citizens (alex+morgan) as v0.1 validation requirement | Claude Code |
