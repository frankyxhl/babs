# CHG-2211: Implement Phase 3 SQLite Citizen Registry

**Applies to:** BAB project
**Last updated:** 2026-05-05
**Last reviewed:** 2026-05-05
**Status:** Proposed
**Date:** 2026-05-05
**Requested by:** —
**Priority:** Medium
**Change Type:** Normal

---

## What

Implement Phase 3 from [BAB-2210](BAB-2210-PRP-Phase-3-SQLite-Citizens-Table-and-Auto-Respawn.md):

- Add `Babs.Citizens.Repo` with SQLite persistence.
- Add the `citizens` migration and `Babs.Citizens.CitizenRecord` schema.
- Add `Babs.Citizens.Catalog` as the persistence boundary.
- Add `Babs.Citizens.Bootstrap` as the ordered boot owner.
- Refactor `ReattachScanner` to scan SQLite rows instead of discovering TOML
  itself.
- Preserve Phase 2a `workspace_root` semantics and Phase 2 transcript replay.
- Add/maintain [BAB-1505](BAB-1505-SOP-Operate-SQLite-Citizen-Registry.md) as
  the operations SOP for the SQLite registry.

## Why

Phase 1-2a proved the flywheel can host Citizens, persist/replay terminal bytes,
and keep workspaces configurable. Phase 3 gives that flywheel durable Citizen
memory: Babs can distinguish `running`, `stopped`, and `failed` Citizens across
node restarts and can auto-reattach/respawn from SQLite.

## Impact Analysis

- **Systems affected:** `:babs_citizens` application startup, Citizen TOML
  import, lifecycle status writes, ReattachScanner planning, Mix dependencies,
  test setup, BDD restart flows, and SQLite operational docs.
- **Data affected:** New local SQLite registry at `BABS_CITIZENS_DB_PATH` or the
  default `<BABS_ROOT>/var/babs_citizens.sqlite3`.
- **Security/privacy:** SQLite may contain spawn-ready `env` values. File
  permissions, log redaction, and backup warnings must follow `BAB-2210` and
  `BAB-1505`.
- **Rollback plan:** Stop Babs, restore from the pre-change branch/commit, and
  either keep the SQLite file unused or restore a backup. The initial migration
  must support rollback via `mix ecto.rollback` or the chosen Babs-specific
  rollback task.

## Implementation Plan

1. **RED: persistence schema tests**
   - Add failing tests for `CitizenRecord` changeset validation, status CHECK
     constraint, JSON/map round-trips, role shapes, id generation, and
     `to_config/1`.
2. **GREEN: Repo + migration**
   - Add Ecto dependencies/config, Repo supervision, database path setup,
     migration/rollback tasks, and test database isolation.
3. **RED/GREEN: side-effect-free TOML import**
   - Add `create_cwd: false` tests to the TOML loader, then implement option
     plumbing while keeping default `create_cwd: true`.
4. **RED/GREEN: Catalog import semantics**
   - Implement slug-keyed import with id mismatch warnings, status/cwd
     preservation, running-row spawn-field preservation, stopped/failed repair
     semantics, and SQLite-only row retention.
5. **RED/GREEN: Bootstrap + scanner**
   - Add `Babs.Citizens.Bootstrap`; refactor `ReattachScanner` to consume
     SQLite rows/configs and tmux sessions; cover running/stopped/failed,
     missing cwd, SQLite-only rows, and full boot order.
6. **RED/GREEN: lifecycle status writes**
   - Mark successful start/reattach as `running`, stop as `stopped`, and
     failures as `failed` with redacted `last_error`.
7. **BDD/E2E**
   - Preserve existing browser tests and add a restart/import test proving
     SQLite drives boot behavior after TOML is hidden/renamed.
8. **Docs**
   - Finalize `BAB-1505`, record validation in `BAB-2210`, and update roadmap
     status after implementation.
9. **Validation**
   - Run the full stack from `BAB-2210`: format, compile warnings-as-errors,
     unit/coverage, JS, E2E, BDD, Gate A, `git diff --check`, and `af validate`.

## Approval

Approved to implement once the operator confirms Phase 3 execution should begin.
The PRP is already approved by Trinity GLM and DeepSeek R5 fast-review.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-05 | Initial version | — |
| 2026-05-05 | Draft implementation CHG for approved Phase 3 SQLite registry PRP | Codex |
