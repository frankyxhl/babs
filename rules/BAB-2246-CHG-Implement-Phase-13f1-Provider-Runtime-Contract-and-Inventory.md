# CHG-2246: Implement Phase 13f.1 Provider Runtime Contract and Inventory

**Applies to:** BAB project
**Last updated:** 2026-05-08
**Last reviewed:** 2026-05-08
**Status:** Approved
**Date:** 2026-05-08
**Requested by:** Operator
**Priority:** High
**Change Type:** Normal

---

## What

Implement **Phase 13f.1: Provider Runtime Contract + inventory** from
`BAB-2241`.

This slice creates a read-only Babs-native contract surface for supported
provider/backend combinations. It does not migrate execution paths yet. The goal
is to make provider capabilities discoverable from one place before Phase 14-17
automation starts depending on provider-specific behavior.

Scope:

- Add `Babs.Citizens.ProviderRuntime` contract modules under
  `apps/babs_citizens/lib/babs_citizens/provider_runtime/`.
- Add a struct/normalizer for provider runtime contracts with fields for
  provider, backend, command shape, cwd/env policy, launch profile behavior,
  input modes, resume support, parser capabilities, output limits, diagnostics,
  interactive attach, ownership, and version/canary metadata.
- Contract rows are keyed by `{provider, backend, ownership}`. Launch profile
  behavior is a field on a row rather than a third key dimension unless a later
  provider needs profile-specific rows.
- Add an inventory module for current provider/backend combinations:
  - Claude direct CLI
  - Codex direct CLI
  - Copilot direct CLI
  - Fake direct CLI
  - Hardline AI CLI Citizens
  - Imported external Hardline Citizens
  - Reserved/deferred `droid` and `pi`
  - Reserved `lazy_tmux`
- Add unit tests for capability maps, inventory lookup, reserved providers,
  ownership semantics, output limits, and public-safe artifact references.
- Add a documentation inventory reference for the current providers.

Out of scope:

- Migrating direct CLI adapters to the normalized result shape. That is 13f.2.
- Replacing Hardline lifecycle labels with capability data. That is 13f.3.
- Standardizing diagnostics/redaction for provider failures. That is 13f.4.
- Changing provider credentials, CLI command execution, tmux lifecycle, Ticket
  Writer behavior, or provider session persistence.
- Live quota-consuming provider canaries.

## Why

Phase 13a introduced direct CLI execution and provider sessions, but provider
knowledge is still spread across direct adapters, runner code, transcript
parsers, ticket backend labels, and imported Hardline metadata. Phase 14-17 will
route, inspect, plan, and remotely control Citizens based on capability. Those
phases need a stable read-only capability source before they can make routing
decisions safely.

13f.1 deliberately avoids behavior changes. It establishes the contract and
inventory first, then later slices can migrate call sites to use it.

## Impact Analysis

- **Systems affected:** `:babs_citizens` provider metadata only.
- **Runtime behavior:** no execution behavior change; no new processes; no
  database migration.
- **Tests:** new unit tests should be deterministic and CPU-light.
- **Privacy:** inventory docs/fixtures must not include raw local paths, private
  hostnames, private IPs, env maps, tokens, or raw provider output.
- **Rollback:** revert the CHG commit. Since this slice is additive and
  read-only, rollback should not affect existing runtime data or tmux sessions.

## Implementation Plan

1. **Review this CHG before code**
   - Run Trinity `fast-review` against this CHG and fold blockers.

2. **Add contract data model**
   - Add `Babs.Citizens.ProviderRuntime.Contract`.
   - Normalize fields with string keys for public/capability maps and atom keys
     for internal struct access.
   - Validate required fields and safe enum values.
   - Add public `to_map/1` for UI/routing consumers.

3. **Add inventory lookup**
   - Add `Babs.Citizens.ProviderRuntime.Inventory`.
   - Provide `all/0`, `get/2`, `for_config/1`, and `capability_map/1` helpers.
     `for_config/1` returns `{:ok, Contract.t()} | {:error, term()}` and
     `capability_map/1` returns the public-safe map for a contract or config.
   - Resolve direct CLI configs using existing direct adapter support rules
     without invoking provider commands. Do not duplicate direct-provider
     detection logic independently of `DirectCli.Adapters`.
   - Resolve Hardline/imported Hardline from `ticket_backend` and imported
     ownership metadata.

4. **Add provider rows**
   - Direct providers: Claude, Codex, Copilot, Fake.
   - Hardline: generic AI CLI Hardline with interactive attach and Babs
     ownership.
   - Imported Hardline: external ownership, attach/detach only, no kill
     authority.
   - Reserved: `droid`, `pi`, and `lazy_tmux` marked as reserved/deferred.
     `droid` and `pi` may exist as UI/config presets, but they are provider
     runtime deferred until direct or Hardline-specific provider behavior is
     implemented and tested.

5. **Add tests**
   - Contract validation and map shape.
   - Inventory contains required provider/backend pairs.
   - `for_config/1` maps Claude/Codex/Copilot/Fake direct CLI configs.
   - Hardline vs imported Hardline ownership/capabilities differ correctly.
   - Reserved rows are discoverable but not executable.
   - Output limits and raw artifact refs are public-safe opaque values, not
     local paths. For 13f.1, direct CLI providers should expose an empty
     artifact-ref list; Hardline providers may expose opaque ref kinds such as
     `transcript_cursor` but not filesystem paths.

