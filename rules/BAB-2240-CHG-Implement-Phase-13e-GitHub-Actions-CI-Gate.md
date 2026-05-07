# CHG-2240: Implement Phase 13e GitHub Actions CI Gate

**Applies to:** BAB project
**Last updated:** 2026-05-08
**Last reviewed:** 2026-05-08
**Status:** Approved
**Date:** 2026-05-08
**Requested by:** Operator
**Priority:** High
**Change Type:** Normal
**GitHub Issue:** `#32`

---

## What

Implement Phase 13e: GitHub Actions CI Gate.

Add the first public GitHub Actions workflow for Babs so pull requests and
pushes to `main` get an automated build/test signal in addition to local
validation, Trinity review, and GitHub Codex review.

Scope:

- Add `.github/workflows/test.yml`.
- Run on pull requests and pushes to `main`.
- Set up Erlang/OTP and Elixir for the repository's current Mix requirements.
- Cache Mix dependencies and build output.
- Run:
  - `mix deps.get`
  - `mix compile --warnings-as-errors`
  - `mix format --check-formatted`
  - `mix test`

Out of scope:

- Browser-harness BDD in CI.
- Playwright E2E in CI.
- macOS runner matrix.
- Credo, Dialyzer, coverage upload, or release packaging.

## Why

Babs is a public repository, so basic GitHub Actions runner minutes are
available. GitHub Codex can review PR diffs, but it does not replace a
repeatable build/test gate. A minimal CI workflow gives human reviewers,
Trinity reviewers, GitHub Codex, and local watchdogs a concrete pass/fail signal
before merge.

## Impact Analysis

- **Systems affected:** GitHub pull request and push validation.
- **Data affected:** None.
- **Runtime behavior:** None.
- **Risk:** CI may initially fail on missing Linux tooling, version mismatch,
  or assumptions hidden by local development state. That is useful feedback and
  should be resolved before making CI required.
- **Rollback plan:** Revert the workflow file.

## Implementation Plan

1. **Document first**
   - Track GitHub issue `#32` as Phase 13e.

2. **Environment checks**
   - Confirm no PostgreSQL service is needed; Babs currently uses
     `ecto_sqlite3`.
   - Confirm the repo-root `.mise.toml` toolchain and pin matching CI versions.
   - Confirm `mix test` does not require frontend asset deployment or Python.
   - Treat SQLite native/runtime package assumptions as the most likely first
     Linux runner compatibility check.

3. **Implementation**
   - Add `.github/workflows/test.yml`.
   - Use `erlef/setup-beam@v1`.
   - Use `version-file: .mise.toml` with strict version handling so CI consumes
     the same `erlang` and `elixir` pins as local development.
   - Set job-level `MIX_ENV: test`.
   - Use least-privilege workflow permissions: `contents: read`.
   - Add a bounded job timeout and cancel superseded runs for the same branch
     or pull request ref.
   - Cache `deps` and `_build` with a key derived from the runner OS,
     `.mise.toml`, and `mix.lock`.

4. **Validation**
   - Run the local equivalent commands.
   - Open a PR and verify GitHub Actions reports a CI result.

## Acceptance Criteria

- GitHub issue `#32` is traceable to Phase 13e.
- `.github/workflows/test.yml` exists on `main`.
- CI uses the repo `.mise.toml` BEAM line unless a future ADR changes it.
- A fresh PR runs CI automatically.
- CI runs compile, format, and ExUnit tests.
- No browser or secret-dependent tests are added to CI in this first slice.

## Guard Rails

- Do not add secrets, deployment credentials, or write permissions.
- Do not make GitHub Actions required in repository branch protection in this
  slice.
- Do not add browser-harness, Playwright, JS, Dialyzer, Credo, or coverage
  upload jobs in this first workflow.
- Keep CI tied to the repo BEAM toolchain pin rather than a hidden local
  machine version.
- Keep the first CI gate bounded; do not let a hung runner consume unbounded
  minutes.

## Validation Results

- 2026-05-08 environment check:
  - repo-root `.mise.toml` pins Erlang/OTP `28.5`
  - repo-root `.mise.toml` pins Elixir `1.19.5-otp-28`
  - umbrella test config uses `ecto_sqlite3`; no PostgreSQL service required
  - `mix test` is an umbrella ExUnit alias and does not call asset deployment
    or browser-harness Python scripts
- 2026-05-08 Trinity fast-review of this CHG: GLM PASS, DeepSeek PASS.
- Review packet:
  `.trinity/reviews/20260508-041413-rules-BAB-2240-CHG-Implement-Phase-13e-GitHub-Actions-CI-Gate.md`
- Non-blocking advisories folded into this document:
  Guard Rails, deferred gates, explicit `MIX_ENV: test`, least-privilege
  permissions, cache key strategy, `.mise.toml` setup-beam consumption, and
  SQLite runner-risk callout.
- 2026-05-08 local CI-equivalent validation:
  - `mise exec -- mix deps.get`: pass
  - `mise exec -- mix compile --warnings-as-errors`: pass
  - `mise exec -- mix format --check-formatted`: pass
  - `mise exec -- mix test`
    - `babs_citizens`: 324 tests, 0 failures
    - `babs`: 82 tests, 0 failures
  - `af validate --root .`: 148 documents checked, 0 issues found
  - `git diff --check`: pass
- 2026-05-08 Trinity fast-review of implementation diff: GLM PASS, DeepSeek
  PASS.
- Implementation review packet:
  `.trinity/reviews/20260508-041802-Phase-13e-GitHub-Actions-CI-gate-implementation-diff`
- Non-blocking implementation advisories folded in:
  `mix deps.get` command, workflow timeout, and branch/ref concurrency.
- 2026-05-08 post-implementation-advisory validation:
  - `mise exec -- mix deps.get`: pass
  - `mise exec -- mix compile --warnings-as-errors`: pass
  - `mise exec -- mix format --check-formatted`: pass
  - `mise exec -- mix test`
    - `babs_citizens`: 324 tests, 0 failures
    - `babs`: 82 tests, 0 failures
  - `af validate --root .`: 148 documents checked, 0 issues found
  - `git diff --check`: pass

## Deferred Gates

- Browser-harness BDD in CI.
- Playwright E2E in CI.
- JavaScript unit tests in CI.
- Coverage threshold/upload in CI.
- Credo, Dialyzer, macOS matrix, release packaging, and branch-protection
  enforcement.

## References

- GitHub issue `#32`
- `BAB-1503` Phase Delivery Workflow
- `COR-1616` Contract-First Delivery Workflow

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial Phase 13e CI gate CHG | Codex |
| 2026-05-08 | Mark approved after Trinity review and fold in CI guard rails | Codex |
| 2026-05-08 | Add local CI-equivalent validation results | Codex |
| 2026-05-08 | Fold implementation review advisories into workflow timeout, concurrency, and deps command | Codex |
| 2026-05-08 | Record implementation review and post-advisory validation | Codex |
