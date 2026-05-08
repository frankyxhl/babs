# ADR-1109: UI Federation Plus Configured Operator Control for v0.1

**Applies to:** BAB project
**Last updated:** 2026-05-09
**Last reviewed:** 2026-05-09
**Status:** Accepted
**Amends:** `BAB-1104` (A2A scope is now intra-node-only in v0.1; cross-node restored as UI federation plus explicitly configured single-operator remote control)

---

## Context

The original `BAB-1104` ADR (Accepted, pre-2026-05-03) defined a two-transport A2A:
- Intra-node: BEAM-native (`GenServer.call`, Registry-based)
- Inter-node: HTTP JSON-RPC over Tailscale, full bidirectional messaging

The v0.1 scope redefinition (2026-05-03) narrows this. Cross-node citizen messaging adds substantial complexity (auth, idempotency, retry semantics, partition handling, distributed state) — none of which is required to demonstrate Babs's core value (multi-agent ticket-driven runtime on a single BEAM node).

## Decision

**v0.1 supports:**
1. **Intra-node A2A** — fully supported (Citizens on the same BEAM node coordinate via the Ticket system; see `BAB-1111`)
2. **Read-only UI federation across BEAM nodes** — Tailscale-connected Babs nodes can render each other's tickets and transcripts in their own UI
3. **Explicitly configured single-operator remote write/control** — a configured Babs peer may request Ticket writes or Citizen control on another configured Babs node only when the receiving node's local federation config allows it

**v0.1 does NOT support:**
- Cross-node A2A messaging (Citizen on node A messaging Citizen on node B)
- Remote Ticket creation
- Distributed cross-node ticket storage, conflict resolution, or shared assignment ownership
- Cross-node Citizen spawning as an autonomous Citizen-to-Citizen operation
- Distributed state of any kind beyond read replication for UI
- Public-internet remote control or a general multi-user auth/RBAC model

Remote write/control in v0.1 is a deliberately narrow operator exception:

- The receiving node is authoritative. It checks the caller peer id against its
  local federation config, then applies peer-level and per-Citizen capabilities.
- Tailscale remains the assumed network boundary. The Phase 17.4 request
  identity is for allowlist and audit inside that trusted boundary, not a
  public authentication scheme.
- Remote actions call the receiving node's local Babs APIs. They do not edit
  remote files directly and do not bypass Ticket, lifecycle, imported ownership,
  or transcript rules.
- Successful remote write/control actions append audit data on the receiving
  node.

## Rationale

1. **Single-operator default**: v0.1 assumes one human operator. Multi-machine scenarios are observation-driven (operator on iPad watching desktop's Babs run), not coordination-driven.
2. **PWA + mobile now includes operator control**: The operator has accepted
   phone/tablet control inside the same trusted Tailscale network. This is
   still a single-operator workflow, not a multi-user permission system.
3. **Federation auth complexity remains deferred**: Public-internet or
   multi-user remote control still requires stronger authentication and
   authorization. v0.1 stays inside the operator's trusted network and explicit
   per-peer configuration.
4. **Distributed tickets are a hard problem**: Two Babs nodes simultaneously editing the same ticket is the same conflict-resolution challenge as any distributed system. v0.1 sidesteps by saying tickets are local; remote write/control asks the owning node to mutate its own local state.

## What UI Federation Looks Like

Each Babs node exposes a small HTTP API.

Read endpoints:
- `GET /api/v1/tickets` — list local tickets (with cursor pagination)
- `GET /api/v1/tickets/<id>` — read one ticket
- `GET /api/v1/citizens` — list local citizens
- `GET /api/v1/citizens/<name>/transcript?since=<cursor>` — stream transcript bytes

A second Babs node, given a peer URL and explicit local config, can mount the
peer's tickets and citizens in its own UI under a remote namespace.

Phase 17.4 may add mutating endpoints for configured remote operator actions,
such as Ticket comments/transitions and Citizen lifecycle/injection. Those
endpoints must be capability-guarded and audited on the receiving node.

## Consequences

- `BAB-1104` is **amended**, not replaced. Its intra-node A2A design stays. Its inter-node HTTP design is re-scoped to UI federation plus explicitly configured single-operator remote control in v0.1.
- v0.2+ may add cross-node A2A; this ADR does not preclude that. The decision here is timing.
- Phase 17 (Mobile and Federated Control, in `BAB-2300` and `BAB-2245`) implements read-only federation first, then explicitly configured remote write/control.
- Multi-node Babs operators must accept that v0.1 is "one operator, multiple machines" not "multiple operators coordinating."
- Tailscale remains the assumed network layer; no public internet exposure in v0.1.

## What v0.1 Use Cases Look Different Now

- ✅ "Run Babs on my desktop, watch it from my iPad on the couch via PWA"
- ✅ "Run Babs on a beefy home server, watch it from my laptop while traveling"
- ✅ "Restart a stuck Citizen on my desktop Babs from my phone's Babs PWA on the same trusted network"
- ❌ "Babs on machine A spawns a Citizen, then asks a Citizen on machine B for help" (deferred to v0.2+)
- ❌ "Babs on machine A and Babs on machine B share the same Ticket pool" (not on roadmap)

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial decision; restricts cross-node to read-only UI federation in v0.1 | Claude Code |
| 2026-05-06 | Update PWA/Federation phase reference after imported tmux attach inserted as Phase 13 | Codex |
| 2026-05-09 | Reconcile Phase 17.4 single-operator remote write/control exception while keeping cross-node A2A and distributed state out of v0.1 | Codex |
