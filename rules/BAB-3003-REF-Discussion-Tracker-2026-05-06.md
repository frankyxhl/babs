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

`next_d` = **D7** (next new topic gets D7)

---

## Active Items

| ID | Topic | Status | Notes |
|----|-------|--------|-------|
| D1 | Phase 5 preparation | Active | Phase 4 PR #12 is merged. `BAB-2214` PRP approved after Trinity fast-review R2 with GLM and DeepSeek. `BAB-2215` CHG approved after Trinity fast-review strict `COR-1602` + `COR-1609`: GLM 9.49/10, DeepSeek 9.0/10. Phase 5 is implemented locally on `codex/phase-5-prep`: `/citizens` index, root redirect, compact terminal tabs, preserved `?full=1`, socket-token-preserving links, `StatusSnapshot`, and browser-harness Phase 5 multi-Citizen index/tab/fd BDD. Local validation passed: ExUnit/coverage (`:babs_citizens` 83.59%, `:babs` 84.10%), JS tests, browser-harness BDD, Playwright smoke, Gate A, Alfred validation, and whitespace check. Trinity implementation fast-review passed with GLM 9.19/10 and DeepSeek 9.38/10. GitHub Codex PR review R1/R2/R3 findings were fixed, and R4 on the current head reported no major issues. The 30 minute fd stability run stays deferred to Phase 6/M2. |
| D2 | Phase 6 Stop/Start/Restart UI | Done | Created and approved `BAB-2216` CHG for Stop/Start/Restart UI. Trinity fast-review passed with GLM 9.05/10 and DeepSeek 9.0/10, no blockers. Implemented and merged in PR #14: SQLite-sourced start/restart lifecycle APIs, same-slug lifecycle lock, `StatusSnapshot.actions`, `/citizens` row controls, default terminal controls, and browser-harness Phase 6 lifecycle/restart reconciliation BDD. Local validation passed: ExUnit/coverage (`:babs_citizens` 83.88%, `:babs` 82.17%), JS tests, browser-harness BDD, Playwright smoke, Gate A, Alfred validation, and whitespace check. Trinity implementation review passed on scoped `apps/` review with GLM PASS and DeepSeek PASS; DeepSeek's conditional missing Stop-click test was fixed. GitHub Codex R1 P2 sibling-control race was fixed with async in-flight lifecycle UI; R2 reported no major issues. Local main is clean and 4000 runs from `babs-web-main`. |
| D3 | M3 Phase 7-12 ticket/billboard planning | Active | Operator approved continuous Phase 7-12 delivery as one M3 goal while keeping reviewable PR slices. Drafted `BAB-2217` PRP for filesystem-first Tickets/Billboard: Phase 7 ticket storage/writer/CLI, Phase 8 `/tickets` UI, Phase 9 assignment/injection, Phase 10 state machine, Phase 11 approval/reject, and Phase 12 cross-Citizen comments. Trinity fast-review R5 passed with GLM and DeepSeek and no PRP blockers. Operator decisions recorded: Phase 6.5 dogfood waived as gate, assignment auto-starts stopped Citizens, all communication is persisted to Ticket/Billboard history first, terminal notifications are mirrors only, and Tickets are runtime data under a gitignored configurable tickets root. Next step: prepare Phase 7 implementation CHG/TDD plan for the continuous Phase 7-12 goal. |
| D4 | M3 execution contract pattern | Active | Operator approved turning the continuous Phase 7-12 defaults into an execution contract before implementation. Drafted and approved `BAB-2218` CHG to authorize automated slice execution, max five GitHub Codex review rounds, repo-external configurable Ticket data root, deferred long validations, Clare/Dylan/Elena/Flora multi-CLI validation, PR/merge policy, stop conditions, UI action-button icon requirements, and a reusable SOP template idea for future multi-phase projects. Trinity fast-review R2 passed with GLM and DeepSeek and no blockers. PR #15 merged the PRP and execution contract to `main`. |
| D5 | Phase 7 Ticket storage core CHG | Done | PR #16 merged Phase 7 into `main`: configurable Ticket root, strict markdown/frontmatter parsing with `yaml_elixir`, date-scoped ID allocation, history JSONL, read/list/show store, per-ticket writer, public API, and temporary `mix babs.ticket.*` bridge. Trinity implementation review passed with GLM and DeepSeek. GitHub Codex reached R4 on the current head with no major issues after fixes for oversized comments, zero-sequence IDs, multiline titles, orphan history, and create/list hardening. Local `main` was pulled clean after merge. |
| D6 | Phase 8 Ticket UI and watcher CHG | Done | PR #17 merged Phase 8 into `main`: `/tickets`, `/tickets/<id>`, `/citizens` cross-linking, semantic icon buttons, filesystem watcher PubSub refresh, invalid Ticket visibility, and browser-harness BDD. Local validation passed: ExUnit 161 `:babs_citizens` tests and 57 `:babs` tests, coverage `:babs_citizens` 82.62% and `:babs` 84.39%, JS tests, browser-harness BDD with Phase 8 Ticket scenarios, Playwright E2E smoke, Gate A, Alfred validation, whitespace check, and privacy scan. Trinity implementation review passed with GLM and DeepSeek; GitHub Codex reported no major issues on the merge head. Local `main` was pulled clean, isolated Chrome BDD process was cleaned up, and `:4000` was restarted from detached tmux session `babs-web-main`. |
| D7 | Phase 9-10 Ticket assignment and state machine | Active | PR C is implemented locally on branch `codex/m3-phase-9-10-assignment-state` under the approved M3 execution contract. `BAB-2221` adds assignment, stopped-Citizen auto-start, history-first prompt injection, state-machine enforcement, temporary Mix bridge commands, semantic-icon UI controls, ExUnit/LiveView coverage, and browser-harness BDD for assignment plus pending approval. Local validation passed after Trinity advisory fixes: format, compile warnings-as-errors, ExUnit (`:babs_citizens` 181 tests, `:babs` 59 tests), coverage (`:babs_citizens` 82.36%, `:babs` 84.36%), JS tests, browser-harness BDD, Playwright E2E smoke, Gate A, Alfred validation, whitespace check, and privacy scan. Trinity implementation review R1 and R2 both passed with GLM and DeepSeek; R1 low-cost advisories were fixed before R2. Next step: PR/Codex loop. |

---

## Archived Items

(none yet)

---

## Notes for Next Session

- Phase 6 PR #14 is merged; local main is clean and 4000 runs from `babs-web-main`.
- Continue the approved M3 Phase 7-12 execution contract with Phase 8 PR B
  after Phase 7 PR #16 merge.
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
| 2026-05-06 | Record GitHub Codex R1 oversized-comment fix for PR #16 | Codex |
| 2026-05-06 | Record GitHub Codex R2 zero-sequence Ticket ID fix for PR #16 | Codex |
| 2026-05-06 | Record GitHub Codex R3 multiline title and orphan history fixes for PR #16 | Codex |
| 2026-05-06 | Mark Phase 7 PR #16 merged and add D6 for Phase 8 Ticket UI and watcher CHG | Codex |
| 2026-05-06 | Record Phase 8 plan approval, implementation, and local validation pass | Codex |
| 2026-05-06 | Mark Phase 8 PR #17 merged and add D7 for Phase 9-10 PR C planning | Codex |
| 2026-05-06 | Mark `BAB-2221` approved after Trinity R2 GLM/DeepSeek PASS | Codex |
