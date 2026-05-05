# CHG-2213: Implement Phase 4 NewCitizenLive Spawn UI

**Applies to:** BAB project
**Last updated:** 2026-05-05
**Last reviewed:** 2026-05-05
**Status:** Completed
**Date:** 2026-05-05
**Requested by:** —
**Priority:** Medium
**Change Type:** Normal

---

## What

Implement Phase 4 from
[BAB-2212](BAB-2212-PRP-Phase-4-NewCitizenLive-Spawn-UI.md):

- Add `/citizens/new` and `BabsWeb.NewCitizenLive`.
- Add `Babs.Citizens.Spawner.create_and_start/1` as the ordered side-effect
  boundary for UI-created Citizens.
- Add an internal TOML writer for the current flat Citizen TOML shape.
- Add `Catalog.insert_new/1` as an insert-only SQLite API for UI creation.
- Spawn browser-created Citizens through existing lifecycle/tmux ownership.
- Preserve existing `/citizens/:slug` terminal behavior and seed Citizen boot.
- Add unit, LiveView/controller, browser-harness BDD, and existing E2E coverage.

## Why

Phase 3 made Citizen identity and runtime state durable in SQLite. Phase 4 makes
the flywheel usable from the browser: an operator can create a new non-seed
Citizen without hand-editing TOML, land in its terminal, and validate that TOML,
SQLite, tmux, and transcript persistence all agree.

## Impact Analysis

- **Systems affected:** `:babs_citizens` Catalog/Spawner/config writer,
  `:babs` router and LiveView layer, browser-harness BDD, and terminal route
  regression coverage.
- **Data affected:** New local TOML files under configured `config_dir`, new
  SQLite `citizens` rows, new workspace directories under configured
  workspace root, and new `transcript.jsonl` files.
- **Security/privacy:** Phase 4 does not add browser env editing. Auth-dependent
  CLI presets rely on existing local CLI auth/environment. Error messages must
  continue to use redacted failure details.
- **Rollback plan:** Stop Babs, restore the previous branch/commit, and remove
  any test-created TOML files/workspaces/SQLite rows if they should not remain.
  Preserved TOML files may also be reconciled by boot/import if the operator
  intentionally keeps them.

## Implementation Plan

1. **RED: Spawner validation and side-effect boundaries**
   - Add failing tests for slug format, reserved slugs (`new`, `edit`, `index`),
     required display name, unknown CLI preset, absolute browser cwd rejection,
     duplicate TOML/SQLite slug, and no side effects on validation failure.
   - Add failing concurrency tests proving same-slug creates serialize and only
     one reaches SQLite insert/lifecycle start.
   - Add a different-slug concurrency test proving the lock is per-slug rather
     than global.
2. **RED/GREEN: Catalog insert-only API**
   - Add `Catalog.insert_new/1` accepting `%CitizenConfig{}` with resolved cwd.
   - Return `{:ok, %CitizenRecord{}}` or `{:error, %Ecto.Changeset{}}` /
     `{:error, reason}`.
   - Return the 2-tuple `{:ok, record}` on success, not the 3-tuple
     `{:ok, record, warnings}` shape used by `import_config/1`.
   - Set `status = "running"`, `metadata = %{}`, and `is_mayor = false`.
   - Non-behaviors: do not call `File.mkdir_p/1`; do not merge an existing row;
     do not upsert; do not read or write TOML. The existing
     `insert_import/1` path is a known copy-paste trap because it does mkdir
     and import reconciliation.
3. **RED/GREEN: TOML writer**
   - Add a deterministic internal writer; do not add a new Hex TOML encoder
     dependency for Phase 4.
   - Respect configured `root` and `config_dir`.
   - Remove stale temp files for the same slug before writing.
   - Use unique same-directory temp files named like
     `.citizen-<slug>.<unique>.toml.tmp`, then rename into place.
   - Re-check that the target `citizen-<slug>.toml` file does not exist
     immediately before rename, so an external hand-written file is not silently
     overwritten.
   - Emit explicit `cli_args`, omit nil/blank optional fields, omit empty env,
     and escape TOML-special characters.
   - Round-trip through `Config.load_file/2`, verifying that the loaded
     config's resolved absolute `cwd` matches Spawner cwd resolution rather than
     string-level TOML cwd equality.
