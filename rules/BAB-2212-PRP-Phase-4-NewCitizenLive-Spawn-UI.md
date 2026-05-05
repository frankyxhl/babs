# PRP-2212: Phase 4 NewCitizenLive Spawn UI

**Applies to:** BAB project
**Last updated:** 2026-05-05
**Last reviewed:** 2026-05-05
**Status:** Approved

---

## What Is It?

Phase 4 adds an operator-facing `/citizens/new` browser flow for creating a new
Citizen without hand-editing TOML first.

The form writes the same durable sources that earlier phases established:

- a `citizens/citizen-<slug>.toml` config file for reviewable/offline edits
  by default, respecting configured `config_dir` when overridden
- a SQLite `citizens` row through `Babs.Citizens.Catalog`
- a live tmux/Hardline process started through the existing lifecycle boundary

After successful spawn, the operator is redirected to `/citizens/<slug>` and can
interact with the new terminal.

## Why

Phase 1 proved the flywheel can host seed Citizens. Phase 2 preserved terminal
bytes. Phase 2a made workspaces configurable. Phase 3 made Citizen identity,
status, and respawn intent durable in SQLite.

The next missing flywheel step is ergonomic creation: the operator should be
able to add a non-seed Citizen from the browser, confirm it reaches an
interactive prompt, and then use the existing terminal page.

## Scope

In scope:

- Add `/citizens/new` route and `BabsWeb.NewCitizenLive`.
- Add a small `Babs.Citizens.Spawner` or equivalent context API in
  `:babs_citizens` so web code does not write TOML, SQLite, or tmux directly.
- Add a dedicated TOML writer helper in `:babs_citizens` for the current flat
  Citizen TOML shape.
- Validate slug, display name, CLI preset, and workspace/cwd input before any
  side effects. Phase 4 uses fixed CLI presets rather than arbitrary command
  editing.
- Generate Citizen ids as `BAB-CIT-` plus `Ecto.UUID.generate/0` for UI-created
  Citizens, per `BAB-2210`.
- Resolve cwd using Phase 2a workspace-root semantics and store the resolved
  absolute path in SQLite.
- Write `citizen-<slug>.toml` under the configured Citizen config directory
  using the current Phase 1/3 TOML shape.
- Insert the SQLite row through a new `Catalog.insert_new/1` or equivalent
  insert-only API.
- Start the Citizen through `Lifecycle.start_config/1`.
- On success, redirect to `/citizens/<slug>`.
- On failure, show a concise error and mark the row `failed` when a durable row
  already exists.
- Add unit, LiveView/controller, browser-harness BDD, and existing E2E smoke
  coverage.

Out of scope:

- Multi-Citizen index and tab navigation; Phase 5 owns that.
- Stop/start/restart controls; Phase 6 owns that.
- Arbitrary env editing in the browser. Phase 3 explicitly requires a
  secret-storage/redaction design before exposing env editing.
- Encrypted credential storage.
- Ticket/billboard UI or Ticket creation.
- Role editing beyond preserving existing schema support; V0-L owns
  role-driven assignment.

## UX Contract

The first screen at `/citizens/new` is the usable form, not a marketing page.

Fields:

- `slug`: required, lowercase URL/session slug using the existing
  `^[a-z][a-z0-9-]{0,47}$` rule. Reserved slugs are rejected even when they
  match the regex: `new`, `edit`, and `index`.
- `display_name`: required human label.
- `description`: optional short text.
- `cli_preset`: required option set.
- `cwd`: optional relative workspace name, defaulting to the slug.

Phase 4 browser input rejects absolute `cwd` values. Operators who need an
absolute cwd can still hand-edit TOML; the browser flow keeps cwd relative to
the configured workspace root.

CLI presets:

