# PRP-2200: Phase 0 — PTY Stability Spike

**Applies to:** BAB project
**Last updated:** 2026-05-04
**Last reviewed:** 2026-05-04
**Status:** Draft

---

## What Is It?

The first build phase. A self-contained sub-mix-project at `spikes/hardline/` (inside this repo) that runs the empirical erlexec PTY stability test defined in `BAB-1502`. This phase **gates everything else** — Phase 1 production code does not start until Phase 0 produces a pass/fail decision recorded against `BAB-1103`. The `hardline` name is from *The Matrix*'s wired cross-world phones; the full naming exploration is in `BAB-1005`.

Phase 0a (`BAB-2202`) is a separate optional usability spike on the same `spikes/hardline/` codebase. It adds a browser manager console for multiple tmux-backed hardlines. Phase 0a can make manual operation easier, but it does **not** replace this PRP's official 24h+ validation gate.

---

## Problem

`BAB-1103` accepts erlexec PTY attach (Method A) as the primary substrate but flags one production-blocking risk: an erlexec port crash propagating into the attached tmux session and killing the AI CLI inside. Whether this happens in our specific environment (macOS / Apple Silicon / current tmux / current Claude/Codex CLI versions) is unknown.

Building Phase 1+ on Method A and discovering the failure mode in production means re-architecting the citizen subtree and possibly losing transcripts. The cost of finding out now is one weekend; the cost of finding out in production is a phase rebuild.

---

## Proposed Solution

### Scope

A self-contained sub-mix-project at `spikes/hardline/` inside this repo. It has its own `mix.exs` and is isolated from the (yet-to-exist) main `:babs` mix project — if the spike fails and a different PTY substrate is chosen, the directory is deleted in one move without touching the main project.

```
spikes/hardline/
├── mix.exs                  (deps: {:erlexec, "~> 2.2"}, {:phoenix, "~> 1.8"} for Channel test, {:phoenix_live_view, "~> 1.0"} optional)
├── lib/
│   ├── hardline.ex             (top-level API: start, stop, report)
│   ├── hardline/runner.ex      (provisions N tmux sessions, attaches via erlexec)
│   ├── hardline/chaos.ex       (kill-port-at-random)
│   ├── hardline/observer.ex    (logs every port event + tmux state to file)
│   ├── hardline/scenarios.ex   (resize storm, slow reader, soak)
│   └── hardline/web/           (minimal Phoenix Endpoint + Channel + xterm.js page for byte-path validation)
├── priv/static/                (xterm.js, addon-fit, single index.html)
├── results/                    (per-run subdir: logs, SUMMARY.md, metrics CSV)
└── README.md                   (how to run, how to read results; references BAB-1005 for name origin)
```

**Note on dep version:** `{:erlexec, "~> 2.3"}` does not exist on Hex (latest published is in the 2.2 line as of 2026-05-03). Use `~> 2.2` and pin in `mix.lock`. If a newer major appears before Phase 0 starts, re-evaluate.

### Execution

Per `BAB-1502` SOP: 24-48h soak (steady-state) → 12-24h chaos (kill-port at intervals, observe tmux survival) → 1h resize storm → 1h slow reader → tabulate.

Total wall-clock: ~3-4 days for a full pass with margin. Engineer attention: ~4-6 hours total (setup + result review). Most of the time is the test running unattended.

### Output

CHG entries appended to `BAB-1103`, `BAB-1106`, and `BAB-1110` recording each validated slice plus the run's `results/run-YYYY-MM-DD/SUMMARY.md` path. If pass, `BAB-1103` Method A is empirically validated, `BAB-1106`'s Channel→xterm.js byte path is validated, and `BAB-1110`'s β + γ detach/reattach path is validated. If fail, the failure mode determines which ADR and downstream PRPs (`BAB-2201`+) need follow-up CHGs.

### Implementation Plan

