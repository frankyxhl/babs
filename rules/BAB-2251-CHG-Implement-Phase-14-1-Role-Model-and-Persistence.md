# CHG-2251: Implement Phase 14.1 Role Model and Persistence

**Applies to:** BAB project
**Last updated:** 2026-05-08
**Last reviewed:** 2026-05-08
**Status:** Approved
**Date:** 2026-05-08
**Requested by:** Operator
**Priority:** High
**Change Type:** Data migration

---

## What

Implement **Phase 14.1: Role model and persistence** from `BAB-2242`.

This slice establishes the canonical multi-role data model without changing
Ticket role routing or browser role editing yet.

Scope:

- Add `Babs.Citizens.Roles` as the only normalization and validation boundary
  for Citizen roles.
- Add a `roles` JSON/text column to `citizens`, defaulting to `[]`.
- Backfill existing `citizens.role` values into canonical `citizens.roles`.
- Extend `%Babs.Citizens.CitizenConfig{}` with `roles`.
- Extend `CitizenRecord`, `Catalog`, TOML loading, and TOML writing to preserve
  legacy `role` while exposing canonical `roles`.
- Accept TOML:
  - legacy `role = "developer"`
  - legacy `[role] name = "developer"`
  - canonical `roles = ["developer", "inspector"]`
  - canonical repeated `[[roles]]` tables with optional `skills`
- Continue writing legacy `role` as the first normalized role during this
  migration window.
- Default `%CitizenConfig{}` `roles` to `[]` and keep the typespec precise:
  a list of `%{"name" => String.t(), "skills" => [String.t()]}` maps.
- Add focused tests for normalizer behavior, migration/backfill, TOML
  compatibility, catalog import/update, and TOML writer output.

Out of scope:

- Citizen role UI chips or edit controls. That is Phase 14.2.
- Ticket `assignee_role` router behavior. That is Phase 14.3.
- BDD/E2E browser hardening. That is Phase 14.4.
- Removing or renaming the legacy `role` field.
- Role permissions, security scopes, inspector automation, or Mayor behavior.

## Why

Phase 15 and Phase 16 depend on role-selected Citizens, and the operator has
approved multi-role Citizens instead of a single `role` value. Today Babs can
store one loose `role` value, but code has no canonical list form and no shared
normalization boundary.

Phase 14.1 creates that foundation while preserving existing rows and TOML seed
files. Keeping this as a persistence-only slice reduces migration risk before
UI and routing start reading the new roles surface.

## Impact Analysis

- **Systems affected:** `:babs_citizens` Citizen config loading, TOML writing,
  SQLite schema, `CitizenRecord` changesets, and `Catalog` import/to-config
  conversion.
- **Database:** adds nullable/defaulted JSON/text `roles` column and backfills
  from existing `role`.
- **Runtime behavior:** existing legacy single-role Citizens should continue to
  import and run unchanged. New code can read `config.roles` and `record.roles`.
- **Compatibility:** legacy `role` remains persisted and written as the first
  normalized role. Canonical `roles` becomes the preferred public shape.
- **Tests:** focused unit/repo tests are required before implementation.
- **Privacy:** role fixtures must not include hostnames, private IPs, tokens,
  paths, or runtime Ticket data.
- **Rollback:** revert the CHG commit. The migration adds a column only; rollback
  would require a reverse migration that drops `roles` if applied to a live DB.

## Implementation Plan

1. **Review this CHG before code**
   - Run Trinity `fast-review` against this CHG and fold blockers.

2. **Add role normalizer**
   - Add `Babs.Citizens.Roles`.
   - Normalize supported inputs into:

     ```elixir
     [
       %{"name" => "developer", "skills" => ["elixir", "phoenix"]},
       %{"name" => "inspector", "skills" => []}
     ]
     ```

   - Accept atom-keyed and string-keyed maps at boundaries.
   - Normalize role names to lowercase slug-style labels.
   - Normalize skills to lowercase slug-style labels where practical.
   - Merge duplicate role names and skill lists with stable ordering.
   - Reject invalid role names, invalid skill values, and unsupported shapes.
   - Provide helpers for legacy first-role compatibility.

