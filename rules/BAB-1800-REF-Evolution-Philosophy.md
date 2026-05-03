# REF-1800: Evolution Philosophy

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Active
**Inherits from:** COR-1800 (full-replace per table; unspecified tables inherit COR defaults)

---

## What Is It?

PRJ-layer override of COR-1800 for Babs. Babs is a **runtime system** — a long-lived application hosting independently-supervised citizens that talk to AI CLIs, route messages between external surfaces, and coordinate via A2A. Its "behavior" is observable in production: citizens stay alive, messages reach their targets, latency stays bounded, A2A round-trips succeed. This is fundamentally different from a config repo (CLD) or a CLI tool (FXA-Alfred), so weights, signal sources, and the behavior baseline are redefined here.

---

## Behavior Baseline

`Fitness = same behavior / (LoC + doc words)` requires a "behavior" definition. For Babs:

- **Behavior** = the observable outcomes a Babs node produces under a fixed set of regression scenarios stored in `samples/regression-scenarios/`. Created lazily — the first evolve cycle that needs a baseline writes the initial scenarios.
- **Same behavior** = on each scenario, the new code produces (a) the same final state across observable surfaces (citizen.status, transcript output, A2A response payload) within tolerance, AND (b) latency / memory / process count within ±10% of the prior version on the same hardware.
- **Scenario types** (each documented in `samples/regression-scenarios/<id>.md`):
  - **Relay scenarios**: inject a Discord-like message → expect a transcript line and an outbound reply within N seconds
  - **A2A scenarios**: dispatch an A2A call → expect a typed response payload
  - **Lifecycle scenarios**: kill a PaneSession → expect supervised restart and citizen status to recover within N seconds
  - **Backpressure scenarios**: flood a PaneSession with concurrent inject calls → expect serialized output and bounded mailbox growth
- **When a scenario cannot be reproduced** (e.g., hardware-specific timing, real Discord rate limits): the baseline falls back to *PR diff + targeted-surface human review* — no synthetic claim of equivalence.

---

## Override: Code Evolution Weights

Replaces COR-1800 default code weights in full. Sums to 100%.

| Dimension | Weight | Measures |
|-----------|--------|----------|
| Runtime safety | 30% | Does the change preserve supervision-tree semantics? Are crash boundaries intact? Are no-PubSub hot paths (terminal bytes) still hot? |
| Behavior verifiability | 25% | Can the change be validated against an existing regression scenario, or does it ship with a new scenario? Untestable changes score low. |
| Scope restraint | 20% | Change touches one logical surface (one supervisor's children / one ADR's domain / one boundary contract); does not bleed across boundary lines defined in `BAB-1003` |
| Compression ratio | 15% | (chars deleted + chars merged) / (chars added). Net negative or neutral preferred; net positive must be justified by capability gained, not aesthetics |
| Necessity | 10% | Concrete signal evidence — production incident, repeated user correction, measurable latency/memory regression — not "feels improvable" |

---

## Override: Document Evolution Weights

Replaces COR-1800 default doc weights in full. Sums to 100%.

| Dimension | Weight | Measures |
|-----------|--------|----------|
| ADR/SOP fidelity | 30% | Does the doc accurately reflect the running system, or has the code drifted? Stale docs score very low. |
| Necessity | 25% | Evidence from incidents, repeated corrections, validate failures, hook errors, or onboarding friction |
| Atomicity | 20% | One ADR/SOP/REF = one thing. CLAUDE.md sections must not duplicate ADR content; ADRs must not duplicate REF vocabulary |
| Consistency | 15% | No conflict with COR PKG docs, other BAB docs, code conventions, or `BAB-1003` boundary definitions |
| Compression ratio | 10% | Same formula as code; documentation that grows must justify against deletions elsewhere |

---

## Override: Signal Sources

Replaces COR-1800 default signal table in full. Default sources (test failures, coverage) apply but are insufficient — Babs's behavior is operational, not just unit-testable.

| Signal | Where to look | Cadence |
|--------|---------------|---------|
| Supervision-tree drift | `mix.exs` deps changes; `Babs.Application.start/2` children diff vs. `BAB-1001` | Per evolve cycle |
| ADR drift | grep code for patterns explicitly rejected in `BAB-11xx` ADRs (e.g., DETS use, `:erpc` use, PubSub on terminal hot path) | Per evolve cycle |
| Boundary leak | Any module outside `Babs.Tmux.Core` calling erlexec or `System.cmd("tmux", ...)`; any module outside `Babs.Connectors.*` doing direct Discord/Telegram HTTP | Per evolve cycle |
| Persistence sprawl | Any new `:dets` open, any new external DB driver, any new `mnesia:*` call | Per evolve cycle |
| Regression scenario coverage | `samples/regression-scenarios/` count vs. ADR-mandated scenario types (relay, A2A, lifecycle, backpressure) | Per evolve cycle |
| Production incident frequency | Babs logs grep for crashes, restart loops, A2A timeouts, PaneSession OOM | Continuous (when noticed) |
| Latency / memory regression | BabsWeb metrics page or external Grafana over the last week vs. baseline | Per evolve cycle |
| Repeated corrections | Same operator/user correction across multiple sessions | Continuous (when noticed) |
| `af validate` output | Structural issues in `rules/` BAB docs | Per evolve cycle |
| Citizen catalog drift | Live `Babs.Citizens.Registry` listing vs. `relay_config` and SQLite registry | Per evolve cycle |

---

## Inherited from COR-1800 (not overridden)

- Evolution cycle: Signal Collection → Candidate Generation → Evaluation → Implementation → Review → PR
- Thresholds: candidate discard < 7.0; review pass ≥ 9.0
- Guard rails: evolve process must not modify `BAB-1800` / `BAB-1801` / `COR-1800` itself; weight/threshold changes go through PRP/CHG, not the evolve loop
- Override contract semantics: full-replace per table

---

## Babs-Specific Guard Rails

Beyond the inherited COR guard rails:

- **Never weaken supervision strategy** without an ADR. Changing `:rest_for_one` to `:one_for_one` on a CitizenSupervisor is an ADR-grade decision.
- **Never introduce a new boundary** (new external service, new on-disk persistence, new wire protocol) via the evolve loop. Boundaries are defined in `BAB-1003` and changed via PRP+ADR.
- **Never collapse the LiveView/Channel split** for the dashboard. The Channel→PubSub→xterm.js byte path (`BAB-1106`) is a live-reload-safety decision, not stylistic; evolve-loop refactors that touch it must score against `BAB-1106` explicitly.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial PRJ override of COR-1800 for Babs runtime system | Claude Code |
| 2026-05-03 | Update LiveView/Channel guard rail to match `BAB-1106` v0.1 PubSub byte-path amendment | Codex |
