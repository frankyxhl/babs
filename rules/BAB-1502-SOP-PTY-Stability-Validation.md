# SOP-1502: PTY Stability Validation (Phase 0 Spike)

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Active (Amended for v0.1)
**Depends on:** BAB-1103 (PTY method choice; Method A primary, Method B fallback), BAB-1110 (β + γ live-reload-safety)
**Gates:** Phase 1 implementation (`BAB-2201` Phase 1 SEED Flywheel Ignition)
**Spike location:** `/Users/frank/Projects/babs/spikes/hardline/` (sub-mix-project inside the babs repo, per `BAB-2200` D8 amendment)

---

## What Is It?

The empirical pre-flight check that decides whether Babs can use **erlexec PTY attach (Method A)** as the citizen-pane substrate, or whether it must fall back to **`tmux send-keys` + `capture-pane` polling (Method B)**. Run before any production Babs Elixir code is written. Result is a binary: A passes, or A fails and B becomes mandatory.

---

## Why

`BAB-1103` accepts erlexec-PTY-attach as the primary method but explicitly identifies one production-blocking risk: an erlexec port crash may propagate into the attached tmux session and kill the AI CLI inside it. We do not know empirically whether this happens on our actual hardware, OS, tmux version, and AI CLI mix. Building Phase 1+ on Method A and discovering this risk in production would mean re-architecting the citizen subtree mid-build. The cheap fix is to find out now.

---

## When to Use

- Before writing any production Babs Elixir code (including Phase 1 Dashboard)
- Whenever the underlying erlexec, tmux, OTP, or macOS version changes by a major release
- Whenever a production incident suggests the failure mode this SOP was designed to detect

## When NOT to Use

- Routine erlexec version bumps within the same major version (rely on the existing pass)
- Validating Method B (Method B is `tmux send-keys` + `capture-pane` polling — well-understood as a tmux primitive; no spike needed)

---

## Test Setup

A self-contained sub-mix-project at `/Users/frank/Projects/babs/spikes/hardline/` (inside the babs repo, isolated from the future main `:babs` umbrella per `BAB-1110`) with the minimum dependency set:

```
mix.exs:
  deps: [
    {:erlexec, "~> 2.2"},          # NOTE: "~> 2.3" does NOT exist on Hex; use ~> 2.2
    {:phoenix, "~> 1.8"},          # for Hardline.Web (Channel + xterm.js validation, BAB-1106)
    {:phoenix_live_view, "~> 1.0"} # optional, only if testing LiveView reattach UX
  ]

lib/hardline/runner.ex:
  - Hardline.Runner.start/1     spawns N tmux sessions with a long-running command (e.g. `bash -c "while true; do echo tick; sleep 1; done"`)
  - Hardline.Runner.attach/1    erlexec PTY attach to each session
lib/hardline/chaos.ex:
  - Hardline.Chaos.run/2        kills the erlexec port at random intervals (next section)
lib/hardline/observer.ex:
  - Hardline.Observer.start/1   records timestamps of: port crash, tmux session death, AI-CLI-equivalent process death
lib/hardline/scenarios.ex:
  - Hardline.Scenarios.resize_storm/0
  - Hardline.Scenarios.slow_reader/0
  - Hardline.Scenarios.detach_reattach/0   (per BAB-1110, BAB-2200 step 7)
lib/hardline/web/                          (BAB-1106 Channel→xterm.js validation)
priv/static/index.html                     (xterm.js page for byte-path test)
```

The "AI CLI equivalent" can be a real Claude/Codex CLI in interactive mode if available, or a long-running bash loop with stdin/stdout interactions for cheaper iteration. Both must be exercised; reality may differ from the synthetic case.

---

## Steps

1. **Set up the test harness.** Create `spikes/hardline/` (inside the babs repo) with the structure above. `mix deps.get && mix compile` to confirm erlexec builds on the target machine. If the C++ build fails, log the toolchain delta and stop — no point testing further.

2. **Provision the test fleet.** Start `N = 5` tmux sessions, each running the long-running command. For each, start an erlexec PTY attach. Confirm bidirectional bytes (write something to the PTY and read it back through capture).

3. **Run the soak test (24-hour minimum, 48-hour preferred).** Let the fleet run untouched. Record `:exec` port `:DOWN` events and tmux session deaths to a single timestamped log. **No chaos in this phase** — establish the steady-state baseline first.

