# PRP-2245: Phase 17 Mobile and Federated Control

**Applies to:** BAB project
**Last updated:** 2026-05-09
**Last reviewed:** 2026-05-09
**Status:** Implemented
**Date:** 2026-05-07
**Requested by:** Operator
**Priority:** High

---

## What Is It?

Add Phase 17: Mobile and Federated Control.

The original Phase 17 was "PWA + mobile + read-only federation." The operator
has refined the target:

- mobile should have the same operator permissions when used inside the
  Tailscale network;
- Babs should allow remote control of Citizens on other configured machines;
- each node, and even each Citizen, can be configured as read-only, writable, or
  controllable;
- node names are configurable;
- the first practical remote behavior should be real-time remote reads.

Phase 17 therefore becomes the mobile and federation product layer: a
Tailscale-scoped multi-node Babs UI that starts with real-time remote reads and
then adds explicit, audited remote write/control actions where configuration
allows them.

## Problem

By Phase 16, Babs has a strong single-node flywheel:

- Tickets and Citizens are durable.
- Work can be routed by role.
- Inspector Councils can approve/reject.
- Mayor can propose child Tickets.

The operator still has to be on the machine running the relevant Babs node, or
open that node directly in a desktop browser. The desired operating model is a
small Tailscale-connected fleet:

- phone or tablet can inspect and operate the same Babs node;
- one Babs UI can show Citizens and Tickets from another Babs node;
- some remote Citizens are read-only, while others can be controlled;
- remote data is live enough to feel like one operations surface.

The previous read-only-only ADR (`BAB-1109`) deliberately avoided cross-node
writes for v0.1. The operator has now accepted remote control as a Phase 17
goal, but only with explicit configuration and without distributed shared Ticket
state.

## Dependencies

- `BAB-1109`: current v0.1 federation ADR; Phase 17 implementation may need a
  reviewed ADR/CHG to amend the read-only-only restriction before write/control
  code lands.
- Remote write/control implementation must not land until that reviewed
  `BAB-1109` reconciliation is complete.
- `BAB-1104`: HTTP remains the cross-node transport; distributed Erlang remains
  out of scope.
- `BAB-1113`: imported external tmux ownership still controls what a remote
  operator may do to imported sessions.
- Phase 13f provider runtime contract for Citizen capability metadata.
- Phase 14 roles for remote role summaries and routing display.
- Phase 15/16 Ticket lifecycle surfaces for remote operation context.
- `BAB-1004` light-first UI design and mobile responsive expectations.

## Proposed Solution

### 1. Node Identity And Configuration

Add explicit node identity and peer configuration.

Example shape:

```toml
[node]
id = "node-local"
name = "Local Babs"
public_url = "http://babs-node:4000"

[peers.home]
name = "Home Babs"
url = "http://home-babs:4000"
capabilities = ["read"]

[peers.workbench]
name = "Workbench Babs"
url = "http://workbench-babs:4000"
capabilities = ["read", "control"]

[peers.workbench.citizens.clare]
capabilities = ["read"]

[peers.workbench.citizens.dylan]
capabilities = ["read", "control"]
```

Rules:

- Node names are operator-configurable and shown in the UI.
- `node.public_url` is how this node describes its own reachable browser/API
  address; `peers.<name>.url` is the address this node dials for a peer.
- Public docs and fixtures must use placeholder hostnames, not private operator
  hostnames or private IPs.
- Peer configuration is an allowlist. Unknown nodes are not mounted.
- Capabilities are explicit: `read`, `write`, `control`.
- Per-Citizen capabilities override the peer default.
- `control` implies write-like actions plus lifecycle/terminal controls, so
  listing `write` beside `control` is optional and redundant.
- Runtime state remains local to each node; Phase 17 does not create a shared
  distributed database.

### 2. Federation API

Expose a versioned HTTP API for node-to-node UI federation.

Read endpoints:

- `GET /api/v1/node`
- `GET /api/v1/citizens`
- `GET /api/v1/citizens/:slug`
- `GET /api/v1/citizens/:slug/transcript`
- `GET /api/v1/tickets`
- `GET /api/v1/tickets/:id`

Real-time read stream:

- `GET /api/v1/events?cursor=...`