| Preset | TOML output | Notes |
|--------|-------------|-------|
| `shell` | `cli = "/bin/zsh"`, `cli_args = ["-f"]` | deterministic automated validation path |
| `claude` | `cli = "claude"`, `cli_args = []` | uses existing local auth state |
| `codex` | `cli = "codex"`, `cli_args = []` | uses existing local auth state |
| `droid` | `cli = "droid"`, `cli_args = []` | requires local command/auth |
| `pi` | `cli = "pi"`, `cli_args = []` | requires local command/auth |
| `copilot-cli` | `cli = "gh"`, `cli_args = ["copilot"]` | uses `gh` auth state |

The UI may use a dropdown instead of radios if the option list would crowd the
form. The shell preset exists so tests can validate the full spawn path without
using AI CLI tokens or credentials. The UI may prefill `display_name` from the
slug, but server-side validation still requires a non-empty display name.

Auth-dependent presets (`claude`, `codex`, `droid`, `pi`, and `copilot-cli`)
work only when the Babs server/tmux environment already has the required local
auth state. Phase 4 does not add browser env editing, so `shell` is the only
credential-free deterministic validation preset.

## Proposed Design

### 1. Add a Spawn Boundary

Add a context boundary such as `Babs.Citizens.Spawner.create_and_start/1`.

The boundary owns the ordered side effects:

1. Normalize and validate form params.
2. Build a `%CitizenConfig{}` with generated id, display name, optional
   description, resolved cwd, CLI preset, empty env, and nil role. The Spawner
   keeps both the original relative TOML cwd value and the resolved absolute cwd
   in local variables; `%CitizenConfig{}.cwd` uses the resolved absolute path.
3. Fail before writing anything if slug already has a TOML file or SQLite row.
4. Write TOML atomically enough for local operation through an internal writer:
   remove stale temp files for the same slug, write a unique temp file in the
   configured Citizen config directory, then rename into place.
5. Create the resolved workspace directory with `File.mkdir_p/1`.
6. Insert the SQLite row through a new `Catalog.insert_new/1` or equivalent
   insert-only API.
7. Start via `Lifecycle.start_config/1`.
8. Return `{:ok, %CitizenRecord{}}` or `{:error, reason}` with enough detail for
   the UI.

The web layer must call this boundary rather than Ecto, `File.write!`, tmux, or
`Lifecycle` directly.

The side-effect sequence runs under a per-slug Spawner lock. The implementation
can use a small local lock helper such as `:global.trans/4` on the current node
or a Registry-backed lock, but concurrent `create_and_start/1` calls for the
same slug must not interleave TOML writes, workspace creation, SQLite inserts,
or lifecycle starts. The TOML/SQLite pre-check is for operator-friendly errors;
the SQLite unique constraint remains the final correctness guard if an external
process races Babs.

`Catalog.insert_new/1` is not `Catalog.import_config/1`. The import path is for
boot-time TOML reconciliation and may merge existing rows. Phase 4 creation
already checked duplicate TOML/SQLite slugs, so it needs a pure insert path that
does not upsert, merge, or create the workspace directory as a hidden side
effect.

`Catalog.insert_new/1` contract:

- Input: `%CitizenConfig{}` with resolved absolute `cwd`.
- Success: `{:ok, %CitizenRecord{}}`.
- Failure: `{:error, %Ecto.Changeset{}}` for validation/constraint errors or
  `{:error, reason}` for non-changeset failures.
- Defaults: set `status = "running"`, `metadata = %{}`, and
  `is_mayor = false`, mirroring the existing import insert defaults.
- Non-behaviors: do not call `File.mkdir_p/1`; do not merge an existing row; do
  not upsert; do not read or write TOML.

The TOML writer should not add a new Hex dependency unless implementation proves
one is required. The current config shape is small and flat enough for a
deterministic internal writer. Its tests must prove the emitted TOML round-trips
through `Babs.Citizens.Citizen.Config.load_file/2`.
The current `:toml` dependency is decode-only for Babs' needs, so Phase 4 starts
from the internal writer path rather than trying to encode through `Toml`.

The TOML writer and duplicate-file checks must use the same `root` and
`config_dir` resolution as `Babs.Citizens.Citizen.Config`, not a hardcoded
`citizens/` path. The default final path remains
`citizens/citizen-<slug>.toml`.

