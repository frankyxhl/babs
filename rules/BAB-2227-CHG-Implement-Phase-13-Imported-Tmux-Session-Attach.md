# CHG-2227: Implement Phase 13 Imported Tmux Session Attach

**Applies to:** BAB project
**Last updated:** 2026-05-06
**Last reviewed:** 2026-05-06
**Status:** Approved
**Date:** 2026-05-06
**Requested by:** Operator
**Priority:** High
**Change Type:** Normal

---

## What

Implement Phase 13 from `BAB-2225`: let the operator attach an existing
stopped/detached Citizen to an externally created tmux pane without taking kill
ownership of that tmux session.

The implementation must keep `BAB-1113` as the lifecycle authority:
external-owned imported hardlines can attach, stream, inject, detach, and
reattach, but Babs must not kill, rename, or silently adopt the external tmux
session.

## Why

Phase 12a makes Ticket delivery and reply capture reliable for Babs-owned
hardlines. The operator also needs to bring already-running shell or AI CLI tmux
work into the same browser and Ticket/Billboard flywheel without restarting the
process and losing context.

## Scope

### 1. Tmux inventory

- Add a structured tmux inventory boundary that lists sessions/windows/panes
  without capturing pane contents.
- Classify panes as Babs-owned, already imported, attachable external, or
  unavailable/ambiguous.
- Show operator-facing metadata: session, window, pane id, current command,
  current path, and attached state.

### 2. Imported metadata persistence

- Store imported hardline metadata in the existing SQLite `metadata` JSON field
  to avoid a schema migration for the first implementation.
- Persist at minimum:
  - ownership mode `external`;
  - tmux session name;
  - tmux pane id or exact attach target;
  - observed command/current path for UI only;
  - import timestamp;
  - last attach error.
- Keep existing Babs-owned rows backward compatible by treating missing
  ownership metadata as `babs`.

### 3. External-owned lifecycle

- Add an explicit attach/import API for an existing Citizen.
- Refuse import when the Citizen already has an active hardline.
- For external-owned Citizens:
  - `start` means reattach to the persisted external target;
  - `stop` means detach Babs' hardline only and mark the Citizen stopped;
  - `restart` means detach then reattach to the same target;
  - boot reattach starts only from explicit persisted metadata;
  - missing external targets mark the Citizen failed and do not spawn a
    replacement `babs-<slug>` tmux session.
- Preserve existing Babs-owned Start/Stop/Restart behavior and tests.

### 4. Browser UI

- Add a `/citizens/attach` LiveView reachable from the Citizens index.
- List attachable tmux panes and eligible existing Citizens.
- Attach a selected pane to a selected Citizen and redirect to its terminal on
  success.
- Use the existing dark, compact operational UI style and icon-button
  conventions.
- Surface ownership visibly:
  - imported Citizens show an `Imported · External-owned` badge;
  - Stop controls for imported Citizens show `Detach only · tmux stays running`
    or equivalent tooltip/reminder.

### 5. Ticket integration

- Keep Ticket assignment/comment injection on the same `Hardline.Pane` path, so
  imported Citizens receive prompts exactly like Babs-owned Citizens once
  attached.
- If upstream JSONL reply capture is unsupported for the imported CLI, Phase 12a
  advisory behavior remains the response; this CHG does not invent a new
  transcript source.

## Out Of Scope

- Creating a new Citizen identity directly from an imported pane.
- Auto-importing all unmanaged tmux sessions.
- Taking kill ownership of external sessions.
- Renaming imported sessions.
- Remote tmux over SSH.
- Multiple active hardlines per Citizen.
- Multi-pane tmux orchestration beyond attaching the selected target.

## Implementation Plan

1. **Inventory and metadata helpers**
   - Add `Babs.Citizens.TmuxInventory` for tmux pane parsing/listing and
     classification.
   - Add metadata helper functions for imported ownership in `Catalog` or a
     small dedicated module, keeping map shape stable and testable.
2. **Lifecycle integration**
   - Extend `Lifecycle` with imported attach, external reattach, external
     detach, and external restart paths.
   - Extend `ReattachScanner` so persisted external targets are reattached only
     when they still exist; otherwise mark failed.
   - Ensure external stop never calls `Runner.kill_session/1`.
3. **Status and UI integration**
   - Extend `StatusSnapshot` with ownership, import badge, target label, and
     ownership-specific action labels.
   - Add `/citizens/attach`, `CitizenPath.attach/1`, controller route, and a
     compact attach LiveView.
   - Add badges/reminders to Citizens index and Terminal UI.
4. **Ticket dogfood path**
   - Validate that assignment/comment injection works after imported attach by
     using the same `Pane.inject_system/2` and `Pane.inject/2` boundaries.
5. **Documentation and tracker**
   - Record local implementation results and validation in this CHG and
     `BAB-3003`.

## TDD Plan

