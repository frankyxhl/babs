# CHG-2266: Implement Phase 17.4 Remote Write Control Gate

**Applies to:** BAB project
**Last updated:** 2026-05-09
**Last reviewed:** 2026-05-09
**Status:** Approved
**Date:** 2026-05-09
**Requested by:** Operator
**Priority:** High
**Related:** `BAB-2245`, `BAB-1109`, `BAB-2263`, `BAB-2264`, `BAB-2265`

---

## Objective

Implement **Phase 17.4: Remote write/control capability gate** from `BAB-2245`.

Phase 17.1 added node identity and read-only APIs. Phase 17.2 added cursored
remote reads and read-only remote UI sections. Phase 17.3 added the mobile/PWA
shell. Phase 17.4 is the first slice that allows a configured Babs peer to ask
another Babs node to mutate local state or control a local Citizen.

This slice must first reconcile `BAB-1109`, because that ADR currently says v0.1
cross-node federation is read-only.

## Non-Goals

- No cross-node Citizen-to-Citizen A2A.
- No distributed Ticket store or shared SQLite database.
- No public-internet exposure or general auth/RBAC system.
- No direct remote file edits. Remote writes must call the receiving node's
  local Babs APIs.
- No full remote operation UI/E2E polish. That remains Phase 17.5.
- No remote stop/kill of external-owned imported tmux sessions. Existing
  imported ownership semantics still apply; a stop-like action detaches only.
- No idempotency or replay-protection layer for mutating federation requests.
  v0.1 assumes a single operator on a trusted network; duplicate-submit
  protection can be added in a later protocol revision.
- Do not rename `BAB-1109`'s file in this slice. The title changes, but the ACID
  and filename remain stable so existing references keep resolving.

## Dependencies

- `BAB-1109` must be amended in this branch before remote write/control code
  lands.
- `BAB-2245` defines the accepted Phase 17 target.
- Existing Ticket APIs remain the only mutation path for Ticket state/history.
- Existing `Lifecycle` and `Hardline.Pane` APIs remain the only mutation path
  for Citizen lifecycle/control behavior.

## ADR Amendment

Update `BAB-1109` from "read-only UI federation only" to:

- v0.1 still forbids cross-node Citizen-to-Citizen A2A and distributed state.
- v0.1 allows a **single operator** to perform explicitly configured remote
  write/control actions between Babs nodes on the operator's trusted Tailscale
  network.
- Remote write/control is an exception to read-only federation, not a general
  multi-user security model.
- The receiving node is authoritative: it checks its local federation config,
  applies per-peer and per-Citizen capabilities, runs local APIs, and writes
  local audit events.
- Public examples continue to use placeholder hostnames only.

## Contract

### Request Identity

All mutating federation API requests require:

- `x-babs-peer-id`: the configured peer id making the request.

For v0.1 this is an audit and allowlist identity inside the trusted Tailscale
boundary. It is not a public-internet authentication scheme. A future phase may
add signed requests or shared secrets if Babs leaves the single-operator
Tailscale assumption.

The receiving node loads its own federation config and finds
`peers.<x-babs-peer-id>`. Unknown peers are denied.

### Capability Model

Use the existing normalized capabilities:

- `read`
- `write` expands to `read + write`
- `control` expands to `read + write + control`

Checks happen on the receiving node:

1. peer default capabilities;
2. per-Citizen override when the action targets a Citizen.

`write` allows:

- add a Ticket comment;
- perform a legal Ticket state transition.

Remote-origin transitions are treated as state/history writes only. If a future
transition path would start, inject into, or otherwise control a Citizen, that
specific remote transition must require `control` or be split into a control
endpoint.

`control` allows:

- assign/unassign a Ticket to/from a Citizen when the action may start,
  inject, or otherwise control that Citizen;
- inject a message into a Citizen hardline;
- start/stop/restart a Babs-owned Citizen;
- detach an external-owned imported Citizen without killing the external tmux
  session.

Read-only peers and read-only Citizen overrides must receive typed forbidden
errors and must not mutate Ticket files, Citizen records, tmux sessions, or
transcripts.

### API Surface

Add mutating endpoints under `/api/v1`:

- `POST /api/v1/tickets/:id/comments`
  - body: `{"body": "message text"}`
  - peer capability: `write`
- `POST /api/v1/tickets/:id/transitions`
  - body: `{"to": "pending_approval"}`
  - event: assigned by the receiving node as `remote_transition`; client-supplied
    event names are ignored or rejected rather than trusted
  - peer capability: `write`