4. **RED/GREEN: Spawner create-and-start flow**
   - Generate `id` with `CitizenRecord.generate_id/0` before building
     `%CitizenConfig{}`.
   - Resolve relative cwd under workspace root while preserving the original
     relative cwd for TOML. TOML gets the relative cwd; `%CitizenConfig{}.cwd`,
     `Catalog.insert_new/1`, and `Lifecycle.start_config/1` get the resolved
     absolute cwd.
   - Serialize side effects with a v0.1 local per-slug Spawner lock, preferably
     a Registry-backed lock helper owned by `:babs_citizens`. Same-slug creates
     must not interleave TOML writes, workspace creation, SQLite inserts, or
     lifecycle starts; different slugs must not block each other. Future
     multi-node work may revisit `:global` or another distributed lock.
   - Treat duplicate TOML/SQLite pre-checks as operator-friendly validation.
     The SQLite unique constraint remains the final correctness guard if an
     external process races Babs.
   - Order effects as TOML write -> workspace mkdir -> SQLite insert ->
     `Lifecycle.start_config/1`.
   - Follow the partial-failure table below exactly.
   - Let `Lifecycle.start_config/1` perform its existing `mark_running` /
     `mark_failed` status writes; Spawner should surface a redacted UI error
     and should not independently double-mark lifecycle failures.
   - After lifecycle failure, call `Catalog.get_by_slug/1`, read the persisted
     redacted `last_error` from the row, and return that to the UI rather than
     duplicating Catalog's redaction regexes in Spawner.
   - Use structured error tuples for UI mapping, such as
     `{:toml_write_failed, reason}`, `{:workspace_mkdir_failed, reason}`,
     `{:sqlite_insert_failed, reason}`, and
     `{:lifecycle_start_failed, redacted_reason}`.
   - Set `%CitizenConfig{}.path` to the written TOML path for debugging
     consistency, even though lifecycle currently does not consume it.
5. **RED/GREEN: NewCitizenLive UI**
   - Add `/citizens/new` before `/citizens/:slug`.
   - Use a standalone LiveView form with slug, display name, description,
     preset dropdown, and relative cwd input.
   - Implement exactly the approved preset list from `BAB-2212`: `shell`,
     `claude`, `codex`, `droid`, `pi`, and `copilot-cli`.
   - Label the GitHub Copilot preset as `copilot-cli`, writing
     `cli = "gh"` and `cli_args = ["copilot"]`.
   - On success, redirect to `/citizens/<slug>`; on failure, stay on the form
     with concise errors.
6. **BDD/E2E**
   - Add browser-harness BDD for unique shell Citizen creation, terminal marker
     echo exactly once, TOML/SQLite assertions, transcript creation, duplicate
     rejection, and `/citizens/sentinel` regression.
   - Add restart/bootstrap regression for a browser-created shell Citizen:
     after restart, TOML import and SQLite reconciliation preserve the Citizen
     and it can reconnect. Prefer an automated browser-harness helper that
     stops/starts the server; if that proves too large for Phase 4, record this
     as a manual validation step in the CHG before PR.
   - Preserve existing Playwright smoke coverage as legacy E2E.
7. **Docs**
   - Record final partial-failure validation evidence in this CHG after
     implementation.
   - Update roadmap/discussion tracker and PRP implementation results after
     validation.
8. **Validation**
   - Run format, compile warnings-as-errors, unit tests, coverage, JS tests,
     browser-harness BDD, Playwright E2E, Gate A, `af validate`, and
     `git diff --check`.

## Approval

Trinity GLM/DeepSeek CHG review passed with no blockers on 2026-05-05. Operator
approved Phase 4 implementation on 2026-05-05.

## Partial Failure Semantics

| Failure point | TOML | Workspace | SQLite row | Recovery |
|---------------|------|-----------|------------|----------|
| TOML write failure | none | none | none | Retry after fixing the write failure. |
| Workspace mkdir failure | preserved | none | none | Fix the issue and let boot/import reconcile the TOML, or delete TOML and retry. |
| SQLite insert failure | preserved | exists | none | Fix the issue and let boot/import reconcile the TOML, or delete TOML/workspace and retry. |
| Lifecycle start failure | preserved | preserved | `failed` | Use existing lifecycle/start controls or future Phase 6 controls after fixing the root cause. |

The Spawner must not silently delete durable artifacts after a partial success.
This preserves operator intent and makes recovery explicit.

## Validation

Local validation on 2026-05-06:

- `mise exec -- mix format --check-formatted`: passed.
- `mise exec -- mix compile --warnings-as-errors`: passed.
- `mise exec -- mix test`: passed, `:babs_citizens` 114 tests and `:babs` 29
  tests.
- `mise exec -- mix test --cover`: passed, `:babs_citizens` 83.24% and
  `:babs` 77.24%.