3. **Extend schema and migration**
   - Add a new Ecto migration that adds `citizens.roles` as JSON/text with
     default `[]`.
   - Backfill existing role values into canonical roles in migration-safe code:
     decode the existing `role` JSON text with `Jason.decode/1`, normalize the
     decoded value with a migration-local copy of the supported compatibility
     rules, write canonical JSON with `Jason.encode!/1`, and fall back to `[]`
     if the legacy role value is invalid or undecodable.
   - Keep this migration self-contained; do not call application modules from
     the migration.
   - Add `roles` to `CitizenRecord` schema, fields, changeset, and validation.

4. **Extend runtime config and Catalog**
   - Add `roles` to `%CitizenConfig{}`.
   - In `Catalog.config_attrs/1`, persist both `role` and canonical `roles`.
   - In `Catalog.merge_import/2`, treat roles like existing display metadata,
     not spawn fields: update canonical roles and legacy first-role from
     incoming TOML even when the Citizen is running. This preserves the current
     legacy `role` re-import behavior while only protecting true spawn fields
     such as `cli`, `cli_args`, `launch_profile`, and `env`.
   - In `Catalog.to_config/1`, populate `roles` from `record.roles`, falling
     back to normalized `record.role` for legacy rows.

5. **Extend TOML loader and writer**
   - `Citizen.Config.load_file/2` reads canonical `roles` first and legacy
     `role` only when `roles` is absent.
   - Verify the TOML library's decoded shapes for `[[roles]]` array-of-tables,
     `roles = [...]` arrays, legacy `[role]` tables, and `role = "..."` strings
     in loader tests.
   - `Citizen.TomlWriter` writes canonical `[[roles]]` for multiple roles and
     writes the legacy `role` field/table as the first normalized role during
     the migration window.
   - Preserve existing single-role TOML output compatibility where reasonable.

6. **Add tests**
   - `Roles` unit tests for strings, maps, list labels, repeated maps,
     duplicate merging, atom keys, invalid role names, and invalid skills.
   - `CitizenRecord` tests for valid/invalid `roles`.
   - Repo/migration-facing tests proving existing `role` values backfill into
     `roles` and `Catalog.to_config/1` exposes canonical roles.
   - TOML loader tests for legacy `role`, legacy `[role]`, `roles = [...]`, and
     `[[roles]]`.
   - TOML writer tests proving canonical roles and legacy first-role
     compatibility are written.
   - Round-trip tests that load TOML, write it back through `TomlWriter`, and
     load it again without losing canonical roles or legacy first-role
     compatibility.

7. **Validate and review**
   - Run focused tests first.
   - Run the applicable local validation stack.
   - Run Trinity implementation `fast-review`.
   - Open PR with `gh` as `ryosaeba1985` and follow `COR-1615`/`COR-1612`.

## Acceptance Criteria

- `Babs.Citizens.Roles.normalize/1` returns one canonical list shape for all
  supported role inputs.
- Duplicate role names merge without losing skills.
- `CitizenConfig` and `CitizenRecord` expose `roles` while preserving legacy
  `role`.
- Existing legacy `role` rows and TOML files continue to import.
- New `roles` TOML forms import correctly.
- New/updated Citizen rows persist canonical `roles`.
- TOML writer emits canonical roles and legacy first-role compatibility.
- No Ticket routing behavior changes in this slice.
- Tests cover role normalization, TOML compatibility, schema validation,
  migration/backfill, and Catalog conversion.

## Validation Plan

Focused:

