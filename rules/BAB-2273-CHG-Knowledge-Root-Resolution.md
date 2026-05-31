# CHG-2273: Knowledge Root Resolution

**Applies to:** BAB project
**Last updated:** 2026-06-01
**Last reviewed:** 2026-06-01
**Status:** Approved
**Date:** 2026-06-01
**Requested by:** @frankyxhl via GitHub issue #84
**Priority:** P2
**Change Type:** Normal

---

## What

Implement `BAB-2271` Phase 2 slice 2.1 / GitHub issue #84 by adding
configured Citizen knowledge-home path resolution.

The slice introduces:

- A `knowledge_root` app/env configuration value, read from
  `BABS_KNOWLEDGE_ROOT` at runtime.
- A reusable `Babs.Citizens.Knowledge.Config` boundary that resolves a
  Citizen's knowledge home.
- Safe `(slug, relative_path, opts)` to resolved absolute paths scoped to that
  Citizen home, rejecting traversal and non-relative child paths.

The default knowledge home is the Citizen workspace directory
`<workspace_root>/<slug>`. If `knowledge_root` is configured, the default home
is `<knowledge_root>/<slug>`.

This module lives under `Babs.Citizens.Knowledge` because it resolves
Citizen-scoped paths. The later top-level `Babs.Knowledge` CRUD context from
slice 2.2 will delegate to this resolver instead of duplicating path policy.

## Why

Phase 2 needs durable, file-backed Citizen standing context (`Readme.md`,
notes, GOAL files) before browser read/edit surfaces can be built. The later
`Babs.Knowledge` CRUD context must have one canonical resolver so all file
operations share the same root semantics and traversal guard.

## Impact Analysis

- **Systems affected:** `config/runtime.exs`, the `:babs_citizens` app env,
  new `Babs.Citizens.Knowledge.Config` module, and tests under
  `apps/babs_citizens/test/`.
- **Runtime behavior:** no files are read or written by this slice. It only
  resolves paths for future Knowledge APIs.
- **Security behavior:** non-relative child paths and `..` traversal return
  `{:error, ...}` instead of paths outside the Citizen home. The resolver uses
  defense in depth: reject invalid inputs first, expand the candidate path under
  the Citizen home, then verify the expanded path is still inside the expanded
  home.
- **Symlink behavior:** this slice does not read or write files and does not
  resolve symlinks with `File.realpath/1`. It provides lexical path containment.
  Slice 2.2 file operations must reject unsafe symlink-following before reading
  or writing through resolved paths.
- **Directory behavior:** this slice only resolves paths. It does not create the
  knowledge root, Citizen home, or child directories.
- **Rollback plan:** remove the runtime `knowledge_root` config assignment,
  delete the Knowledge config module/tests, and remove this CHG/index entry.

## Acceptance Criteria

- [x] Config/env override resolves a knowledge root per Citizen, defaulting
      under the workspace root.
- [x] Relative `knowledge_root` values expand from `BABS_ROOT` /
      `:babs_citizens, :root`.
- [x] `(slug, rel)` path resolution rejects `..` traversal and non-relative
      paths, including absolute paths and `Path.type/1 == :volumetric` inputs.
      Because Unix treats `~` as a normal relative path segment, any child path
      whose first segment starts with `~` is also rejected, such as
      `~/notes.md` or `~other/notes.md`.
- [x] `citizen_home/2` returns an absolute path:
      `<knowledge_root>/<slug>` when configured, otherwise
      `<workspace_root>/<slug>`.
- [x] Slug validation reuses `Babs.Citizens.Citizen.Config.valid_slug?/1`.
- [x] Path resolution is read-only and does not create directories.
- [x] Unit tests cover default resolution, override resolution, and traversal
      rejection.
- [x] Validation passes: focused tests, `mix format --check-formatted`,
      `mix compile --warnings-as-errors`, `mix test`, `npm run test:js`,
      `af validate --root .`, and `git diff --check`.