- `npm run test:js`: passed, 6 Node tests.
- `BABS_HTTP_PORT=4013 BABS_BROWSER_BASE_URL=http://127.0.0.1:4013 npm run test:bdd`:
  passed, 11 scenarios plus 1 expected `BABS_WORKSPACE_ROOT` skip. Browser BDD
  was not rerun after the final detach-only fix; the affected reload path was
  covered by `mix babs.gate_a` and lifecycle integration tests after that fix.
- `npm run test:e2e`: passed, 6 Playwright tests.
- `mise exec -- mix babs.gate_a`: passed.
- Targeted socket-token regression validation passed:
  `mise exec -- mix test apps/babs/test/babs_web/live/new_citizen_live_test.exs apps/babs/test/babs_web/controllers/terminal_controller_test.exs apps/babs/test/babs_web/channels/user_socket_test.exs`.
- `af validate --root <repo>`: passed, 108 docs checked.
- `git diff --check`: passed.

## Implementation Results

Implemented in branch `codex/phase-4-prep`:

- Added `Catalog.insert_new/1` as a 2-tuple insert-only API for UI-created
  Citizens. It does not mkdir, merge, upsert, or touch TOML.
- Added `Babs.Citizens.Citizen.TomlWriter` for deterministic internal TOML
  writing with configured `root`/`config_dir`, stale temp cleanup,
  same-directory unique temp files, final-path overwrite guard, explicit
  `cli_args`, and TOML basic-string escaping.
- Hardened TOML installation against final-path overwrite races by linking the
  temp file into place without replacing an existing destination, and converted
  stale-temp listing failures into typed errors.
- Added `Babs.Citizens.Spawner.create_and_start/2` with validation, reserved
  slugs, preset mapping, relative browser cwd handling, per-slug Registry-backed
  locking, TOML -> workspace mkdir -> SQLite -> lifecycle ordering, structured
  errors, and redacted lifecycle failure surfacing.
- Hardened Spawner browser inputs by rejecting `..` cwd traversal, avoiding
  dynamic atom creation from untrusted params, bounding same-slug lock waits,
  rejecting symlink-based cwd escapes, revalidating workspace paths immediately
  before creation, safely creating workspace directories one segment at a time,
  handling filesystem-root workspace roots, and converting lifecycle exceptions
  and exits into redacted `failed` rows.
- Changed hardline detach to signal only the BEAM-side erlexec
  `tmux attach-session` process, avoiding a standalone Gate A hang while
  preserving the underlying tmux session.
- Added `/citizens/new` via `BabsWeb.NewCitizenLive`, with
  slug/display name/description/preset/cwd fields and a `copilot-cli` preset
  that writes `cli = "gh"` and `cli_args = ["copilot"]`.
- Routed `/citizens/new` through `TerminalController.new/2` so an existing
  Citizen whose slug is `new` keeps its terminal URL instead of being shadowed
  by the spawn form.
- Preserved `socket_token` through the `/citizens/new` LiveView session and
  post-create redirect so auth-token-protected browser terminals can connect
  after a successful create.
- Added the Phoenix LiveView browser client as a vendored static asset and a
  small `live_boot.js`, plus LiveView socket/session/CSRF configuration.
- Added `BABS_HTTP_PORT` support in dev config so browser validation can run on
  an isolated port.
- Added ExUnit coverage for Catalog insert-only semantics, TOML writer
  round-trip/escaping/temp cleanup, Spawner validation/partial failures/
  concurrency, route ordering, LiveView rendering, redirect, and inline errors.
- Expanded browser-harness BDD to create a temporary shell Citizen from
  `/citizens/new`, verify terminal input exactly once, inspect TOML/SQLite,
  verify transcript persistence, reject duplicate slug, and confirm a
  browser-created Citizen survives a managed server restart with post-restart
  TOML and SQLite assertions.

## Review Results

- Trinity fast-review R1 found blockers in GLM and DeepSeek. This CHG was
  revised to carry forward the approved PRP's ID generation, per-slug lock,
  TOML temp-file naming, insert-only Catalog non-behaviors, and partial-failure
  semantics.
- Trinity fast-review R3 returned PASS from GLM and DeepSeek with advisories
  only. Low-cost advisories for SQLite unique-constraint fallback and redacted
  `last_error` read-back were folded into this CHG.
- Operator confirmed Trinity fast-review is sufficient for Phase 4 code review.
- Trinity fast-review on `apps/babs/lib` passed with GLM and DeepSeek. GLM
  advisories for browser security headers, flash fetching, and duplicate root
  layout setup were folded in.
