# REF-3003: Discussion Tracker 2026-05-06

**Applies to:** BAB project
**Last updated:** 2026-05-06
**Last reviewed:** 2026-05-06
**Status:** Active

---

## What Is It?

Per-day session tracker for BAB project per COR-1201. Records discussion items
raised during 2026-05-06 sessions so planning decisions survive context breaks.

---

`next_d` = **D6** (next new topic gets D6)

---

## Active Items

| ID | Topic | Status | Notes |
|----|-------|--------|-------|
| D1 | Phase 5 preparation | Active | Phase 4 PR #12 is merged. `BAB-2214` PRP approved after Trinity fast-review R2 with GLM and DeepSeek. `BAB-2215` CHG approved after Trinity fast-review strict `COR-1602` + `COR-1609`: GLM 9.49/10, DeepSeek 9.0/10. Phase 5 is implemented locally on `codex/phase-5-prep`: `/citizens` index, root redirect, compact terminal tabs, preserved `?full=1`, socket-token-preserving links, `StatusSnapshot`, and browser-harness Phase 5 multi-Citizen index/tab/fd BDD. Local validation passed: ExUnit/coverage (`:babs_citizens` 83.59%, `:babs` 84.10%), JS tests, browser-harness BDD, Playwright smoke, Gate A, Alfred validation, and whitespace check. Trinity implementation fast-review passed with GLM 9.19/10 and DeepSeek 9.38/10. GitHub Codex PR review R1/R2/R3 findings were fixed, and R4 on the current head reported no major issues. The 30 minute fd stability run stays deferred to Phase 6/M2. |
| D2 | Phase 6 Stop/Start/Restart UI | Done | Created and approved `BAB-2216` CHG for Stop/Start/Restart UI. Trinity fast-review passed with GLM 9.05/10 and DeepSeek 9.0/10, no blockers. Implemented and merged in PR #14: SQLite-sourced start/restart lifecycle APIs, same-slug lifecycle lock, `StatusSnapshot.actions`, `/citizens` row controls, default terminal controls, and browser-harness Phase 6 lifecycle/restart reconciliation BDD. Local validation passed: ExUnit/coverage (`:babs_citizens` 83.88%, `:babs` 82.17%), JS tests, browser-harness BDD, Playwright smoke, Gate A, Alfred validation, and whitespace check. Trinity implementation review passed on scoped `apps/` review with GLM PASS and DeepSeek PASS; DeepSeek's conditional missing Stop-click test was fixed. GitHub Codex R1 P2 sibling-control race was fixed with async in-flight lifecycle UI; R2 reported no major issues. Local main is clean and 4000 runs from `babs-web-main`. |
| D3 | M3 Phase 7-12 ticket/billboard planning | Active | Operator approved continuous Phase 7-12 delivery as one M3 goal while keeping reviewable PR slices. Drafted `BAB-2217` PRP for filesystem-first Tickets/Billboard: Phase 7 ticket storage/writer/CLI, Phase 8 `/tickets` UI, Phase 9 assignment/injection, Phase 10 state machine, Phase 11 approval/reject, and Phase 12 cross-Citizen comments. Trinity fast-review R5 passed with GLM and DeepSeek and no PRP blockers. Operator decisions recorded: Phase 6.5 dogfood waived as gate, assignment auto-starts stopped Citizens, all communication is persisted to Ticket/Billboard history first, terminal notifications are mirrors only, and Tickets are runtime data under a gitignored configurable tickets root. Next step: prepare Phase 7 implementation CHG/TDD plan for the continuous Phase 7-12 goal. |
| D4 | M3 execution contract pattern | Active | Operator approved turning the continuous Phase 7-12 defaults into an execution contract before implementation. Drafted and approved `BAB-2218` CHG to authorize automated slice execution, max five GitHub Codex review rounds, repo-external configurable Ticket data root, deferred long validations, Clare/Dylan/Elena/Flora multi-CLI validation, PR/merge policy, stop conditions, UI action-button icon requirements, and a reusable SOP template idea for future multi-phase projects. Trinity fast-review R2 passed with GLM and DeepSeek and no blockers. PR #15 merged the PRP and execution contract to `main`. |
| D5 | Phase 7 Ticket storage core CHG | Active | Began PR A under the approved M3 execution contract on branch `codex/m3-phase-7-ticket-core`. Drafted and approved `BAB-2219` to implement configurable Ticket root, strict markdown/frontmatter parsing with `yaml_elixir`, date-scoped ID allocation, history JSONL, read/list/show store, per-ticket writer, public API, and minimal command surface. Trinity fast-review R3 passed with GLM and DeepSeek and no blockers after folding in config precedence, atomic create, `updated_at`, sort order, `assignees: []` invariant, temp-file cleanup, and history/communication semantics. Implemented locally with RED tests: 156 `:babs_citizens` tests and 51 `:babs` tests pass; coverage is `:babs_citizens` 82.49% and `:babs` 81.49%; Gate A passes; manual temporary-root command smoke created/listed/showed five Tickets. Trinity implementation review passed with GLM and DeepSeek; actionable findings for writer idle timer refs, pre-write validation, ID sequence exhaustion, non-raising claim, and placeholder cleanup were fixed. The implementation uses a documented temporary `mix babs.ticket.*` bridge while ADR-complete `bb ticket` over UDS remains deferred. Next step: open PR. |

