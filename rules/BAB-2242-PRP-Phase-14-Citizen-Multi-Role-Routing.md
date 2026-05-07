# PRP-2242: Phase 14 Citizen Multi-Role Routing

**Applies to:** BAB project
**Last updated:** 2026-05-07
**Last reviewed:** 2026-05-07
**Status:** Approved
**Date:** 2026-05-07
**Requested by:** Operator
**Priority:** High

---

## What Is It?

Add Phase 14: Citizen Multi-Role Routing.

Phase 14 turns the reserved Citizen role metadata into an operator-visible,
runtime-used routing surface. The important operator decision is that one
Citizen may have multiple roles. A Citizen such as Clare or Dylan might be both
`developer` and `inspector`; Elena might be both `copilot-cli` and `developer`.

This phase must therefore avoid the earlier single-role design. The canonical
model becomes `roles`: a normalized ordered list of role entries. The existing
single `role` field remains as a backwards-compatible seed/import field and
database compatibility surface until later cleanup.

## Problem

Babs already has several pieces that point toward role automation:

- `citizens.role` exists in SQLite as a reserved flexible JSON/text field.
- `citizens/citizen-<slug>.toml` accepts either `role = "..."` or a `[role]`
  table with `name` and optional `skills`.
- Ticket frontmatter already has `assignee_role`.
- Phase 15 and Phase 16 depend on role-based routing for inspectors and Mayor
  proposals.

The current roadmap still describes Phase 14 as a single `citizens.role` field
becoming user-settable. That is no longer correct. Single-role Citizens would
force duplicate Citizen identities or awkward manual reassignment once a
Citizen can serve multiple purposes.

Concrete gaps:

- There is no canonical normalized representation for multiple roles.
- Existing code can read `role` directly and miss future `roles`.
- The UI cannot show or edit multiple role badges.
- Ticket assignment by `assignee_role` cannot select a Citizen whose matching
  role is not the single legacy `role`.
- Phase 15 inspector automation would become unnecessarily coupled to a single
  role per Citizen.

## Proposed Solution

### 1. Add Canonical `roles`

Introduce a canonical multi-role model:

```elixir
[
  %{"name" => "developer", "skills" => ["elixir", "phoenix"]},
  %{"name" => "inspector", "skills" => []}
]
```

Rules:

- Role names are normalized lowercase labels using the existing Citizen-slug
  style where practical: letters, digits, and hyphens.
- Duplicate names collapse to one entry; skills merge by normalized set union.
- Ordering is stable and operator-controlled; the first role may be used as a
  compact display/default but must not be the only routing source.
- `skills` are optional and must be a list of strings.
- A simple string role such as `"developer"` normalizes to
  `%{"name" => "developer", "skills" => []}`.
- The normalizer should accept both string-keyed and atom-keyed maps at module
  boundaries, but the persisted/public canonical shape uses string keys.

The implementation should add a small role-normalization boundary, for example
`Babs.Citizens.Roles`, so routing and UI code do not parse role shapes directly.
Extend `%CitizenConfig{}` with a `roles` field mirroring the normalized list, and
update `Catalog.to_config/1` to populate it.

### 2. TOML Compatibility

Preferred multi-role TOML:

```toml
[[roles]]
name = "developer"
skills = ["elixir", "phoenix"]

[[roles]]
name = "inspector"
```

Convenience TOML may also accept a list of labels:

```toml
roles = ["developer", "inspector"]
```

Legacy TOML remains valid:

```toml
role = "developer"
```

and:

```toml
[role]
name = "developer"
skills = ["elixir"]
```

Compatibility rules:

- If `roles` is present, it is canonical.
- If `roles` is absent and `role` is present, import `role` as a one-entry
  `roles` list.
- For one migration window, continue writing the legacy `role` field as the
  first normalized role so old code remains safe during the Phase 14 slice.
- Do not remove legacy `role` in Phase 14.

### 3. SQLite Migration

Add a `roles` JSON/text column to `citizens`, defaulting to `[]`.

Migration behavior:

- Backfill existing rows by normalizing `citizens.role` into `citizens.roles`.
- Preserve existing `role` values.
- New/updated records validate both the new canonical `roles` and the legacy
  `role` field.
- `Catalog.to_config/1` and TOML writer paths should emit canonical `roles`
  when multiple roles exist; they may keep legacy `role` for single-role
  compatibility during Phase 14.

Routing and new UI code must read roles through the normalization boundary, not
by directly pattern matching on `record.role`.

### 4. Ticket Role Routing

Keep the existing Ticket `assignee_role` field for Phase 14.

Phase 14 does not need to introduce multi-required-role Tickets. Instead:

- A Ticket with `assignee_role: developer` matches any Citizen whose normalized
  `roles` list includes `developer`.
- A Citizen with `roles: []` is not eligible for role-based routing and can only
  receive Tickets by named assignment.
- A named assignee still wins over role routing.
- Role routing only applies to unassigned Tickets.
- The router must ignore stale SQLite-only Citizens hidden by Phase 13d unless
  explicitly requested by a repair/debug path.
- The router should prefer Citizens that are eligible for Ticket execution:
  known to Babs, not failed, not externally owned in a way that prevents
  injection, and not already executing another Ticket under the current serial
  Citizen model.
- Startup/direct-run behavior remains delegated to the existing assignment
  executor. Phase 14 chooses the Citizen; it does not create a second startup
  policy.

