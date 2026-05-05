# PRP-2210: Phase 3 SQLite Citizens Table and Auto Respawn

**Applies to:** BAB project
**Last updated:** 2026-05-05
**Last reviewed:** 2026-05-05
**Status:** Approved

---

## What Is It?

Phase 3 adds a durable SQLite-backed Citizen registry to Babs.

Phases 1-2a proved the Hardline/tmux browser terminal, transcript replay, and
configurable Citizen workspace root. The remaining gap for a usable flywheel is
that Babs still discovers Citizens primarily from
`citizens/citizen-<slug>.toml` and live tmux state. There is no durable runtime
registry that records which Citizens should exist, which ones are intentionally
stopped, which spawn failed, or which resolved `cwd` must be preserved across
node restarts.

Phase 3 introduces `Babs.Citizens.Repo`, a SQLite database, a `citizens` table,
and a boot-time auto-respawn path. TOML remains the seed/import source; SQLite
becomes the runtime authority for Citizen records after import.

---

## Problem

The current runtime can reconnect to existing Babs-managed tmux sessions, but it
cannot distinguish durable operator intent from current process state.

Concrete gaps:

- If Babs restarts and a tmux session is gone, the only durable source is the
  TOML file. That is enough for seed Citizens, but not for Phase 4 UI-created
  Citizens.
- `stop_citizen/1` kills tmux but does not durably record that the Citizen is
  intentionally stopped. A future boot scanner cannot know whether to leave the
  Citizen stopped or start it again.
- Spawn failures are only logged / returned. They are not queryable durable
  state.
- The web UI can only show a terminal for already-running panes. It has no
  durable registry to list known Citizens or explain why a Citizen is stopped or
  failed.
- Phase 4 `/citizens/new` needs a durable table before it can create Citizens
  from the browser without relying on hand-written seed TOML alone.

Phase 2a also made workspace storage configurable, so Phase 3 must avoid
reintroducing ambiguous cwd semantics. A Citizen row must preserve the resolved
workspace path that was chosen at import/spawn time.

## Proposed Solution

### 1. Add SQLite Repo

Add `Babs.Citizens.Repo` inside the `:babs_citizens` OTP app.

Configuration:

- Add `ecto_sql` and `ecto_sqlite3` dependencies to `:babs_citizens`.
- Supervise `Babs.Citizens.Repo` before `Babs.Citizens.ReattachScanner`.
- Add runtime database path config:
  - env var: `BABS_CITIZENS_DB_PATH`
  - default: `<BABS_ROOT>/var/babs_citizens.sqlite3`
- Ensure the default parent directory exists before Repo startup, with
  owner-only permissions where the filesystem supports it.
- Ensure the SQLite file is created with owner-only permissions where possible,
  because Phase 3 may persist spawn-ready `env` values.
- Keep database path docs generic; do not put operator-specific absolute paths
  in public docs or PR text.
- `BAB-1001` still mentions `Babs.Repo` from the older top-level architecture
  sketch. Phase 3 follows the current roadmap and two-OTP-app boundary by adding
  `Babs.Citizens.Repo`; a later architecture rewrite can reconcile the old
  diagram.
- `BAB-2300` has a concise Phase 3 roadmap summary. This PRP's table definition
  is authoritative for Phase 3 implementation details.
- Add [BAB-1505](BAB-1505-SOP-Operate-SQLite-Citizen-Registry.md) as the
  dedicated SQLite registry operations SOP, covering
  database path discovery, migration commands, backup/restore, local inspection,
  status repair, file permissions, and troubleshooting. This gives Phase 4-6 a
  stable operational reference instead of rediscovering the database contract
  from code.

### 2. Add `citizens` table

Migration location: `apps/babs_citizens/priv/repo/migrations/`.

Table shape:

