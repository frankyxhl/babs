# SOP-1801: Evolve Babs

**Applies to:** BAB project
**Last updated:** 2026-05-04
**Last reviewed:** 2026-05-03
**Status:** Active
**Depends on:** BAB-1800 (weights, thresholds, signals), COR-1800 (philosophy + cycle)

---

## What Is It?

The concrete evolve loop for the Babs runtime. Implements the COR-1800 cycle (Signal → Candidate → Evaluation → Implementation → Review → PR) using `BAB-1800`'s overridden weights, thresholds, and signal sources. Specialized for a long-lived runtime system (not a config repo, not a CLI tool).

---

## Why

Babs accumulates entropy distinct from other project types: supervision-tree drift, boundary leaks (modules talking to tmux/Discord outside their owners), ADR drift (code reintroducing patterns explicitly rejected in `BAB-11xx`), regression scenario gaps as features land. Without an explicit evolve loop, these go unnoticed until a production incident makes them expensive. This SOP makes prevention a deliberate, scored process.

---

## When to Use

- User explicitly invokes the evolve loop ("run evolve", "audit Babs", "compress runtime")
- Before a major release (Phase boundary: 0→1, 1→2, 2→3)
- Periodic maintenance (suggested cadence: monthly during active development; quarterly post-Phase-3)
- After resolving an incident where the root cause was structural (suggests a class of similar issues to surface)

## When NOT to Use

- For a single targeted edit with clear scope (just edit the file)
- For changes inside COR PKG documents (read-only — propose upstream instead)
- For changes to `BAB-1800` or this SOP itself (use PRP/CHG per COR-1800 guard rails)
- For phase-implementation work driven by `BAB-22xx` PRPs (those are forward-design, not evolve)

---

## Steps

1. **Signal Collection.**

   Run each signal source from `BAB-1800` §Signal Sources. Concrete commands (some require Babs code to exist; those marked TODO until Phase 2):

   ```bash
   # ADR drift — patterns explicitly rejected
   git grep -nE ':dets\.|:mnesia\.' lib/                     # BAB-1105 violations
   git grep -nE ':erpc\.|:rpc\.' lib/                        # BAB-1104 violation (cross-node)
   git grep -nE 'PaneSession|bypasses PubSub|direct.*pane PID|socket\.assigns.*pane' lib/  # BAB-1106 code violation

   # Boundary leak — owners-only modules
   git grep -nE 'erlexec|:exec\.' lib/ -- ':!lib/babs_citizens/hardline/'  # outside Hardline boundary
   git grep -nE 'discord|telegram' lib/ -- ':!lib/babs/connectors/' # outside Connectors

   # Persistence sprawl
   git grep -nE ':dets\.open_file|:mnesia\.create_table' lib/

   # Supervision-tree drift
   diff <(grep -A 200 '^  def start' lib/babs/application.ex) \
        <(grep -A 200 'OTP supervision tree' rules/BAB-1001-REF-Architecture-Overview.md)
       # rough — verify Application children match BAB-1001's tree

   # Regression scenario coverage
   ls samples/regression-scenarios/ | wc -l
   # Compare counts by type (relay/a2a/lifecycle/backpressure) to BAB-1800 mandated set

   # af validate
   af validate --root /Users/frank/Projects/babs

   # Citizen catalog drift
   # (Phase 2+) compare `Babs.Citizens.Registry` listing with `relay_config` SQLite rows
   ```

   For each finding, record: surface, evidence (file:line or log excerpt), proposed action.