4. **Run the chaos phase (additional 12-24 hours).** Periodically (every 30-60 minutes) kill one erlexec port at random:
   - Soft kill: send `SIGTERM` to the port's `os_pid`
   - Hard kill: send `SIGKILL` to the port's `os_pid`
   - NIF-induced: trigger an erlexec-side error path (oversized payload, invalid resize) — only if a known trigger exists
   For each kill, immediately check whether the underlying tmux session is still alive (`tmux has-session -t <name>`). Record outcome.

5. **Run the resize-storm test (1 hour).** Continuously call `:exec.pty_resize/2` on each port at 10 Hz, randomly varying cols/rows. Check for port crashes, tmux session corruption, and BEAM-side memory growth.

6. **Run the slow-reader test (1 hour).** On one port, do not consume output for several minutes (simulate a stuck consumer / browser tab gone away). Confirm no unbounded BEAM-side memory growth and no PTY-side blocking that affects other ports.

7. **Run the detach + reattach test (30 min minimum, per `BAB-1110` β + γ requirement).** For each of N=3 sessions:
   - Start tmux session detached (`tmux new-session -d -s babs-test-<i>`); spawn a long-running interactive workload inside (e.g. `vim`, `htop`, or real `claude` CLI)
   - Open erlexec port that attaches and consumes byte stream; collect bytes for 5 min
   - **Kill ONLY the erlexec port** (simulating `:babs_citizens` reload or BEAM crash) — confirm tmux session and the workload inside survive
   - Wait 5 s
   - Open a fresh erlexec port that attaches to the SAME tmux session; resume byte collection
   - Continue for 20 min
   - **Verify zero byte loss across the gap** (ground truth: drive the workload with a known sequence and check sequence completeness in the captured byte log)
   - Verify tmux session ID and the workload's OS PID are unchanged before/after the port-kill
   This is the test that validates the Phase 2 chicken-and-egg solution: a Citizen modifying its own host code triggers `:babs_citizens` reload, which kills the erlexec port; γ guarantees the AI CLI inside tmux survives and reattach is loss-free.

8. **Run the Channel→xterm.js byte-path test (30 min minimum, per `BAB-1106` revision).** Start `Hardline.Web` (the minimal Phoenix Endpoint inside the spike); open `priv/static/index.html` in a browser; confirm:
   - PTY bytes flow from erlexec → `Hardline.Pane` GenServer → `Phoenix.PubSub` topic `pane:test` → Channel → WebSocket → xterm.js
   - PubSub publishes are chunked at ≤4 KB per message (per `BAB-1106` constraint)
   - TUI session inside tmux (e.g. `htop`) renders correctly: ANSI colors intact, cursor positioning correct, no garbled escape sequences over 30 min
   - Reload the browser tab mid-stream — Channel re-subscribes the PubSub topic; xterm.js sees brief flicker (≤2s) but stream resumes
   - Optional: edit a file in `lib/hardline/web/` to trigger Phoenix `live_reload`; confirm Channel dies but tmux + erlexec port + Hardline.Pane all survive

9. **Compile the results.** Tabulate:
   - Total port-hours run
   - Number of unprovoked port crashes (steady-state phase)
   - Number of tmux session deaths correlated with port deaths (chaos phase)
   - BEAM memory growth over the run
   - Any unexpected behaviors not in the test plan

---

## Pass / Fail Criteria

**Method A passes** if all of the following hold:

- ≤ **1** unprovoked erlexec port crash per 48 port-hours in the steady-state phase
- **0%** of intentional port kills cause the underlying tmux session to die (the AI CLI inside is the irreplaceable thing — losing the port is recoverable; losing the session is not)
- BEAM memory does not grow without bound under resize storm or slow reader
- No NIF-induced VM crashes
- **Detach + reattach test (step 7)**: zero byte loss across a port-kill + reattach gap; tmux session ID and workload PID unchanged before/after; reattach completes in ≤5s
- **Channel→xterm.js byte-path test (step 8)**: TUI renders correctly over 30 min; PubSub messages chunked ≤4 KB; browser tab reload recovers within 2s without backend disruption

