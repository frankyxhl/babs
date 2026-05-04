# ADR-1110: Two OTP Applications + Tmux Detach (β + γ Live-Reload-Safe Lifecycle)

**Applies to:** BAB project
**Last updated:** 2026-05-04
**Last reviewed:** 2026-05-04
**Status:** Accepted
**Sources:** `BAB-1006` (Trinity Review), v0.1 design session 2026-05-03

---

## Context

Babs is designed to **bootstrap itself** — once Phase 1 SEED is alive, every subsequent feature is implemented by an AI Citizen running INSIDE Babs (the "flywheel"). For this to work, the Citizen must be able to edit Babs's source code, trigger a reload, and remain alive throughout.

Phoenix's standard live reload restarts the entire OTP application. If `Citizen` processes are supervised inside the same OTP application as the Phoenix endpoint, **the Citizen modifying the code is killed when its modification reloads the app**. This breaks the flywheel.

Trinity review (`BAB-1006`) confirmed this is a real chicken-and-egg, not a theoretical concern. The fix requires **two layers of isolation**: OTP supervision-level (independent application) AND OS process-level (tmux session that survives BEAM restart).

## Decision

**Adopt β + γ together.**

### β (OTP application separation)

Babs ships as **two OTP applications** in one mix project:

| App | Owns | Reloads when? |
|-----|------|---------------|
| `:babs` | Phoenix Endpoint, LiveView, Channels, BabsWeb routing, BusView UI | On any web/UI code change |
| `:babs_citizens` | DynamicSupervisor for Citizen subtrees, `Hardline.Pane` GenServers, tmux session ownership, Ticket file watcher, persistence | Only on citizen-lifecycle code change (rare) |

Live reload triggered by editing UI code reloads `:babs` only; `:babs_citizens` keeps running. Citizens stay alive.

### γ (tmux detach + reattach)

All tmux sessions are created **detached** (`tmux new-session -d`). The AI CLI runs inside tmux; tmux itself runs as an OS process outside the BEAM node.

- BEAM crash or `:babs_citizens` reload → tmux session continues running, AI CLI continues working
- On `:babs_citizens` startup, scan `tmux ls` for `babs-` prefixed sessions; for each, open a fresh `erlexec` port that attaches and resumes `Hardline.Pane`
- Reattach is byte-loss-free if Phase 0 spike validation passes

### Why both, not one or the other

| Failure mode | β alone | γ alone | β + γ |
|--------------|---------|---------|-------|
| UI code edit reloads `:babs` | ✅ Citizens survive | ✅ Citizens survive | ✅ |
| `:babs_citizens` code edit reloads it | ❌ Citizens die mid-task (chicken-and-egg) | ✅ tmux survives, BEAM-side proxy reattaches | ✅ tmux survives, reattach is fast |
| Whole BEAM node crashes | ❌ Everything dies | ✅ tmux survives, manual restart of BEAM rebinds | ✅ tmux survives, BEAM auto-rebinds on restart |
| Operator wants to manually attach to inspect | Possible but fragile | ✅ tmux is OS-native | ✅ |

β alone fails the chicken-and-egg case. γ alone fails the OTP-supervision-cleanliness goal. Together they cover everything.

## Implementation

### Mix project structure

```
babs/
├── mix.exs                    (umbrella OR path-based deps; both apps live in apps/)
├── apps/
│   ├── babs/                  (Phoenix web app)
│   │   ├── mix.exs            (deps on :babs_citizens via {:in_umbrella, true} or path)
│   │   └── lib/babs/
│   └── babs_citizens/         (citizen lifecycle app)
│       ├── mix.exs            (no dep on :babs)
│       └── lib/babs_citizens/
└── ...
```

Choice: **Umbrella project** — Mix's first-class support for two apps in one repo with shared `_build`, shared `deps`. Path-deps would also work but add config friction.

### Reattach protocol (γ)

On `:babs_citizens` `Application.start/2`:

1. List all tmux sessions matching `^babs-(.+)$`
2. For Phase 1, derive `<slug>` from the session name and read `citizens/citizen-<slug>.toml` directly. SQLite lookup starts in Phase 3.
3. If a matching config exists:
   - Open `erlexec` port that runs `tmux attach-session -t babs-<slug>` (or `pipe-pane` — see Phase 0 spike for which works)
   - Spawn fresh `Hardline.Pane` GenServer with the new port
   - Publish received bytes to PubSub topic `pane:<slug>` for browser Channel reconnection
