# CHG-2211: Implement Phase 3 SQLite Citizen Registry

**Applies to:** BAB project
**Last updated:** 2026-05-05
**Last reviewed:** 2026-05-05
**Status:** Approved
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

Approved by the operator on 2026-05-05. The PRP is approved by Trinity GLM and
DeepSeek R5 fast-review.

## Implementation Results

Implemented in branch `codex/phase-3-prep`:

- Added `Babs.Citizens.Repo`, SQLite runtime path config, owner-only best-effort
  file permissions, and Ecto migration/rollback support.
- Added `Babs.Citizens.CitizenRecord` plus JSON-text field handling for
  `cli_args`, `env`, `metadata`, and `role`.
- Added `Babs.Citizens.Catalog` for TOML import/upsert, slug-keyed identity,
  state-dependent preservation rules, `to_config/1`, and durable status writes.
- Added `Babs.Citizens.Bootstrap` as the ordered boot sequencer: migrate,
  import TOML, then scan SQLite rows.
- Updated `ReattachScanner` to plan and scan SQLite rows, including
  SQLite-only rows, stopped/failed skips, missing-cwd failure, and tmux
  reattach/start decisions.
- Updated lifecycle start/reattach/stop/failure paths to write SQLite status
  while preserving existing tmux semantics.
- Added browser-harness BDD coverage that verifies the sentinel row is present
  and running in SQLite after boot.
- Disabled Repo SQL query logging by default so persisted `env` values are not
  emitted as query parameters.

## Validation

Local validation on 2026-05-05:

- `mise exec -- mix format --check-formatted`: passed.
- `mise exec -- mix compile --warnings-as-errors`: passed.
- `mise exec -- mix test`: passed, `:babs_citizens` 91 tests and `:babs` 20
  tests.
- `mise exec -- mix test --cover`: passed, `:babs_citizens` 84.21% and
  `:babs` 78.00%.
- `npm run test:js`: passed, 6 Node tests.
- `npm run test:bdd`: passed, 9 scenarios with 1 expected
  `BABS_WORKSPACE_ROOT` skip.
- `npm run test:e2e`: passed, 6 Playwright tests.
- `mise exec -- mix babs.gate_a`: passed.
- `mise exec -- mix ecto.migrate -r Babs.Citizens.Repo`: passed.
- `mise exec -- mix ecto.rollback -r Babs.Citizens.Repo --step 1 && mise exec -- mix ecto.migrate -r Babs.Citizens.Repo`: passed.
- `af validate --root /Users/frank/Projects/babs-phase3-prep`: passed, 106 docs
  checked.
- `git diff --check`: passed.
- Private-IP scan found no real Tailscale IP; remaining matches were generic
  Tailscale documentation and deliberate test secret fixtures.

## Review Results

- Trinity DeepSeek final code review: PASS with advisories only,
  `.trinity/reviews/20260505-182916-./`.
- Trinity GLM final code review: PASS with advisories only,
  `.trinity/reviews/20260505-183419-./`.
- Addressed earlier Trinity advisories for unknown raw status handling,
  lower-case token/secret redaction, redundant Repo `pool_size` config, and
  `scan_rows/1` tmux-error coverage.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-05 | Initial version | — |
| 2026-05-05 | Draft implementation CHG for approved Phase 3 SQLite registry PRP | Codex |
| 2026-05-05 | Mark approved after operator confirmed Phase 3 execution should begin | Codex |
| 2026-05-05 | Record Phase 3 implementation results and validation evidence | Codex |
| 2026-05-05 | Address Trinity DeepSeek/GLM advisories with unknown-status skip coverage, stronger secret redaction coverage, and scan_rows tmux-error coverage | Codex |