| Field | Type | Notes |
|-------|------|-------|
| `id` | string primary key | Stable Citizen id from TOML, e.g. `BAB-CIT-0001` |
| `slug` | string unique not null | URL/session identity; same validation as TOML slug |
| `display_name` | string not null | Human label |
| `description` | text nullable | TOML description; useful for Phase 4/5 UI |
| `cwd` | string not null | **Resolved absolute cwd** preserved from Phase 2a resolution |
| `cli` | string not null | CLI binary |
| `cli_args` | JSON/text list not null default `[]` | Round-trips string argv list |
| `env` | JSON/text map not null default `%{}` | Optional resolved/inherited env overrides for spawn |
| `status` | string not null | `running`, `stopped`, or `failed` |
| `metadata` | JSON/text map not null default `%{}` | Reserved for Phase 7+ / V0-L |
| `role` | JSON/text nullable | Optional role value; preserves current TOML string or `[role]` table |
| `is_mayor` | boolean default false | Reserved for V0-L |
| `last_error` | text nullable | Most recent spawn/reattach failure, if any |
| `inserted_at` / `updated_at` | timestamps | Ecto timestamps |

Use Ecto's default `inserted_at` and `updated_at` timestamp columns.

Implementation details:

- Ecto schema module name: `Babs.Citizens.CitizenRecord`. Avoid
  `Babs.Citizens.Citizen.Config` / `Babs.Citizens.Citizen.*` names that collide
  cognitively with the existing TOML config loader.
- TOML imports use TOML-provided ids. Phase 4+ non-TOML UI-created Citizens
  generate ids as `BAB-CIT-` plus an `Ecto.UUID.generate/0` value. The schema
  deliberately treats ids as strings so seed ids and generated ids can coexist.
- Add a unique index on `slug`; import/upsert correctness depends on it.
- Add a database CHECK constraint and changeset validation for `status in
  ('running', 'stopped', 'failed')`.
- `cli_args`, `env`, and `metadata` must have shape validation in changesets.
  `cli_args` is a list of strings; `env` and `metadata` are maps.
- `role` validation must accept only `nil`, a string role label, or a map shaped
  like the current BAB-1112 `[role]` example (`name` plus optional `skills` list
  of strings). `to_config/1` must round-trip the accepted role value into
  `%CitizenConfig{}`.
- If `ecto_sqlite3` map support is not sufficient for predictable round-trips,
  implement a small JSON-text `Ecto.Type` and cover it with tests.

### 3. TOML import and SQLite authority

TOML remains the seed/import source during Phase 3:

- On boot, load `citizens/citizen-<slug>.toml` files with the existing
  `Babs.Citizens.Citizen.Config` loader.
- The loader already returns resolved absolute `cwd` values using Phase 2a
  `workspace_root` semantics.
- Phase 3 must add a side-effect-free config load path, for example
  `create_cwd: false`, so TOML import can resolve `cwd` without silently
  creating missing workspace directories.
- `load_slug/2`, `load_file/2`, and `list_configs/1` should all accept
  `create_cwd: false`; the default remains `true` for backward compatibility.
  Internally, cwd resolution should carry that option into the mkdir step and
  skip `File.mkdir_p/1` when disabled.
- Import valid TOML configs into SQLite.
- Upsert key is `slug`, not `id`, because slug is the URL/tmux/session identity.
- Insert missing rows with the TOML `id` and `status = "running"` by default.
- If an existing row with the same slug has a different TOML `id`, preserve the
  SQLite `id`, log/surface an import warning, and do not overwrite the id.
- TOML import order follows the existing sorted `Config.list_configs/1` order.
  If duplicate TOML files declare the same slug on first import, the first file
  in that deterministic order wins the initial id; later duplicates become id
  mismatch warnings.
- For existing rows, update static config fields (`display_name`, `description`,
  and `role`) from TOML, but preserve `status` unless an explicit lifecycle
  action changes it.
- `role` is deliberately updated from TOML re-import for existing rows; it is
  descriptive/routing metadata rather than a live process spawn setting.
