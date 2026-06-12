# PRP-2278: Dogfood Program v0.1

**Applies to:** BAB project
**Last updated:** 2026-06-13
**Last reviewed:** 2026-06-13
**Status:** Draft
**Date:** 2026-06-13
**Requested by:** Operator (@frankyxhl)
**Priority:** P1
**Depends on:** BAB-2271 (operator dashboard panels, all delivered), BAB-2300 (v0.1 roadmap, Phases 0-17 complete)

---

## What Is It?

A two-week structured dogfood window (2026-06-13 → 2026-06-27) in which Babs
stops being only self-hosting and becomes the operator's daily driver for real,
non-Babs work. The deliverable is not a feature — it is a **prioritized friction
log** that becomes the next PRP batch.

---

## Problem

Every cycle of the flywheel so far (`BAB-2300` Phases 2-17, `BAB-2271`
#80-#103) was Citizens building Babs inside Babs. That loop is self-referential:
it validates that Babs can build *Babs*, not that Babs is pleasant or even
viable for arbitrary work. Concretely untested under real load:

- The just-delivered standing-context pipeline (Knowledge Home → `prompt_assembler`
  injection → preview) has never carried real, durable operator-authored content.
- Mobile diff review + approve has only been exercised by BDD suites and
  deliveries it was itself part of.
- Workspaces have essentially only ever pointed at the Babs checkout; external
  repos will stress `Babs.Git`, workspace resolution, and diff review at new
  boundaries.
- The next feature batch would otherwise be picked speculatively from the
  `BAB-2271` §Out of Scope list instead of from observed need.

## Proposed Solution

### Program shape

1. **Run Babs as a resident node.** Long-lived process on the operator's Mac
   (dev mode acceptable; prod token gating + Tailscale for phone access already
   exist via Phase 17). Babs is "up" by default for the whole window, not
   started per delivery.
2. **Seed Citizens pointed at real repos.** Beyond the Phase 1 seeds:
   - one Citizen on the **Alfred** repo (`af` CLI / SOP system)
   - one Citizen on the **`.claude` config** repo
   - the existing Citizen on **babs** itself (maintenance only during the window)
3. **Author standing context for each.** Fill each Citizen's Knowledge Home
   (Readme/GOAL, notes) with real content; rely on the injection policy + preview
   surface (#93-#96) rather than ad-hoc prompt pasting.
4. **Route work through Tickets.** During the window, AI-delegable tasks on the
   covered repos (docs, hooks, tests, small fixes, research) are filed as Babs
   Tickets instead of opened directly in a terminal. Review and approve from the
   mobile diff panel whenever practical.
5. **Keep a friction log.** Every annoyance, workaround, or missing affordance is
   recorded the same day as a `[friction]`-tagged D item in the daily Discussion
   Tracker (`BAB-30xx`). No fix-it-now: friction is logged, not chased, unless it
   hard-blocks the loop (P0).

### Exit criteria (review session 2026-06-27)

- ≥ 10 Tickets completed against non-Babs repos through the full
  create → work → mobile-review → approve loop.
- Standing-context injection actively used (preview consulted, content iterated)
  for at least 2 Citizens.
- ≥ 10 friction entries collected and consolidated.
- A review session ranks friction by frequency × severity and converts the top
  items into the next PRP (which supersedes speculative selection from
  `BAB-2271` §Out of Scope).

### Rules during the window

- **No new feature development** on Babs except P0 fixes that hard-block the
  dogfood loop itself. Everything else goes to the friction log.
- Friction entries must record the concrete moment ("wanted to approve from
  phone but never noticed the Ticket reached `pending_approval`"), not abstract
  wishes.

### Predicted friction (to confirm or refute, not pre-fix)

- No `bb` CLI — Ticket creation only via browser/Mix may be the top entry.
- No push when a Ticket hits `pending_approval` — likely first real pull toward
  notifications (Web Push or an IM adapter slice).
- Cross-repo workspace/git boundaries (external checkouts, dirty trees,
  non-standard layouts).
- Standing-context capacity: whether Knowledge Home alone gives enough
  cross-Ticket continuity per Citizen.

## Open Questions

- Whether a minimal `bb ticket new` shim qualifies as a P0 blocker (loop
  ergonomics) or must wait as friction entry #1 — decided in the first days of
  the window by actual usage.
- Whether the Alfred and `.claude` Citizens get write access immediately or
  start read-only/propose-only for the first week.
- Where consolidated friction lives at review time: roll-up section in this PRP
  vs. a dedicated REF created at the review session.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-06-13 | Initial version | — |
| 2026-06-13 | Draft dogfood program: 2-week window, real-repo Citizens, friction-log-driven next PRP | Claude Code |