6. **Add provider inventory doc**
   - Add a `REF` or appendix section documenting the current inventory.
   - Cross-reference `BAB-2241`, `BAB-2235`, `BAB-1112`, and `BAB-1113`.

7. **Validate and review**
   - Run focused tests first.
   - Run the applicable local validation stack.
   - Run Trinity implementation `fast-review`.
   - Open PR with `gh` as `ryosaeba1985` and follow `COR-1615`/`COR-1612`.

## Acceptance Criteria

- Each supported provider/backend has an explicit contract row:
  Claude/direct CLI, Codex/direct CLI, Copilot/direct CLI, Fake/direct CLI,
  Hardline/Babs-owned, Hardline/imported external-owned, reserved `droid`,
  reserved `pi`, and reserved `lazy_tmux`.
- Capability maps expose at least:
  `provider`, `backend`, `resume`, `input_modes`, `reply_parser`,
  `session_id_parser`, `interactive_attach`, `ownership`, `launch_profiles`,
  `output_limits`, `diagnostics`, `version_fingerprint`, and
  `raw_artifact_refs`.
- `raw_artifact_refs` contains public-safe opaque descriptors only. It must not
  contain absolute paths, private hostnames, raw provider output, or credentials.
- Direct provider capability rows reflect current adapter behavior without
  invoking live provider CLIs.
- Imported Hardline contracts distinguish attach/detach authority from kill
  authority.
- Reserved `droid`, `pi`, and `lazy_tmux` rows are visible but marked
  unsupported/deferred for execution.
- Tests prove inventory lookup for Citizen configs and metadata.
- No raw secrets, private hostnames, private IPs, local checkout paths, or raw
  provider outputs are added to docs, tests, fixtures, PR body, or review
  packets.

## Validation Plan

Focused:

```bash
mise exec -- mix test apps/babs_citizens/test/babs_citizens/provider_runtime
```

Standard local gates for this additive, CPU-light slice:

```bash
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
af validate --root .
git diff --check
```

Because this slice is read-only provider metadata and does not change browser
behavior, `npm run test:js`, `npm run test:e2e`, and `npm run test:bdd` are not
required locally unless implementation touches browser assets or LiveViews. The
GitHub Actions Test workflow remains the PR gate.

## Review Plan

- Trinity `fast-review` on this CHG before implementation.
- Trinity `fast-review` on the implementation diff before PR.
- GitHub Codex review loop on the PR, capped at five rounds.
- Use `gh` authenticated as `ryosaeba1985` for public GitHub writes.

## Results

- 2026-05-08 CHG review:
  - Trinity fast-review passed with GLM and DeepSeek.
  - Review packet:
    `.trinity/reviews/20260508-085040-Phase-13f.1-Provider-Runtime-Contract-CHG-dirty-diff`
  - Folded advisories for 13f.1 naming, contract row keys, public API names,
    DirectCli.Adapter relationship, `droid`/`pi` status, and raw artifact refs.
- 2026-05-08 implementation:
  - Added `Babs.Citizens.ProviderRuntime.Contract`.
  - Added `Babs.Citizens.ProviderRuntime.Inventory`.
  - Added provider runtime unit tests covering contract normalization,
    validation errors, recursive artifact-ref path rejection, inventory rows,
    direct CLI config resolution through existing adapters, Hardline ownership
    capability differences, reserved rows, and public-safe capability maps.
  - Added `BAB-2247` Provider Runtime Inventory reference.
- 2026-05-08 local validation after implementation and review-advisory fold:
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/provider_runtime`:
    12 tests, 0 failures.
  - `mise exec -- mix format --check-formatted`: pass.
  - `mise exec -- mix compile --warnings-as-errors`: pass.
  - `mise exec -- mix test`: `babs_citizens` 336 tests, 0 failures; `babs`
    82 tests, 0 failures.
  - `af validate --root .`: 155 documents checked, 0 issues found.
  - `git diff --check`: pass.
  - Targeted privacy scan for private host/IP/path patterns in the Phase 13f.1
    docs/code/tests: pass.
- 2026-05-08 implementation review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-090214-Phase-13f.1-provider-runtime-implementation-diff`
  - GLM PASS and DeepSeek PASS.
  - Folded low-risk advisories for string-keyed direct CLI config maps,
    recursive artifact-ref path detection, missing error-path tests, and
    portable local-path assertions.
- 2026-05-08 final implementation review after advisory fold:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-090957-Phase-13f.1-provider-runtime-final-diff-after-advisory-fold`
  - GLM PASS and DeepSeek PASS with no blocking findings.
  - Remaining findings were low-risk test/type/memoization advisories deferred
    to later 13f hardening because they do not affect the read-only acceptance
    criteria for this slice.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial Phase 13f.1 implementation CHG | Codex |
| 2026-05-08 | Trinity fast-review passed GLM and DeepSeek; folded advisories for 13f.1 naming, contract row keys, public API names, DirectCli.Adapter relationship, `droid`/`pi` status, and raw artifact refs | Codex |
| 2026-05-08 | Record Phase 13f.1 implementation results, validation, and implementation review advisory fold | Codex |
| 2026-05-08 | Record final Trinity implementation review pass after advisory fold | Codex |