- For existing rows, **do not overwrite `cwd` from TOML re-import**. SQLite owns
  the resolved cwd after first import. This avoids a dangerous mismatch where a
  live tmux session continues running in the old directory while Babs starts
  writing transcripts to a newly imported cwd. Changing an existing Citizen cwd
  becomes an explicit future lifecycle/config operation, not an accidental boot
  side effect.
- For `running` rows, do not overwrite spawn-affecting fields (`cli`,
  `cli_args`, `env`) from TOML re-import. The live tmux process was started with
  the prior values. Config changes to a running Citizen become explicit
  stop/start or future restart operations.
- For `stopped` and `failed` rows, TOML re-import may update `cli`, `cli_args`,
  and `env` so an operator can repair a failed config before a later explicit
  start/retry. It still does not auto-retry `failed` rows.
- For new TOML-backed rows, the import path may create the resolved cwd before
  inserting the row. For existing rows, import must not create a missing cwd;
  scanner failure detection owns that case.
- Do not delete SQLite rows when a TOML file disappears.
- Row deletion is not a Phase 3 lifecycle operation. Manual deletion is an
  operator repair action covered by
  [BAB-1505](BAB-1505-SOP-Operate-SQLite-Citizen-Registry.md), and deleting a
  row must not by itself kill a tmux session.

After import, the boot scanner scans **all SQLite rows**, including rows that no
longer have a matching TOML file. This is required for Phase 4 UI-created
Citizens and for the "TOML hidden after import" restart test.

### 4. Auto-respawn semantics

Boot-time behavior:

- `running` row + live `babs-<slug>` tmux session -> reattach Hardline.Pane.
- `running` row + missing tmux session -> start a new tmux session from the row.
- `running` row + missing resolved `cwd` directory -> mark `failed` with a
  descriptive `last_error`; do not silently recreate the directory because that
  masks workspace loss.
- `stopped` row -> do not start or reattach.
- `failed` row -> do not auto-retry. Preserve config/workspace for forensics;
  later start/retry UI belongs to Phase 6.
- TOML decode/import errors are logged and surfaced in scanner events, but do not
  prevent valid SQLite rows from starting.

Lifecycle behavior:

- Successful `start_config` / `reattach` marks the row `running`.
- `stop_citizen/1` marks the row `stopped` after the pane/session stop path
  succeeds or is already gone.
- Spawn/reattach failures mark the row `failed` with `last_error`.
- Existing hardline/tmux rules remain unchanged: reload must not kill tmux; only
  explicit stop kills Babs-managed tmux sessions.

### 5. Query API

Add a small persistence boundary instead of letting web/controllers call Ecto
directly:

- `Babs.Citizens.Catalog` or equivalent context module:
  - `import_configs/1`
  - `list_citizens/0`
  - `get_by_slug/1`
  - `import_config/1` fetches the existing row by slug and delegates to
    insert/merge behavior
  - `merge_import/2` receives `{existing_row, incoming_config}` and applies the
    state-dependent preservation rules
  - `mark_running/1`
  - `mark_stopped/1`
  - `mark_failed/2`
  - `to_config/1` converts a row to the existing
    `%Babs.Citizens.CitizenConfig{}` struct
- `to_config/1` drops database-only fields that are not spawn configuration
  (`status`, `metadata`, `is_mayor`, `last_error`, timestamps) and preserves
  `id`, `slug`, `display_name`, `description`, `cli`, `cli_args`, `env`, `cwd`,
  and `role`.
- `to_config/1` sets `%CitizenConfig{path: nil}` because SQLite is the runtime
  authority. TOML path is import provenance, not spawn configuration.
- `ReattachScanner` consumes that context.
- `ReattachScanner` should gain a SQLite-oriented entry point that accepts
  pre-resolved row/config data plus tmux sessions, rather than reading TOML
  itself. Existing TOML-reading scan helpers may remain for tests only if they
  delegate through Bootstrap/Catalog.
