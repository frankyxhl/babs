# PRP-2225: Phase 13 Imported Tmux Session Attach

**Applies to:** BAB project
**Last updated:** 2026-05-06
**Last reviewed:** 2026-05-06
**Status:** Approved
**Date:** 2026-05-06
**Requested by:** Operator
**Priority:** High

---

## What

Add a Phase 13 feature that lets the operator attach an existing Babs Citizen to
a tmux pane that was created outside Babs and is not currently managed by Babs.

This is an explicit import/attach workflow, not automatic tmux takeover. The
default ownership mode is external, per `BAB-1113`: Babs may stream, inject,
record transcript, and reconnect to the imported pane, but Stop/Detach must not
kill the external tmux session.

## Why

The current Babs lifecycle works well when Babs creates the Citizen. The
operator also has real workflows where an AI CLI or shell is already running in
tmux before Babs knows about it. Restarting that process just to bring it into
the browser loses useful context.

Imported attach gives Babs a bridge from existing terminal work into the
Ticket/Billboard flywheel:

- keep the already-running session alive;
- view and operate it through the same browser terminal UI;
- assign Tickets and inject messages into it;
- persist Babs-side transcript and status;
- detach without killing the operator-owned tmux process.

## Preconditions

- Phase 12a should finish first so Ticket prompt delivery and AI CLI reply
  capture are reliable for normal Babs-owned Citizens.
- `BAB-1113` owns the lifecycle decision for imported external sessions.
- `BAB-1107` remains the default rule for Babs-owned sessions.
- The Phase 13 implementation must preserve the one-Citizen-one-Hardline
  invariant from `BAB-1002`.

## Scope

### 1. Tmux Inventory

- Add a tmux inventory module that lists tmux sessions/windows/panes in a
  structured way.
- Identify whether each pane is:
  - already Babs-owned;
  - already imported by Babs;
  - unmanaged and attachable;
  - unavailable or ambiguous.
- Show useful operator-facing metadata such as session name, window, pane id,
  current command, attached flag, and observed current path.
- Do not capture pane contents until the operator explicitly attaches.

### 2. Imported Hardline Persistence

- Persist imported target metadata for the Citizen:
  - ownership mode `external`;
  - tmux session name;
  - tmux pane id;
  - window target if needed;
  - import timestamp;
  - last attach error.
- Prefer explicit fields if the schema pressure is high; otherwise structured
  SQLite `metadata` is acceptable for the first implementation.
- Keep existing Babs-owned Citizen rows backward compatible.

### 3. Lifecycle Semantics

- Add attach/detach paths that do not call `tmux kill-session`.
- On Babs restart, reattach to persisted imported targets if they still exist.
- If an imported target is missing, mark the Citizen visibly unavailable or
  failed and do not create a replacement tmux session automatically.
- Prevent attaching an imported pane to a Citizen that already has an active
  Hardline unless the operator detaches/stops the existing Hardline first.
- Preserve existing Start / Stop / Restart semantics for Babs-owned Citizens.

### 4. Browser UI

- Add an attach/import UI reachable from the Citizens area, for example
  `/citizens/attach`.
- List attachable tmux panes with status badges and icon buttons.
- Support attaching to an existing stopped/detached Citizen.
- Use the same terminal visual style, responsive sizing, and icon-button
  conventions as the existing Citizens UI.
- Make ownership visible so the operator understands whether Stop means kill or
  detach.
- Show a persistent status badge for imported external sessions, for example
  `Imported · External-owned`, anywhere lifecycle actions are available.
- Show a lifecycle reminder badge or tooltip such as
  `Detach only · tmux stays running` beside Stop/Detach controls for imported
  sessions.

### 5. Ticket Integration

- Imported Citizens can receive Ticket assignment/comment injections through the
  same Hardline path as Babs-owned Citizens.
- Ticket history remains the authoritative communication surface.
- If Phase 12a JSONL capture cannot locate the imported AI CLI's upstream
  transcript, Babs should report that as an advisory and keep pane capture as
  fallback/diagnostic.

## Out Of Scope

