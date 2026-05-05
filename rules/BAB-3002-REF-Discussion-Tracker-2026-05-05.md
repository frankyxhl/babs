# REF-3002: Discussion Tracker 2026-05-05

**Applies to:** BAB project
**Last updated:** 2026-05-05
**Last reviewed:** 2026-05-05
**Status:** Active

---

## What Is It?

Per-day session tracker for BAB project per **COR-1201**. Records discussion
items raised within today's session(s), with a numbered identifier, lifecycle
status, and notes that survive interruptions.

---

`next_d` = **D3** (next new topic gets D3)

---

## Active Items

| ID | Topic | Status | Notes |
|----|-------|--------|-------|
| D1 | Phase 3 SQLite citizens table + auto-respawn preparation | Active | PR #10 Phase 2a merged. Cleaned Phase 2a worktree/branch and created clean Phase 3 prep worktree from `origin/main`. Drafted `BAB-2210` PRP and `BAB-1505` SQLite registry operations SOP. Trinity fast-review R5 passed with GLM and DeepSeek; `BAB-2210` is Approved. Next route: CHG -> TDD implementation. Follow-up: `BAB-1001` still has old `Babs.Repo` top-level diagram and should be reconciled in the later architecture rewrite. |
| D2 | Phase 4 NewCitizenLive spawn UI preparation | Active | PR #11 Phase 3 merged. Cleaned old phase worktrees while preserving the Trinity review-status note outside the public commit. Created Phase 4 prep worktree on `codex/phase-4-prep` rebased to merged `origin/main`. Drafted `BAB-2212` PRP for `/citizens/new`: spawn boundary, TOML + SQLite consistency, shell preset for deterministic BDD, no arbitrary env editing until secret-storage/redaction design exists. Operator resolved PRP questions: ship without env editing, label GitHub Copilot preset `copilot-cli` while writing `cli = "gh"` + `cli_args = ["copilot"]`, and preserve TOML after SQLite failure for inspection. Trinity fast-review R1/R2 found blockers; R3 returned PASS with advisories from GLM and DeepSeek, and low-cost advisories were folded into the PRP. Drafted `BAB-2213` CHG for TDD implementation; Trinity CHG review R3 passed with GLM and DeepSeek. Operator approved implementation. Phase 4 is implemented locally with validation passed. Scoped Trinity fast-review on web, citizens-core, and BDD slices passed after review findings were fixed. PR #12 was opened by `ryosaeba1985`; five rounds of GitHub Codex findings were fixed, including TOML install race, cleanup error handling, symlink cwd escapes, TOML error mapping, `/citizens/new` route shadowing of a real `new` Citizen, cwd symlink-swap revalidation, workspace-root `/` handling, lifecycle exit failure persistence, and Gate A detach hang cleanup, with validation rerun. Final capped Codex review found a socket-token redirect P1; operator asked to finish that known item without continuing the loop. The targeted socket-token fix is implemented, validated, and ready for operator merge. |

---

## Archived Items

(none yet)

---

## Notes

- The main worktree has pre-existing local changes and is intentionally not used
  for Phase 3 prep.
- Phase 3 prep uses a clean sibling worktree on branch `codex/phase-3-prep`.
- Phase 4 prep uses a clean sibling worktree on branch `codex/phase-4-prep`.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-05 | Initial version | — |
| 2026-05-05 | Add D1 for Phase 3 preparation after Phase 2a merge cleanup | Codex |
| 2026-05-05 | Add D2 for Phase 4 spawn UI preparation and cleanup of old phase worktrees | Codex |
| 2026-05-05 | Resolve Phase 4 PRP open questions for env editing, `copilot-cli` label, and TOML preservation after SQLite failure | Codex |
| 2026-05-05 | Record Trinity GLM/DeepSeek review outcome for Phase 4 PRP and next CHG step | Codex |
| 2026-05-05 | Draft `BAB-2213` Phase 4 implementation CHG | Codex |
| 2026-05-05 | Record Trinity GLM/DeepSeek PASS on `BAB-2213` CHG and pending operator approval | Codex |
| 2026-05-05 | Record operator approval for `BAB-2213` and start Phase 4 implementation | Codex |
| 2026-05-05 | Record local Phase 4 implementation and validation pass, pending code review and PR | Codex |
| 2026-05-05 | Record full-scope Trinity code-review execution blocker and remove host-specific worktree path from active notes | Codex |
| 2026-05-05 | Record scoped Trinity fast-review pass and Phase 4 PR readiness | Codex |
| 2026-05-05 | Record PR #12 GitHub Codex review fixes and validation rerun | Codex |
| 2026-05-05 | Record second PR #12 GitHub Codex review fixes and validation rerun | Codex |
| 2026-05-05 | Record third PR #12 GitHub Codex review fix for `/citizens/new` route shadowing and validation rerun | Codex |
| 2026-05-05 | Record fourth PR #12 GitHub Codex review fixes for cwd symlink-swap revalidation and workspace-root `/` handling | Codex |
| 2026-05-05 | Record fifth PR #12 Codex review fix for lifecycle exits and local Gate A detach cleanup | Codex |
| 2026-05-06 | Record final targeted socket-token redirect fix and stop Codex review loop per operator cap | Codex |