- `Lifecycle` may call `Babs.Citizens.Catalog` directly for status writes in
  Phase 3. Tests should isolate the Repo/database rather than introduce a new
  dependency-injection layer unless implementation pressure proves one is
  needed.
- `TerminalController` may keep requiring a live pane in Phase 3; listing and
  stopped-state UI are Phase 5/6. The persistence API should still make those
  later phases straightforward.

### 6. Boot Sequencing Owner

Add `Babs.Citizens.Bootstrap` or an equivalent one-shot startup module to own
the ordered boot sequence. `ReattachScanner` should become the scanner/planner
that consumes SQLite rows, not the owner of every startup concern.

Supervision integration:

- `Babs.Citizens.Application` keeps a single top-level supervisor and starts
  children in this order: PubSub, PaneRegistry, `Babs.Citizens.Repo`,
  `Babs.Citizens.DynamicSupervisor`, then `Babs.Citizens.Bootstrap`.
- Elixir/Erlang supervisors start children synchronously in child-spec order, so
  Repo and the DynamicSupervisor are available before Bootstrap runs.
- Bootstrap is the last child and performs its one-shot sequence in
  `handle_continue/2` or equivalent after `init/1`, so startup remains
  supervised and testable without moving import/scan into `Application.start/2`.
- If Bootstrap restarts, it reruns the same idempotent import/scan sequence.
  Import preserves row identity/status/cwd, and start/reattach paths already
  tolerate existing tmux sessions and already-started panes.

The boot sequencer:

1. Confirms migrations are complete for the current environment.
2. Imports TOML seed configs into SQLite through `Babs.Citizens.Catalog`.
3. Queries all SQLite rows through `Catalog`.
4. Calls `ReattachScanner` to plan and run start/reattach/skip/fail actions.
5. Stores scanner events for test visibility, preserving the current
   `ReattachScanner.events/0` debugging shape or an equivalent API.

### 7. Migration execution

Phase 3 should include a deterministic migration path for local/dev/test use:

- `mix ecto.migrate` or a Babs-specific alias/task must work.
- `mix ecto.rollback` or a Babs-specific rollback task must work for the Phase 3
  migration.
- Tests must create and migrate isolated SQLite databases.
- Dev/test should auto-run pending migrations before import/scan so the flywheel
  can restart without a manual terminal step.
- Prod/release should require an explicit migration command unless an operator
  later accepts boot-time migration risk.
- Boot order must be deterministic:
  1. Repo starts.
  2. Migrations are complete for the active environment.
  3. TOML import/upsert completes.
  4. `ReattachScanner` queries SQLite rows and starts/reattaches Citizens.

### 8. Secret and Env Guardrails

Phase 3 may persist spawn-ready `env` maps in SQLite because
`%CitizenConfig{}` already needs those values to spawn CLI processes. This is
acceptable only with explicit guardrails:

- SQLite file and parent directory should be owner-only where supported.
- `env` values must be redacted from logs, scanner events, PR bodies, and test
  output.
- The Phase 3 SQLite operations SOP must warn that DB backups may contain
  secrets.
- Imported env values are point-in-time snapshots. Changing an OS environment
  variable after import requires a re-import or explicit row update before a
  future spawn will see it.
- Phase 4 `/citizens/new` must not expose arbitrary env editing until it has a
  secret-storage/redaction design. This is a Phase 4 precondition, not Phase 3
  implementation scope.

## Acceptance

Phase 3 is complete when:

- A SQLite `citizens` table exists and is managed by Ecto migrations.
- Seed TOML Citizens (`sentinel`, `clare`, `dylan`, `elena`) import into SQLite.
- Imported rows store resolved absolute `cwd` values, preserving Phase 2a
  `workspace_root` behavior.
- Existing SQLite rows do not have `cwd` overwritten by TOML re-import.
- Existing running rows do not have `cli`, `cli_args`, or `env` overwritten by
  TOML re-import.