The event stream may use Server-Sent Events, long polling, or Phoenix Channels.
The implementation CHG should pick the simplest reliable option for BabsWeb and
browser-harness tests. The contract requirement is cursored, resumable remote
reads, not a specific streaming technology. Cursor values should be opaque to
clients; implementation CHGs must define replay and ordering semantics.

Write/control endpoints are only enabled when configuration allows them:

- add Ticket comment or message;
- update Ticket state through existing legal transitions;
- assign/unassign through existing APIs;
- inject a message into a remote Citizen through the remote node;
- start/stop/restart a remote Babs-owned Citizen;
- detach, but not kill, external-owned imported Citizens.

Remote write/control must call the remote node's existing local APIs. It must
not edit remote files directly over the network.

Tailscale remains the v0.1 network boundary, but remote write/control still
needs an auditable peer identity on each request so the receiving node can log
which configured peer initiated the action. The exact mechanism belongs in the
`BAB-1109` reconciliation CHG.

### 3. Capability Guard

Every remote action checks capability at two levels:

1. peer node default;
2. per-Citizen override when the action targets a Citizen.

Examples:

- `read` can list/view Citizens, Tickets, transcripts, and events.
- `write` can add Ticket comments and legal Ticket transitions.
- `control` can inject terminal input and start/stop/restart Babs-owned
  Citizens.

Denied actions should be visible and testable: the UI disables the control and
the API returns a typed forbidden error. The denial must not leak remote local
paths, env, tokens, or raw provider output.

All successful remote write/control actions append audit history on the remote
node where the state actually changes.

### 4. Mobile And PWA

Make Babs installable and usable from a phone on the same Tailscale network:

- web app manifest and installable icons;
- service worker for shell caching where safe;
- mobile layouts for Tickets, Citizens, terminal/full-window views, and remote
  node selector;
- touch-sized controls;
- no hidden desktop-only path for critical actions;
- same operator permissions as desktop, constrained by node/Citizen capability
  config.

Mobile offline mutation is out of scope. If the phone loses network access,
Babs should show stale/read-disconnected state rather than queueing writes.

### 5. Remote UI Namespace

Render remote nodes clearly:

- Node switcher in the app shell.
- Badges such as `local`, `remote`, `read-only`, `writable`, and
  `control-enabled`.
- Remote Tickets and Citizens use a namespace such as
  `remote:<node-name>/<resource>` in display text. Implementation CHGs should
  choose URL-safe route segments rather than treating this display namespace as
  a literal path format.
- Remote detail pages are visually similar to local pages but show capability
  status and remote latency/read freshness.
- Remote events update the UI in real time for read streams.
- If a configured peer is unreachable, the UI shows it as degraded/unreachable
  with last-successful-read freshness instead of hiding it.

The user should never have to infer whether a Stop/Inject/Approve action is
local or remote.

### 6. ADR Reconciliation

Because `BAB-1109` currently says v0.1 cross-node is read-only, implementation
must include a reviewed ADR/CHG before remote write/control code lands.

The likely amendment:

- Phase 17 starts with read-only UI federation.
- Phase 17 may add explicitly configured remote write/control for the single
  operator over Tailscale.
- There is still no cross-node Citizen-to-Citizen A2A, no distributed Ticket
  store, and no public-internet exposure.

## Out of Scope

- Public internet deployment.
- Multi-user auth, RBAC, or organization-level permissions.
- Distributed shared Ticket storage or conflict resolution.
- Cross-node Citizen-to-Citizen A2A.
- Remote OS shell access outside Babs APIs.
- Secret synchronization between nodes.
- Offline mobile write queueing.
- Remote control of external-owned imported tmux sessions beyond attach/detach
  semantics allowed by their ownership metadata.

## Implementation Slices

Phase 17 should be delivered in small reviewed PRs:

1. **17.1 Node identity and read API**
   - Add node identity config and `/api/v1/node`.
   - Add read-only citizens/tickets API.
   - Add capability config parser with tests.
   - Keep remote writes unavailable.

2. **17.2 Real-time remote reads**
   - Add cursored event stream.
   - Mount one configured peer in the local UI.
   - Show remote node freshness and read-only badges.
   - Add BDD for live remote Ticket/Citizen updates.