2. **Candidate Generation.**

   Convert each finding into a candidate:

   ```
   Candidate ID: C<n>
   Surface: <module / supervisor / ADR / SOP / REF section>
   Action: <delete | merge | rewrite | add-scenario | rename>
   Evidence: <pointer to signal>
   Estimated compression: +<chars added> / -<chars removed>
   ```

   **Surface taxonomy** (mirrors CLD-1801's CHG-1802 amendment):
   - Single-purpose file (one module, one ADR, one SOP, one scenario): file is the surface
   - Multi-section doc (a CLAUDE.md-equivalent, an ADR with multiple Rejected Alternatives sections): each `##` heading is a surface; one candidate touches ≤ 1 such section
   - Symmetric multi-file refactor (e.g., the same boundary fix applied across all Connectors): the *class* is the surface; one candidate scoped to the class
   - Cross-class candidates: always N separate candidates

   Discard immediately if action is "add new feature" without a deletion offset — this loop is for compression and integrity, not growth. New features go through PRP, not evolve.

3. **Evaluation.**

   Score each candidate against `BAB-1800` weights. Code candidates use the code weight table; doc candidates use the doc weight table; mixed candidates score against both and use the lower of the two composites.

   For each dimension, score 0-10 with a one-line justification. Composite = Σ(weight × score). Discard candidates with composite < 7.0.

   Surface the surviving candidates to the user before implementation.

4. **Implementation.**

   For each surviving candidate:
   - Make the change on a feature branch
   - Touch only the surface listed in the candidate
   - Run regression scenarios that touch the changed surface; if no scenario covers it and behavior verifiability scored ≥ 8, write the scenario now and commit it alongside
   - Run the signal-collection grep that found this candidate AFTER the change — confirm it now returns clean

5. **Review.**

   Two-reviewer gate per inherited COR-1800. Both must score ≥ 9.0:
   - Reviewer A: re-score against `BAB-1800` weights with the implemented diff in hand
   - Reviewer B: independent reviewer (different agent/model, or human) confirms behavior is preserved on the relevant regression scenario(s)

6. **PR.**

   Bundle survivors into a single PR titled `evolve(bab): <one-line summary>`. PR body includes:
   - Candidate IDs and final composite scores
   - Compression delta (lines/chars added vs removed)
   - Regression scenario results
   - Any candidates rejected at review and why
   - Updated signal-collection output showing the targeted issues are now clean

---

## Examples

### Example 1 — Boundary leak found

**Signal**: `git grep` finds `:exec.run` in `lib/babs_web/live/citizen_live.ex` (outside the Hardline boundary).
**Candidate C1**: Move erlexec access into `Hardline.Pane`; expose typed attach/inject/resize calls from the Hardline boundary.
**Score**: Runtime safety 9, Behavior verifiability 8 (existing `Hardline.Pane` scenarios cover it), Scope 9 (one boundary), Compression 5 (small net add for the Hardline API), Necessity 8 (clear ADR `BAB-1003` violation). Composite ≈ 8.0.
**Pass.** Implement, regress, PR.

### Example 2 — Stale REF

**Signal**: Architecture diff shows `BAB-1001` mentions `:hot_routing_cache` ETS table that no longer exists in code.
**Candidate D1**: Update `BAB-1001` to remove the stale entry.
**Score**: ADR/SOP fidelity 10, Necessity 7, Atomicity 9, Consistency 9, Compression 8 (deletes a stale line). Composite ≈ 8.7.
**Pass.** Update, validate, PR.

### Example 3 — Tempting growth, rejected

**Signal**: Operator says "wouldn't it be nice to add a Slack connector via evolve?"
**Candidate C2**: Add `Babs.Connectors.Slack`.
**Discard at step 2**: This is feature growth, not compression or integrity. Route to PRP per `BAB-2100`, not evolve.

---

## Guard Rails

- This SOP must not modify `BAB-1800`, `COR-1800`, or itself. Changes to these go through PRP/CHG.
- Never delete files based on signal alone — every deletion needs evidence in the candidate record AND human reviewer sign-off.
- Never merge two surfaces without verifying the merged surface still passes its regression scenarios.
- Phase implementation work is NOT eligible for evolve — it is forward design via PRP.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial version — adapted CLD-1801 for Babs runtime system | Claude Code |
| 2026-05-03 | Self-review fix: Phase 0/1/2/3 → 0/1/2/3/4 in guard rails | Claude Code |
| 2026-05-04 | Reverse stale terminal-byte PubSub violation check; update boundary examples to `Hardline.Pane` and current phase-roadmap wording | Codex |
