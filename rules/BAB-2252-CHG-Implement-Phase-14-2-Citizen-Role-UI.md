# CHG-2252: Implement Phase 14.2 Citizen Role UI

**Applies to:** BAB project
**Last updated:** 2026-05-08
**Last reviewed:** 2026-05-08
**Status:** Approved
**Date:** 2026-05-08
**Requested by:** Operator
**Priority:** High
**Change Type:** Feature

---

## What

Implement **Phase 14.2: Citizen role UI** from `BAB-2242`.

This slice makes the canonical multi-role model from `BAB-2251` visible and
editable in the Citizen browser surfaces.

Scope:

- Show normalized Citizen role badges on `/citizens`.
- Show normalized roles for the active Citizen in the default terminal chrome
  when there is enough space.
- Add a multi-role input to `/citizens/new` and pass normalized role data to the
  Citizen spawner.
- Extend `Babs.Citizens.Spawner` so browser-created Citizens can persist
  canonical `roles` to TOML and SQLite.
- Keep role validation in `Babs.Citizens.Roles`; LiveViews should only format
  input/output around that boundary.
- Add focused LiveView and Spawner tests for role rendering, create flow
  submission, persistence, and validation errors.

Out of scope:

- Ticket `assignee_role` routing. That is Phase 14.3.
- Ticket create/edit role dropdowns. That belongs with Phase 14.3 because the
  role label source becomes useful only when routing exists.
- Citizen edit flow role controls. `BAB-2242` calls for new/edit role controls,
  but Babs currently has no Citizen edit flow; this slice covers creation and
  explicitly defers edit support until that surface exists.
- Browser-harness BDD/E2E hardening. That is Phase 14.4.
- Removing the legacy `role` field.
- Role permissions, role-based security, inspector automation, Mayor behavior,
  or cross-machine routing.
- Building a full repeated-row role editor. This slice uses a simple
  newline/comma separated role label input so the data path is usable and
  testable before richer role editing.

## Why

Phase 14.1 added canonical `roles` persistence, but the operator still cannot
see or set multiple roles from the browser. Phase 14.3 cannot be validated
comfortably unless Citizens already expose the role data that routing will use.

A compact first UI keeps this slice small: the browser form creates valid
multi-role Citizens, the index makes roles visible, and tests lock the data path
from UI parameters through TOML and SQLite.

## Impact Analysis

- **Systems affected:** `Babs.Citizens.StatusSnapshot`,
  `Babs.Citizens.Spawner`, `/citizens`, `/citizens/new`, terminal chrome tests,
  and focused Citizen web tests.
- **Database:** no schema change. Existing `citizens.roles` from `BAB-2251` is
  used.
- **Runtime behavior:** existing Citizens without roles still render normally.
  Browser-created Citizens may now include roles.
- **Compatibility:** the spawner writes canonical `[[roles]]` plus the legacy
  first `role` compatibility field through the existing TOML writer.
- **UI:** role badges/chips must fit within existing dense operator UI and use
  existing icon/button style conventions where controls are added.
- **Tests:** focused ExUnit and LiveView tests are required before
  implementation. Browser-harness BDD/E2E remains for Phase 14.4 unless this
  slice adds JavaScript behavior.
- **Privacy:** docs, tests, PR body, and comments must not include private IPs,
  hostnames, local checkout paths, tokens, or runtime Ticket data.
- **Rollback:** revert this slice. No migration rollback is needed.

## Implementation Plan

1. **Review this CHG before code**
   - Run Trinity `fast-review` against this CHG and fold blockers.

2. **Add RED tests**
   - Add `CitizensLiveTest` coverage that configured Citizens with multiple
     roles render stable role badges/chips on `/citizens` using test IDs like
     `citizen-role-<slug>-<index>`.
   - Add `TerminalLiveTest` render coverage that the active Citizen can show
     compact role badges in default terminal mode with test IDs like
     `terminal-role-<slug>-<index>`, hides that chrome in full mode, and keeps
     fallback active tabs safe with `roles: []`.
   - Add `NewCitizenLiveTest` coverage that the form renders a role input,
     submits role text to the spawner, and displays role validation errors.
   - Add `SpawnerTest` coverage that browser params with multiple role labels
     persist `record.roles`, sync legacy `record.role`, and write TOML roles.
   - Add Spawner coverage for raw string params and pre-split list params so
     `@param_atoms` and the text-to-list normalization path are both tested.

3. **Expose roles in snapshots**
   - Add `roles` to the snapshot map assembled by `StatusSnapshot`.
   - Read through `Catalog.to_config/1` and normalize through
     `Babs.Citizens.Roles.normalize/1` as a defensive display boundary.
   - Default to `[]` if persisted role data cannot be normalized for display.
   - Add small formatting helpers for role names and optional skill labels.

4. **Render roles**
   - Add role chip CSS to `/citizens`.
   - Render each normalized role name with a stable `data-testid`.
   - Include skills only when present, using compact text inside the same chip.
   - Reuse the existing pill style direction from ownership/lifecycle badges.
   - Add compact active-Citizen role chips to default terminal chrome in a
     dedicated role strip after the tab list and before lifecycle controls.
   - Always render terminal role chips when roles exist; use CSS max-width,
     truncation, and horizontal overflow to prevent crowding on small screens.

