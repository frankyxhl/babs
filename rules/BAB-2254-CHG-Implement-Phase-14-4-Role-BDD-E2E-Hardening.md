# CHG-2254: Implement Phase 14.4 Role BDD/E2E Hardening

**Applies to:** BAB project
**Last updated:** 2026-05-08
**Last reviewed:** 2026-05-08
**Status:** Approved
**Date:** 2026-05-08
**Requested by:** Operator
**Priority:** High
**Change Type:** Test

---

## What

Implement **Phase 14.4: BDD/E2E hardening** from `BAB-2242`.

This is a validation-only slice for the Phase 14 role flow already implemented
in 14.1 through 14.3.

Scope:

- Add browser-harness BDD coverage for creating a multi-role Citizen from the
  browser and using that Citizen through a role-routed Ticket.
- Add browser E2E coverage for setting `assignee_role` from `/tickets/new` and
  routing the Ticket from the Ticket detail UI.
- Reuse the existing deterministic fake direct CLI path where practical so the
  test proves Ticket execution without requiring a real provider.
- Extend the existing BDD form helpers for Citizen `roles` and Ticket
  `assignee_role`.
- Keep runtime behavior unchanged except for testability fixes discovered by
  the new browser tests.
- Update docs with validation results and review outcomes.

Out of scope:

- New runtime role-router behavior.
- Inspector Council behavior. That is Phase 15.
- Mayor proposal behavior. That is Phase 16.
- Mobile/federated control. That is Phase 17.
- Replacing browser-harness or Playwright infrastructure.
- Long-running stability tests.

## Why

Phase 14.1 added canonical role persistence, Phase 14.2 exposed roles in UI,
and Phase 14.3 implemented explicit Ticket role routing. The remaining Phase 14
gap is end-to-end confidence that an operator can perform the role flow in the
browser:

1. create or use a Citizen with multiple roles;
2. create a Ticket with `assignee_role`;
3. route the Ticket by role;
4. observe the existing Ticket execution path and chat/history updates.

## Impact Analysis

- **Systems affected:** browser-harness BDD scripts, Playwright browser tests,
  test helpers, docs.
- **Runtime code:** only if tests expose a small testability or selector gap.
  No new role-routing feature scope is intended.
- **Database:** no schema change.
- **Runtime data:** tests must create only temporary BDD/E2E Citizens and
  Tickets and must clean them safely.
- **Privacy:** docs, PR body, comments, and fixtures must not include private
  IPs, hostnames, local checkout paths, tokens, or runtime Ticket data.
- **Rollback:** revert the test/docs slice. No migration rollback is needed.

## Implementation Plan

1. **Review this CHG before code**
   - Run Trinity `fast-review` against this CHG and fold blockers.

2. **Add RED browser-harness BDD**
   - Add a scenario named around "role routed ticket flow".
   - Create a unique BDD Citizen with roles including `developer` and another
     role.
   - Create a Ticket from `/tickets/new` with `assignee_role=developer`.
   - Route from Ticket detail using the role-route button.
   - Assert the Ticket becomes `in_progress`, the selected Citizen appears as an
     assignee, and Ticket history/chat exposes the role-routed assignment.

3. **Add browser E2E coverage**
   - Add a Playwright test for the same browser flow or a narrower UI-level
     variant if browser-harness owns the full execution path.
   - Prefer deterministic fake direct CLI or shell fixtures over real external
     providers.
   - Verify `assignee_role` select options come from known normalized roles and
     the detail page exposes the route button.

4. **Refactor test helpers only as needed**
   - Extend BDD form helpers to set role fields and Ticket `assignee_role`.
   - Extend E2E helper `writeTicket` or new Ticket form helpers to support
     `assignee_role`.
   - Keep helpers scoped and avoid broad UI refactors.

5. **Validate and review**
   - Run focused BDD/E2E scenarios first with filters.
   - Run relevant JS/browser tests.
   - Run standard local gates.
   - Run Trinity implementation `fast-review`.
   - Open a PR with `gh` as `ryosaeba1985` and follow `COR-1615`/`COR-1612`.

## Acceptance Criteria

- Browser-harness BDD proves a multi-role Citizen can be used by a
  role-routed Ticket from the browser.
- Browser E2E proves `/tickets/new` can set `assignee_role` and Ticket detail
  can trigger the route action.
- At least one role-routed Ticket turn exercises the existing Ticket execution
  path and records visible history/chat feedback.
- The new tests are deterministic when run with isolated browser-harness Chrome
  per `BAB-1503` policy and do not require real Claude/Codex/Copilot
  credentials.
- BDD/E2E-created Citizens and Tickets are cleaned up after each scenario and
  do not leak into persistent state.
- Existing unit/API/LiveView coverage from 14.1-14.3 remains green.
- No runtime feature scope is added beyond small selector/testability fixes.

## Validation Plan

Focused:

```bash
BABS_BDD_SCENARIO="role routed ticket flow" npm run test:bdd
npm run test:e2e -- --grep "role"
```

Standard local gates:

```bash
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
mise exec -- mix test --cover
npm run test:js
npm run test:e2e
npm run test:bdd
af validate --root .
git diff --check
```

If full browser runs are unstable because an external browser authorization
prompt interrupts `browser-harness`, document the blocker and keep the focused
scenario command as the primary local reproduction.