**If Method A passes:** mark `BAB-1103` Method A as validated; **mark `BAB-1106` Channel→PubSub→xterm.js path validated**; **mark `BAB-1110` β + γ detach/reattach validated**; proceed to Phase 1 (`BAB-2201`).

**Method A fails** if any of:

- > 1 unprovoked port crash per 48 port-hours
- ANY chaos-phase port kill kills the underlying tmux session
- Memory growth indicates a leak under sustained operation
- BEAM VM crashes from a NIF path
- **Detach + reattach test fails**: bytes lost across the gap, OR tmux session dies on port kill, OR reattach fails / hangs
- **Channel→xterm.js test fails**: garbled rendering, byte loss, BEAM scheduler block on large payloads (>4 KB unchunked)

**If Method A fails:** the failure mode determines the response:
- *PTY-substrate failure* (port crashes, tmux deaths under chaos, NIF crashes) → activate `BAB-1103` Method B fallback. File CHG.
- *Detach/reattach failure* → `BAB-1110` β + γ design must be revised; specifically the chicken-and-egg solution for Phase 2 needs an alternative. Phase 1 SEED (`BAB-2201`) cannot start until alternative is designed and validated.
- *Channel→xterm.js failure* → `BAB-1106` revision needs follow-up; specific failure determines fix (chunking strategy, alternative transport, or LiveView replacement of Channel).

In all failure cases, file CHG entries on the affected ADRs and reread `BAB-2201` Phase 1 plan before starting any production code.

---

## Examples

### Example 1 — Clean pass

24-hour soak: 0 unprovoked crashes. 12-hour chaos: 23 port kills, 0 tmux session deaths. 1-hour resize storm: 0 issues. 1-hour slow reader: BEAM memory flat ±5%. **Method A validated.** File a CHG appending the result to `BAB-1103`'s Change History.

### Example 2 — Critical fail (the exact failure mode the SOP exists to catch)

24-hour soak: 0 unprovoked crashes. 12-hour chaos: 8 port kills, **3 tmux session deaths** (one of them with the AI CLI exiting). **Method A fails.** Activate Method B. Update `BAB-1103` Status to "Accepted (Method B active)" and add a Change History entry citing this run.

### Example 3 — Marginal result (the hard case)

48-hour soak: 2 unprovoked crashes (just over threshold). Chaos phase: 0 tmux session deaths. **Method A is on the boundary.** Re-run the soak test for another 48 hours with verbose logging. If the crash rate stays at this level, treat as a fail (the threshold exists for a reason). If the crash rate drops to 0-1 with no environmental change, escalate to a discussion — possibly a bad initial test setup.

---

## Output Artifacts

The spike produces, in order of priority:

1. **Pass/fail decisions** filed as CHG entries against `BAB-1103` (PTY substrate), `BAB-1106` (Channel→PubSub byte path), and `BAB-1110` (β + γ detach/reattach)
2. **The raw log file** (port events, tmux events, memory samples, byte-stream sequences for detach/reattach) committed to `spikes/hardline/results/run-YYYY-MM-DD/`
3. **A short writeup** (`spikes/hardline/results/run-YYYY-MM-DD/SUMMARY.md`) with tabulated results and decisions
4. **Phase 0 → Phase 1 handoff artifact list** (per Trinity 2nd-round review): erlexec flags / tmux command shapes / PubSub byte contract / xterm.js asset versions / OS+toolchain versions / detach test thresholds — all captured in SUMMARY.md so Phase 1 SEED (`BAB-2201`) implementation can reference exact values
5. **Issue or follow-up notes** for any unexpected behavior worth investigating later

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial version — gates Phase 1+ on empirical erlexec PTY validation | Claude Code |
| 2026-05-03 | v0.1 amendments: spike location moved to `spikes/hardline/` inside babs repo (was throwaway sibling repo); module namespace `Spike.*` → `Hardline.*`; erlexec dep `~> 2.3` → `~> 2.2` (Hex correction); added step 7 (detach + reattach test per `BAB-1110` β + γ); added step 8 (Channel→xterm.js byte-path test per `BAB-1106` revision); pass/fail criteria expanded to cover both new tests; output artifacts now also CHG against `BAB-1106` and `BAB-1110`; Phase 0 → Phase 1 handoff artifact list added per Trinity 2nd-round review | Claude Code |