4. Record a `:reattached` event in the Phase 1 in-memory lifecycle log. Phase 2 appends it to `<cwd>/transcript.jsonl`; Phase 3 also updates SQLite state.

### Channel re-registration (cross-cutting concern)

When `:babs` reloads, all Channel processes die. `Hardline.Pane` (in `:babs_citizens`) holds no PIDs to dead Channels — instead it publishes bytes to `Phoenix.PubSub` topic `pane:<slug>`.

In Phase 1 the Phoenix Channel topic is also `pane:<slug>`. Phoenix already subscribes the joined Channel process to its topic, so the Channel MUST NOT call `Phoenix.PubSub.subscribe/2` again for that same topic. Explicit PubSub subscription is only valid if a future design uses a distinct Channel topic and PubSub topic.

This decoupling is captured in the `BAB-1106` revision.

### Reload Mechanism (custom file watcher for `:babs_citizens`)

Phoenix's standard `live_reload` is **NOT** suitable for `:babs_citizens` because it works at the module level (recompile + reload modules in place) rather than at the OTP-application level (stop + start the supervision tree). Module reload of `Hardline.Pane` while it holds an open `erlexec` port is undefined behavior.

Babs ships a dev-only watcher process `Babs.DevReloader` (in `:babs`, outside the target app):

1. Watches `apps/babs_citizens/lib/**/*.ex` via [FileSystem](https://hex.pm/packages/file_system) (FSEvents on macOS, inotify on Linux)
2. On change: runs `mix compile` for `:babs_citizens` only
3. If compile succeeds: calls `Application.stop(:babs_citizens)` → wait until stopped → `Application.start(:babs_citizens)`
4. The stop+start cycle triggers γ — tmux sessions stay running; ReattachScanner re-acquires them on start
5. The brief BEAM-side blindness window (~3-5s) is documented as expected per the trade-offs section

`Babs.DevReloader` must live outside `:babs_citizens`; otherwise the watcher kills itself when it stops the target application.

**Phoenix `live_reload` watches ONLY `apps/babs/lib/**`** — leave it as-is for `:babs` (the web app); `Babs.DevReloader` handles `:babs_citizens` separately.

This watcher is part of the Phase 1 SEED scope (`BAB-2201`); without it, the Flywheel Test cannot pass.

## Consequences

- **Mix project setup is umbrella, not single app** — affects `mix.exs`, build commands (`mix phx.server` runs umbrella), test setup (each app has own test suite with shared helpers in `apps/_shared/` if needed).
- **Phase 0 spike must validate the detach + reattach scenario** — `BAB-2200` updated.
- **`Hardline.Pane` cannot hold Channel PIDs** — must publish to PubSub. `BAB-1106` updated.
- **`:babs_citizens` startup includes reattach scan** — adds 1-2s to BEAM startup but unavoidable.
- **Operator-facing: `mix phx.server` starts both apps** — no extra commands.
- **Live reload split**: Phoenix `live_reload` for `:babs` (modules); `Babs.DevReloader` for `:babs_citizens` (Application stop+start). See "Reload Mechanism" section above.
- **`:babs_citizens` reload is a detach+reattach cycle, not a kill** — each cycle is ~3-5s of BEAM-side blindness, but tmux + AI process + ticket files are unaffected. Only an explicit citizen `stop` may call `tmux kill-session`. This is the safety boundary that makes self-hosting Phase 2+ possible.

## Trade-offs Accepted

- **Slightly higher v0.1 setup cost** (~1 day) than single-app — accepted because it removes the chicken-and-egg permanently.
- **Two apps means two `Application` callbacks** — minor cognitive overhead but standard OTP idiom.
- **Citizen modifying `:babs_citizens` code is still complex** — the modifying citizen survives in tmux but is "blind" for the few seconds during BEAM proxy reattach. This is documented as expected behavior and is an acceptable price for the benefit.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial decision; β + γ adopted after Trinity review | Claude Code |
| 2026-05-03 | Trinity 2nd-round fix: added "Reload Mechanism" section specifying `Babs.Citizens.SourceWatcher` (custom FileSystem watcher → `Application.stop`/`start`); resolves contradiction between BAB-1110's "live_reload watches only `apps/babs/lib/**`" and BAB-2201 Flywheel Test requiring `:babs_citizens` reload | Claude Code |
| 2026-05-04 | Phase 1 cleanup: TOML config is read from `citizens/citizen-<slug>.toml` until SQLite starts in Phase 3; reload watcher moved to `Babs.DevReloader` in `:babs`; Channel/PubSub no-duplicate-subscribe rule and detach-vs-stop kill semantics clarified | Codex |