The temp file should live in the same configured directory as the final file,
for example `.citizen-<slug>.<unique>.toml.tmp`, so `File.rename/2` stays on the
same filesystem and concurrent attempts do not share a deterministic temp path.
The writer should emit `cli_args` explicitly even when empty, omit
`description` when nil/blank, omit `role` for Phase 4 UI-created Citizens, and
omit `[env]` when empty. String fields must escape TOML-special characters such
as quotes, backslashes, and control characters.

### 2. Keep TOML and SQLite Consistent

The TOML file remains the operator-editable source. SQLite remains runtime
authority after import.

For a newly-created Citizen:

- TOML stores `cwd = "<slug>"` or the operator-provided relative cwd value.
- SQLite stores the resolved absolute `cwd`.
- `env` is omitted or `{}`.
- The SQLite row is created with intended `running` status immediately before
  lifecycle start; if lifecycle start fails, `Lifecycle.start_config/1` marks
  the row `failed` through its existing failure path before `Spawner` returns to
  the UI.
- `Lifecycle.start_config/1` may mark the row `running` again on success. This
  idempotent double-write is acceptable and should not be worked around in
  Phase 4.

### 3. Validation and Failure Semantics

Validation failures do not write files, rows, or tmux sessions.

Partial side-effect failures should prefer explicit state over silent cleanup:

- TOML write failure: no SQLite row is inserted.
- Workspace mkdir failure after TOML write: return error and leave TOML for
  operator inspection; no SQLite row is inserted and no tmux session is started.
- SQLite insert failure after TOML write: return error and leave TOML for
  operator inspection; the workspace directory may already exist; document this
  in the CHG.
- tmux/lifecycle failure after row insert: mark row `failed` and show the
  redacted failure.

Recovery from TOML-written/SQLite-missing states must be documented in the CHG.
The operator can either fix the underlying issue and let boot/import reconcile
the preserved TOML, or delete the TOML file and optional workspace directory
before retrying the browser create flow for the same slug.

### 4. Browser Flow

Routes:

- `GET /citizens/new` renders the form.
- form submit is handled by LiveView.
- success redirects to `/citizens/<slug>`.

The `/citizens/new` route must be declared before the existing
`/citizens/:slug` route so Phoenix does not match `"new"` as a slug.
Use a standalone Phoenix LiveView route for `NewCitizenLive`; it should not go
through the existing terminal controller because that controller intentionally
requires an already-running pane.

The existing `/citizens/<slug>` terminal page remains the terminal owner. Phase
4 does not add a multi-citizen index; after a failed spawn, the operator stays
on `/citizens/new` with the failed reason.

## Acceptance

Phase 4 is complete when:

- A new non-seed Citizen can be spawned from `/citizens/new` with the `shell`
  preset and reaches an interactive prompt.
- The spawned Citizen has a TOML file at `citizen-<slug>.toml` under the
  configured Citizen config directory.
- The spawned Citizen has a SQLite row with the generated id, slug, display
  name, resolved absolute cwd, CLI fields, and `running` status.
- The spawned Citizen redirects to `/citizens/<slug>` and browser terminal input
  reaches tmux exactly once.
- `transcript.jsonl` starts persisting in the resolved workspace.
- Duplicate slug submission fails before starting another tmux session.
- Invalid slug/display name/CLI preset submissions show errors without writing
  TOML or SQLite rows.
- Missing CLI or failed spawn records a durable `failed` row with redacted
  `last_error`.
- Existing seed Citizens (`sentinel`, `clare`, `dylan`, `elena`) continue to
  boot and connect.

## Test Plan

Unit tests:

- `Spawner` validates params and returns structured errors.
- CLI preset mapping is deterministic.
- TOML writer emits the Phase 1/3 config shape and round-trips through
  `Config.load_file/2`, verifying resolved absolute cwd rather than string-level
  cwd equality.