- `POST /api/v1/tickets/:id/assignments`
  - body: `{"slug": "citizen-slug"}`
  - capability target: the assignee Citizen
  - required capability: `control`, because assignment may start or inject into
    that Citizen through existing Ticket delivery behavior
- `DELETE /api/v1/tickets/:id/assignments/:slug`
  - capability target: the assigned Citizen
  - required capability: `control`, because unassignment changes that Citizen's
    active work relationship
- `POST /api/v1/citizens/:slug/injections`
  - body: `{"data": "terminal input"}`
  - encoding: UTF-8 text, passed as-is to the local hardline injection API
  - max size: reuse the existing terminal input byte ceiling; oversized payloads
    return `invalid_params`
  - newline policy: the remote caller must include any desired newline; the
    receiving node does not append one
  - capability target: the Citizen slug in the route
  - required capability: `control`
- `POST /api/v1/citizens/:slug/lifecycle`
  - body: `{"action": "start" | "stop" | "restart"}`
  - capability target: the Citizen slug in the route
  - required capability: `control`

Endpoint handlers must:

- validate peer identity and capability before calling local APIs;
- validate body shape and return typed JSON errors;
- redact internal reasons, local paths, env, raw provider output, and secret-like
  fields;
- return local API results as small JSON summaries rather than raw structs.

### Audit

All successful remote write/control actions must append audit information on the
receiving node.

- Ticket writes reuse existing Ticket history by setting `by` to
  `remote:<peer-id>` and including safe remote metadata where the existing
  history event shape permits it.
- Non-Ticket control actions append an audit JSONL record under the receiving
  node's runtime `var/` area, for example
  `<BABS_ROOT>/var/federation_audit.jsonl`.
- Audit records must include at least timestamp, peer id, action, target type,
  target id/slug, result, and capability used.
- Denied remote write/control requests should append a redacted denied audit
  record with timestamp, peer id when known, endpoint/action, and reason code.
- Audit records must not include local checkout paths, env values, command
  lines, raw terminal data, or secret-like fields.
- Audit rotation/compaction is out of scope for this slice; add a follow-up note
  if the JSONL grows beyond practical single-operator v0.1 use.

## Implementation Plan

1. **Docs/ADR first**
   - Amend `BAB-1109`.
   - Add this CHG to `BAB-0000`.
   - Update `BAB-2300` to mark Phase 17.3 merged and 17.4 proposed.
   - Run Trinity fast-review on the plan and fold blockers.

2. **RED/GREEN: capability guard**
   - Add focused tests for peer lookup, `write`/`control` checks, per-Citizen
     overrides, and redacted forbidden errors.
   - Implement a small guard module so controller code does not duplicate
     capability logic.

3. **RED/GREEN: Ticket write endpoints**
   - Add controller tests for allowed comment/transition.
   - Add denial tests for read-only peer.
   - Verify Ticket history is written with `remote:<peer-id>` actor metadata.

4. **RED/GREEN: Citizen control endpoints**
   - Add controller tests for lifecycle/injection allowed by `control`.
   - Add denial tests for read-only peer and read-only Citizen override.
   - Verify external-owned stop semantics detach rather than kill.

5. **RED/GREEN: audit JSONL**
   - Add tests for successful lifecycle/injection audit records.
   - Add tests that denied requests do not append success audit records.

6. **Client helpers, not full UI**
   - Add `PeerClient` mutating helper functions so Phase 17.5 can wire browser
     UI and BDD flows without duplicating HTTP details.
   - Update the existing `read_only?` snapshot field so peers with configured
     `write` or `control` capabilities are not always presented as read-only.
   - Keep Phase 17.5 responsible for remote operation UI polish and full
     end-to-end browser flows.

## Acceptance Criteria

- `BAB-1109` is reconciled before mutating federation code lands.
- Mutating `/api/v1` federation endpoints exist only behind explicit peer
  identity and capability checks.
- Read-only peers are denied with typed JSON errors.
- Per-Citizen read-only overrides deny Citizen-targeted control actions even
  when the peer default has `control`.
- Allowed remote Ticket comment and transition actions mutate local Ticket
  history through existing Ticket APIs.
- Allowed remote Citizen lifecycle/injection actions call existing local
  lifecycle/hardline APIs.
- Successful remote control actions append redacted audit records on the
  receiving node.
- Denied actions do not mutate Tickets, Citizens, tmux sessions, transcripts, or
  success audit logs.
