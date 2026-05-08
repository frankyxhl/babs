# CHG-2258: Implement Phase 15.4 Inspection UI BDD E2E

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

Implement **Phase 15.4: inspection approval-panel UI plus BDD/E2E coverage**
from `BAB-2243`.

This is the fourth and final small PR slice for Phase 15 Inspector Council
auto-approval. Phase 15.1 added inspection policy and event constructors.
Phase 15.2 added inspector selection and redacted prompt assembly. Phase 15.3
added decision capture and `all_pass` quorum. Phase 15.4 makes the feature
visible and testable through the browser.

Scope:

- Add a Ticket inspection panel to `/tickets/<id>` that summarizes:
  - approval mode: Human, Auto single, or Auto council;
  - configured inspector slugs/roles when available;
  - selected inspectors from `inspection_requested`;
  - per-inspector delivery/decision status;
  - verdict badges for `approve`, `reject`, `needs_changes`, unparseable
    decisions, and delivery/parse failures;
  - decision summaries and findings;
  - completion result and quorum.
- Keep existing human Approve/Reject controls visible as override actions for
  `pending_approval` Tickets.
- Add New Ticket UI controls for choosing Human approval or Auto inspection
  from known inspector roles/Citizens, while keeping Human as the default.
- Add LiveView unit tests for the inspection panel, new-ticket inspection
  metadata, and preserved human approval controls.
- Add browser-harness BDD scenarios for:
  - one auto-approved Ticket path;
  - one rejected/needs_changes Ticket path;
  - a two-inspector council status render.
- Keep all introduced buttons icon-bearing and aligned with the existing
  light-theme Babs UI direction.

Out of scope:

- Changing the Phase 15.3 quorum rules.
- Adding new quorum modes such as `majority` or `any_pass`.
- Timeout scheduling or stale-inspection sweeps.
- Inspector quality scoring.
- Mayor proposal behavior from Phase 16.
- Remote/federated inspector behavior from Phase 17.

## Why

Phase 15.3 can automatically parse and reduce inspector decisions, but the
operator still sees the raw event stream unless they inspect history manually.
The Ticket detail view needs a compact approval panel so the operator can see
which Citizens inspected the Ticket, what each decided, why the Ticket closed or
returned to `in_progress`, and when human override is still available.

BDD/E2E coverage is also the Phase 15 acceptance gate: the browser must prove
one auto-approve path, one rejection path, and one council render before moving
to Mayor automation in Phase 16.

## Impact Analysis

- **Systems affected:** `TicketLive`, `TicketPresenter`, `NewTicketLive`,
  Ticket LiveView tests, browser-harness BDD.
- **Runtime behavior:** existing Ticket lifecycle and inspection reduction
  behavior remains unchanged; this slice primarily presents existing metadata
  and history and writes inspection metadata from the New Ticket form.
- **Human override:** Approve/Reject controls remain visible and functional for
  `pending_approval` Tickets.
- **Database:** no schema change.
- **Runtime data:** no migration; new Ticket form may write existing
  inspection metadata under Ticket frontmatter `metadata.inspection`.
- **Privacy:** UI and fixtures must not expose raw provider logs, env maps,
  private hostnames, private IPs, local checkout paths, tokens, or secrets.
- **Rollback:** revert this CHG implementation. Existing Tickets remain valid
  because no history schema changes are introduced.

## Implementation Plan

1. **Review this CHG before code**
   - Run Trinity `fast-review` against this CHG.
   - Fold blockers and update status before implementation.

2. **RED/GREEN: presenter summary**
   - Add a presentation helper that reduces Ticket metadata and history into an
     inspection panel model.
   - Cover human mode, malformed or partial inspection data, auto single, auto
     council, requested inspectors, pending delivery,
     approve/reject/needs_changes decisions, `inspection_failed`, and
     `inspection_completed` results.
   - Unit-test the presenter reduction in isolation; LiveView tests in the next
     step should verify only rendered output and interactions.
   - REFACTOR: keep history parsing presentational only; do not duplicate the
     quorum reducer's state-machine authority.

3. **RED/GREEN: Ticket detail panel**
   - Render the inspection panel in the Ticket detail rail or approval area.
   - Use status dots/badges and icon-bearing controls.
   - Preserve existing Approve/Reject buttons for human override.
   - Render summaries/findings in readable rows, not raw JSON maps.
   - Add LiveView tests for panel states and override controls.
   - REFACTOR: extract small rendering helpers for badges/status text if the
     template starts duplicating logic.

4. **RED/GREEN: New Ticket inspection controls**
   - Extend `/tickets/new` with Human/Auto inspection controls.
   - List known inspector role labels and known inspector Citizens.
   - Default to Human approval.
   - Write existing Phase 15 inspection metadata only when Auto is selected.
   - Add LiveView tests for default Human metadata absence and Auto metadata
     creation.
   - REFACTOR: keep inspection form normalization separate from base title/body
     validation.

5. **BDD/E2E**
   - Add browser-harness scenarios for auto approve, rejection/needs_changes,
     and two-inspector council render.
   - Seed runtime data through browser UI and public Ticket APIs only; use
     `Api.create_ticket/2`, `Api.request_inspection/2`,
     `Api.comment_ticket/3`, and `Api.append_ticket_events/3` from the BDD
     helper process when deterministic history setup is needed.
   - Prefer deterministic fake inspector events over live external AI calls for
     BDD stability.

