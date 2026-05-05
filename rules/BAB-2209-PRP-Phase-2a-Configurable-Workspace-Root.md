# PRP-2209: Phase 2a Configurable Workspace Root

**Applies to:** BAB project
**Last updated:** 2026-05-05
**Last reviewed:** 2026-05-05
**Status:** Draft

---

## What Is It?

Phase 2a makes the Citizen workspace storage root explicitly configurable.

Today, Phase 1/2 seed citizen TOML files use values like
`cwd = "workspaces/sentinel"`, and `Babs.Citizens.Citizen.Config` resolves
relative `cwd` values against `BABS_ROOT` / the current Babs application root.
That is convenient for tests, but ambiguous for real use because a different
worktree or launch directory can silently move Citizen working files and
transcripts under a different project checkout.

Phase 2a separates:

- **Babs application root**: where repo code and `citizens/citizen-<slug>.toml`
  live
- **Citizen workspace root**: where Citizen working directories,
  `transcript.jsonl`, AI-created files, and other durable working state live

---

## Problem

Citizen workspaces are durable operator state. They should not be implicitly tied
to whichever Babs checkout or temporary phase worktree is running the node.

Current behavior has three concrete problems:

- Running Babs from a branch worktree changes the effective workspace location.
- The default `workspaces/<slug>` convention makes it easy to confuse test,
  phase, and production workspaces.
- Phase 3 will persist `cwd` in SQLite, so the path semantics should be made
  explicit before SQLite becomes the authority.

This PRP deliberately does not record any operator-specific absolute path. Public
docs and PRs should use placeholders such as `<workspace-root>` or environment
variables.

## Proposed Solution

Add a configurable workspace root to `:babs_citizens`.

1. Add runtime config:
   - environment variable: `BABS_WORKSPACE_ROOT`
   - app config: `config :babs_citizens, workspace_root: <path>`
2. Default behavior:
   - if `BABS_WORKSPACE_ROOT` is unset, default to
     `<BABS_ROOT>/workspaces`
   - this preserves the current repo-local developer behavior
3. New relative `cwd` behavior:
   - absolute `cwd` values remain exact per-citizen overrides
   - relative `cwd` values resolve under `workspace_root`, not under
     `BABS_ROOT`
4. Seed TOML migration:
   - change seed configs from `cwd = "workspaces/<slug>"` to
     `cwd = "<slug>"`
   - with the default workspace root this still becomes
     `<BABS_ROOT>/workspaces/<slug>`
   - with `BABS_WORKSPACE_ROOT=/some/dir`, it becomes `/some/dir/<slug>`
5. Keep `config_dir` separate:
   - `citizens/citizen-<slug>.toml` remains under `BABS_ROOT` / `config_dir`
   - only workspace `cwd` resolution changes
6. Keep transcript behavior unchanged after resolution:
   - `Hardline.Pane` still writes `<resolved-cwd>/transcript.jsonl`
   - `PaneChannel` still replays from the live Pane's resolved cwd

## Acceptance

Phase 2a is complete when:

- Without `BABS_WORKSPACE_ROOT`, seed citizen `cwd = "sentinel"` resolves to
  `<BABS_ROOT>/workspaces/sentinel`.
- With `BABS_WORKSPACE_ROOT=<workspace-root>`, seed citizen `cwd = "sentinel"`
  resolves to `<workspace-root>/sentinel`.
- Absolute TOML `cwd` values continue to resolve exactly as provided.
- `citizens/citizen-<slug>.toml` lookup remains controlled by `BABS_ROOT` and
  `config_dir`, not by `workspace_root`.
- `transcript.jsonl` is written and replayed from the resolved workspace path.
- Gate A and browser-harness BDD still pass with default workspace root.
- A focused test proves a custom workspace root works without writing under the
  repo checkout.
- Public docs and PR bodies do not contain real local filesystem paths.

## Tests

Expected test additions:

- `Babs.Citizens.Citizen.Config` unit tests:
  - default `workspace_root` resolves `cwd = "sentinel"` to
    `<root>/workspaces/sentinel`
  - configured `workspace_root` resolves `cwd = "sentinel"` under that root
  - absolute `cwd` remains exact
  - `config_dir` lookup is still rooted at `BABS_ROOT`
- `Babs.Citizens.GateA.Validator` or integration coverage:
  - Gate A still uses the resolved sentinel cwd
- Browser-harness BDD:
  - at least one scenario runs with a temporary `BABS_WORKSPACE_ROOT` and
    verifies terminal connect plus transcript replay
- Validation stack:
  - `mise exec -- mix format --check-formatted`
  - `mise exec -- mix compile --warnings-as-errors`
  - `mise exec -- mix test`
  - `mise exec -- mix test --cover`
  - `npm run test:bdd`
  - `npm run test:e2e`
  - `mise exec -- mix babs.gate_a`
  - `af validate --root <repo>`

## Out Of Scope

- Moving existing workspaces automatically.
- Archiving or migrating old workspace directories.
- SQLite schema changes beyond preserving the resolved `cwd` contract for
  Phase 3.
- UI for editing workspace root; this is config/env first.
- Per-user secrets or credentials storage.

## Open Questions

- Should existing `cwd = "workspaces/<slug>"` values be supported as a legacy
  compatibility path? Proposed answer: not for seed configs; migrate seeds to
  `cwd = "<slug>"`. Absolute `cwd` remains the explicit compatibility escape
  hatch for custom deployments.
- Should `BABS_WORKSPACE_ROOT` be required outside dev/test? Proposed answer:
  not yet. Warn or document clearly first; consider making it required only when
  release/deployment experience proves the default is dangerous.
- Should workspace root be exposed in the web UI? Proposed answer: defer until
  `/citizens/new` or an operator settings page exists.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-05 | Initial PRP for configurable Citizen workspace root and `BABS_WORKSPACE_ROOT` semantics | Codex |
