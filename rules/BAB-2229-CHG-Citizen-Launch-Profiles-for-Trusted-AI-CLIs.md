# CHG-2229: Citizen Launch Profiles for Trusted AI CLIs

**Applies to:** BAB project
**Last updated:** 2026-05-07
**Last reviewed:** 2026-05-07
**Status:** Completed
**Date:** 2026-05-07
**Requested by:** —
**Priority:** Medium
**Change Type:** Normal

---

## What

Add a durable Citizen `launch_profile` setting so Babs can distinguish
conservative interactive sessions from Babs-owned trusted AI CLI sessions.

Profiles:

- `safe_interactive` — default; preserves current command arguments.
- `trusted_autonomous` — for Babs-owned workspaces where the operator has
  already accepted the risk of autonomous AI CLI operation. Babs appends
  provider-specific non-blocking permission flags when they are missing.
  For Copilot CLI, Babs also pre-trusts the resolved Babs-owned workspace in
  Copilot's `trustedFolders` setting in `COPILOT_HOME/config.json` because
  `--allow-all` does not bypass folder-trust prompts.

Also switch Elena from the historical `gh copilot` wrapper to the direct
`copilot` CLI now that the local binary and transcript store have been verified.

## Why

Manual dogfood showed a repeated first-run friction point: new Citizen
workspaces can trigger "trust this directory" or permission prompts from the
hosted AI CLI. tmux is only the persistence substrate; the prompts belong to
`claude`, `codex`, or `copilot`. Babs needs an explicit, reviewable way to mark
seed/AI Citizens as trusted without changing shell Citizens or imported external
tmux sessions.

## Impact Analysis

- **Systems affected:** Citizen TOML parsing/writing, SQLite Citizen records,
  Runner command construction and launch preparation, browser-created AI
  Citizen presets, Elena seed config, and current CLI vocabulary docs.
- **Compatibility:** Missing `launch_profile` remains valid and defaults to
  `safe_interactive`. Existing `gh copilot` configs remain recognized by Babs,
  but new Copilot presets and Elena use direct `copilot`.
- **Risk:** Autonomous flags reduce CLI prompts and Copilot trusted-autonomous
  launches edit the operator's Copilot CLI settings. They should only be used
  for Babs-owned workspaces, not imported operator tmux sessions.
- **Rollback plan:** Remove the `launch_profile` field/migration, restore Elena
  to `cli = "gh"` with `cli_args = ["copilot"]`, and revert Runner argument
  expansion.

## Implementation Plan

1. Add RED tests for `launch_profile` parsing, validation, TOML writing, SQLite
   persistence, and Runner argument expansion.
2. Extend `CitizenConfig`, TOML config loading/writing, `CitizenRecord`, and
   `Catalog` to preserve the profile.
3. Add a SQLite migration with a safe default of `safe_interactive`.
4. Make Runner append provider-specific trusted-autonomous args for Claude,
   Codex, and Copilot without duplicating explicitly configured flags.
5. Switch the New Citizen Copilot preset and Elena seed config to direct
   `copilot` with `launch_profile = "trusted_autonomous"`.
6. Add Copilot settings preparation tests so malformed settings are not
   overwritten and `safe_interactive` sessions stay untouched.
7. Update current vocabulary/routing docs that describe Elena/Copilot.
8. Run focused tests, formatter, and validation.

## Implementation Outcome

- Added `launch_profile` to runtime config, TOML parsing/writing, SQLite
  Citizen records, Catalog import/repair paths, and New Citizen presets.
- Added `trusted_autonomous` argument expansion for Claude, Codex, and Copilot
  while preserving explicitly configured flags.
- Added Copilot launch preparation for Babs-owned trusted-autonomous sessions:
  Babs now updates `COPILOT_HOME/config.json` with the resolved workspace in
  `trustedFolders` before starting the tmux session.
- Switched Elena and the browser Copilot preset to direct `copilot`.
- Restarted Elena and verified a fresh Copilot session reaches the input prompt
  without the folder-trust dialog.

## Validation

- RED confirmed missing `CopilotSettings` / `Runner.prepare_launch/1` coverage
  before implementation.
- `mise exec -- mix test apps/babs_citizens/test/babs_citizens/copilot_settings_test.exs apps/babs_citizens/test/babs_citizens/runner_test.exs`
- `mise exec -- mix test apps/babs_citizens/test/babs_citizens/copilot_settings_test.exs apps/babs_citizens/test/babs_citizens/runner_test.exs apps/babs_citizens/test/babs_citizens/citizen/config_test.exs apps/babs_citizens/test/babs_citizens/citizen_record_test.exs apps/babs_citizens/test/babs_citizens/catalog_test.exs apps/babs_citizens/test/babs_citizens/spawner_test.exs`
- `mise exec -- mix compile --warnings-as-errors && mise exec -- mix test`
  - `babs_citizens`: 248 tests, 0 failures
  - `babs`: 75 tests, 0 failures
- `af validate --root .` — 136 documents checked, 0
  issues found.
- `git diff --check`

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-07 | Initial version | — |
| 2026-05-07 | Completed launch profile implementation and Copilot trust validation | Codex |