| Boundary | RED | GREEN | REFACTOR |
|----------|-----|-------|----------|
| Tmux inventory | Failing parser/classifier tests for Babs-owned, imported, and attachable panes | Implement structured inventory and candidate filtering | Keep tmux shell calls behind a narrow fakeable function |
| Metadata | Failing round-trip tests for external ownership metadata in SQLite `metadata` | Add helper functions and persistence update path | Keep missing metadata equivalent to Babs-owned |
| Lifecycle | Failing tests proving imported stop does not kill tmux and missing target does not spawn `babs-<slug>` | Implement external attach/detach/reattach paths | Share lock/status handling with existing lifecycle code |
| Reattach scanner | Failing tests for boot reattach of existing external target and failure of missing target | Extend row planning/actions for imported metadata | Keep Babs-owned row behavior unchanged |
| Browser attach UI | Failing LiveView tests for candidate listing, eligible Citizen select, success redirect, and conflict flash | Implement `/citizens/attach` | Keep CSS local and aligned with existing Citizens UI |
| Browser BDD/E2E | Failing scenario for external tmux attach, type, detach, and tmux survival | Implement full UI flow | Keep runtime cleanup isolated to BDD-owned sessions |
| Ticket integration | Failing BDD/E2E assertion that Ticket assignment injects into imported pane | Reuse existing Writer/Injector path after imported attach | Avoid special-case Ticket delivery for imported Citizens |

