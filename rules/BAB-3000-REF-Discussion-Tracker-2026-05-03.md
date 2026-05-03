# REF-3000: Discussion Tracker 2026-05-03

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Active

---

## What Is It?

Per-day session tracker for BAB project per **COR-1201**. Records discussion items (D items) raised within today's session(s). Each D item has a numbered identifier, a lifecycle status, and is persisted in real-time so nothing is lost across session breaks.

`next_d` = **D14** (next new topic gets D14)

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
| D8 | PTY spike location + name | Closed | Decided: option (a) — sub-mix-project at `spikes/hardline/` inside babs repo (no sibling repo, no main mix project yet). Name **`hardline`** chosen from The Matrix (双向 hardline phone)。完整命名探讨（古希腊/蝙蝠侠/Earpiece/Relay/Replay/Matrix 六个命名空间）记入 `BAB-1005`。Memory 已更新，`BAB-2200` 已整体修订。 |
| D9 | v0.1 conceptual world (5-concept architecture) | Closed | After multi-round design dialogue, settled on 5 concepts: Babs / Mayor / Citizen / Ticket / Hardline. "thread" rejected (collides with OS thread); "mission" + "assignment" + "need" collapsed into unified **Ticket** primitive (per ServiceNow / Linear / Jira issue typing). Mayor as special citizen for V0-L. Billboard = filesystem (`tickets/` directory). Captured in `BAB-1002` v0.1 vocabulary section, `BAB-1111` Ticket ADR, and `BAB-1107` Tmux lifecycle ADR. |
| D10 | Bootstrap → Flywheel architecture (17 phases) | Closed | v0.1 split into Bootstrap (Phase 0-1, manual) + Flywheel (Phase 2-16, Citizens build Babs in browser). Phase 1 SEED is the only manual phase post-spike. Once SEED ignites, all subsequent phases are user-piloted via BabsWeb terminal. Phase 6.5 "Manual Ticket Dogfood" inserted on Trinity recommendation. Captured in `BAB-2300` (master roadmap) and `BAB-2201` (Phase 1 SEED PRP, replaces old `BAB-2201` Core Supervision Skeleton). |
| D11 | Live-reload-safety (β + γ) post-Trinity | Closed | Trinity 3-model review (Codex/Gemini/DeepSeek, archived in `BAB-1006`) flagged Phase 2 chicken-and-egg: citizen modifying `:babs_citizens` kills itself on reload. Decision: **β + γ together** — independent OTP application (`:babs` + `:babs_citizens`) AND tmux detach + reattach. Captured in `BAB-1110`. `BAB-2200` Phase 0 spike amended to validate detach/reattach. |
| D12 | Multi-CLI day-1 + GitHub Copilot CLI added | Closed | Babs is AI-CLI-agnostic from Phase 1 SEED. Supported CLIs: `claude`, `codex`, `droid`, `pi` (pi.dev / pi-mono), `gh copilot`, future. Per-citizen `<name>.bob/citizen.toml` declares `cli`, `cli_args`, `env` (for API keys). Captured in `BAB-1112`. |
| D13 | Trinity 2nd-round review of integrated docs | Closed | Three-model post-integration review (Codex/Gemini/DeepSeek) found 12 issues across the landed docs. 8 fixed: BAB-1106 stale-body warning + 4KB chunk limit, BAB-1107 `babs-` prefix, BAB-1111 `bb` CLI transport spec + `assignees` list + Writer OTP app, BAB-1110 SourceWatcher reload mechanism, BAB-2201 implementation plan reordered + Flywheel Gate A/B split + reattach race fix, BAB-2300 seed count reconciled. 4 nice-to-have findings deferred to post-Phase-1. Full record in `BAB-1006`. |

---

## Archived Items

(none yet)

---

## Notes for Tomorrow's Session