6. **Validation**
   - Run focused presenter and LiveView tests.
   - Run browser-harness BDD.
   - Run `mix format --check-formatted`.
   - Run `mix compile --warnings-as-errors`.
   - Run `mix test --max-cases 1`.
   - Run full `mix test`.
   - Run exported coverage gate.
   - Run `af validate --root .`.
   - Run `git diff --check`.
   - Run added-line privacy scan.

7. **Review and PR**
   - Run Trinity `fast-review` on the implementation diff.
   - Create the PR with `gh` as `ryosaeba1985`.
   - Follow `COR-1615` / `COR-1612` GitHub Codex loop, max five review rounds.

## Acceptance Criteria

- `/tickets/<id>` shows inspection mode, selected inspectors, inspector
  statuses, decisions, summaries, findings, completion result, and quorum.
- `/tickets/<id>` renders a stable Human approval or "inspection data
  unavailable" fallback for Tickets without inspection metadata or with
  unexpected manual history shapes.
- Human Approve/Reject override controls still render and work for
  `pending_approval` Tickets.
- `/tickets/new` defaults to Human approval and can create an Auto inspection
  Ticket using known inspector roles/Citizens.
- Browser-harness BDD covers one auto-approve path, one rejected/needs-changes
  path, and one two-inspector council render.
- Existing Phase 15.3 decision capture and quorum tests remain green.
- No raw secrets, private hostnames, private IPs, local checkout paths, or
  runtime Ticket data are published in docs, PR body, comments, or fixtures.

## Validation Commands

```bash
mise exec -- mix test apps/babs/test/babs_web/ticket_presenter_test.exs
mise exec -- mix test apps/babs/test/babs_web/live/new_ticket_live_test.exs apps/babs/test/babs_web/live/tickets_live_test.exs apps/babs/test/babs_web/ticket_presenter_test.exs
BABS_BROWSER_BASE_URL=http://127.0.0.1:4100 BABS_HTTP_PORT=4100 BABS_HTTP_IP=127.0.0.1 BABS_BDD_SCENARIO="inspection panel" npm run test:bdd
BABS_CITIZENS_DB_PATH=/tmp/babs-bdd.sqlite3 BABS_BROWSER_BASE_URL=http://127.0.0.1:4100 BABS_HTTP_PORT=4100 BABS_HTTP_IP=127.0.0.1 npm run test:bdd
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test --max-cases 1
mise exec -- mix test
mise exec -- mix test --cover --export-coverage phase15_4 && mise exec -- mix cmd mix test.coverage
af validate --root .
git diff --check
git diff -U0 | rg -n '^\+.*(100\.[0-9]{1,3}|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|/Users/[^[:space:]]+|api_token|secret|token)' || true
```

## Results

- 2026-05-08 Trinity CHG review:
  - Trinity fast-review packet:
    `.trinity/reviews/20260508-171813-rules-BAB-2258-CHG-Implement-Phase-15-4-Inspection-UI-BDD-E2E.md`.
  - GLM PASS at 9.4/10 and DeepSeek PASS at 9.05/10; no blocking findings.
  - Folded advisories for distinct unparseable/failure badges, exact new test
    paths, malformed-data fallback rendering, presenter/LiveView test
    boundary, UI REFACTOR passes, deterministic BDD seed mechanics, and broader
    private-IP scan coverage.
- 2026-05-08 implementation:
  - Added `TicketPresenter.inspection_panel/2` to reduce Ticket metadata and
    history into a presentational inspection summary.
  - Added the Ticket detail inspection panel with human mode, auto mode,
    selected inspectors, decision badges, summaries, findings, failure states,
    and quorum/completion status.
  - Added New Ticket Human/Auto inspection controls that default to Human and
    write Phase 15 inspection metadata only for Auto inspection.
  - Added browser-harness BDD scenarios for auto approval, rejection, and
    two-inspector council status rendering.
- 2026-05-08 validation:
  - `mise exec -- mix test apps/babs/test/babs_web/ticket_presenter_test.exs`
    passed: 5 tests.
  - Focused LiveView/presenter suite passed: 28 tests.
  - Focused browser-harness BDD `inspection panel` scenarios passed: 3
    scenarios.
  - Full browser-harness BDD passed against a temporary local SQLite database;
    one workspace-root scenario remained intentionally skipped.
  - `mise exec -- mix format --check-formatted` passed.
  - `mise exec -- mix compile --warnings-as-errors` passed.
  - `mise exec -- mix test --max-cases 1` passed: `babs_citizens` 435 tests,
    `babs` 97 tests.
  - `mise exec -- mix test` passed: `babs_citizens` 435 tests, `babs` 97 tests.
  - Coverage passed: `babs_citizens` 85.66%, `babs` 88.92%.
  - `af validate --root .` passed: 167 documents checked, 0 issues.
  - `git diff --check` passed.
  - Added-line privacy scan passed for private IPs, local checkout paths,
    tokens, and secrets.
- 2026-05-08 Trinity implementation review:
  - Trinity packet:
    `.trinity/reviews/20260508-180453-Phase-15.4-inspection-UI-implementation-diff`.
  - GLM PASS with no blocking findings.
  - GLM noted three non-blocking advisories: repeated history reversals in the
    presenter, the intentional default `inspector` role for Auto inspection,
    and possible council UX friction when max inspectors defaults to 1.
  - DeepSeek was skipped for this implementation gate after repeated provider
    timeout/service-down behavior; this was treated as reviewer unavailability,
    not as a code finding.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Record implementation results, validation, and DeepSeek reviewer unavailability | Codex |
| 2026-05-08 | Mark Approved after Trinity fast-review PASS/PASS and fold advisories | Codex |
| 2026-05-08 | Initial Phase 15.4 inspection UI, BDD, and E2E CHG | Codex |
