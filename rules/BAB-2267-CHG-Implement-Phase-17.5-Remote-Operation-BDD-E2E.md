# CHG-2267: Implement Phase 17.5 Remote Operation BDD E2E

**Applies to:** BAB project
**Last updated:** 2026-05-09
**Last reviewed:** 2026-05-09
**Status:** Approved
**Date:** 2026-05-09
**Requested by:** Operator
**Priority:** High
**Change Type:** Feature
**Related:** `BAB-2245`, `BAB-2263`, `BAB-2264`, `BAB-2265`, `BAB-2266`, `BAB-1109`

---

## Objective

Implement **Phase 17.5: Remote operation BDD/E2E hardening** from `BAB-2245`.

Phase 17.1 added node identity and read APIs. Phase 17.2 mounted one configured
peer in the local UI. Phase 17.3 made the shell mobile/PWA friendly. Phase 17.4
added receiving-node remote write/control API gates plus `PeerClient` mutating
helpers. Phase 17.5 wires those helpers into the browser surface and proves the
mobile/federated operator flows end-to-end enough to close Phase 17.

## Non-Goals

- No distributed Ticket store, shared SQLite database, or cross-node
  Citizen-to-Citizen A2A.
- No public-internet auth/RBAC, signed request protocol, secrets, or token
  exchange.
- No remote Ticket creation; remote writes target existing Tickets owned by the
  receiving node.
- No full remote Ticket detail page redesign. This slice may add compact remote
  operation controls to the existing remote sections.
- No offline mutation queue, retry queue, push notifications, or background
  sync.
- No publication of private IPs, private hostnames, local checkout paths,
  runtime Ticket data, generated remote-node data, browser profiles, or cache
  artifacts.

## Dependencies

- `BAB-2263` through `BAB-2266` are merged on `main`.
- `BAB-2266` supplies the receiving-node `/api/v1` mutating endpoints,
  `ControlGuard`, audit JSONL, and `PeerClient` mutating helpers.
- `BAB-1109` has already been amended to allow explicitly configured
  single-operator remote write/control inside the trusted network boundary.
- Existing `TicketsLive` and `CitizensLive` remote sections already render one
  configured peer and refresh snapshots through `PeerClient.fetch_first_peer/1`.

## Contract

### UI Capability Semantics

Remote UI controls must be derived from the latest `PeerClient` snapshot:

- `read_only? == true`: render remote data as read-only and do not present
  clickable write/control buttons.
- `write` capability: allow remote Ticket comment and legal remote Ticket state
  transition controls.
- `control` capability: allow remote Citizen lifecycle controls and any
  Citizen-targeted Ticket assignment controls that this slice chooses to expose.
- per-Citizen read-only overrides: control buttons for that Citizen must render
  disabled/read-only and the API denial path must remain tested.

The UI must label remote/local and read-only/writable/control-enabled state
plainly. It must not look like a local mutation when it targets a remote peer.
The existing hardcoded "Read-only" remote badge in Tickets/Citizens must become
capability-derived, for example `Read-only`, `Writable`, or `Control-enabled`.

### Remote Ticket Operations

Add compact remote Ticket operations in the existing Tickets remote section:

- comment on a remote Ticket through `PeerClient.comment_ticket/4`;
- transition a remote Ticket through `PeerClient.transition_ticket/4`;
- show success or typed failure feedback without exposing remote URLs, local
  paths, raw provider output, or secrets.

The transition UI may expose a conservative fixed option such as
`pending_approval` where legal, rather than a full state-machine editor. The UI
must only enable that action for a Ticket state where the current state machine
allows it, or it must surface the typed API error as a normal failure state.

### Remote Citizen Operations

Add compact remote Citizen controls in the existing Citizens remote section:

- restart a remote Citizen through `PeerClient.lifecycle_citizen/4`;
- show disabled state for read-only peers or read-only Citizen overrides;
- show success or typed failure feedback without exposing remote URLs, local
  paths, raw terminal content, or secrets.

Start/stop/injection controls may remain follow-up polish if restart provides
the accepted remote control proof and the underlying API coverage remains in
Phase 17.4 tests.

### Browser BDD/E2E

Add BDD coverage for:

- remote read still renders remote Tickets/Citizens;
- an allowed remote Ticket comment succeeds through the browser;
- an allowed remote Ticket transition succeeds through the browser;
- an allowed remote Citizen lifecycle control succeeds through the browser;
- a read-only peer or read-only Citizen override renders controls disabled and
  the API still denies the corresponding write/control request;
