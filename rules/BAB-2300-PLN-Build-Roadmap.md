# PLN-2300: Build Roadmap

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Draft

---

## What Is It?

The end-to-end coordination plan for building Babs from zero to a working multi-agent runtime. Sequences the five build phases (`BAB-2200` through `BAB-2204`), names each phase's gating decision, and defines the kill criteria that would force a re-plan rather than push forward.

---

## Goals

- Stand up Babs to feature parity with the operator's mental model: citizens hosted, messages relayed, A2A working, web dashboard usable
- Eliminate the highest-risk decision (PTY method choice) before any production code
- Keep each phase narrow enough that one engineer can complete it in 1-2 weeks of focused work
- Produce a runnable system at the end of each phase, not just at the end of the roadmap

---

## Milestones

| # | Milestone | PRP | Gates next phase on... | Tentative effort |
|---|-----------|-----|-----------------------|------------------|
| 1 | Phase 0 — PTY Stability Spike | `BAB-2200` | erlexec PTY pass/fail recorded against `BAB-1103` | ~3-4 days wall-clock; ~6h attention |
| 2 | Phase 1 — Core Supervision Skeleton | `BAB-2201` | `iex` round-trip: inject bytes → tmux pane; subtree restarts cleanly | 1 week |
| 3 | Phase 2 — A2A + SQLite + First Citizen | `BAB-2202` | Two citizens A2A-talk locally; transcripts tail live; cross-process A2A over HTTP works | 2 weeks |
| 4 | Phase 3 — Connectors (Discord + Telegram) | `BAB-2203` | Discord message round-trip ≤3s; reconnect after 60s network drop; rate-limit handled | 2 weeks |
| 5 | Phase 4 — BabsWeb (LiveView + React + xterm.js) | `BAB-2204` | All 5 views per `BAB-1004` render correctly; terminal latency ≤50ms | 2-3 weeks |

**Total tentative**: ~8-10 weeks of focused work spread across whatever calendar that fits operator availability. No hard deadlines.

---

## Phase Dependencies

```
Phase 0 (PTY spike)
  │  pass → continue
  │  fail → switch BAB-1103 to Method B; downstream PRPs unchanged structurally,
  │         but PaneSession internals differ
  ▼
Phase 1 (supervision skeleton)
  │  acceptance: iex demo
  ▼
Phase 2 (A2A + registry + first citizen)
  │  acceptance: two citizens A2A-talk; transcripts live
  ▼
Phase 3 (Connectors)
  │  acceptance: Discord + Telegram round-trip
  ▼
Phase 4 (BabsWeb)
  │  acceptance: 5 views per BAB-1004 + xterm.js terminal panel
  ▼
v0.1.0 release
```

Phases are **strictly sequential** for v0.1.0. Parallelization (Phase 4 chrome work alongside Phase 3 Connectors) is tempting and probably fine for the no-real-PaneSession-needed parts of Phase 4 (Dashboard skeleton, palette/typography), but the rule for the roadmap is "don't start the next phase's *integration* work until the prior phase's acceptance ships."

---

## Kill Criteria (when to re-plan instead of push)

If any of the following happen, **stop and replan** rather than carry the issue forward:

| Trigger | Action |
|---------|--------|
| Phase 0 fails AND Method B has unexpected blockers (e.g., tmux capture-pane unreliable on the target system) | File an INC + ADR; consider Method C (custom NIF) or pause project |
| Phase 1 supervision strategy reveals fundamental flaw in `BAB-1102` (e.g., `:rest_for_one` causes pathological restart loops in real use) | File a PRP to revise `BAB-1102`; do NOT proceed to Phase 2 with a known-broken supervision pattern |
| Phase 2 A2A latency over HTTP is >100ms intra-host (way above estimate) | Reopen `BAB-1104` ADR — possibly investigate `:erpc` for *intra-host between BEAM nodes* (a different question than inter-machine) |
| Phase 3 Discord rate-limits prevent realistic operator workloads | File an INC; consider message batching, queue, or lower-cadence relay; may revise `BAB-1003` Discord boundary contract |
| Phase 4 LiveView reconnection causes terminal byte loss | Reopen `BAB-1106` — possibly pivot to a SPA frontend for Citizen Detail and Full Terminal; LiveView remains for Dashboard / Ops / Diagram |

These are not soft thresholds. Hitting any means the roadmap stops; the trigger is documented as an INC; a CHG or ADR addresses it; the roadmap restarts.

---

## Rollback Path

There is no production system to roll back to — Babs is greenfield. "Rollback" means: revert the offending commit, keep the prior phase's state, file an INC documenting why the phase was rolled back, and re-plan.

If a phase is started and abandoned, its branch / WIP commits stay in git history (do NOT force-push). The phase's PRP gets a Change History entry recording the abandonment + reason.

---

## Status

**Current**: Roadmap drafted; nothing started. Phase 0 is the next concrete action.

**Cadence for updating this doc**: At each phase boundary (start + end), append a Change History entry with the date, phase, and one-line outcome. If the roadmap changes (insertion / deletion / re-ordering of phases), file a CHG.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial draft — five-phase roadmap with kill criteria | Claude Code |