- Duplicate slug blocks before side effects.
- Reserved slugs such as `new`, `edit`, and `index` are rejected.
- Unknown CLI preset values are rejected before side effects.
- Absolute cwd values submitted through the browser are rejected before side
  effects.
- Concurrent create requests for the same slug serialize; only one can reach
  SQLite insert/lifecycle start.
- Concurrent create requests for different slugs do not block each other.
- TOML write failure does not insert a SQLite row.
- Workspace mkdir failure leaves TOML for inspection and does not insert a
  SQLite row.
- `Catalog.insert_new/1` inserts only and does not merge existing rows or create
  the workspace directory.
- TOML writer escapes quotes, backslashes, and control characters in
  `display_name` and `description`.
- Failed lifecycle start marks an existing row `failed`.
- Secret-like values in failure reasons are redacted.

LiveView/controller tests:

- `GET /citizens/new` renders form fields and CLI presets.
- Router matches `/citizens/new` to `NewCitizenLive` rather than
  `TerminalController.show/2`.
- Invalid submit renders inline errors.
- Successful submit redirects to `/citizens/<slug>`.
- Existing `/citizens/:slug` behavior is unchanged.

Browser-harness BDD:

- Operator opens `/citizens/new`, submits a unique shell Citizen, lands on the
  terminal, sends a marker, and sees it exactly once.
- BDD inspects SQLite and TOML for the spawned Citizen.
- BDD verifies transcript creation under the resolved workspace.
- Duplicate slug attempt is rejected and does not create a second tmux session.
- Existing `/citizens/sentinel` terminal route still connects and accepts input
  after `/citizens/new` is added.

Existing gates:

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`
- `mise exec -- mix test --cover`
- `npm run test:js`
- `npm run test:bdd`
- `npm run test:e2e`
- `mise exec -- mix babs.gate_a`
- `af validate --root <repo>`
- `git diff --check`

## Decisions

- Phase 4 ships without arbitrary browser env editing. Env editing remains
  deferred until a secret-storage/redaction design exists.
- The GitHub Copilot CLI preset label is `copilot-cli`; it writes
  `cli = "gh"` and `cli_args = ["copilot"]` to TOML.
- If TOML write succeeds but SQLite insert fails, Babs leaves the TOML file in
  place for operator inspection instead of deleting it.
- UI creation uses a dedicated insert-only Catalog API, not the TOML import
  reconciliation path.
- Spawner explicitly owns workspace directory creation between TOML write and
  SQLite insert.
- Phase 4 starts with a deterministic internal TOML writer and round-trip tests,
  avoiding a new dependency decision unless implementation proves it necessary.
- `shell` is the only guaranteed credential-free preset; auth-dependent presets
  rely on existing local CLI auth/environment.
- Browser-created cwd values are relative to workspace root in Phase 4; absolute
  cwd remains a manual TOML/admin path.

## Review Plan

- Trinity fast-review R1/R2 found blockers and the PRP was revised.
- Trinity fast-review R3 returned PASS with advisories from GLM and DeepSeek;
  low-cost advisories were folded into this PRP.
- Next: file a Phase 4 CHG for TDD implementation.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-05 | Initial Draft PRP for Phase 4 spawn UI | Codex |
| 2026-05-05 | Resolve operator questions: defer env editing, label GitHub Copilot preset as `copilot-cli`, preserve TOML after SQLite failure, and clarify preset-only/status semantics | Codex |
| 2026-05-05 | Address Trinity R1 blockers: insert-only Catalog API, internal TOML writer, explicit workspace mkdir ownership, route ordering, and expanded failure tests | Codex |
| 2026-05-05 | Address Trinity R2 blockers: reserved slugs, per-slug create serialization, full `Catalog.insert_new/1` contract, configured `config_dir`, and auth preset caveats | Codex |
| 2026-05-05 | Fold in Trinity R3 advisories for cwd dual-tracking, decode-only TOML dependency, writer escaping, relative browser cwd, and partial-failure recovery | Codex |
| 2026-05-05 | Mark PRP reviewed and ready for CHG after Trinity R3 PASS with advisories | Codex |
