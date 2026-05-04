# PRP-2201: Phase 1 — V0-S0 SEED (Flywheel Ignition)

**Applies to:** BAB project
**Last updated:** 2026-05-04
**Last reviewed:** 2026-05-04
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
│   │   │   ├── dev_reloader.ex          (dev-only restarts :babs_citizens)
│   │   │   ├── endpoint.ex
│   │   │   ├── live/
│   │   │   │   └── terminal_live.ex     (single LiveView per citizen)
│   │   │   └── channels/
│   │   │       └── pane_channel.ex      (joins pane:<slug>; no duplicate subscribe)
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
├── citizens/
│   ├── citizen-clare.toml               (cli = "claude", env = ANTHROPIC_API_KEY, ...)
│   ├── citizen-dylan.toml               (cli = "codex", env = OPENAI_API_KEY, ...)
│   └── citizen-sentinel.toml            (cli = "/bin/zsh", used by Gate A)
├── workspaces/
│   ├── clare/
│   ├── dylan/
│   └── sentinel/
└── ...
```

### Key Design Decisions (each links to its ADR)

1. **Two OTP apps** (β): `:babs` reload doesn't touch `:babs_citizens` → citizens survive. See `BAB-1110`.
2. **Tmux detach + reattach** (γ): All sessions `tmux new-session -d`; on `:babs_citizens` startup, reattach existing `babs-*` sessions. See `BAB-1110`.
3. **Multi-CLI agnostic**: `citizens/citizen-<slug>.toml` declares `id`, `slug`, `cli`, `cli_args`, `cwd`, and `env`. `claude`, `codex`, `droid`, `pi`, `gh copilot` all supported day-1 via TOML. See `BAB-1112`.
4. **Babs owns tmux lifecycle**: Babs creates / destroys / reattaches; sessions prefixed `babs-`. See `BAB-1107`.
5. **Hardline.Pane publishes to PubSub**, holds NO Channel PIDs: Channels die on `:babs` reload but PubSub topic survives. In Phase 1, Channel join topic and PubSub topic are both `pane:<slug>`; Phoenix already subscribes the joined Channel process to that topic, so the Channel MUST NOT call `Phoenix.PubSub.subscribe/2` again. See `BAB-1106` revision.
6. **Restricted keyboard set**: printable + Enter + Tab + Ctrl+C/D/Z + arrows + paste. Full fn/cmd combos deferred to Phase 5 polish.
7. **Reload is detach-only**: `:babs_citizens` reload or BEAM restart detaches erlexec ports but never kills tmux. Only explicit `stop_citizen/1` may call `tmux kill-session`.
8. **Gate A uses a synthetic sentinel citizen**: infrastructure reload/reattach is validated with deterministic `/bin/zsh`, not with an AI CLI whose behavior can confound the result.

### Spawn Flow (programmatic only in Phase 1; UI in Phase 4)

```elixir
# Phase 1: hardcoded boot of seed citizens from citizens/*.toml
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
  # 2. For Phase 1, read citizens/citizen-<slug>.toml directly (NO SQLite yet)
  # 3. Call Lifecycle.reattach(config) — opens fresh erlexec port to existing session
  # 4. If no sessions exist, read default seed configs and spawn them
