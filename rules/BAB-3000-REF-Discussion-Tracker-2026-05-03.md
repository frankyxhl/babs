# REF-3000: Discussion Tracker 2026-05-03

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Active

---

## What Is It?

Per-day session tracker for BAB project per **COR-1201**. Records discussion items (D items) raised within today's session(s). Each D item has a numbered identifier, a lifecycle status, and is persisted in real-time so nothing is lost across session breaks.

`next_d` = **D8** (next new topic gets D8)

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
| D7 | Batch C — five Phase PRPs + Build Roadmap PLN + UI Design Spec | Closed | `BAB-2200`-`2204` (Phase 0-4), `BAB-2300` Build Roadmap PLN, `BAB-1004` UI Design Spec (with image-gen prompt templates per user request) |

---

## Archived Items

(none yet)

---

## Notes for Tomorrow's Session

- Batches A, B, C all complete. 19 BAB docs in `rules/`. All reflect from-scratch project framing.
- Doc-tier work is **done**. Next concrete action is **Phase 0 (PTY Stability Spike)** per `BAB-2200` — create `~/Projects/babs_pty_spike/` and run the test matrix from `BAB-1502`.
- Phase 0 result (pass/fail filed against `BAB-1103`) gates Phases 1-4. Don't write any production Babs Elixir code until Phase 0 is resolved.
- Use `BAB-1004` UI Design Spec's image-generation prompts to produce mockups now if desired; the mockups inform Phase 4 visual implementation.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial creation — captures D1-D4 from the architecture/naming/PRJ-init session | Claude Code |
| 2026-05-03 | D4 closed (Batch B 5/6 done); D5 added for `BAB-1501` open questions | Claude Code |
| 2026-05-03 | D5 closed (BAB-1501 dropped); D6 added & closed (from-scratch reframing sweep) | Claude Code |
| 2026-05-03 | D7 added & closed (Batch C — 5 PRPs + PLN + UI Design Spec) | Claude Code |