## Review Plan

- Trinity `fast-review` on this CHG before implementation.
- Trinity `fast-review` on the implementation diff before PR.
- Follow the `BAB-1503` / `COR-1616` contract-first delivery workflow.
- GitHub Codex review loop on the PR, capped at five rounds.
- Use `gh` authenticated as `ryosaeba1985` for public GitHub writes.

## Results

- 2026-05-08 CHG review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-125357-rules-BAB-2254-CHG-Implement-Phase-14-4-Role-BDD-E2E-Hardening.md`
  - GLM PASS and DeepSeek PASS.
  - Folded advisories for explicit BDD helper extension, cleanup acceptance,
    `BAB-1503` / `COR-1616` traceability, browser-harness deterministic
    qualifier, and coverage validation.
- 2026-05-08 implementation:
  - Added browser-harness BDD scenario `role routed ticket flow`.
  - Extended BDD helpers for Citizen `roles` and Ticket `assignee_role`.
  - Added Playwright E2E coverage for browser-created role Tickets and role
    route action.
  - Added `BABS_E2E_PORT` / `BABS_E2E_BASE_URL` Playwright config support so
    focused browser tests can run on temporary ports without disturbing a local
    `:4000` service.
- 2026-05-08 local validation:
  - Focused BDD passed:
    `BABS_CITIZENS_DB_PATH=$(mktemp ...) PORT=4025 BABS_BROWSER_BASE_URL=http://127.0.0.1:4025 BABS_BDD_SCENARIO="role routed ticket flow" npm run test:bdd`.
  - Focused E2E passed:
    `BABS_CITIZENS_DB_PATH=$(mktemp ...) BABS_E2E_PORT=4026 npm run test:e2e -- --grep "role routing"`.
  - `npm run test:js` passed: 15 tests.
  - Full E2E passed:
    `BABS_CITIZENS_DB_PATH=$(mktemp ...) BABS_E2E_PORT=4027 npm run test:e2e`
    with 14 tests.
  - Full BDD passed:
    `BABS_CITIZENS_DB_PATH=$(mktemp ...) PORT=4028 BABS_BROWSER_BASE_URL=http://127.0.0.1:4028 npm run test:bdd`.
    The existing workspace-root scenario skipped because `BABS_WORKSPACE_ROOT`
    was not set.
  - `mise exec -- mix format --check-formatted` passed.
  - `mise exec -- mix compile --warnings-as-errors` passed.
  - `mise exec -- mix test` passed: 376 `babs_citizens` tests and 88 `babs`
    tests.
  - `mise exec -- mix test --cover --export-coverage phase14_4 && mise exec -- mix cmd mix test.coverage`
    passed: `:babs_citizens` 84.54%, `:babs` 89.27%.
  - Direct `mise exec -- mix test --cover` ran all tests successfully and
    printed `:babs_citizens` 82.07%, then hit the known OTP `:cover` HTML
    stylesheet generation issue; the stable exported coverage gate above
    passed.
  - `af validate --root .` passed: 163 documents checked.
  - `git diff --check` passed.
  - Added-line privacy scan found no matches.
- 2026-05-08 implementation review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-131109-Phase-14.4-role-BDD-E2E-hardening-implementation-diff`.
  - GLM PASS and DeepSeek PASS.
  - Non-blocking advisories were reviewed: pre-existing prompt capture cleanup,
    intentional split between full BDD execution and narrower E2E UI coverage,
    and happy-path scope matching this validation-only slice.
- 2026-05-08 GitHub Codex review R1:
  - Fixed P2 Playwright config bug: when only `BABS_E2E_BASE_URL` is set, the
    spawned Phoenix port now derives from that URL instead of silently staying
    on the default port.
  - Focused E2E passed with only `BABS_E2E_BASE_URL` set:
    `BABS_CITIZENS_DB_PATH=$(mktemp ...) BABS_E2E_BASE_URL=http://127.0.0.1:4029 npm run test:e2e -- --grep "role routing"`.
- 2026-05-08 GitHub Codex review R2:
  - Fixed P2 Playwright config bug: an explicit non-local `BABS_E2E_BASE_URL`
    now skips local Phoenix `webServer` startup instead of trying to bind a
    local `80` or `443` port while waiting on the external URL.
  - Stabilized the role-routing E2E assertion to wait on durable assignee and
    history UI state rather than short-lived flash text.
  - Verified explicit external base URL config does not define a local
    `webServer`.
  - Focused E2E passed again with only local `BABS_E2E_BASE_URL` set.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial Phase 14.4 BDD/E2E hardening CHG | Codex |
| 2026-05-08 | Trinity fast-review passed GLM and DeepSeek; folded cleanup, helper, workflow, browser-harness, and coverage advisories | Codex |
| 2026-05-08 | Implemented role-flow BDD/E2E hardening with local validation results | Codex |
| 2026-05-08 | Trinity implementation fast-review passed GLM and DeepSeek | Codex |
| 2026-05-08 | Fixed GitHub Codex R1 P2 around `BABS_E2E_BASE_URL` port synchronization | Codex |
| 2026-05-08 | Fixed GitHub Codex R2 P2 around explicit external E2E base URLs | Codex |