## Implementation Plan

1. Add `BABS_KNOWLEDGE_ROOT` parsing to `config/runtime.exs`, matching the
   existing workspace/tickets root pattern.
2. Add `Babs.Citizens.Knowledge.Config` with:
   - `root(opts \\ []) :: String.t()`
   - `workspace_root(opts \\ []) :: String.t()`
   - `knowledge_root(opts \\ []) :: String.t()`
   - `citizen_home(slug, opts \\ []) ::
     {:ok, String.t()} | {:error, {:invalid_slug, term()}}`
   - `resolve(slug, relative_path, opts \\ []) ::
     {:ok, String.t()} | {:error, reason}`
3. Define `resolve/3` as this explicit sequence:
   1. Validate slug with `Babs.Citizens.Citizen.Config.valid_slug?/1`; on
      failure return `{:error, {:invalid_slug, slug}}`.
   2. Validate `relative_path` is a binary; otherwise return
      `{:error, {:invalid_relative_path, relative_path}}`.
   3. Reject `relative_path` values containing a null byte with
      `{:error, {:null_byte, relative_path}}`.
   4. Trim for blank detection only; if blank, return
      `{:error, {:empty_relative_path, relative_path}}`.
   5. Reject any child path where `Path.type(relative_path) != :relative`,
      including absolute and `:volumetric` paths; return
      `{:error, {:non_relative_path, relative_path}}`.
   6. Split raw path segments and reject any first segment starting with `~`;
      return
      `{:error, {:non_relative_path, relative_path}}`. This is required on
      Unix/macOS because `Path.type("~/notes.md")` is still `:relative`.
   7. Split raw path segments and reject any segment equal to `..`; return
      `{:error, {:path_traversal, relative_path}}`.
   8. Resolve `citizen_home(slug, opts)`. Match on `{:ok, home}`; if it returns
      `{:error, reason}`, return `{:error, reason}`.
   9. Expand the candidate under that home with `Path.expand(relative_path,
      home)`.
   10. Verify the expanded candidate equals the expanded home or starts with the
      expanded home plus the path separator, equivalent to
      `expanded == home or String.starts_with?(expanded, home <> "/")`;
      otherwise return
      `{:error, {:path_escape, expanded_path}}`.
   11. Return `{:ok, expanded_path}`. Single-dot segments such as
      `./Readme.md` are accepted and normalized by expansion.
4. Define `resolve/3` error reasons as tagged tuples:
   - `{:invalid_slug, slug}` for slugs rejected by
     `Babs.Citizens.Citizen.Config.valid_slug?/1`
   - `{:invalid_relative_path, relative_path}` for non-string child paths
   - `{:null_byte, relative_path}` for child paths containing `<<0>>`
   - `{:empty_relative_path, relative_path}` for blank child paths
   - `{:non_relative_path, relative_path}` for any child path whose
     `Path.type/1` is not `:relative`
   - `{:path_traversal, relative_path}` when any raw input segment is `..`
   - `{:path_escape, expanded_path}` if the expanded candidate is not inside the
     expanded Citizen home
5. Keep defaults aligned with `Babs.Citizens.Citizen.Config`: `workspace_root`
   defaults to `<root>/workspaces`, and Citizen home defaults to
   `<workspace_root>/<slug>`. `citizen_home/2` validates the slug and returns
   `{:ok, Path.expand(Path.join(knowledge_root(opts), slug))}`, so callers
   always receive an absolute path on success.
   `knowledge_root(opts)` returns `workspace_root(opts)` when no configured
   knowledge root is present.
6. Resolve roots from explicit opts first, then `Application` env, then
   defaults. Blank or whitespace-only `knowledge_root` values fall back to
   `workspace_root(opts)`. Non-string root values warn and fall back. Relative
   `knowledge_root` values expand with `Path.expand(value, root(opts))`, not the
   process CWD.