Tie-breaking should be deterministic and simple in the first implementation.
Prefer least-recent role-routed Ticket assignment using existing Ticket history
or provider-session metadata, with slug order as the final deterministic
fallback. Do not add a separate durable round-robin cursor unless the
implementation CHG proves it is simpler than reusing existing assignment data.

### 5. UI

Expose roles as first-class operator controls:

- Citizen index shows role badges/chips instead of a single role string.
- Citizen detail shows the normalized role list and skills where present.
- New/edit Citizen UI supports multiple role entries.
- Ticket creation/editing can set `assignee_role` from known role labels. The
  known-label list comes from normalized roles across non-stale Citizens, plus
  the Ticket's current `assignee_role` if that role no longer has a matching
  Citizen so existing data remains editable without loss.
- Role-routed assignment events should render clearly in the Ticket chat/history
  surface, for example "assigned to Clare via role developer".

The UI must follow the existing Babs light-theme direction and icon-button
rules. Buttons introduced for role editing or routing should include relevant
icons, matching the current design-system pattern.

### 6. Relationship to Phase 15 and Phase 16

Phase 14 provides the substrate only.

Phase 15 may then use role labels such as `inspector`, `reviewer`, or
operator-defined review roles to select one or more Citizen inspectors.

Phase 16 may use Mayor proposal rules to create Tickets with `assignee_role`
instead of named assignees. Mayor remains out of scope for Phase 14.

## Out of Scope

- Inspector auto-approval decisions.
- Multiple inspector quorum/council review.
- Mayor ticket decomposition or Alfred rule interpretation.
- Multi-required-role Tickets such as "must have both developer and reviewer".
- Removing or renaming the existing legacy `role` column.
- Arbitrary role permissions, security scopes, or remote-node control.
- Cross-machine remote Citizen routing from Phase 17.

## Implementation Slices

Phase 14 should be delivered in small reviewed PRs:

1. **14.1 Role model and persistence**
   - Add `Babs.Citizens.Roles` normalization/validation tests.
   - Add SQLite `roles` column and migration backfill.
   - Extend `CitizenRecord`, `Catalog`, TOML loader, and TOML writer.
   - Extend `%CitizenConfig{}` with canonical `roles`.
   - Preserve legacy `role` compatibility.
   - Include test coverage for legacy `[role]` TOML table form with `name` and
     `skills`, because current seed files do not exercise that path.

2. **14.2 Citizen role UI**
   - Show role badges on `/citizens`.
   - Add multi-role controls to new/edit Citizen flows.
   - Add LiveView/unit tests for role rendering and form validation.

3. **14.3 Ticket role router**
   - Implement role-based Citizen selection for `assignee_role`.
   - Keep named-assignee behavior unchanged.
   - Add routing tests for multi-role matches, stale-Citizen exclusion, and
     deterministic tie-breaking.

4. **14.4 BDD/E2E hardening**
   - Add BDD coverage for creating/using a multi-role Citizen.
   - Add browser-harness E2E for setting a role route from the Ticket UI.
   - Verify at least one role-routed Ticket turn still works through the
     existing Ticket execution path.
   - This slice is a validation-hardening slice only; it should not introduce
     new runtime feature scope beyond closing test gaps from 14.1-14.3.

## Acceptance Criteria

- A Citizen can have multiple normalized roles.
- Legacy single `role` TOML and SQLite data continue to work.
- Existing Citizens are backfilled to canonical `roles` without data loss.
- `/citizens` and Citizen detail views show multi-role badges.
- Ticket UI can set `assignee_role` from known roles.
- A Ticket with `assignee_role: developer` can auto-select an eligible Citizen
  whose roles include `developer`, even if `developer` is not the first role.
- Named assignee routing still takes precedence over role routing.
- Stale SQLite-only Citizens are not selected by the normal role router.
- Tests cover normalization, migration, TOML import/write, UI rendering,
  routing, and regression cases for existing single-role data.
- BDD/E2E coverage proves one role-routed Ticket flow in the browser.
- No raw secrets, private hostnames, private IPs, local checkout paths, or
  runtime Ticket data are published in docs, PR body, comments, or fixtures.

## Validation Plan

Each implementation CHG under Phase 14 should include focused tests first, then
the standard Babs validation stack where practical:

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

For docs-only PRP work, `af validate --root .` and `git diff --check` are
sufficient locally; the GitHub Actions Test workflow provides the broader CI
gate after PR creation.

## Review Plan

- Review this PRP with Trinity `fast-review` and fold blockers before
  implementation CHGs.
- Implementation CHGs should update `BAB-1002` vocabulary where singular
  `role: inspector` wording becomes misleading after `roles` ships.
- Each implementation CHG must follow `BAB-1503` / `COR-1616`.
- GitHub PRs must use the correct project GitHub identity and follow
  `COR-1612` + `COR-1615` review loops.
- Maximum five GitHub Codex review rounds per PR unless the operator explicitly
  extends the loop.

## Open Questions

None for the PRP. Implementation CHGs may still choose the exact UI control
shape and deterministic tie-breaker after reading the current LiveView code.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-07 | Initial Phase 14 PRP for multi-role Citizen routing | Codex |
| 2026-05-07 | Trinity R1 fast-review passed GLM and DeepSeek; folded advisories for duplicate-role skill merging, empty-role routing semantics, CitizenConfig propagation, legacy role-table tests, UI role-label inventory, validation-only hardening scope, and vocabulary follow-up | Codex |
