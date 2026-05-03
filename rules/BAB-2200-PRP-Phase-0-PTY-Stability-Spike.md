# PRP-2200: Phase 0 — PTY Stability Spike

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Draft

---

## What Is It?

The first build phase. A throwaway repo `babs_pty_spike/` that runs the empirical erlexec PTY stability test defined in `BAB-1502`. This phase **gates everything else** — Phase 1 production code does not start until Phase 0 produces a pass/fail decision recorded against `BAB-1103`.

---

## Problem

`BAB-1103` accepts erlexec PTY attach (Method A) as the primary substrate but flags one production-blocking risk: an erlexec port crash propagating into the attached tmux session and killing the AI CLI inside. Whether this happens in our specific environment (macOS / Apple Silicon / current tmux / current Claude/Codex CLI versions) is unknown.

Building Phase 1+ on Method A and discovering the failure mode in production means re-architecting the citizen subtree and possibly losing transcripts. The cost of finding out now is one weekend; the cost of finding out in production is a phase rebuild.

---

## Proposed Solution

### Scope

A separate repo at `~/Projects/babs_pty_spike/` (NOT inside `babs/`):

```
babs_pty_spike/
├── mix.exs                  (single dep: {:erlexec, "~> 2.3"})
├── lib/
│   ├── spike.ex             (top-level API: start, stop, report)
│   ├── spike/runner.ex      (provisions N tmux sessions, attaches via erlexec)
│   ├── spike/chaos.ex       (kill-port-at-random)
│   ├── spike/observer.ex    (logs every port event + tmux state to file)
│   └── spike/scenarios.ex   (resize storm, slow reader, soak)
├── results/                 (per-run subdir: logs, SUMMARY.md, metrics CSV)
└── README.md                (how to run, how to read results)
```

### Execution

Per `BAB-1502` SOP: 24-48h soak (steady-state) → 12-24h chaos (kill-port at intervals, observe tmux survival) → 1h resize storm → 1h slow reader → tabulate.

Total wall-clock: ~3-4 days for a full pass with margin. Engineer attention: ~4-6 hours total (setup + result review). Most of the time is the test running unattended.

### Output

A single CHG appended to `BAB-1103`'s Change History recording: pass/fail + the run's `results/run-YYYY-MM-DD/SUMMARY.md` path. If pass, `BAB-1103` Method A is empirically validated. If fail, Method A status is downgraded and Method B becomes mandatory; downstream PRPs (`BAB-2201`+) get a CHG noting the implication.

### Implementation Plan

1. Create the `babs_pty_spike/` repo (outside babs/)
2. Implement `Spike.Runner` (~50 LOC) and verify mix compile + erlexec build on the target machine — if C++ build fails, halt and triage toolchain
3. Implement `Spike.Observer` (~30 LOC, just `:exec.run/2` + receive loop into a file)
4. Implement `Spike.Chaos` (~20 LOC, periodic SIGTERM/SIGKILL of random `os_pid`)
5. Implement `Spike.Scenarios.resize_storm/0` and `Spike.Scenarios.slow_reader/0`
6. Run scenarios per `BAB-1502` step sequence
7. Compile `SUMMARY.md` per `BAB-1502` Output Artifacts section
8. File CHG against `BAB-1103`

### Acceptance

This PRP is "done" when:

- The `babs_pty_spike/` repo exists, compiles, and runs end-to-end
- A complete run's `results/run-YYYY-MM-DD/` exists with logs + SUMMARY
- `BAB-1103` has a Change History entry recording the pass/fail
- If fail: a follow-up CHG against affected downstream PRPs is filed

---

## Open Questions

- **Hardware target**: validate on the operator's primary machine (M-series Mac), or also on a Linux/x86 box if cross-platform deployment is anticipated? **Default**: macOS only; Linux validation deferred until a Linux deployment is concretely planned.
- **AI CLI vs synthetic load**: spike runs the *real* Claude/Codex CLI in interactive mode, or a synthetic bash loop? **Default**: both, in sequence. Synthetic for cheap-iteration during development; real CLI for the validation run that produces the CHG.
- **Concurrency target**: how many simultaneous PTY ports during the soak? **Default**: 5. Real Babs deployments are unlikely to exceed 10 citizens; 5 is enough to surface contention.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial draft | Claude Code |
