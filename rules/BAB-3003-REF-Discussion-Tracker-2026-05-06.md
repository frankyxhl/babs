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

`next_d` = **D13** (next new topic gets D13)

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
| D7 | Phase 9-10 Ticket assignment and state machine | Done | PR #18 merged Phase 9-10 into `main`: Ticket assignment API/UI, stopped-Citizen auto-start, history-first prompt injection, strict state-machine enforcement, temporary Mix bridge commands, semantic-icon controls, invalid-slug guards, redacted pane lookup errors, concurrent assignment coverage, and browser-harness BDD for assignment plus pending approval. Local validation passed after Trinity advisory fixes: ExUnit (`:babs_citizens` 181 tests, `:babs` 59 tests), coverage (`:babs_citizens` 82.36%, `:babs` 84.36%), JS tests, browser-harness BDD, Playwright E2E smoke, Gate A, Alfred validation, whitespace check, and privacy scan. Trinity implementation review R1/R2 passed with GLM and DeepSeek, and GitHub Codex reported no major issues on the merge head. Local `main` was pulled clean and `:4000` was restarted from detached tmux session `babs-web-main`. |
| D8 | Phase 11 Approval UI | Done | PR #19 merged Phase 11 into `main`: pending-approval approve/reject controls, required rejection feedback, history-first feedback injection into assigned Citizen terminals, temporary Mix bridge commands, LiveView/BDD/unit coverage, and docs. Trinity implementation R1-R6 passed with GLM/DeepSeek after advisory fixes for approval guard ordering, empty feedback messaging, empty-assignee invariant coverage, multi-assignee feedback coverage, nil-event rejection bypass, oversized rejection feedback history prevalidation, and rejection-feedback timeline rendering. Local validation before merge passed: ExUnit (`:babs_citizens` 187 tests, `:babs` 60 tests), coverage (`:babs_citizens` 83.00%, `:babs` 85.31%), JS tests, browser-harness BDD, Playwright E2E smoke, Gate A, Alfred validation, whitespace check, and privacy scan. GitHub Codex R3 on the merge head reported no major issues. Local `main` is clean and `:4000` was restarted from detached tmux session `babs-web-main`. |
| D9 | Phase 12 Cross-Citizen Ticket Comments | Active | `BAB-2223` CHG is approved on `codex/m3-phase-12-ticket-comments` for `bb ticket comment`, live comment notification mirrors, Ticket detail comment form, Babs-owned tmux runtime env/PATH support, BDD, validation, and review flow. The plan keeps ADR-complete UDS `bb` deferred but adds a tracked command bridge so Citizens can use the intended `bb ticket comment <id> "..."` command shape during M3. Trinity plan review R4 passed with GLM and DeepSeek after blockers/advisories were folded in. Phase 12 is implemented locally with validation passing: ExUnit (`:babs_citizens` 194 tests, `:babs` 62 tests), coverage (`:babs_citizens` 83.11%, `:babs` 85.69%), JS tests, browser-harness BDD including ticket comment notification, Playwright E2E including browser comment form, Gate A, Alfred validation, whitespace check, and privacy scan. Trinity implementation review passed through GLM/DeepSeek R2, DeepSeek R3, GLM scoped R4, and parser-fix GLM/DeepSeek scoped review. PR #20 Codex R1 P3 option-looking comment body finding was fixed and validated locally. Next step: push fix and continue GitHub Codex review loop. |
| D10 | Phase 12a PFC-informed hardline relay reliability | Active | Operator asked whether Babs should align with the `prefrontal-cortex` approach for tmux agent interaction. Decision: add Phase 12a after Phase 12, not as a decimal phase. Drafted `BAB-2224` PRP for adaptive system prompt delivery and upstream AI CLI JSONL reply capture. Babs should borrow PFC's reliable paste/submit and JSONL response mechanics, while keeping Babs' own architecture: local Ticket/Billboard history as the authoritative communication surface, no Discord relay copy, no direct model API calls, and pane capture as fallback/diagnostic only. Trinity plan review R1 (`.trinity/reviews/20260506-200953-rules`) found stale phase references; R2 (`.trinity/reviews/20260506-201548-rules`) passed GLM/DeepSeek with only advisories, which were folded into the docs; R3 (`.trinity/reviews/20260506-202119-rules`) passed GLM/DeepSeek and final wording/timeline advisories were folded in; R4 (`.trinity/reviews/20260506-202633-rules`) passed GLM/DeepSeek with no blockers. `BAB-2224` is Approved. `BAB-2226` implementation CHG passed strict Trinity review R4 with GLM 9.2/10 and DeepSeek 9.0/10; `BAB-2226` is Approved. Phase 12a is implemented locally with adaptive system delivery, Ticket new/chat polish, read-only Claude/Codex transcript parsing, bounded reply capture, explicit unsupported Copilot transcript behavior, browser-terminal keyboard parity, immediate transcript visibility, and restart reconnect handling. GitHub Codex PR #21 R1 P2 found premature `:no_transcripts` termination; fixed by keeping missing transcript files pending until reply capture succeeds or expires. Trinity follow-up review on PR #21 fixes passed GLM/DeepSeek with no blockers, and advisories were cleaned up. GitHub Codex PR #21 R3 P2 found follow-up comment/rejection prompts did not schedule reply capture; fixed by registering capture after successful comment notification and rejection feedback injection. GitHub Codex PR #21 R4 P2 found embedded terminal-response sequences could bypass input filtering; fixed by rejecting those sequences anywhere in browser/server input. GitHub Codex PR #21 R5 P2 found storage-only comments still recorded notification-attempt history; fixed by honoring `notify_assignees: false` when building history events. Trinity follow-up R3/R4/R5 for the final PR #21 fixes passed GLM/DeepSeek with no blockers. The browser terminal now owns tmux/readline shortcuts including tmux prefix, Ctrl-A, Alt-B, and extension-style `Escape` focus recovery when the page can observe the key event; operator-side Vimium site exclusion is still needed for full `Escape` parity because Vimium can consume Escape before page JavaScript. Reconnect snapshots prefer the live tmux pane over stale transcript fallback. Final local validation for the Phase 12a/13 working tree passed: ExUnit (`:babs_citizens` 235 tests, `:babs` 75 tests), coverage (`:babs_citizens` 81.28%, `:babs` 87.55%), 15 JS tests, browser-harness BDD, 13 Playwright E2E tests, Gate A, Alfred validation, whitespace check, and privacy scan. R5 was the operator-capped final Codex round, so no R6 review was requested. |
| D11 | Phase 13 imported external tmux session attach | Active | Operator requested a feature where an existing Citizen can attach to a tmux session that was created outside Babs and has not been attached by Babs. Decision: make this Phase 13, backed by `BAB-1113` ADR and `BAB-2225` PRP. Imported sessions default to external ownership: Babs can attach, stream, inject, persist transcript, detach, and reattach, but it must not kill the external tmux session. UI should show a persistent `Imported · External-owned` style badge wherever lifecycle controls appear and `Detach only · tmux stays running` near imported lifecycle controls. Existing Citizen Roles/Inspector/Mayor/Federation phases shift to Phase 14-17. Phase 13 remains scoped to existing Citizen attach; creating a new Citizen identity from an imported pane is deferred. Trinity R4 passed GLM/DeepSeek with no blockers. `BAB-2225` is Approved. `BAB-2227` CHG passed Trinity R1 GLM/DeepSeek plan review with no blockers and is Approved. Phase 13 is implemented locally with tmux inventory, imported metadata, external-owned lifecycle, `/citizens/attach`, imported badges/reminders, LiveView coverage, browser-harness BDD, and Playwright E2E proving Attach/Detach leaves the external tmux session alive. Trinity implementation review passed with GLM 9.2/10 and DeepSeek PASS; post-review advisories for attach-failure coverage and explicit reply-capture default were fixed. GitHub Codex PR #21 R1 P2 found positional imported targeting; fixed by using stable `%pane_id` as the operational target while preserving the positional target for display. GitHub Codex PR #21 R2 P1 found pane IDs were still being passed to `attach-session`; fixed by selecting the pane id but attaching to the recorded tmux session name/session id. GitHub Codex PR #21 R5 P2 found imported terminal snapshots still captured `babs-<slug>` instead of the attached external pane; fixed by exposing the Pane's tmux target and snapshotting that target. A post-R5 GitHub Codex P2 found the attach UI still submitted positional targets; fixed by submitting stable `%pane_id` values from both the select and quick-pick button. Trinity implementation R3/R4/R5 for the final fixes passed GLM/DeepSeek with no blockers. Hardline pane shutdown now detaches tmux attach clients reliably while preserving detached Babs-owned/imported tmux sessions. Gate A was isolated from broad Citizen autostart so validation no longer attaches AI/Imported Citizens just to run the sentinel gate. |
| D12 | External repo design references | Active | Operator asked for subagent research on `bfly123/claude_codex_bridge` and `liliMozi/openhanako`. CCB takeaways for Phase 13: structured tmux inventory, exact pane identity, buffer paste, explicit external-attach ownership, and no auto-recovery/kill behavior for external bindings. OpenHanako takeaways for later Billboard/Inspector design: treat Ticket history JSONL as the channel stream, add per-Citizen read cursors/bookmarks in SQLite, scope events by Citizen/Ticket/session, keep volatile abort state separate from durable history, and improve UI with activity/unread badges plus right-side Ticket/workspace/transcript panels. Avoid copying CCB's aggressive project-owned cleanup into imports or OpenHanako's ad hoc Markdown parsing/Electron split. |

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
| 2026-05-06 | Mark Phase 9-10 PR #18 merged and add D8 for Phase 11 Approval UI planning | Codex |
| 2026-05-06 | Mark `BAB-2222` approved after Trinity R4 GLM/DeepSeek PASS | Codex |
| 2026-05-06 | Record local Phase 11 implementation and validation evidence | Codex |
| 2026-05-06 | Record Phase 11 Trinity implementation R1 advisory fixes and post-fix validation | Codex |
| 2026-05-06 | Record Phase 11 Trinity implementation R2 pass and multi-assignee coverage fix | Codex |
| 2026-05-06 | Record Phase 11 Trinity implementation R3 nil-event bypass fix and post-fix validation | Codex |
| 2026-05-06 | Record Phase 11 Trinity implementation R4 GLM/DeepSeek PASS | Codex |
| 2026-05-06 | Record PR #19 Codex R1 P2 history prevalidation fix and post-fix validation | Codex |
| 2026-05-06 | Record Trinity R5 PASS on post-Codex-R1 fix | Codex |
| 2026-05-06 | Record PR #19 Codex R2 P2 rejection feedback timeline rendering fix and post-fix validation | Codex |
| 2026-05-06 | Record Trinity R6 PASS on post-Codex-R2 fix | Codex |
| 2026-05-06 | Mark Phase 11 PR #19 merged and add D9 for Phase 12 Ticket comments CHG | Codex |
| 2026-05-06 | Mark `BAB-2223` approved after Trinity R4 GLM/DeepSeek PASS | Codex |
| 2026-05-06 | Record Phase 12 local implementation and validation results before Trinity implementation review | Codex |
| 2026-05-06 | Record Phase 12 Trinity implementation review results and advisory coverage fixes | Codex |
| 2026-05-06 | Record PR #20 Codex R1 parser fix and parser-fix Trinity scoped review | Codex |
| 2026-05-06 | Add D10 and BAB-2224 for Phase 12a PFC-informed hardline relay reliability | Codex |
| 2026-05-06 | Add D11 plus BAB-1113/BAB-2225 for Phase 13 imported external tmux session attach with external-owned badge semantics | Codex |
| 2026-05-06 | Record Trinity R1/R2 plan review results for Phase 12a/13 docs and advisory fold-in | Codex |
| 2026-05-06 | Record Trinity R3 plan review pass and final advisory fold-in for Phase 12a/13 docs | Codex |
| 2026-05-06 | Mark BAB-2224 and BAB-2225 approved after Trinity R4 GLM/DeepSeek PASS and operator authorization to continue under SOP gates | Codex |
| 2026-05-06 | Add BAB-2226 Phase 12a implementation CHG draft | Codex |
| 2026-05-06 | Mark BAB-2226 approved after strict Trinity R4 GLM/DeepSeek PASS with no blockers | Codex |
| 2026-05-06 | Add BAB-2227 Phase 13 imported tmux attach implementation CHG draft | Codex |
| 2026-05-06 | Mark BAB-2227 approved after Trinity R1 GLM/DeepSeek PASS and advisory fold-in | Codex |
| 2026-05-06 | Record local Phase 12a/13 implementation validation results and external repo research takeaways | Codex |
| 2026-05-06 | Record PR #21 Codex R1 P2 fixes for reply capture retry and imported pane-id targeting | Codex |
| 2026-05-06 | Record browser-terminal keyboard parity, transcript/restart fixes, Gate A autostart isolation, and refreshed validation numbers | Codex |
| 2026-05-06 | Record Trinity follow-up PASS and advisory cleanup for PR #21 fixes | Codex |
| 2026-05-06 | Record PR #21 Codex R2 P1 imported attach-session target fix | Codex |
| 2026-05-06 | Record PR #21 Codex R3 P2 reply-capture follow-up fix and refreshed validation | Codex |
| 2026-05-06 | Record PR #21 R4 terminal-response filtering, browser shortcut parity, reconnect snapshot, attach-client cleanup, and refreshed validation | Codex |
| 2026-05-06 | Record PR #21 R5 storage-only comment history and imported snapshot-target fixes; no R6 requested per review cap | Codex |
| 2026-05-07 | Record Trinity R3 PASS for final PR #21 R5 fixes | Codex |
| 2026-05-07 | Record stable pane-id attach submission fix, terminal focus recovery limits, refreshed validation, and Trinity R4/R5 PASS | Codex |
