# CHG-2253: Implement Phase 14.3 Ticket Role Router

**Applies to:** BAB project
**Last updated:** 2026-05-08
**Last reviewed:** 2026-05-08
**Status:** Approved
**Date:** 2026-05-08
**Requested by:** Operator
**Priority:** High
**Change Type:** Feature

---

## What

Implement **Phase 14.3: Ticket role router** from `BAB-2242`.

This slice uses canonical Citizen `roles` to route a Ticket with
`assignee_role` to an eligible Citizen without the operator choosing a specific
slug.

Scope:

- Add a role routing boundary that resolves a Ticket `assignee_role` to one
  eligible Citizen.
- Keep explicit named assignment behavior unchanged.
- Add a Ticket API entry point for role-routed assignment.
- Add Ticket detail UI action for open, unassigned Tickets with
  `assignee_role`.
- Add `/tickets/new` controls to set `assignee_role` from known role labels.
- Persist role-routed assignment events clearly in Ticket history.
- Add focused unit/API/LiveView tests for matching, stale exclusion,
  deterministic tie-breaking, UI role selection, and assignment delivery.

Out of scope:

- Background daemon routing on page load or file watcher events. Role routing is
  explicit through an API/UI action in this slice.
- Multi-required-role Tickets.
- Inspector quorum/council behavior. That is Phase 15.
- Mayor rule proposal behavior. That is Phase 16.
- Arbitrary role permissions or security scopes.
- Browser-harness BDD/E2E hardening. That is Phase 14.4.
- Changing existing named assignee assignment semantics.

## Why

Phase 14.1 added canonical multi-role persistence and Phase 14.2 made roles
visible/editable in Citizen UI. Tickets already have an `assignee_role`
frontmatter field, but Babs cannot yet use it to select a Citizen.

This slice closes that routing gap while keeping the operator in control:
Tickets can declare a desired role, the UI can route by that role, and the
history records which Citizen was selected and why.

## Impact Analysis

- **Systems affected:** Ticket API, Ticket writer, role routing helper, Ticket
  detail LiveView, new Ticket LiveView, Ticket history rendering, focused Ticket
  tests, and docs.
- **Database:** no schema change.
- **Runtime data:** Ticket markdown/history JSONL files may include
  `assignee_role` and role-routed assignment events with a `via_role` field and
  compact body text.
- **Routing behavior:** explicit named assignment still wins. A Ticket that is
  already assigned is not role-routed.
- **Eligibility:** normal role routing considers only configured or imported
  Citizens visible to Babs, excludes stale SQLite-only rows, excludes failed
  Citizens, requires a normalized role match, and avoids Citizens with an active
  execution lock.
- **Tie-breaking:** choose the candidate with the least recent role-routed
  assignment for that role based on existing Ticket history, with slug order as
  the final deterministic fallback. Do not add a durable round-robin cursor.
  The history scan is O(ticket history events) and acceptable at Phase 14
  scale; keep it as a single-pass scan and revisit only if ticket volume makes
  this measurable.
- **Delivery:** once a slug is selected, existing assignment delivery behavior
  is reused. Phase 14.3 chooses the Citizen; it does not add a second startup or
  injection policy.
- **Privacy:** docs, tests, PR body, and comments must not include private IPs,
  hostnames, local checkout paths, tokens, or runtime Ticket data.
- **Rollback:** revert this slice. No migration rollback is needed.

## Implementation Plan

1. **Review this CHG before code**
   - Run Trinity `fast-review` against this CHG and fold blockers.

2. **Add RED tests**
   - Add `RoleRouter` unit tests for:
     - matching a Citizen when the role is not the first role;
     - excluding stale SQLite-only Citizens by using the configured/imported
       Catalog source;
     - excluding failed Citizens;
     - avoiding execution-busy Citizens;
     - deterministic least-recent tie-breaking using existing history events;
     - returning a clear error when no eligible Citizen exists.
- Add Ticket API/writer tests proving role-routed assignment selects a slug,
     writes `assignees`, transitions to `in_progress`, appends `via_role`
     history, and reuses the existing injection/direct delivery path.
   - Add API tests for blank/missing `assignee_role` and already-assigned
     Tickets so named assignment precedence is explicit.
   - Add LiveView tests for:
     - `/tickets/new` role dropdown from known roles;
     - `/tickets/new` passing string-keyed `assignee_role` form params through
       to Ticket creation;
     - creating a Ticket with `assignee_role`;
     - Ticket detail role-route action and clear success/error feedback;
     - role-route inflight/disabled behavior using the existing
       `start_ticket_action/3` pattern;
     - stale Citizens not appearing as role candidates.

3. **Add routing boundary**
   - Add a small `Babs.Citizens.Tickets.RoleRouter` module.
   - Normalize the incoming `assignee_role` with `Babs.Citizens.Roles`.
   - Compare the Ticket's normalized `assignee_role` name against each
     Citizen's canonical role names, not against full role maps.
   - Read candidates from `Catalog.list_configured_or_imported_citizens/1` by
     default.
   - Read canonical roles through `Catalog.to_config/1`, not by inspecting
     `record.role` directly.
   - Exclude failed Citizens and Citizens whose slug is currently in
     `Babs.Citizens.ExecutionLockRegistry`.
   - Use Ticket history under `tickets_root` to find the latest previous
     role-routed assignment per candidate for the same role.
   - Sort by `{has_previous_assignment?, latest_assignment_ts, slug}` where
     candidates with no previous assignment come first.