end
```

### The Flywheel Test (acceptance gate)

Phase 1 is **NOT done** until both gates below pass.

**Gate A — Scripted Sentinel Reload Test** (objective, machine-verifiable):

Gate A is run by a repeatable task:

```sh
mix babs.gate_a
```

The task uses `citizens/citizen-sentinel.toml` (`cli = "/bin/zsh"`) so the
reload test is deterministic and not affected by AI CLI behavior.

> 1. Start Babs (`mix phx.server`); confirm the sentinel citizen reaches a zsh prompt within 10s
> 2. Capture `tmux` session ID and pane PID for `babs-sentinel`
> 3. Inject a split sentinel byte sequence into sentinel's hardline, e.g. `printf 'BEFORE_RELOAD_'; date +%s`
> 4. Touch (no-op modify) `apps/babs_citizens/lib/babs_citizens/hardline/pane.ex` to trigger `Babs.DevReloader` (per `BAB-1110`) → compile `:babs_citizens`, stop it, then start it
> 5. Wait for ReattachScanner completion (≤5s)
> 6. Inject another split sentinel, e.g. `printf 'AFTER_RELOAD_'; date +%s`
> 7. **PASS** if both sentinels appear in sentinel's xterm.js view; tmux session ID unchanged; pane PID unchanged (verify via `tmux display-message -p -t babs-sentinel '#{session_id}'` and `tmux list-panes -t babs-sentinel -F '#{pane_pid}'`)
> 8. **FAIL** if any sentinel is lost, tmux session ID changes, pane PID changes, reattach takes >5s, or tmux is killed

**Gate B — Dogfood Flywheel Test** (subjective, AI-competence-bounded):

> 1. With Babs running and Gate A passing, **close all terminal windows**. From this moment, the user is in browser only.
> 2. In clare's terminal (xterm.js in browser), give clare the prompt: "Implement Phase 2 (transcript JSONL persistence) per `BAB-2300`. Edit `apps/babs_citizens/lib/babs_citizens/hardline/pane.ex` to write each PTY byte to `<cwd>/transcript.jsonl`. Commit when done."
> 3. Watch clare work entirely in browser.
> 4. **PASS** if clare makes the edits, `Babs.DevReloader` triggers reload, clare survives the reload (per Gate A semantics), clare completes the work without context loss, clare `git commit`s the change.
> 5. **FAIL** if clare dies, or if Gate A semantics fail mid-task.

**Both gates must pass**. Gate A isolates the infrastructure question (does β+γ + `Babs.DevReloader` actually work?); Gate B confirms the integrated system is usable end-to-end. If Gate A fails, debug infra without burning AI-CLI tokens. If Gate A passes but Gate B fails, the issue is AI competence or higher-level UX, not the substrate.

### Implementation Plan (sequenced — dependency-correct)

> Reordered after Trinity 2nd-round review and Phase 0 hardening: TOML parsing must precede Citizen.Lifecycle (which reads `citizens/citizen-<slug>.toml`); SQLite is Phase 3, so Phase 1 reads TOML directly without DB.

1. **Day 1-2: Mix umbrella scaffold** — `mix new --umbrella`; create `:babs` and `:babs_citizens` apps; verify `mix phx.server` starts both; confirm Phoenix `live_reload` config watches ONLY `apps/babs/lib/**`
2. **Day 2-3: Citizen config — TOML parser** — read `citizens/citizen-<slug>.toml`; resolve `[env]` interpolations from BEAM node env; validate required fields (`id`, `slug`, `cli`, `cwd`); produce `%CitizenConfig{}` struct. Required by Day 3-4 below.
3. **Day 3-4: Hardline.Pane (`:babs_citizens`)** — port erlexec port + PubSub publishing logic from Phase 0 spike (`spikes/hardline/`); chunk PubSub publishes to ≤4KB per `BAB-1106`; add input injection method
4. **Day 4-5: Citizen.Lifecycle (`:babs_citizens`)** — `start_citizen(config)` takes `%CitizenConfig{}` (from Day 2-3), creates detached tmux session `babs-<slug>`, opens erlexec port with `[env]` injected, spawns Hardline.Pane; `stop_citizen(slug)` is the only path that kills tmux; reload / BEAM restart only detaches erlexec and reattaches
5. **Day 5-6: ReattachScanner (`:babs_citizens`)** — boot-time `tmux ls` + filter `^babs-(.+)$` + read `citizens/citizen-<slug>.toml` for each (NO SQLite in Phase 1); call `Lifecycle.reattach(config)` for each; write `:reattached` event to in-memory log (Phase 2 adds JSONL); **must complete before DynamicSupervisor accepts spawns** (race fix per Trinity 2nd-round review)
6. **Day 6-7: DevReloader (`:babs`)** — dev-only FileSystem watcher on `apps/babs_citizens/lib/**/*.ex`; debounce changes; run `mix compile` for `:babs_citizens`; if success, `Application.stop(:babs_citizens)` then `Application.start(:babs_citizens)`. This process lives outside `:babs_citizens`, so it survives the stop/start cycle. **Required for Flywheel Gate A.**
7. **Day 7-9: BabsWeb (`:babs`)** — Phoenix endpoint; `TerminalLive` mounts xterm.js + FitAddon; `PaneChannel` joins `pane:<slug>`; because the Channel topic equals the PubSub topic, do not call `Phoenix.PubSub.subscribe/2` manually; bytes pushed to xterm.js
8. **Day 9-11: Keyboard forwarding** — xterm.js `onData` → Channel `push` → Hardline.Pane `inject`; restrict to essential keys (printable / Enter / Tab / Ctrl+C/D/Z / arrows / paste); test `Ctrl+C` specifically (erlexec gotcha — buffer 3-5 days here per Trinity findings)
9. **Day 11-13: Live-reload Channel re-registration** — verify `:babs` reload kills Channels but `:babs_citizens` stays; browser auto-reconnects; new Channel rejoins `pane:<slug>`; xterm.js sees flicker only
10. **Day 13-14: Multi-CLI verification** — boot two seed citizens (`clare` running `claude`, `dylan` running `codex`) from `citizens/citizen-clare.toml` and `citizens/citizen-dylan.toml`; verify both reach interactive prompt; verify env var interpolation correctly injected per-citizen
11. **Day 14-21: Flywheel test (Gates A + B) + bug fixes** — run scripted Gate A first; once green, run dogfood Gate B; iterate on whatever breaks. Both gates must pass.

### Acceptance Criteria

This PRP is "done" when ALL of the following hold:

- [ ] `mix phx.server` starts cleanly with both apps in supervision tree
- [ ] Three Phase 1 configs exist: `citizens/citizen-sentinel.toml`, `citizens/citizen-clare.toml`, and `citizens/citizen-dylan.toml`
- [ ] Two seed citizens (`clare` running `claude`, `dylan` running `codex`) boot with valid env vars and reach an interactive prompt within 10s
- [ ] Browser at `http://localhost:4000/citizens/clare` renders clare's terminal; keyboard input reaches AI CLI; AI output renders in xterm.js with correct ANSI colors
- [ ] Editing a file in `apps/babs/lib/` triggers `:babs` reload; clare's xterm.js Channel briefly disconnects then reconnects (≤2s); clare's session is intact (no bytes lost from AI CLI's perspective)
- [ ] Editing a file in `apps/babs_citizens/lib/` triggers `Babs.DevReloader`; `:babs_citizens` restarts; clare's tmux session survives (γ); Hardline.Pane respawns; clare's AI CLI continues; brief blindness window ≤5s; **acceptable per `BAB-1110`**
- [ ] Killing the entire BEAM node (Ctrl+C twice in `mix phx.server`); restart `mix phx.server`; ReattachScanner finds existing tmux sessions; clare/dylan reappear in browser without losing AI CLI state
- [ ] `mix babs.gate_a` passes against sentinel
- [ ] **The Flywheel Test passes** (clare implements Phase 2 entirely from browser)

### Output

A CHG entry on this PRP recording flywheel-test pass + a short writeup of any deviations. Phase 2 begins immediately after.

---

## Open Questions

- **Channel reconnect "flicker" UX** — is the brief disconnect on `:babs` reload acceptable to operator? Default: yes, ≤2s tolerable; UI shows "reconnecting…" badge.
- **Where does `transcript.jsonl` live?** — In Phase 1, it doesn't exist (Phase 2 adds it). Phase 1 transcripts are in-memory only. Phase 2 should write to the citizen's configured `cwd` (for example `workspaces/clare/transcript.jsonl`).
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
| 2026-05-03 | Trinity 2nd-round fixes: split Flywheel Test into Gate A (scripted sentinel) + Gate B (dogfood); reordered Implementation Plan so TOML parsing (Day 2-3) precedes Citizen.Lifecycle (Day 4-5); removed Phase 1 SQLite reference (Phase 1 reads citizen.toml only); added reload watcher day (per `BAB-1110` reload mechanism); fixed ReattachScanner-vs-DynamicSupervisor race; added 4KB PubSub chunk constraint reference; clarified two-seed-citizens as v0.1 validation requirement | Claude Code |
| 2026-05-04 | Phase 1 pre-implementation cleanup: replace alex/morgan with clare/dylan; add synthetic sentinel Gate A; move citizen config to `citizens/citizen-<slug>.toml`; move reload watcher out of `:babs_citizens` as `Babs.DevReloader`; clarify Channel/PubSub no-duplicate-subscribe rule; clarify reload detach-vs-stop kill semantics | Codex |