- Automatically importing every unmanaged tmux session.
- Taking kill ownership of external tmux sessions.
- Renaming imported sessions to `babs-<slug>`.
- Remote tmux over SSH.
- Multi-pane tmux app orchestration.
- Multiple active Hardlines for one Citizen.
- Creating a new Citizen identity directly from an imported tmux pane.
- Moving the external process working directory or rewriting its environment.

## Acceptance Criteria

- Start a tmux session outside Babs, then open the Babs browser UI and see it as
  an unmanaged attach candidate.
- Attach that pane to an existing stopped/detached Citizen.
- The attached Citizen shows a visible `Imported · External-owned` style badge.
- Stop/Detach controls show a visible reminder that Babs detaches only and does
  not kill the external tmux session.
- The Citizen terminal page streams the imported pane and accepts browser input.
- Assigning a Ticket to the imported Citizen injects the Ticket prompt into the
  imported pane.
- Detach/Stop from Babs does not kill the external tmux session; the operator
  can still attach to it from a terminal afterward.
- Restarting Babs reattaches to the imported pane when it still exists.
- Restarting Babs after the external tmux session is gone shows a visible
  missing-target state and does not spawn a replacement session.
- Existing Babs-owned Citizens still pass the Phase 6 lifecycle validation.
- Unit, LiveView, browser-harness BDD, and E2E coverage are added for the new
  attach/detach flows.

## Review Results

- R1 `.trinity/reviews/20260506-200953-rules`: GLM found stale phase-reference
  blockers; DeepSeek passed with advisories.
- R2 `.trinity/reviews/20260506-201548-rules`: GLM and DeepSeek passed with
  advisories; advisories were folded in.
- R3 `.trinity/reviews/20260506-202119-rules`: GLM and DeepSeek passed with
  advisories; final wording/timeline advisories were folded in.
- R4 `.trinity/reviews/20260506-202633-rules`: GLM and DeepSeek passed with no
  blockers. Remaining notes were non-blocking process/wording advisories.

## Test Plan

- Unit tests for tmux inventory parser and classification.
- Unit tests proving external-owned detach never calls kill-session.
- Unit tests for missing-target reattach behavior.
- SQLite/persistence tests for imported metadata round trip.
- LiveView tests for attach candidate listing, attach action, conflict errors,
  and ownership-specific button labels.
- Browser-harness BDD for "create external tmux session -> attach -> type ->
  detach -> session still alive".
- E2E smoke for terminal rendering after imported attach.
- Existing validation remains required: ExUnit/coverage, JS tests if browser JS
  changes, browser-harness BDD, Playwright/browser E2E, Gate A, Alfred
  validation, whitespace/privacy scan, Trinity review, GitHub Codex review loop.

## Implementation Slices

1. **CHG 13.1: Inventory + ADR-backed persistence**
   - Add tmux inventory and imported metadata schema.
   - Add unit tests for parsing, classification, and persistence.

2. **CHG 13.2: External-owned attach/detach lifecycle**
   - Add attach/detach APIs and reattach-on-restart behavior.
   - Prove external-owned detach does not kill tmux.

3. **CHG 13.3: Browser attach UI + Ticket dogfood**
   - Add `/citizens/attach` UI and end-to-end browser flow.
   - Validate Ticket injection into an imported AI CLI/shell pane.

## References

- `BAB-1002` Naming and Vocabulary
- `BAB-1003` Glossary of Boundaries
- `BAB-1107` Babs Owns Tmux Session Lifecycle
- `BAB-1110` Two OTP Apps Plus Tmux Detach
- `BAB-1112` Multi AI CLI Citizen Configuration
- `BAB-1113` Imported Tmux Sessions Are External-Owned Hardlines
- `BAB-2224` Phase 12a PFC-Informed Hardline Relay Reliability

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-06 | Draft Phase 13 imported external tmux session attach PRP | Codex |
| 2026-05-06 | Fold Trinity R2 advisory by keeping Phase 13 scoped to existing Citizen attach only | Codex |
| 2026-05-06 | Mark approved after Trinity R4 GLM/DeepSeek PASS with no blockers and operator authorization to continue Phase 12a/13 under SOP gates | Codex |