- SQLite-only rows, with no matching TOML file, are still scanned and can
  reattach/respawn when `status = "running"`.
- Missing `cwd` for a running row marks the row failed instead of silently
  recreating the directory.
- On Babs boot, `running` rows are reattached if tmux exists and respawned if
  tmux is missing.
- `stopped` rows are not auto-started on boot.
- `failed` rows are not auto-retried on boot.
- `stop_citizen/1` durably records `stopped`.
- Spawn failure durably records `failed` plus a useful `last_error`.
- Existing Gate A still passes.
- Browser-harness BDD still passes.
- A focused restart/respawn test proves a Citizen can be restored from SQLite
  even when TOML is not the runtime decision surface.
- A focused BDD or integration test hides/renames seed TOML after import and
  proves the SQLite row still drives boot behavior.
- `BAB-1505` SQLite registry operations SOP exists and is linked from this PRP.
- Coverage gates remain at least `:babs_citizens` 80% and `:babs` 70%.

## Tests

Expected test additions:

- Schema/changeset unit tests:
  - valid row inserts
  - invalid slug rejected
  - invalid status rejected
  - `status` database CHECK constraint rejects invalid values
  - `cli_args` and `env` round-trip
  - `cli_args` must validate as a list of strings
  - `env` and `metadata` must validate as maps
  - `role` round-trips `nil`, string role labels, and BAB-1112-style role maps
  - `to_config/1` preserves spawn fields and drops database-only fields
- Import tests:
  - TOML config imports missing row
  - new TOML row creates cwd; existing TOML row with missing cwd does not
    recreate it during import
  - TOML import upserts by `slug`
  - TOML id match for an existing slug updates non-conflicting metadata fields
  - TOML id mismatch for an existing slug preserves SQLite id and emits a warning
  - TOML config update preserves existing `status`
  - TOML config update preserves existing `cwd`
  - TOML config update preserves running-row `env`
  - TOML config update may repair stopped/failed-row `env`
  - resolved `cwd` is stored as absolute path
  - missing/deleted TOML does not delete existing row
- Scanner/lifecycle tests:
  - `running` + existing tmux -> reattach
  - `running` + missing tmux -> start
  - `stopped` -> no start
  - `failed` -> no retry
  - SQLite-only `running` row with no TOML still starts/reattaches
  - running row with missing cwd marks failed with `last_error`
  - start success marks `running`
  - stop marks `stopped`
  - spawn failure marks `failed`
  - full boot order runs migrate -> import -> scan -> Citizen ready
  - env values are redacted from logs/scanner events/test output
- Browser-harness BDD:
  - restart Babs with existing SQLite rows and verify terminal reconnect/replay
  - if practical, hide/rename seed TOML after import and verify the running row
    still drives boot behavior
- Validation stack:
  - `mise exec -- mix format --check-formatted`
  - `mise exec -- mix compile --warnings-as-errors`
  - `mise exec -- mix test`
  - `mise exec -- mix test --cover`
  - `npm run test:js`
  - `npm run test:e2e`
  - `npm run test:bdd`
  - `mise exec -- mix babs.gate_a`
  - `af validate --root <repo>`

## Out Of Scope

- `/citizens/new` spawn UI; Phase 4 owns that.
- Full secret-management UI or encrypted credential store; Phase 4+ owns that
  before exposing env editing.
- Multi-Citizen index UI; Phase 5 owns that.
- Stop/start/restart browser buttons; Phase 6 owns that.
- Ticket tables or ticket filesystem automation; Phase 7+ owns that.
- Moving existing workspaces or migrating transcript files.
- Replacing Babs-owned Hardline transcript JSONL with SQLite.
- Parsing upstream Claude/Codex transcripts into semantic messages.

## Proposed Decisions

- SQLite stores resolved absolute `cwd`, not raw TOML `cwd`, so Citizen workspace
  location is preserved across app root or workspace-root config changes.