## Validation Plan

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`
- `mise exec -- mix test --cover --export-coverage phase13`
- `mise exec -- mix cmd mix test.coverage`
- `npm run test:js`
- `npm run test:bdd`
- `npm run test:e2e`
- `mise exec -- mix babs.gate_a`
- `af validate --root .`
- `git diff --check`
- Privacy scan for private IPs, local host paths, tokens, and machine-local URLs
  in changed files and public PR text.

Coverage floors stay at the current project gate unless a stricter per-app gate
already applies: `:babs_citizens >= 80%` and `:babs >= 75%`.

## Review Plan

- Plan review: Trinity fast-review using GLM and DeepSeek before implementation.
- Implementation review: Trinity fast-review using GLM and DeepSeek on the full
  implementation diff.
- PR review: GitHub Codex loop per `COR-1615`, current-head matched and capped
  at five rounds unless the operator explicitly extends it.

## Review Results

- R1 `.trinity/reviews/20260506-215446-rules-BAB-2227-Phase-13-imported-tmux-attach-implementation-CHG-plan`:
  GLM PASS and DeepSeek PASS with no blockers. Folded non-blocking advisories by
  documenting ReplyCapture best-effort crash semantics, explaining the larger
  BDD transcript search window, and making the Phase 12a `inject_system` call
  timeout configurable while keeping the default at 5 seconds.
- Implementation R1 `.trinity/reviews/20260506-223834-Phase-12a-relay-reliability-and-Phase-13-imported-external-tmux-attach-implementation`:
  GLM PASS at 9.2/10 and DeepSeek PASS with no blockers. Post-review
  non-blocking advisories were addressed by adding attach-failure LiveView
  coverage and making `ReplyCapture.enabled?/0`'s unset-env default explicit.
- Implementation R2 `.trinity/reviews/20260506-234257-Phase-12a-13-PR-21-R1-fixes-plus-terminal-keyboard-parity-and-Gate-A-isolation`:
  GLM PASS and DeepSeek PASS with no blockers. Non-blocking advisories were
  addressed by documenting Gate A's Application env mutation, removing the
  obsolete browser paste helper, and aligning C1 terminal-control filtering
  between JavaScript and the Phoenix Channel.
- Implementation R3 `.trinity/reviews/20260507-012721-Phase-12a-13-PR-21-R5-fixes`:
  GLM PASS and DeepSeek PASS with no blockers for the final PR #21 R5 fixes.
  Remaining observations were informational/non-blocking.
- Implementation R4 `.trinity/reviews/20260507-020009-Phase-12a-13-final-stable-pane-and-terminal-focus-fixes`:
  GLM PASS and DeepSeek PASS with no blockers for the final stable pane-id
  attach submission and browser terminal focus recovery fixes.
- Implementation R5 `.trinity/reviews/20260507-020800-Phase-12a-13-final-terminal-focus-followup`:
  GLM PASS and DeepSeek PASS with no blockers after terminal focus recovery
  advisory hardening.

## Implementation Results

- Added `Babs.Citizens.TmuxInventory` for structured tmux pane inventory and
  classification across Babs-owned, imported, and attachable panes.
- Added `Babs.Citizens.ImportedHardline` and Catalog metadata helpers for
  durable external ownership, target labels, badges, reminders, and last attach
  errors.
- Extended Lifecycle/ReattachScanner so imported Citizens can attach, detach,
  reattach, and fail visibly on missing external targets without spawning a
  replacement `babs-<slug>` session or killing the external tmux session.
- Added `/citizens/attach` with icon-labeled attach controls, candidate lists,
  tmux inventory, token-preserving navigation, and success redirect to the
  imported terminal.
- Added imported ownership badges and `Detach only · tmux stays running`
  reminders to the Citizens index and terminal chrome.
- Kept Ticket assignment/comment delivery on the same Hardline pane path, so
  imported Citizens receive Ticket prompts like Babs-owned Citizens once
  attached.
- After import, lifecycle and reattach operations prefer the stable tmux
  `pane_id` while the positional `session:window.pane` target stays available
  as the operator-facing label.
- The attach UI now submits stable `%pane_id` values instead of positional
  `session:window.pane` values, so pane/window renumbering between render and
  submit does not attach the wrong external pane.
- Imported pane attach now separates the stable pane target from the session
  attach target: Babs selects the stored `%pane_id` and then attaches to the
  recorded tmux session name/session id.
- Imported terminal initial snapshots now capture the actual attached tmux pane
  target, so pre-existing external pane output is visible immediately after
  attach.
- Hardline pane shutdown now detaches the tmux attach client reliably while
  preserving the detached tmux session, covering both Babs-owned and imported
  terminal streams.
- Validation gate execution now disables broad Citizen autostart before running
  the sentinel-only Gate A reload check, so imported/AI Citizen panes are not
  attached just to validate this phase.

## Validation Results

Final local validation:

- `mise exec -- mix format --check-formatted`: pass
- `mise exec -- mix compile --warnings-as-errors`: pass
- `mise exec -- mix test`: `:babs_citizens` 235 tests, `:babs` 75 tests, all
  pass
- `mise exec -- mix test --cover --export-coverage phase13` then
  `mise exec -- mix cmd mix test.coverage`: `:babs_citizens` 81.28% and
  `:babs` 87.55%
- `npm run test:js`: 15 tests pass
- `npm run test:bdd`: pass; expected externally managed-server skips remain for
  managed restart/fd-threshold scenarios, and the `BABS_WORKSPACE_ROOT` scenario
  is skipped when that env var is unset; the run used a dedicated automation
  Chrome via `BU_CDP_URL` so it did not attach to the operator's daily browser
  profile
- `npm run test:e2e`: 13 Playwright tests pass, including imported external
  tmux attach/detach and browser tmux-prefix/Ctrl-A/Alt-B/`Escape` focus
  recovery shortcut parity
- `mise exec -- mix babs.gate_a`: pass
- `af validate --root .`: 131 documents checked, 0 issues
- `git diff --check`: pass
- Privacy scan over changed diff: pass

## Acceptance Criteria

- An external tmux session created outside Babs appears as an unmanaged attach
  candidate.
- The operator can attach that pane to an existing stopped/detached Citizen.
- The imported Citizen shows an `Imported · External-owned` badge.
- Stop/Detach controls visibly communicate `Detach only · tmux stays running`.
- The imported terminal page streams output and accepts browser input.
- Ticket assignment to the imported Citizen injects the Ticket prompt into the
  imported pane.
- Stop/Detach from Babs leaves the external tmux session alive.
- Babs restart reattaches to the imported pane if it still exists.
- Babs restart after the external tmux session is gone marks the Citizen failed
  and does not spawn a replacement `babs-<slug>` session.
- Existing Babs-owned lifecycle validation remains green.
- Unit, LiveView, browser-harness BDD, and E2E coverage cover the new flow.

## References

- `BAB-1113` Imported Tmux Sessions Are External-Owned Hardlines
- `BAB-2225` Phase 13 Imported Tmux Session Attach
- `BAB-2226` Phase 12a Relay Reliability
- `BAB-1107` Babs Owns Tmux Session Lifecycle
- `BAB-1002` Naming and Vocabulary

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-06 | Draft Phase 13 imported tmux attach implementation CHG | Codex |
| 2026-05-06 | Mark approved after Trinity R1 GLM/DeepSeek PASS and fold non-blocking advisories | Codex |
| 2026-05-06 | Record Phase 13 implementation and final local validation results | Codex |
| 2026-05-06 | Record Trinity implementation PASS and post-review advisory fixes | Codex |
| 2026-05-06 | Fix GitHub Codex R1 P2 by using stable tmux pane IDs for imported operations | Codex |
| 2026-05-06 | Refresh validation after keyboard parity, restart reconnect, transcript visibility, and Gate A isolation fixes | Codex |
| 2026-05-06 | Record Trinity R2 PASS and advisory cleanup for PR #21 follow-up fixes | Codex |
| 2026-05-06 | Fix GitHub Codex R2 P1 by selecting imported pane IDs but attaching to tmux sessions | Codex |
| 2026-05-06 | Refresh validation after PR #21 R3 reply-capture follow-up fix | Codex |
| 2026-05-06 | Refresh validation after PR #21 R4 terminal-response filtering, hardline shortcut parity, and attach-client cleanup fixes | Codex |
| 2026-05-06 | Fix GitHub Codex R5 P2 by snapshotting imported terminals from the attached pane target | Codex |
| 2026-05-06 | Refresh final validation after R5 fixes; no R6 requested per operator review cap | Codex |
| 2026-05-07 | Record Trinity implementation R3 PASS for final PR #21 R5 fixes | Codex |
| 2026-05-07 | Fix stable pane-id attach submissions, add terminal focus recovery validation, and record Trinity R4/R5 PASS | Codex |