4. **Expose role-routed assignment API**
   - Add `Api.assign_ticket_by_role/2`.
   - Add `Writer.assign_by_role/3`.
   - Return `{:error, {:missing_assignee_role, ticket_id}}` when a Ticket has no
     usable `assignee_role`.
   - Return `{:error, {:role_route_already_assigned, ticket_id}}` when a Ticket
     already has named assignees.
   - Writer reads the current Ticket, rejects already-assigned Tickets, resolves
     the role through `RoleRouter`, then calls the same assignment persistence
     and delivery path used by named assignment.
   - Pass the selected `via_role` into assignment history events.

5. **Update Ticket history events**
   - Add `"via_role" => role` to the `assigned` event for role-routed
     assignments.
   - Add a compact `"body"` such as `"assigned to clare via role developer"` so
     existing history rendering makes the route visible without a new timeline
     component.
   - Keep non-role named assignment history unchanged.

6. **Update Ticket UI**
   - `/tickets/new` gathers known role labels from normalized roles across
     `Catalog.list_configured_or_imported_citizens/1` and exposes a blankable
     `assignee_role` select.
   - Ticket detail shows a role-route button for open, unassigned Tickets with a
     nonblank `assignee_role`.
   - The role-route button uses a route icon, follows existing action/button
     patterns, and calls `Api.assign_ticket_by_role/2`.
   - Existing per-Citizen assignment buttons remain available and unchanged.

7. **Validate and review**
   - Run focused tests first.
   - Run the local validation stack.
   - Run Trinity implementation `fast-review`.
   - Open a PR with `gh` as `ryosaeba1985` and follow `COR-1615`/`COR-1612`.

## Acceptance Criteria

- A Ticket with `assignee_role: developer` can be routed to an eligible Citizen
  whose normalized roles include `developer`, even when `developer` is not the
  first role.
- A Ticket with blank or missing `assignee_role` returns a clear error from the
  role-route API.
- Named assignment behavior remains unchanged and is never overridden by role
  routing.
- Stale SQLite-only Citizens are not selected.
- Failed Citizens and execution-busy Citizens are not selected.
- Tie-breaking is deterministic and uses existing role-routed Ticket history
  before falling back to slug order.
- `/tickets/new` can persist an `assignee_role` chosen from known roles.
- Ticket detail can route an open, unassigned role Ticket through the browser.
- Role-routed assignment writes clear history with the selected Citizen and
  role.
- Existing assignment delivery and state transition behavior remains covered.
- No Browser E2E requirement is introduced in this slice; Phase 14.4 owns BDD
  and browser-harness hardening.

## Validation Plan

Focused:

```bash
mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/role_router_test.exs apps/babs_citizens/test/babs_citizens/tickets/api_writer_store_test.exs apps/babs/test/babs_web/live/tickets_live_test.exs
```

Standard local gates:

```bash
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
af validate --root .
git diff --check
```

Because this slice is expected to use LiveView-rendered HTML and no new
JavaScript, `npm run test:js`, `npm run test:bdd`, and `npm run test:e2e` are
not required locally unless implementation scope expands into browser assets.
Phase 14.4 remains the browser-harness BDD/E2E hardening slice for role flows.

## Review Plan

- Trinity `fast-review` on this CHG before implementation.
- Trinity `fast-review` on the implementation diff before PR.
- GitHub Codex review loop on the PR, capped at five rounds.
- Use `gh` authenticated as `ryosaeba1985` for public GitHub writes.

## Results

- 2026-05-08 CHG review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-120007-rules-BAB-2253-CHG-Implement-Phase-14-3-Ticket-Role-Router.md`
  - GLM PASS and DeepSeek PASS.
  - Folded advisories for normalized role-name matching, history scan cost,
    shared Catalog pool for UI/router candidates, string-keyed Phoenix form
    params, role-route inflight behavior, blank `assignee_role` errors,
    already-assigned Ticket errors, and explicit API signatures.
- 2026-05-08 implementation:
  - Added `Babs.Citizens.Tickets.RoleRouter`, `Api.assign_ticket_by_role/2`,
    Writer role-routed assignment, role assignment history metadata, and
    Ticket LiveView role-route controls.
  - Added focused RoleRouter unit tests, Ticket API/writer tests, and Ticket
    LiveView tests for role dropdown creation and browser-triggered routing.
- 2026-05-08 local validation:
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/tickets/role_router_test.exs apps/babs_citizens/test/babs_citizens/tickets/api_writer_store_test.exs apps/babs/test/babs_web/live/tickets_live_test.exs`
    passed: 42 `babs_citizens` tests and 19 `babs` tests.
  - `mise exec -- mix format --check-formatted` passed.
  - `mise exec -- mix compile --warnings-as-errors` passed.
  - `mise exec -- mix test` passed: 375 `babs_citizens` tests and 88 `babs`
    tests.
  - `af validate --root .` passed: 162 documents checked.
  - `git diff --check` passed.
  - Added-line privacy scan only matched test fixture `socket_token` strings.
- 2026-05-08 implementation review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-121905-Phase-14.3-ticket-role-router-implementation-diff`
  - GLM PASS and DeepSeek PASS.
  - Non-blocking advisories recorded for future helper extraction, test helper
    cleanup, and history scan scalability.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial Phase 14.3 implementation CHG | Codex |
| 2026-05-08 | Trinity fast-review passed GLM and DeepSeek; folded role matching, history scan, UI candidate, form-param, and error-semantics advisories | Codex |
| 2026-05-08 | Implemented role router and local/Trinity validation results | Codex |