3. **17.3 Mobile/PWA shell**
   - Add manifest, installable assets, and safe service worker.
   - Make Tickets/Citizens/remote node views usable on phone viewport.
   - Add browser-harness mobile viewport tests.

4. **17.4 Remote write/control capability gate**
   - Amend `BAB-1109` through reviewed docs before code lands.
   - Add remote write/control endpoints behind explicit config.
   - Add audit events on the remote node.
   - Add denial tests for read-only peer and read-only Citizen overrides.

5. **17.5 Remote operation BDD/E2E hardening**
   - Prove remote read, remote comment, remote Ticket transition, and remote
     Citizen control in isolated test nodes.
   - Prove read-only controls are disabled and API-denied.
   - Verify mobile UI for the same flows.

## Acceptance Criteria

- Babs has configurable local node identity and peer nodes.
- Node names are operator-configurable and visible in the UI.
- A peer can be mounted read-only and updated through real-time remote reads.
- Mobile browser/PWA can perform the same local actions as desktop when inside
  the allowed network and when capability config permits.
- Per-node and per-Citizen capabilities control read/write/control behavior.
- Remote write/control actions are denied unless explicitly configured.
- Remote write/control actions use the remote node's Babs APIs, not direct file
  access.
- Remote actions append audit history on the node where state changes.
- UI clearly labels local vs remote and read-only vs writable/control-enabled.
- BDD/E2E coverage proves mobile layout, real-time remote reads, one allowed
  remote control action, and one denied read-only action.
- No raw secrets, private hostnames, private IPs, local checkout paths, runtime
  Ticket data, or generated remote-node data are published in docs, PR body,
  comments, or fixtures.

## Validation Plan

Each implementation CHG under Phase 17 should include focused tests first, then
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

Phase 17 BDD/E2E should prefer browser-harness for mobile viewport and local
multi-node browser testing. Implementation tests must use placeholder hostnames
and isolated local test ports; public artifacts must not contain operator
machine names, Tailscale IPs, or private hostnames.

For docs-only PRP work, `af validate --root .` and `git diff --check` are
sufficient locally; the GitHub Actions Test workflow provides the broader CI
gate after PR creation.

## Review Plan

- Review this PRP with Trinity `fast-review` and fold blockers before
  implementation CHGs.
- Remote write/control implementation must first reconcile `BAB-1109` through a
  reviewed ADR/CHG.
- Each implementation CHG must follow `BAB-1503` / `COR-1616`.
- GitHub PRs must use the correct project GitHub identity and follow
  `COR-1612` + `COR-1615` review loops.
- Maximum five GitHub Codex review rounds per PR unless the operator explicitly
  extends the loop.

## Open Questions

None for the PRP. Implementation CHGs still need to pick the concrete event
stream transport and the exact config file location after reading current
runtime config patterns.

## Implementation Results

Phase 17 was delivered through the approved small-PR sequence:

- 17.1 `BAB-2263`: node identity and read API.
- 17.2 `BAB-2264`: real-time remote reads.
- 17.3 `BAB-2265`: mobile/PWA shell.
- 17.4 `BAB-2266`: remote write/control capability gate.
- 17.5 `BAB-2267`: remote operation BDD/E2E hardening.

The v0.1 acceptance scope is implemented: a phone-sized UI can operate the
local node, configured peers can be mounted with live remote reads, remote
write/control actions are explicitly capability-gated and audited on the
receiving node, and BDD/E2E coverage proves allowed and denied remote operation
flows without publishing operator-specific network details.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-07 | Initial Phase 17 PRP for mobile and federated control | Codex |
| 2026-05-07 | Trinity R1 found roadmap blocker for stale M4/anti-goal read-only federation wording; folded blocker plus advisories for capability examples, public_url semantics, peer unreachable UI, and explicit BAB-1109 write/control gate | Codex |
| 2026-05-07 | Trinity R2 passed GLM and DeepSeek; folded implementation advisories for auditable peer identity, opaque cursor semantics, URL-safe remote namespaces, and imported tmux ownership dependency | Codex |
| 2026-05-09 | Mark Phase 17 implemented through the approved 17.1-17.5 slice sequence | Codex |