- Round 0a foundational alignment **done**: 6 new ADRs (`BAB-1107`-`1112`), 1 new REF (`BAB-1006` Trinity Review archive), Phase 1 SEED PRP (`BAB-2201`), Build Roadmap rewrite (`BAB-2300` 17 phases incl. 6.5), `BAB-2200` amended for detach/reattach validation, `BAB-1002` vocabulary updated with v0.1 terms, 5 legacy docs (`BAB-1001`/`1003`/`1102`/`1104`/`1106`) given SUPERSEDED banners pointing to new ADRs. Old Phase PRPs (`BAB-2202`/`2203`/`2204`) and old Phase 1 PRP deleted. Total BAB docs in `rules/` after this session: 27.
- Round 0a **partial debt remaining**: full rewrites of the 5 banner-marked legacy docs are deferred to post-Phase-1 — Babs Citizens themselves do this rewrite once the flywheel is alive. Banner notes which ADRs are now authoritative; legacy docs remain as historical context.
- **Next concrete action**: **Phase 0 (Hardline PTY Spike)** per `BAB-2200`. Create `spikes/hardline/` sub-mix-project; run the validation matrix per `BAB-1502` plus the new detach/reattach scenario per `BAB-1110`.
- After Phase 0 passes, **Phase 1 SEED** per `BAB-2201` ignites the flywheel. Phase 1 is the **last manual build phase**; everything from Phase 2 onward is built BY Citizens IN browser.
- Trinity review archive (`BAB-1006`) is the historical record of why specific design choices were made (Phase 6.5 insertion, β + γ pairing, multi-CLI day-1, etc.). Refer to it before challenging any v0.1 architectural choice.
- Use `BAB-1004` UI Design Spec's image-generation prompts to produce mockups now if desired; the mockups inform Phase 4-5 (NewCitizenLive + multi-citizen index) visual implementation.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial creation — captures D1-D4 from the architecture/naming/PRJ-init session | Claude Code |
| 2026-05-03 | D4 closed (Batch B 5/6 done); D5 added for `BAB-1501` open questions | Claude Code |
| 2026-05-03 | D5 closed (BAB-1501 dropped); D6 added & closed (from-scratch reframing sweep) | Claude Code |
| 2026-05-03 | D7 added & closed (Batch C — 5 PRPs + PLN + UI Design Spec) | Claude Code |
| 2026-05-03 | D8 added & closed (PTY spike location + name = `spikes/hardline/`); `BAB-1005` Naming History added; `BAB-2200` integrally revised (path + erlexec version fix + Channel→xterm.js byte path acceptance criterion); memory updated; `BAB-0000` index updated | Claude Code |
| 2026-05-03 | D9-D12 added & closed in single Round 0a foundational alignment batch. Created: `BAB-1006` (Trinity review archive), `BAB-1107`-`1112` (6 new ADRs), `BAB-2201` (Phase 1 SEED PRP, replacing old Core Supervision Skeleton), `BAB-2300` rewritten (17-phase Bootstrap→Flywheel). Modified: `BAB-2200` (detach/reattach), `BAB-1002` (v0.1 vocabulary). Banner-marked: `BAB-1001`/`1003`/`1102`/`1104`/`1106` as Partially Superseded. Deleted: old `BAB-2201`/`2202`/`2203`/`2204`. Memory + index updated. Trinity review (Codex/Gemini/DeepSeek) drove key changes including Phase 6.5 insertion and β + γ pairing. | Claude Code |
| 2026-05-03 | D13 added & closed: Trinity 2nd-round review of post-integration docs. 12 findings; 8 fixed (Round 0a-fix batch); 4 nice-to-have deferred. Files modified: `BAB-1006` (added 2nd-round summary), `BAB-1106` (STALE BODY WARNING + 4KB chunk constraint + corrected layer-3 description), `BAB-1107` (lifecycle table `babs-<name>` prefix), `BAB-1110` (Reload Mechanism section: `Babs.Citizens.SourceWatcher`), `BAB-1111` (`bb` CLI transport spec + `assignees` list + Writer OTP app), `BAB-2201` (Flywheel Gate A/B + reordered Implementation Plan + reattach race fix), `BAB-2300` (two seed citizens + Gate A/B acceptance). | Claude Code |
