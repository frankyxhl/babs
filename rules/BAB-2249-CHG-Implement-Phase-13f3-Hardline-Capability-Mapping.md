# CHG-2249: Implement Phase 13f.3 Hardline Capability Mapping

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

Implement **Phase 13f.3: Hardline capability mapping** from `BAB-2241`.

This slice exposes Babs-owned Hardline and imported external Hardline
capabilities to the Citizen status snapshot and browser index without changing
tmux lifecycle behavior.

Scope:

- Resolve provider runtime contracts for Citizen records through
  `Babs.Citizens.ProviderRuntime.Inventory.for_config/1`.
- Add public-safe provider runtime capability fields to
  `Babs.Citizens.StatusSnapshot`.
- Expose at least:
  - `provider_runtime` as a small map with `provider`, `backend`, `ownership`,
    and `status`
  - `provider_runtime_capabilities`
  - `interactive_attach?`
  - `kill_authority?`
  - `detach_authority?`
- Keep direct CLI Citizens visible as non-interactive direct-turn providers.
- Keep Babs-owned Hardline Citizens as interactive attachable runtimes with
  kill + detach authority.
- Keep imported external Hardline Citizens as interactive attachable runtimes
  with detach authority but no kill authority.
- Adjust the browser index and TerminalLive lifecycle controls to read
  capability fields for lifecycle labels and affordances while preserving
  existing labels and actions.
- Keep `ownership`, `imported?`, `ownership_badge`, and `lifecycle_reminder` as
  backward-compatible display fields. Capability fields are additive in this
  slice and become the preferred source for lifecycle authority decisions.
- Add unit and LiveView regression tests.

Out of scope:

- Changing lifecycle start/stop/restart semantics.
- Changing tmux attach/import persistence.
- Changing direct CLI execution.
- Changing provider diagnostics/redaction. That remains Phase 13f.4.
- Adding new UI layouts or mobile/federated behavior.

## Why

Phase 13f.1 made provider/backend/ownership contracts available, and Phase
13f.2 normalized direct CLI success results. Hardline behavior is still exposed
mostly through imported metadata and ticket backend labels. Phase 14-17 need
capability-driven routing and UI decisions, especially the distinction between
Babs-owned kill authority and imported external detach-only authority.

This CHG connects the existing Hardline/imported Hardline UI surface to the
provider runtime inventory without changing the lifecycle boundary accepted in
`BAB-1113`.

## Impact Analysis

- **Systems affected:** `:babs_citizens` status snapshot and Babs browser
  Citizen index/terminal display logic.
- **Runtime behavior:** no intended lifecycle behavior change. Start/stop/
  restart/attach actions should continue to call the same lifecycle boundary.
- **Database:** no migrations.
- **Tests:** status snapshot tests and CitizensLive tests expand to assert
  capability-backed fields/labels.
- **Privacy:** capability maps must remain public-safe and must not expose raw
  tmux targets beyond already-visible imported target labels, local paths, env,
  tokens, raw transcript output, or provider output.
- **Rollback:** revert the CHG commit. Since this slice is read-only display
  metadata plus label logic, rollback should not affect existing runtime data or
  tmux sessions.

## Implementation Plan

1. **Review this CHG before code**
   - Run Trinity `fast-review` against this CHG and fold blockers.

2. **Extend status snapshots**
   - Add a helper that calls `ProviderRuntime.Inventory.for_config/1` for each
     Citizen record after mapping the `CitizenRecord` fields into the config
     shape expected by the inventory (`ticket_backend`, `cli`, `cli_args`,
     `metadata`).
   - Add normalized, public-safe capability fields to the returned snapshot.
   - If inventory lookup fails, expose a safe fallback with no kill/detach/
     interactive authority, matching the reserved contract capability shape
     where all runtime authority flags are false.

3. **Preserve action behavior through capabilities**
   - Keep current `actions` output stable for existing hardline/direct/stopped/
     failed rows.
   - Use capability fields to decide whether Open/Full and detach/kill-related
     actions are meaningful where possible.
   - Do not grant kill authority to imported external Hardlines.

4. **Update browser labels**
   - Keep existing text: `Imported · External-owned`, `Detach only · tmux stays
     running`, `Detach`, and `Reattach`.
   - Let labels read snapshot capability fields rather than hardcoded provider
     or CLI name checks.
   - Apply the same label helper behavior in both CitizensLive and
     TerminalLive because both render lifecycle controls from
     `StatusSnapshot`.

5. **Add tests**
   - Status snapshot tests for Babs-owned Hardline, imported external Hardline,
     direct CLI, and lookup-failure fallback.
   - LiveView tests proving imported external controls still show detach-only
     labels and Babs-owned controls still show Stop/Restart.
   - Privacy assertions for capability maps in snapshots.