- Unit/controller tests cover allowed and denied write/control paths.
- No raw secrets, private hostnames, private IPs, local checkout paths, runtime
  Ticket data, generated remote-node data, browser profiles, or cache artifacts
  are published in docs, PR body, comments, commits, tests, or fixtures.

## Validation Commands

```bash
mise exec -- mix test apps/babs_citizens/test/babs_citizens/federation_control_guard_test.exs apps/babs_citizens/test/babs_citizens/federation_audit_test.exs apps/babs/test/babs_web/controllers/api_v1_control_controller_test.exs --seed 1
mise exec -- mix test apps/babs_citizens/test/babs_citizens/federation_config_test.exs apps/babs/test/babs_web/controllers/api_v1_read_controller_test.exs apps/babs/test/babs_web/controllers/api_v1_events_controller_test.exs --seed 1
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
mise exec -- mix test --cover --export-coverage phase17_4
npm run test:js
af validate --root .
git diff --check
git diff -U0 | rg -n '^\+.*(100\.[0-9]{1,3}|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|/Users/[^[:space:]]+|api_token|secret|token)' || true
```

`npm run test:bdd` and mobile remote-operation BDD are Phase 17.5 gates unless
this slice touches browser UI beyond API plumbing.

## Results

- Plan review:
  - Trinity fast-review R1 on 2026-05-09: DeepSeek PASS; GLM conditional PASS
    with one blocker. Folded `BAB-1104` v0.1 banner reconciliation,
    `BAB-1109` use-case/title/review-date cleanup, endpoint body shapes,
    assignment capability target, `PeerClient.read_only?` sequencing, and audit
    rotation scope.
  - Trinity fast-review R2 on 2026-05-09: GLM PASS and DeepSeek PASS. Folded
    final required index title update plus advisories for filename stability,
    transition side-effect boundary, denied-request audit, injection payload
    limits, and deferred idempotency.
  - Trinity fast-review R3 on 2026-05-09: GLM PASS and DeepSeek PASS with no
    blockers. Folded advisories for roadmap anti-goal wording and server-owned
    remote transition event names.
- Implementation:
  - Added a receiving-node capability guard for `write` and `control`
    federation requests, including per-Citizen overrides and typed redacted
    errors.
  - Added redacted JSONL audit records for successful non-Ticket control
    actions and denied remote requests.
  - Added mutating `/api/v1` endpoints for remote Ticket comments,
    transitions, assignments, unassignments, Citizen hardline injection, and
    Citizen lifecycle actions.
  - Added `PeerClient` mutating helpers and corrected remote snapshot
    `read_only?` from configured capabilities.
  - Updated Ticket comment actors to accept `remote:<peer-id>` and Ticket state
    transitions to persist server-owned `remote_transition` history events.
- Validation:
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/federation_control_guard_test.exs apps/babs_citizens/test/babs_citizens/federation_audit_test.exs apps/babs/test/babs_web/controllers/api_v1_control_controller_test.exs apps/babs_citizens/test/babs_citizens/federation/peer_client_test.exs --seed 1` passed.
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/federation_config_test.exs apps/babs/test/babs_web/controllers/api_v1_read_controller_test.exs apps/babs/test/babs_web/controllers/api_v1_events_controller_test.exs --seed 1` passed.
  - `mise exec -- mix format --check-formatted` passed.
  - `mise exec -- mix compile --warnings-as-errors` passed.
  - `mise exec -- mix test` passed.
  - `mise exec -- mix test --cover --export-coverage phase17_4` passed.
  - `npm run test:js` passed.
  - `af validate --root .` passed.
  - `git diff --check` passed.
  - Diff privacy grep passed.
- Implementation review:
  - Trinity fast-review on 2026-05-09:
    `.trinity/reviews/20260509-052757-Phase-17.4-remote-write-control-gate-implementation`.
    GLM PASS and DeepSeek PASS with no blockers.
  - Folded non-blocking advisories for stale `PeerClient` moduledoc,
    unsupported `HttpcClient` method handling, API-boundary missing-peer test,
    assign authorization ordering comment, and denied-audit write observability.
- PR review loop: Pending.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-09 | Initial Phase 17.4 remote write/control gate CHG | Codex |
| 2026-05-09 | Fold Trinity plan review findings for ADR consistency, endpoint body shapes, assignment capability target, PeerClient read-only snapshot, and audit rotation scope | Codex |
| 2026-05-09 | Fold Trinity R3 advisories for roadmap wording and transition event ownership | Codex |
| 2026-05-09 | Implement Phase 17.4 remote write/control gate and record validation results | Codex |
| 2026-05-09 | Fold Trinity implementation review advisories | Codex |