- Trinity fast-review on `apps/babs_citizens/lib` found GLM blockers for cwd
  traversal and dynamic atom creation. Both were fixed with tests. Final
  `apps/babs_citizens/lib` fast-review passed with GLM and DeepSeek.
- Trinity fast-review on `test/browser/bdd` found a DeepSeek blocker where the
  managed restart helper could no-op after shutdown timeout. The restart helper
  now fails closed, and restart BDD explicitly verifies TOML/SQLite after boot.
  Final BDD fast-review passed with GLM and DeepSeek; remaining observations
  were non-blocking cleanup.
- GitHub Codex PR review on PR #12 found P1/P2 issues in `TomlWriter`: final
  rename could overwrite a concurrently-created TOML, and `File.ls!/1` could
  crash stale-temp cleanup. Both were fixed with regression tests and the full
  validation stack was rerun.
- The second GitHub Codex PR review on PR #12 found P1/P3 issues: cwd boundary
  checks needed to resolve existing symlinks before accepting a browser cwd,
  and the LiveView status mapping missed `TomlWriter`'s three-element
  `{:toml_write_failed, path, reason}` tuple. Both were fixed with regression
  tests and the full validation stack was rerun.
- The third GitHub Codex PR review on PR #12 found a P1 route regression where
  `/citizens/new` shadowed an existing Citizen with slug `new`. The route now
  preserves the terminal URL for that slug and only renders the spawn form when
  no such Citizen is running; a controller regression test covers this behavior.
- The fourth GitHub Codex PR review on PR #12 found P1/P2 issues in Spawner:
  cwd needed to be revalidated immediately before workspace creation to close a
  symlink-swap window, and workspace-root `/` needed explicit boundary handling.
  Both were fixed with regression tests and the full validation stack was rerun.
- A later GitHub Codex PR review on PR #12 found a P1 lifecycle exit issue:
  `lifecycle_start` exits could leave a browser-created Citizen row stuck in
  `running`. Spawner now catches exits, persists a redacted failed row, and a
  regression test covers the behavior.
- The final GitHub Codex PR review loop was stopped at the operator-approved
  cap after finding a P1 socket-token redirect issue. The targeted fix
  preserves `socket_token` from `/citizens/new` into the redirected terminal
  URL, with a LiveView regression test. Per operator instruction, no further
  Codex review loop was started after this targeted fix.
- Local validation also found standalone Gate A could hang while detaching the
  BEAM-side erlexec `tmux attach-session` process. Runner detach now sends a
  signal to that attach process instead of using blocking `:exec.stop/1`; Gate A
  passes after the fix.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-05 | Initial draft CHG for approved Phase 4 PRP | Codex |
| 2026-05-05 | Address Trinity R1 CHG blockers by expanding ID generation, per-slug locking, TOML temp-file naming, Catalog non-behaviors, and partial-failure semantics | Codex |
| 2026-05-05 | Address Trinity R2 GLM blockers by adding explicit concurrency tests and replacing ambiguous `:global` wording with a v0.1 local per-slug lock plan | Codex |
| 2026-05-05 | Record Trinity R3 PASS from GLM/DeepSeek and fold in unique-constraint and redacted-error read-back advisories | Codex |
| 2026-05-05 | Address third GitHub Codex PR review P1 by preserving `/citizens/new` as a terminal URL when a `new` Citizen exists | Codex |
| 2026-05-05 | Address fourth GitHub Codex PR review P1/P2 by revalidating cwd before workspace creation and supporting workspace root `/` | Codex |
| 2026-05-05 | Address fifth GitHub Codex PR review P1 by catching lifecycle exits and persisting failed rows | Codex |
| 2026-05-05 | Fix standalone Gate A hang by making hardline detach signal the erlexec tmux attach process without killing tmux | Codex |
| 2026-05-06 | Address final capped Codex review P1 by preserving socket token through `/citizens/new` create redirect without starting another review loop | Codex |
| 2026-05-05 | Mark Approved after operator approval to proceed with Phase 4 implementation | Codex |
| 2026-05-05 | Record Phase 4 implementation results and local validation evidence | Codex |
| 2026-05-05 | Record full-scope Trinity implementation-review execution blocker | Codex |
| 2026-05-05 | Address Trinity Phase 4 code-review findings, rerun validation, and mark implemented | Codex |
| 2026-05-05 | Address GitHub Codex PR review findings for TOML install race and cleanup error handling | Codex |
| 2026-05-05 | Address second GitHub Codex PR review findings for symlink cwd escapes and TOML error mapping | Codex |