6. **Validate and review**
   - Run focused tests first.
   - Run the applicable local validation stack.
   - Run Trinity implementation `fast-review`.
   - Open PR with `gh` as `ryosaeba1985` and follow `COR-1615`/`COR-1612`.

## Acceptance Criteria

- Babs-owned Hardline snapshots expose `interactive_attach? == true`,
  `kill_authority? == true`, and `detach_authority? == true`.
- Imported external Hardline snapshots expose `interactive_attach? == true`,
  `kill_authority? == false`, and `detach_authority? == true`.
- Direct CLI snapshots expose direct-turn capability but no interactive attach,
  kill, or detach authority.
- Browser index labels and controls remain behaviorally equivalent to the
  current UI for Babs-owned and imported external Hardlines.
- TerminalLive lifecycle labels and controls remain behaviorally equivalent to
  the current UI for Babs-owned and imported external Hardlines.
- Capability snapshot data is public-safe and does not expose raw env, tokens,
  private host/IP values, raw transcript/provider output, or local checkout
  paths.
- No tmux lifecycle behavior changes.

## Validation Plan

Focused:

```bash
mise exec -- mix test apps/babs_citizens/test/babs_citizens/status_snapshot_test.exs apps/babs/test/babs_web/live/citizens_live_test.exs
```

Standard local gates for this small UI/snapshot slice:

```bash
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
af validate --root .
git diff --check
```

Because this slice changes server-rendered LiveView markup but not browser
JavaScript behavior, `npm run test:js`, `npm run test:e2e`, and `npm run
test:bdd` are not required locally unless implementation expands into browser
assets. The GitHub Actions Test workflow remains the PR gate.

## Review Plan

- Trinity `fast-review` on this CHG before implementation.
- Trinity `fast-review` on the implementation diff before PR.
- GitHub Codex review loop on the PR, capped at five rounds.
- Use `gh` authenticated as `ryosaeba1985` for public GitHub writes.

## Results

- 2026-05-08 CHG review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-095816-Phase-13f.3-Hardline-capability-mapping-CHG`
  - GLM PASS and DeepSeek PASS.
  - Folded advisories for TerminalLive scope, `provider_runtime` field shape,
    backward-compatible ownership fields, CitizenRecord-to-inventory mapping,
    and lookup-failure fallback shape.
- 2026-05-08 implementation:
  - Extended `Babs.Citizens.StatusSnapshot` with provider runtime summary,
    provider runtime capabilities, and boolean authority helpers.
  - Status snapshots now resolve capability data through
    `ProviderRuntime.Inventory.for_config/1` with a no-authority fallback.
  - CitizensLive and TerminalLive label detach-only lifecycle controls from
    capability fields while preserving existing labels and actions.
  - Added snapshot and TerminalLive regression coverage for Babs-owned,
    imported external, direct CLI, and fallback capability behavior.
- 2026-05-08 local validation:
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/status_snapshot_test.exs apps/babs/test/babs_web/live/terminal_live_test.exs`:
    `babs_citizens` 13 tests, 0 failures; `babs` 12 tests, 0 failures.
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/provider_runtime apps/babs_citizens/test/babs_citizens/status_snapshot_test.exs apps/babs/test/babs_web/live/citizens_live_test.exs apps/babs/test/babs_web/live/terminal_live_test.exs`:
    `babs_citizens` 29 tests, 0 failures; `babs` 21 tests, 0 failures.
  - `mise exec -- mix format --check-formatted`: pass.
  - `mise exec -- mix compile --warnings-as-errors`: pass.
  - `mise exec -- mix test`: `babs_citizens` 343 tests, 0 failures; `babs`
    83 tests, 0 failures.
  - `af validate --root .`: 158 documents checked, 0 issues found.
  - `git diff --check`: pass.
  - Targeted privacy scan for private host/IP/path patterns in the Phase 13f.3
    docs/code/tests: pass.
- 2026-05-08 implementation review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-100655-Phase-13f.3-Hardline-capability-mapping-implementation-diff`
  - GLM PASS and DeepSeek PASS with no blocking findings.
  - Remaining notes were non-blocking future cleanup candidates.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial Phase 13f.3 implementation CHG | Codex |
| 2026-05-08 | Trinity fast-review passed GLM and DeepSeek; folded capability-field and TerminalLive scope clarifications | Codex |
| 2026-05-08 | Record Phase 13f.3 implementation and local validation results | Codex |
| 2026-05-08 | Record Trinity implementation review pass | Codex |