```bash
mise exec -- mix test apps/babs_citizens/test/babs_citizens/roles_test.exs apps/babs_citizens/test/babs_citizens/citizen/config_test.exs apps/babs_citizens/test/babs_citizens/citizen/toml_writer_test.exs apps/babs_citizens/test/babs_citizens/citizen_record_test.exs apps/babs_citizens/test/babs_citizens/citizen_record_repo_test.exs apps/babs_citizens/test/babs_citizens/catalog_test.exs
```

Standard local gates:

```bash
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
af validate --root .
git diff --check
```

Because this slice does not change browser assets or LiveViews, `npm run
test:js`, `npm run test:e2e`, and `npm run test:bdd` are not required locally
unless implementation scope expands into browser code. Phase 14.4 will add
browser-harness BDD/E2E coverage for role flows.

## Review Plan

- Trinity `fast-review` on this CHG before implementation.
- Trinity `fast-review` on the implementation diff before PR.
- GitHub Codex review loop on the PR, capped at five rounds.
- Use `gh` authenticated as `ryosaeba1985` for public GitHub writes.

## Results

- 2026-05-08 CHG review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-105218-Phase-14.1-Role-model-and-persistence-CHG`
  - GLM PASS and DeepSeek PASS.
  - Folded advisories for `CitizenConfig.roles` default/typespec, explicit
    migration-local backfill strategy, TOML decoded-shape/round-trip tests, and
    the decision to treat roles as display metadata rather than protected spawn
    fields during re-import.
- 2026-05-08 implementation review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-111909-Phase-14.1-Role-model-and-persistence-final-diff-after-role-sync-fold`
  - GLM PASS and DeepSeek PASS.
  - No blocking issues found; remaining notes are non-blocking polish.
- 2026-05-08 implementation:
  - Added `Babs.Citizens.Roles` normalization boundary.
  - Added `citizens.roles` migration with migration-local backfill logic.
  - Extended `CitizenConfig`, `CitizenRecord`, `Catalog`, TOML loader, and TOML
    writer for canonical roles plus legacy first-role compatibility.
  - Added focused tests for role normalization, TOML decoded shapes, TOML
    round-trip, schema validation, Catalog conversion, and repo persistence.
  - Folded Trinity implementation advisories by avoiding unrelated-update
    revalidation of persisted `roles` data and documenting the migration-local
    normalizer's tolerant fallback behavior.
  - Folded Trinity final-review advisory by synchronizing legacy `role` from
    canonical `roles` in direct `CitizenRecord.changeset/2` calls.
- 2026-05-08 local validation:
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/roles_test.exs apps/babs_citizens/test/babs_citizens/citizen/config_test.exs apps/babs_citizens/test/babs_citizens/citizen/toml_writer_test.exs apps/babs_citizens/test/babs_citizens/citizen_record_test.exs apps/babs_citizens/test/babs_citizens/citizen_record_repo_test.exs apps/babs_citizens/test/babs_citizens/catalog_test.exs`
    passed: 55 tests, 0 failures.
  - `mise exec -- mix format --check-formatted` passed.
  - `mise exec -- mix compile --warnings-as-errors` passed.
  - `mise exec -- mix test` passed: 449 tests, 0 failures.
  - `af validate --root .` passed: 160 documents checked, 0 issues found.
  - `git diff --check` passed.
  - Changed-file privacy scan found no private host/IP/path/token values.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial Phase 14.1 implementation CHG | Codex |
| 2026-05-08 | Trinity fast-review passed GLM and DeepSeek; folded migration, TOML, config default, and re-import metadata clarifications | Codex |
| 2026-05-08 | Implemented Phase 14.1 roles model and local validation results | Codex |
| 2026-05-08 | Folded Trinity implementation advisories for unrelated-update validation and migration comments | Codex |
| 2026-05-08 | Folded Trinity final-review advisory for direct changeset role synchronization | Codex |
| 2026-05-08 | Trinity final implementation review passed GLM and DeepSeek | Codex |