---

## Archived Items

(none yet)

---

## Notes for Next Session

- Phase 6 PR #14 is merged; local main is clean and 4000 runs from `babs-web-main`.
- Continue from local Phase 7 implementation: open the PR with `gh` as
  `ryosaeba1985` and run the GitHub Codex review loop.
- Phase 5 PR #13 reached GitHub Codex R4 with no major issues on the current
  head.
- Preserve the user-level GitHub identity rule: visible GitHub writes use `gh`
  as `ryosaeba1985`.
- Do not publish private IPs, local host paths, tokens, or machine-local URLs in
  public PR text.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-06 | Initial tracker with D1 Phase 5 preparation | Codex |
| 2026-05-06 | Record local Phase 5 implementation and validation evidence | Codex |
| 2026-05-06 | Record Trinity implementation fast-review PASS | Codex |
| 2026-05-06 | Record GitHub Codex PR review R1 P2 fix | Codex |
| 2026-05-06 | Record GitHub Codex PR review R2 P2 fix | Codex |
| 2026-05-06 | Record GitHub Codex PR review R3 fixes and refreshed validation | Codex |
| 2026-05-06 | Add D2 for Phase 6 CHG preparation and note Phase 5 Codex R4 clear result | Codex |
| 2026-05-06 | Record `BAB-2216` Trinity fast-review approval and advisory fold-in | Codex |
| 2026-05-06 | Record local Phase 6 implementation and validation evidence | Codex |
| 2026-05-06 | Record Phase 6 Trinity implementation review pass and Stop-click test fix | Codex |
| 2026-05-06 | Add D3 for M3 Phase 7-12 Ticket/Billboard PRP planning | Codex |
| 2026-05-06 | Record Phase 7-12 operator decisions and Trinity PRP review pass | Codex |
| 2026-05-06 | Add D4 for M3 execution contract and reusable SOP template idea | Codex |
| 2026-05-06 | Mark `BAB-2218` approved after Trinity fast-review R2 and record UI icon requirement | Codex |
| 2026-05-06 | Add D5 for Phase 7 Ticket storage core CHG planning | Codex |
| 2026-05-06 | Mark `BAB-2219` approved after Trinity R3 plan review | Codex |
| 2026-05-06 | Record local Phase 7 implementation and validation evidence | Codex |
| 2026-05-06 | Record Phase 7 Trinity implementation review pass and fixes | Codex |
