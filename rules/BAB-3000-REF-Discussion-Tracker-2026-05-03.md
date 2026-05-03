# REF-3000: Discussion Tracker 2026-05-03

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Active

---

## What Is It?

Per-day session tracker for BAB project per **COR-1201**. Records discussion items (D items) raised within today's session(s). Each D item has a numbered identifier, a lifecycle status, and is persisted in real-time so nothing is lost across session breaks.

`next_d` = **D7** (next new topic gets D7)

---

## Active Items

| ID | Topic | Status | Notes |
|----|-------|--------|-------|
| D1 | Elixir + Phoenix architecture for the multi-agent runtime | Closed | Captured as `BAB-1100` ADR + `BAB-1001` REF; three-model architecture review done (Codex, DeepSeek, +self) |
| D2 | Project name for the runtime (paired with Alfred) | Closed | Decided: **Babs** — captured as `BAB-1101` ADR |
| D3 | Initialize Alfred PRJ docs in `/Users/frank/Projects/babs/` | Closed | Batch A executed: 9 PRJ docs + CLAUDE.md + README + .gitignore + this tracker |
| D4 | Batch B planning (foundational SOPs, evolution philosophy, glossary) | Closed | Batch B written: `BAB-1003`, `BAB-1500`, `BAB-1502`, `BAB-1800`, `BAB-1801` |
| D5 | `BAB-1501` Migration Cutover SOP | Closed | **Dropped** — Babs is from-scratch with no Python coexistence; no cutover needed. See D6 sweep. |
| D6 | From-scratch reframing — drop migration narrative across all docs | Closed | Sweep done: `BAB-1100`, `BAB-1001`, `BAB-1500`, `BAB-2100`, `BAB-1106`, `README.md`, `CLAUDE.md` revised. `BAB-1106` updated with React-via-LiveView-hooks + xterm.js explicit naming. |

---

## Archived Items

(none yet)

---

## Notes for Tomorrow's Session

- Batch A + B complete. All docs reflect from-scratch project framing.
- Next: Batch C — five Phase PRPs (`BAB-2200` Phase 0 PTY spike, `BAB-2201` Phase 1 supervision skeleton, `BAB-2202` Phase 2 A2A + first citizen, `BAB-2203` Phase 3 Connectors, `BAB-2204` Phase 4 BabsWeb) and `BAB-2300` Build Roadmap PLN. (Phase plan is now 5 phases per `BAB-1001` §"Build Phases", not 4.)
- Phase 0 (PTY stability spike, see `BAB-1502`) gates Phase 1+ — do not start any production Babs Elixir code until Phase 0 is run and `BAB-1103` Method A vs Method B is empirically resolved.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial creation — captures D1-D4 from the architecture/naming/PRJ-init session | Claude Code |
| 2026-05-03 | D4 closed (Batch B 5/6 done); D5 added for `BAB-1501` open questions | Claude Code |
| 2026-05-03 | D5 closed (BAB-1501 dropped); D6 added & closed (from-scratch reframing sweep) | Claude Code |