7. Add tests for option override, app-env override, default resolution, relative
   root expansion, non-string fallback, invalid slugs, null bytes, empty
   relative paths, non-relative paths including `~/notes.md`, absolute paths,
   `.` resolution, and traversal attempts.
8. Run validation and update this CHG with actual results.

## References

- `BAB-2271` — Operator Dashboard Panels, Phase 2 Knowledge Home.
- `BAB-1002` — authoritative Citizen/workspace/slug vocabulary.
- `Babs.Citizens.Citizen.Config` — existing workspace-root and slug-validation
  behavior.
- `Babs.Citizens.Tickets.Config` — existing runtime-root configuration pattern.

## Review Plan

- **Plan review:** Trinity with providers `glm,deepseek,minimax` before code.
- **Implementation review:** Trinity with providers `glm,deepseek,minimax`
  before PR.
- **PR review:** GitHub Codex review loop per `COR-1615`.

## Validation Results

- 2026-06-01 initial plan review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2273-CHG-Knowledge-Root-Resolution.md`
  produced a PASS synthesis, but raw provider output identified plan blockers
  around `resolve/3`, slug validation, containment strategy, symlink policy, and
  directory creation. This revision clarifies those points before
  implementation.
- 2026-06-01 second plan review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2273-CHG-Knowledge-Root-Resolution.md`
  produced a PASS synthesis, but raw provider output identified a remaining
  blocker around non-`:relative` paths (`Path.type/1 == :volumetric`) and mixed
  error shapes. This revision standardizes tagged-tuple errors and rejects all
  non-relative child paths.
- 2026-06-01 third plan review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2273-CHG-Knowledge-Root-Resolution.md`
  produced a PASS synthesis, but raw provider output identified remaining plan
  blockers around Unix `~` paths and explicit `citizen_home/2` error/absolute
  path handling. This revision rejects first-segment `~`, propagates
  `citizen_home/2` errors, and states that Citizen homes are absolute.
- 2026-06-01 final plan review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2273-CHG-Knowledge-Root-Resolution.md`
  passed with no blockers in raw provider output; synthesis at
  `.trinity/reviews/20260601-053350-rules-BAB-2273-CHG-Knowledge-Root-Resolution.md/synthesis.md`.
- RED:
  `mise exec -- mix test apps/babs_citizens/test/babs_citizens/knowledge/config_test.exs`
  failed with 8 tests, 8 failures because
  `Babs.Citizens.Knowledge.Config` did not exist.
- GREEN:
  `mise exec -- mix test apps/babs_citizens/test/babs_citizens/knowledge/config_test.exs`
  passed, 8 tests.
- Focused config regression:
  `mise exec -- mix test apps/babs_citizens/test/babs_citizens/knowledge/config_test.exs apps/babs_citizens/test/babs_citizens/citizen/config_test.exs apps/babs_citizens/test/babs_citizens/tickets/config_test.exs`
  passed, 35 tests.
- `mise exec -- mix format --check-formatted`: passed.
- `mise exec -- mix compile --warnings-as-errors`: passed.
- `mise exec -- mix test`: passed, 529 `babs_citizens` tests and 154 `babs`
  tests.
- `npm run test:js`: passed, 19 tests.
- `af validate --root .`: passed, 200 documents checked.
- `git diff --check`: passed.
- 2026-06-01 implementation review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope apps/babs_citizens`
  passed with `LEGACY — 3/3 PASS · 0 FIX · 0 FAIL`; synthesis at
  `.trinity/reviews/20260601-054142-apps-babs_citizens/synthesis.md`.
- 2026-06-01 final rebased diff review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --base origin/main --head HEAD`
  passed with `LEGACY — 3/3 PASS · 0 FIX · 0 FAIL`; synthesis at
  `.trinity/reviews/20260601-055023-./synthesis.md`.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-06-01 | Initial version | — |
