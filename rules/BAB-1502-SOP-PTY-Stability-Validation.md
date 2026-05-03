# SOP-1502: PTY Stability Validation (Phase 0 Spike)

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Active
**Depends on:** BAB-1103 (PTY method choice; Method A primary, Method B fallback)
**Gates:** Phase 1+ implementation (`BAB-2201`, `BAB-2202`, `BAB-2203`)

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

A throwaway repo `babs_pty_spike/` (NOT in the main Babs codebase) with the minimum dependency set:

```
mix.exs:
  deps: [{:erlexec, "~> 2.3"}]

lib/spike.ex:
  - SpikeRunner.start/1     spawns N tmux sessions with a long-running command (e.g. `bash -c "while true; do echo tick; sleep 1; done"`)
  - SpikeRunner.attach/1    erlexec PTY attach to each session
  - SpikeRunner.chaos/2     kills the erlexec port at random intervals (next section)
  - SpikeRunner.observe/1   records timestamps of: port crash, tmux session death, AI-CLI-equivalent process death
```

The "AI CLI equivalent" can be a real Claude/Codex CLI in interactive mode if available, or a long-running bash loop with stdin/stdout interactions for cheaper iteration. Both must be exercised; reality may differ from the synthetic case.

---

## Steps

1. **Set up the test harness.** Create `babs_pty_spike/` with the structure above. `mix deps.get && mix compile` to confirm erlexec builds on the target machine. If the C++ build fails, log the toolchain delta and stop — no point testing further.

2. **Provision the test fleet.** Start `N = 5` tmux sessions, each running the long-running command. For each, start an erlexec PTY attach. Confirm bidirectional bytes (write something to the PTY and read it back through capture).

3. **Run the soak test (24-hour minimum, 48-hour preferred).** Let the fleet run untouched. Record `:exec` port `:DOWN` events and tmux session deaths to a single timestamped log. **No chaos in this phase** — establish the steady-state baseline first.

4. **Run the chaos phase (additional 12-24 hours).** Periodically (every 30-60 minutes) kill one erlexec port at random:
   - Soft kill: send `SIGTERM` to the port's `os_pid`
   - Hard kill: send `SIGKILL` to the port's `os_pid`
   - NIF-induced: trigger an erlexec-side error path (oversized payload, invalid resize) — only if a known trigger exists
   For each kill, immediately check whether the underlying tmux session is still alive (`tmux has-session -t <name>`). Record outcome.

5. **Run the resize-storm test (1 hour).** Continuously call `:exec.pty_resize/2` on each port at 10 Hz, randomly varying cols/rows. Check for port crashes, tmux session corruption, and BEAM-side memory growth.

6. **Run the slow-reader test (1 hour).** On one port, do not consume output for several minutes (simulate a stuck consumer / browser tab gone away). Confirm no unbounded BEAM-side memory growth and no PTY-side blocking that affects other ports.

7. **Compile the results.** Tabulate:
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

**If Method A passes:** mark `BAB-1103` Method A as validated; proceed to Phase 1.

**Method A fails** if any of:

- > 1 unprovoked port crash per 48 port-hours
- ANY chaos-phase port kill kills the underlying tmux session
- Memory growth indicates a leak under sustained operation
- BEAM VM crashes from a NIF path

**If Method A fails:** activate `BAB-1103` Method B fallback. File a CHG against `BAB-1103` updating its status to record the empirical failure and the switch. Phase 1 plans (`BAB-2201`+) must be reread to confirm they don't assume Method A semantics that B doesn't provide (real-time byte streaming primarily — Method B has a 150-250ms polling floor).

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

1. **A pass/fail decision** filed as a CHG against `BAB-1103`
2. **The raw log file** (port events, tmux events, memory samples) committed to `babs_pty_spike/results/run-YYYY-MM-DD/`
3. **A short writeup** (`results/run-YYYY-MM-DD/SUMMARY.md`) with the tabulated results and the decision
4. **Issue or follow-up notes** for any unexpected behavior worth investigating later

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial version — gates Phase 1+ on empirical erlexec PTY validation | Claude Code |