1. Create `spikes/hardline/` sub-mix-project inside this repo (isolated from any future main `:babs` app)
2. Implement `Hardline.Runner` (~50 LOC) and verify mix compile + erlexec build on the target machine — if C++ build fails, halt and triage toolchain
3. Implement `Hardline.Observer` (~30 LOC, just `:exec.run/2` + receive loop into a file)
4. Implement `Hardline.Chaos` (~20 LOC, periodic SIGTERM/SIGKILL of random `os_pid`)
5. Implement `Hardline.Scenarios.resize_storm/0` and `Hardline.Scenarios.slow_reader/0`
6. Implement `Hardline.Web` — minimal Phoenix Endpoint + one Channel that pushes raw PTY bytes to xterm.js in `priv/static/index.html`. This validates the **full Phase 4 byte path** (PTY → BEAM → Channel → WebSocket → xterm.js render) end-to-end, which `BAB-1502` did not cover in its original scope (HIGH-severity finding from prior multi-model review)
7. **Implement `Hardline.Detach` — detach + reattach scenario** (per `BAB-1110` Trinity-mandated): start a tmux session detached (`tmux new-session -d`), open `erlexec` port that attaches; soak 30 min; kill the BEAM-side `erlexec` port (simulate `:babs_citizens` reload); verify tmux session and AI CLI inside survive; open fresh `erlexec` port that re-attaches to the same session; verify zero byte loss across the gap; the AI CLI process inside tmux must continue uninterrupted. **This validates the Phase 2 chicken-and-egg solution**.
8. Run scenarios per `BAB-1502` step sequence + the Channel→xterm.js byte-path scenario from step 6 + the detach/reattach scenario from step 7
9. Compile `SUMMARY.md` per `BAB-1502` Output Artifacts section
10. File CHG against `BAB-1103` (PTY substrate decision), `BAB-1106` (LiveView/Channels/PTY decision — Channel→xterm.js leg now empirically validated), and `BAB-1110` (β + γ — detach/reattach validated)

### Acceptance

This PRP is "done" when:

- `spikes/hardline/` compiles and runs end-to-end on the target machine
- A complete run's `results/run-YYYY-MM-DD/` exists with logs + SUMMARY
- The Channel→xterm.js byte-path test renders a TUI session (e.g. `htop` or a real Claude/Codex CLI invocation) in a browser tab without dropped bytes, mangled escape sequences, or visible cursor desync over a 30-minute soak
- The **detach + reattach scenario** passes: tmux session + AI CLI process survive an `erlexec` port kill; fresh port attaches to the same session and resumes byte streaming with **zero loss across the gap** (per `BAB-1110`'s β + γ requirement)
- `BAB-1103`, `BAB-1106`, and `BAB-1110` have Change History entries recording the pass/fail of their respective slices
- If fail: a follow-up CHG against affected downstream PRPs is filed; specifically, if detach/reattach fails, `BAB-1110` must downgrade γ and Phase 1 SEED rewrites accordingly (chicken-and-egg fix becomes harder)

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
| 2026-05-03 | Integral revision (D8): spike location moved to `spikes/hardline/` inside babs repo (option a, sub-mix-project); module namespace `Spike.*` → `Hardline.*`; erlexec dep `~> 2.3` → `~> 2.2` (Hex correction); added Channel→xterm.js byte-path validation as new step 6 + acceptance criterion (HIGH-severity review finding now covered); CHG output now files against both `BAB-1103` and `BAB-1106`. Naming origin: `BAB-1005` | Claude Code |
| 2026-05-03 | Trinity-driven amendment (D13/D14): added step 7 = detach + reattach scenario (validates `BAB-1110` β + γ chicken-and-egg solution); added detach/reattach acceptance criterion; CHG output now also files against `BAB-1110` | Claude Code |
| 2026-05-03 | Sync Output section and Change History wording with amended `BAB-1502`; Phase 0 now explicitly records CHG entries against `BAB-1103`, `BAB-1106`, and `BAB-1110` | Codex |
| 2026-05-04 | Cross-reference optional Phase 0a (`BAB-2202`) Hardline Manager Console Spike and clarify it does not replace the official Phase 0 full validation gate | Codex |
