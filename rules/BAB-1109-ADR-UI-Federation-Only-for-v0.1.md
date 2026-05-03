# ADR-1109: UI Federation Only for v0.1 (No Cross-Node A2A)

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Accepted
**Amends:** `BAB-1104` (A2A scope is now intra-node-only in v0.1; cross-node restored only as read-only UI federation)

---

## Context

The original `BAB-1104` ADR (Accepted, pre-2026-05-03) defined a two-transport A2A:
- Intra-node: BEAM-native (`GenServer.call`, Registry-based)
- Inter-node: HTTP JSON-RPC over Tailscale, full bidirectional messaging

The v0.1 scope redefinition (2026-05-03) narrows this. Cross-node citizen messaging adds substantial complexity (auth, idempotency, retry semantics, partition handling, distributed state) — none of which is required to demonstrate Babs's core value (multi-agent ticket-driven runtime on a single BEAM node).

## Decision

**v0.1 supports only:**
1. **Intra-node A2A** — fully supported (Citizens on the same BEAM node coordinate via the Ticket system; see `BAB-1111`)
2. **Read-only UI federation across BEAM nodes** — Tailscale-connected Babs nodes can render each other's tickets and transcripts in their own UI, but cannot send messages, modify tickets, or spawn citizens across nodes

**v0.1 does NOT support:**
- Cross-node A2A messaging (Citizen on node A messaging Citizen on node B)
- Cross-node ticket creation or assignment
- Cross-node spawning (operator on node A spawning a citizen on node B)
- Distributed state of any kind beyond read replication for UI

## Rationale

1. **Single-operator default**: v0.1 assumes one human operator. Multi-machine scenarios are observation-driven (operator on iPad watching desktop's Babs run), not coordination-driven.
2. **PWA + mobile fits read-only**: The realistic mobile use case is "watch what's running at home"; full operator control on mobile is not on v0.1's roadmap.
3. **Federation auth complexity**: Cross-node writes require a real authentication and authorization model. Read-only federation can use Tailscale-level network identity + HTTP basic auth, far simpler.
4. **Distributed tickets are a hard problem**: Two Babs nodes simultaneously editing the same ticket is the same conflict-resolution challenge as any distributed system. v0.1 sidesteps by saying tickets are local; UI federation just shows them.

## What UI Federation Looks Like

Each Babs node exposes a small read-only HTTP API:
- `GET /api/v1/tickets` — list local tickets (with cursor pagination)
- `GET /api/v1/tickets/<id>` — read one ticket
- `GET /api/v1/citizens` — list local citizens
- `GET /api/v1/citizens/<name>/transcript?since=<cursor>` — stream transcript bytes

A second Babs node, given a peer URL + auth token, can mount the peer's tickets and citizens in its own UI under a "remote://" namespace. Click-through opens a read-only view. No write operations.

## Consequences

- `BAB-1104` is **amended**, not replaced. Its intra-node A2A design stays. Its inter-node HTTP design is re-scoped to read-only federation only in v0.1.
- v0.2+ may add cross-node A2A; this ADR does not preclude that. The decision here is timing.
- Phase 16 (PWA + Federation, in `BAB-2300`) implements the read-only federation API.
- Multi-node Babs operators must accept that v0.1 is "one operator, multiple machines" not "multiple operators coordinating."
- Tailscale remains the assumed network layer; no public internet exposure in v0.1.

## What v0.1 Use Cases Look Different Now

- ✅ "Run Babs on my desktop, watch it from my iPad on the couch via PWA"
- ✅ "Run Babs on a beefy home server, watch it from my laptop while traveling"
- ❌ "Babs on machine A spawns a Citizen, then asks a Citizen on machine B for help" (deferred to v0.2+)
- ❌ "Babs on machine A and Babs on machine B share the same Ticket pool" (not on roadmap)

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial decision; restricts cross-node to read-only UI federation in v0.1 | Claude Code |