5. **Create roles from the browser**
   - Add `"roles"` to `NewCitizenLive` form state and normalization.
   - Add a simple textarea or compact input for newline/comma separated role
     labels.
   - Keep the displayed value as text. `Spawner.validate/1` may split
     comma/newline text as a browser-boundary convenience because Spawner is the
     durable create boundary used by both LiveView and tests; it should also
     accept pre-split lists for future richer editors.
   - Surface `:roles` validation errors through an inline field error.

6. **Extend Spawner**
   - Accept string-keyed or atom-keyed `roles` params.
   - Split comma/newline text into role labels, and accept list values without
     requiring browser code to convert trusted future form shapes back to text.
   - Normalize labels with `Babs.Citizens.Roles.normalize/1`.
   - Persist `roles` and legacy first `role` through `%CitizenConfig{}` and the
     existing Catalog/TOML writer path.
   - Preserve default `roles: []` for browser-created Citizens when no roles are
     supplied.

7. **Validate and review**
   - Run focused tests first.
   - Run the local validation stack.
   - Run Trinity implementation `fast-review`.
   - Open a PR with `gh` as `ryosaeba1985` and follow `COR-1615`/`COR-1612`.

## Acceptance Criteria

- `/citizens` shows role badges for Citizens with one or more normalized roles.
- Default terminal chrome can show the active Citizen's compact role badges;
  full terminal mode remains pure terminal.
- `/citizens/new` accepts multiple role labels and submits them without
  JavaScript.
- Citizen edit role controls are deliberately deferred until a Citizen edit
  surface exists.
- Browser-created Citizens persist canonical `roles` in SQLite and TOML.
- Legacy first `role` remains synchronized for browser-created Citizens.
- Invalid role labels render inline validation errors without creating TOML,
  SQLite rows, workspaces, or lifecycle side effects.
- Existing Citizens without roles continue to render and create normally.
- No Ticket routing behavior changes in this slice.

## Validation Plan

Focused:

```bash
mise exec -- mix test apps/babs/test/babs_web/live/citizens_live_test.exs apps/babs/test/babs_web/live/new_citizen_live_test.exs apps/babs/test/babs_web/live/terminal_live_test.exs apps/babs_citizens/test/babs_citizens/spawner_test.exs
```

Standard local gates:

```bash
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
af validate --root .
git diff --check
```

Because this slice is expected to use LiveView-rendered HTML and no new
JavaScript, `npm run test:js`, `npm run test:bdd`, and `npm run test:e2e` are
not required locally unless implementation scope expands into browser assets.
Phase 14.4 remains the browser-harness BDD/E2E hardening slice for role flows.

## Review Plan

- Trinity `fast-review` on this CHG before implementation.
- Trinity `fast-review` on the implementation diff before PR.
- GitHub Codex review loop on the PR, capped at five rounds.
- Use `gh` authenticated as `ryosaeba1985` for public GitHub writes.

## Results

- 2026-05-08 CHG review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-113509-rules-BAB-2252-CHG-Implement-Phase-14-2-Citizen-Role-UI.md`
  - GLM PASS and DeepSeek PASS.
  - Folded advisories for the missing Citizen edit surface, `StatusSnapshot`
    wording, snapshot normalization via `Catalog.to_config/1`, raw role param
    coverage, deterministic role chip test IDs, terminal role chip placement,
    CSS overflow instead of subjective hiding, and `fallback_tab/1` `roles: []`.
- 2026-05-08 implementation:
  - Added role chips to `/citizens` and default terminal chrome.
  - Added `roles` to `StatusSnapshot` through the existing
    `Catalog.to_config/1` normalization boundary.
  - Added `/citizens/new` role text input and inline role validation errors.
  - Extended `Babs.Citizens.Spawner` to accept newline/comma role text and
    pre-split role lists, normalize through `Babs.Citizens.Roles`, and persist
    canonical `roles` plus legacy first `role`.
  - Added focused LiveView and Spawner tests for role rendering, role submit,
    validation errors, TOML/SQLite persistence, and pre-split list params.
- 2026-05-08 local validation:
  - Focused tests passed: 55 tests, 0 failures.
  - `mise exec -- mix format --check-formatted` passed.
  - `mise exec -- mix compile --warnings-as-errors` passed.
  - `mise exec -- mix test` passed: 455 tests, 0 failures.
  - `af validate --root .` passed: 161 documents checked, 0 issues found.
  - `git diff --check` passed.
  - Added-line privacy scan found no private IPs, hostnames, local checkout
    paths, or secret values; it only matched the existing fixture field name
    `socket_token`.
- 2026-05-08 implementation review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-114508-Phase-14.2-citizen-role-UI-implementation-diff`
  - GLM PASS and DeepSeek PASS.
  - No blocking issues found. Both reviewers noted duplicated role display
    helpers across two LiveViews as a non-blocking tidy-up candidate if a third
    consumer appears.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial Phase 14.2 implementation CHG | Codex |
| 2026-05-08 | Trinity fast-review passed GLM and DeepSeek; folded UI, test ID, edit-surface, and snapshot-boundary advisories | Codex |
| 2026-05-08 | Implemented Phase 14.2 role UI with local validation and Trinity implementation PASS | Codex |
