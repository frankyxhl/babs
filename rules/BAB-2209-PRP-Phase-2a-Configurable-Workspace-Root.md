# PRP-2209: Phase 2a Configurable Workspace Root

**Applies to:** BAB project
**Last updated:** 2026-05-05
**Last reviewed:** 2026-05-05
**Status:** Implemented

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

## Implementation Plan

1. **RED config tests**
   - Add `Babs.Citizens.Citizen.Config` tests proving default
     `workspace_root` resolves `cwd = "sentinel"` to
     `<root>/workspaces/sentinel`.
   - Add tests proving explicit `workspace_root` resolves `cwd = "sentinel"` to
     `<workspace-root>/sentinel`.
   - Add tests proving absolute `cwd` values bypass `workspace_root`.
   - Add tests proving `config_dir` lookup remains rooted at `BABS_ROOT` /
     `root`, not `workspace_root`.
2. **GREEN config implementation**
   - Add a `workspace_root` resolver in `Babs.Citizens.Citizen.Config`.
   - Option precedence: explicit `opts[:workspace_root]`, app config
     `:babs_citizens, :workspace_root`, then `<root>/workspaces`.
   - Resolve configured relative workspace roots with
     `Path.expand(workspace_root, root)`, not bare `Path.expand/1`, so behavior
     does not depend on the BEAM launch directory.
   - Resolve relative citizen `cwd` under `workspace_root`; keep absolute `cwd`
     exact.
   - Warn when a relative `cwd` begins with `workspaces/`, because after Phase
     2a it resolves below `workspace_root` and can become
     `<workspace-root>/workspaces/<slug>` for unmigrated non-seed configs.
3. **Runtime config**
   - Add `BABS_WORKSPACE_ROOT` support in `config/runtime.exs`.
   - Only set app config from the environment when a non-empty value is
     present; otherwise rely on `Citizen.Config`'s default.
4. **Seed migration**
   - Change seed configs from `cwd = "workspaces/<slug>"` to `cwd = "<slug>"`.
   - Keep IDs, slugs, display names, CLI commands, roles, and descriptions
     unchanged.
5. **BDD workspace-root coverage**
   - Add a browser-harness `WORKSPACE_ROOT` helper that reads
     `BABS_WORKSPACE_ROOT` when set and otherwise defaults to
     `RUNTIME_ROOT / "workspaces"`.
   - Add a focused BDD scenario that starts Babs with a temporary
     `BABS_WORKSPACE_ROOT`, connects to Sentinel, produces output while the tab
     is closed, and verifies transcript replay from the custom workspace root.
6. **Validation**
   - Run the full Phase 2a validation stack listed above.
   - Record exact test counts and coverage in this PRP after implementation.

## Out Of Scope

- Moving existing workspaces automatically.
- Archiving or migrating old workspace directories.
- SQLite schema changes beyond preserving the resolved `cwd` contract for
  Phase 3.
- UI for editing workspace root; this is config/env first.
- Per-user secrets or credentials storage.

## Validation Results

Phase 2a implementation validation on 2026-05-05:

- `mise exec -- mix format --check-formatted`: passed
- `mise exec -- mix compile --warnings-as-errors`: passed
- `mise exec -- mix test`: passed with `:babs_citizens` 62 tests and `:babs`
  20 tests
- `mise exec -- mix test --cover`: passed with `:babs_citizens` 62 tests and
  81.95% total coverage; `:babs` 20 tests and 78.00% total coverage
- `npm run test:js`: passed with 6 Node tests
- `npm run test:e2e`: passed with 6 Playwright tests
- `npm run test:bdd`: passed with 8 browser-harness BDD scenarios and 1
  expected skip for the custom workspace-root scenario when
  `BABS_WORKSPACE_ROOT` is unset
- `BABS_WORKSPACE_ROOT=<tmp> npm run test:bdd`: passed with all 9
  browser-harness BDD scenarios, including transcript replay from the
  configured workspace root
- `mise exec -- mix babs.gate_a`: passed
- `python3 -m py_compile test/browser/bdd/babs_steps.py test/browser/bdd/run.py`:
  passed
- `git diff --check`: passed
- `af validate --root <repo>`: passed with 102 documents and 0 issues
- Trinity `fast-review` implementation review passed with DeepSeek in
  `.trinity/reviews/20260505-160643-phase-2a-configurable-workspace-root-r2`;
  non-blocking advisories for invalid app config values, leading-dot legacy cwd
  warnings, and BDD helper drift were addressed
- Trinity GLM review was attempted twice, but the provider failed before review
  with `droid` authentication failure; this is a local Trinity provider
  authentication issue, not a Phase 2a code finding

## Resolved Decisions

- Existing `cwd = "workspaces/<slug>"` values remain syntactically valid normal
  relative paths, but seed configs are migrated to `cwd = "<slug>"`. Operators
  who need compatibility with a specific old workspace can use an absolute
  `cwd`. Phase 2a should also emit a warning for unmigrated relative cwd values
  beginning with `workspaces/`.
- `BABS_WORKSPACE_ROOT` is optional for now. The default remains
  `<BABS_ROOT>/workspaces` so dev/test behavior is backward compatible.
- Workspace root is not exposed in the web UI in Phase 2a. Operator-facing UI
  belongs with `/citizens/new` or a future settings page.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-05 | Initial PRP for configurable Citizen workspace root and `BABS_WORKSPACE_ROOT` semantics | Codex |
| 2026-05-05 | Add executable Phase 2a implementation plan and resolve open questions before Trinity plan review | Codex |
| 2026-05-05 | Trinity GLM and DeepSeek fast-review passed; incorporated non-blocking advisories for path expansion, BDD workspace root, and legacy cwd warnings | Codex |
| 2026-05-05 | Implement configurable workspace root with unit, integration, BDD workspace-root, coverage, Gate A, and Alfred validation results | Codex |
| 2026-05-05 | Address DeepSeek R2 implementation-review advisories and record GLM provider authentication blocker | Codex |