- TOML is an import/seed source in Phase 3; SQLite is the runtime authority after
  import.
- TOML import upserts by `slug`; an id mismatch for an existing slug is a warning
  and does not overwrite SQLite's id.
- Phase 4+ UI-created Citizens generate ids as `BAB-CIT-` plus an
  `Ecto.UUID.generate/0` value.
- Existing rows keep `status` across TOML re-imports.
- Existing rows keep `cwd` across TOML re-imports; accidental live cwd migration
  is explicitly avoided.
- Existing rows intentionally refresh `display_name`, `description`, and `role`
  from TOML re-import.
- TOML import uses a side-effect-free config load path for existing rows, so it
  does not recreate missing cwd directories before scanner failure detection.
- Existing running rows keep `cli`, `cli_args`, and `env` across TOML re-imports;
  stopped/failed rows may accept repaired TOML spawn settings.
- `running` means "desired to be running"; boot may reattach or respawn it.
- `stopped` and `failed` are both no-auto-start states.
- Missing `cwd` for a `running` row is failure, not an implicit new workspace.
- Add `id` as the SQLite primary key even though the short roadmap omitted it,
  because Phase 1 TOML already requires stable Citizen ids.
- Keep web terminal routes live-pane-first in Phase 3; stopped/failed UX belongs
  to Phases 5-6.
- Use `Babs.Citizens.Catalog` rather than `Babs.Citizens.Registry` as the Ecto
  context name to avoid confusion with the existing `Babs.Citizens.PaneRegistry`
  process registry.
- Use `Babs.Citizens.CitizenRecord` for the Ecto schema module.
- Add `BAB-1505` as a durable SQLite registry operator reference.
- Scanner events remain in-memory for Phase 3. Durable boot/import event history
  is deferred to future ticket/history work.
- Use Ecto default `inserted_at` and `updated_at` timestamp columns.
- Preserve the current flexible `role` shape in SQLite rather than flattening it
  to a string.

## Open Questions

- Should Phase 3 auto-run migrations at application boot, or require an explicit
  migration task before boot? Proposed answer after Trinity review: auto-migrate
  in dev/test for flywheel ergonomics; require explicit migration in prod.
- Should the database path env var be `BABS_CITIZENS_DB_PATH` or a broader
  future-facing `BABS_DATA_DIR`? Proposed answer: use
  `BABS_CITIZENS_DB_PATH` now for minimal scope; introduce `BABS_DATA_DIR` later
  only when more durable stores exist.
- Should `env` be persisted after interpolation, or only TOML-sourced variable
  references? Proposed answer: persist the spawn-ready map used by
  `%CitizenConfig{}` for Phase 3, and revisit secret storage before exposing UI
  editing in Phase 4.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-05 | Initial version | — |
| 2026-05-05 | Draft Phase 3 SQLite registry, TOML import, status, auto-respawn, tests, and acceptance semantics | Codex |
| 2026-05-05 | Trinity GLM and DeepSeek fast-review passed; incorporated advisories for description, boot ordering, cwd re-import safety, env persistence, context naming, and migration policy | Codex |
| 2026-05-05 | Trinity R2 found boot/import/schema/env/SQLite-only-row blockers; resolved with explicit Bootstrap owner, CitizenRecord schema name, slug-keyed import, running-row spawn-setting preservation, SQLite-only scanning, cwd-missing failure, and SQLite operations SOP requirement | Codex |
| 2026-05-05 | Trinity R4 found config-loader cwd side effect and role/upsert ambiguity; resolved with side-effect-free import loading, role JSON validation, state-aware import API, direct Catalog lifecycle status writes, rollback expectation, and redaction tests | Codex |
| 2026-05-05 | Trinity R5 fast-review passed with GLM and DeepSeek; incorporated non-blocking implementation clarifications for defaults, slug index, idempotent Bootstrap restart, scanner entry point, config loader option plumbing, happy-path import test, `path: nil`, and duplicate TOML ordering | Codex |