- the same flows fit a phone-sized viewport without horizontal overflow.
- BDD step definitions and scenario names must be added in the browser harness.
  The filtered scenario name must include `remote operation bdd e2e` so the
  focused validation command selects it.

The preferred browser proof is a deterministic isolated local test peer. A
loopback peer is acceptable for this slice when it still exercises the HTTP API
boundary and `PeerClient` request path, because the public repository must not
depend on operator-specific hostnames or Tailscale addresses. If a true
dual-node browser-harness fixture is practical without flakiness, prefer it.
The fixture may also use a same-node loopback peer with explicit `write` or
`control` capabilities when that gives deterministic UI coverage without
publishing host-specific addresses.

## Implementation Plan

1. **Docs/plan first**
   - Add this CHG to `BAB-0000`.
   - Update `BAB-2300` to mark Phase 17.4 merged and Phase 17.5 proposed.
   - Run Trinity fast-review on the plan and fold blockers before code.

2. **RED/GREEN: remote Ticket UI actions**
   - Add LiveView tests proving writable/control remote peers show operation
     controls, dynamic capability badges, and read-only peers hide or disable
     mutation controls.
   - Add LiveView event tests using injected remote action clients so failures
     are deterministic.
   - Implement minimal comment and transition controls in `TicketsLive`.

3. **RED/GREEN: remote Citizen UI actions**
   - Add LiveView tests proving control peers show restart controls and
     read-only peers or Citizen overrides disable them.
   - Add LiveView event tests using injected remote action clients.
   - Implement minimal restart controls in `CitizensLive`.

4. **RED/GREEN: BDD/mobile proof**
   - Add a browser BDD scenario for remote operation flows.
   - Add the necessary BDD step definitions under the existing browser harness.
   - Use placeholder hostnames or a loopback local test peer only.
   - Assert mobile viewport has no horizontal overflow for the new controls.
   - Keep audit JSONL verification covered by Phase 17.4 unit/controller tests;
     add a lightweight BDD-side audit assertion only if it is deterministic.

5. **Validation/review/PR loop**
   - Run focused tests first, then the standard Babs validation stack.
   - Run Trinity fast-review on the implementation diff and fold blockers.
   - Publish with `gh` as `ryosaeba1985`; follow COR-1615/COR-1612 with up to
     six Codex review rounds for this PR unless the operator changes the limit.

## Acceptance Criteria

- Writable remote peer snapshots expose remote Ticket comment and transition
  controls in the browser.
- Control-capable remote peer snapshots expose at least one Citizen lifecycle
  control in the browser.
- Read-only remote peers and read-only Citizen overrides do not present active
  controls, and direct API denial remains covered.
- Remote Ticket comment, remote Ticket transition, and remote Citizen lifecycle
  action succeed through the browser BDD scenario.
- Success and failure feedback is visible, typed, and redacted.
- Phone viewport BDD proves the new remote operation controls do not introduce
  horizontal overflow.
- Existing local Tickets/Citizens workflows continue to pass.
- No private IPs, private hostnames, local checkout paths, tokens, secrets,
  runtime Ticket data, generated remote-node data, browser profiles, or cache
  artifacts are committed or published.

## Validation Commands

```bash
mise exec -- mix test apps/babs/test/babs_web/live/tickets_live_test.exs apps/babs/test/babs_web/live/citizens_live_test.exs --seed 1
BABS_BDD_SCENARIO='remote operation bdd e2e' npm run test:bdd
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
mise exec -- mix test --cover --export-coverage phase17_5
npm run test:js
npm run test:bdd
af validate --root .
git diff --check
git diff -U0 | rg -n '^\+.*(100\.[0-9]{1,3}|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|/Users/[^[:space:]]+|api_token|secret|token)' || true
```

`mix test --cover --export-coverage phase17_5` follows the existing project
convention; Mix writes app-local `.coverdata` export files from that basename.

## Results

- Plan review:
  - Trinity fast-review on 2026-05-09:
    `.trinity/reviews/20260509-054833-rules-BAB-2267-CHG-Implement-Phase-17.5-Remote-Operation-BDD-E2E.md`.
    GLM PASS and DeepSeek PASS with no blockers.
  - Folded advisories for explicit dependencies, dynamic remote capability
    badges, BDD step/scenario naming, transition legality, audit coverage scope,
    test fixture strategy, and coverage-export convention.
- Implementation: Pending.
- Validation: Pending.
- Implementation review: Pending.
- PR review loop: Pending.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-09 | Initial Phase 17.5 remote operation BDD/E2E CHG | Codex |
| 2026-05-09 | Fold Trinity plan review advisories and mark CHG approved | Codex |
