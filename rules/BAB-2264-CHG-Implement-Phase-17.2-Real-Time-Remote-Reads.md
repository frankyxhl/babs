# CHG-2264: Implement Phase 17.2 Real-Time Remote Reads

**Applies to:** BAB project
**Last updated:** 2026-05-09
**Last reviewed:** 2026-05-09
**Status:** Approved
**Date:** 2026-05-09
**Requested by:** Operator
**Priority:** High
**Change Type:** Feature

---

## What

Implement **Phase 17.2: Real-time remote reads** from `BAB-2245`.

Phase 17.1 added local node identity, peer config parsing, and read-only JSON
APIs. This slice makes that read API usable as a live remote read surface:

- Add a cursored read-event feed endpoint:
  - `GET /api/v1/events`
- Add a small remote peer read client that can fetch a configured peer's node,
  Citizen, Ticket, and event-feed snapshots.
- Mount one configured peer in the local browser UI with visible node identity,
  freshness, read-only status, and remote Citizen/Ticket counts or rows.
- Add BDD/E2E-style coverage for live remote Ticket/Citizen refresh behavior
  using isolated local test endpoints and placeholder hostnames only.

Out of scope:

- Remote write/control endpoints. That remains Phase 17.4.
- Mobile/PWA installability and full phone polish. That remains Phase 17.3.
- Remote audit events for writes. That remains Phase 17.4.
- Distributed shared Ticket storage, remote file access, or cross-node
  Citizen-to-Citizen A2A.
- Public-internet auth/secret distribution. Operator model remains
  Tailscale/local-network scoped.
- Mounting multiple peers in the first UI pass. The parser may keep supporting
  many peers, but the UI acceptance path is one configured peer.

Depends on:

- `BAB-2245` Phase 17 Mobile and Federated Control PRP.
- Phase 17.1 merged via PR #56 / merge commit `4a2af7d`: local node identity,
  peer config parsing, and path-safe read-only JSON APIs.

## Why

The local read API is only useful for federation once another Babs node can read
it continuously and show freshness. Starting with remote reads keeps the
federation boundary safe: local and remote nodes remain independent, remote
data is clearly labeled, and no remote action can mutate state.

The event-feed design should also prepare Phase 17.4 write/control auditing:
clients need a stable cursor contract before they can safely reason about
whether a remote node is fresh enough for an operator action.

## Impact Analysis

- **Systems affected:** BabsWeb API routes/controllers, federation read facade,
  peer HTTP client, Citizens/Tickets LiveViews, tests, roadmap docs.
- **Runtime behavior:** Local-only use should not change. When peers are
  configured, the UI shows read-only remote peer sections and refresh metadata.
- **Persistence:** No schema migration. Remote snapshots are in-memory
  presentation state only.
- **Security/privacy:** No remote writes. Do not serialize raw host paths,
  tokens, private IPs, local machine names, or local checkout paths. Public
  artifacts must use placeholder hostnames such as
  `http://babs-peer.example:4000`.

## Design

### Cursored Event Feed

Add `GET /api/v1/events`.

The endpoint returns a bounded JSON batch:

```json
{
  "node": {"id": "node-local", "name": "Local Babs"},
  "cursor": "opaque-cursor",
  "events": [
    {
      "id": "node-local:node:hash",
      "type": "node.snapshot",
      "occurred_at": "2026-05-09T00:00:00Z",
      "payload": {
        "node": {"id": "node-local", "name": "Local Babs", "public_url": null}
      }
    },
    {
      "id": "node-local:citizens:hash",
      "type": "citizens.snapshot",
      "occurred_at": "2026-05-09T00:00:00Z",
      "payload": {"citizens": []}
    },
    {
      "id": "node-local:tickets:hash",
      "type": "tickets.snapshot",
      "occurred_at": "2026-05-09T00:00:00Z",
      "payload": {"tickets": [], "invalid": {"count": 0}}
    }
  ]
}
```

This slice should use a stateless cursor rather than a new persistent event
journal. The cursor encodes the last observed snapshot hashes for the
allowlisted node, Citizen, and Ticket projections. On each request, the server
compares the current snapshot hashes with the cursor and returns changed
snapshot events only. If no cursor is supplied, it returns initial
`node.snapshot`, `citizens.snapshot`, and `tickets.snapshot` events.

Cursor rules:

- Cursor format is opaque to callers and may be URL-safe base64 JSON.
- Invalid cursor values return HTTP 400 with code `invalid_cursor`.
- Snapshot hashes are deterministic content fingerprints of the JSON-ready
  projection payload. The implementation should use a canonical JSON encoding
  with sorted map keys, then SHA-256, or an equivalent deterministic canonical
  fingerprint that changes only when the projected payload changes.
- Event ids use `{node_id}:{projection}:{content_hash}`. The example uses the
  literal string `hash` only for readability.
- Resupplying the same cursor while local snapshots are unchanged returns the
  same or equivalent cursor with `"events": []`. The cursor returned from an
  empty-events response must itself be safe to resupply and continue producing
  empty events while the snapshots remain unchanged.
- For stateless snapshot events, `occurred_at` is the server's current UTC time
  at request processing, not a persisted last-change timestamp.
- Event response size is bounded to the current local snapshots; there is no
  unbounded historical replay in Phase 17.2.
- Individual `citizens.snapshot` and `tickets.snapshot` payloads deliberately
  inherit the same unpaginated bounded-local-snapshot behavior as Phase 17.1 list
  endpoints. Per-snapshot pagination/cursor windows remain deferred until remote
  UI scale requires them.
- Event payloads reuse the Phase 17.1 allowlist projections. No raw `cwd`,
  `path`, `last_error`, `target_label`, or invalid-file paths are exposed.
- Events are read-only snapshots, not durable audit events. Durable write audit
  events are Phase 17.4.

This is intentionally not Server-Sent Events yet. A cursored JSON feed is easier
to test, works with simple HTTP clients, and still gives the UI a stable
freshness contract. SSE or WebSocket streaming can be layered later if polling
cost becomes a real problem.

### Remote Peer Client

Add a small `Babs.Citizens.Federation.PeerClient` boundary.

Responsibilities:

- Read peer URLs from `Babs.Citizens.Federation.Config`.
- Fetch peer endpoints with short timeouts:
  - `/api/v1/node`
  - `/api/v1/citizens`
  - `/api/v1/tickets`
  - `/api/v1/events?cursor=<cursor>`
- Normalize remote responses into path-safe local presentation structs/maps.
- Return explicit statuses:
  - `:fresh` for successful recent reads
  - `:stale` when the last successful snapshot is older than the configured
    freshness window
  - `:unreachable` when a fetch fails
  - `:config_error` when peer config is invalid
- Never write remote data into the local Ticket store or Citizen SQLite tables.

Implementation should avoid adding a new dependency for this first slice. Use
the standard Erlang/OTP HTTP client boundary (`:httpc` under `:inets`) behind a
small adapter. Verify `:inets` is included in the needed app supervision/runtime
configuration before using `:httpc`. If the standard client is too brittle
during implementation, stop and document the reason before adding a dependency.

Adapter shape:

- Add a small behaviour such as `Babs.Citizens.Federation.HttpClient`.
- Provide a default `:httpc` implementation.
- Allow tests and LiveView config to inject a fake module or function without
  starting network listeners.

Timeout defaults:

- Connect/read timeout: `1_500ms`.
- UI refresh interval: `5_000ms`.
- Freshness window: `15_000ms`.

These values should be application-configurable so tests can use shorter
intervals.

Phase 17.2 does not add a config cache or watcher. `PeerClient` may reuse the
isolated Phase 17.1 config-read facade, but it must keep config reads behind one
boundary so a later cache/watcher can replace it without changing controllers or
LiveViews.

### UI Mount

Mount one configured peer in the local UI.

Minimum UI acceptance:

- Citizens page shows a remote node section when at least one peer is configured.
- Tickets page shows remote Ticket summaries for the mounted peer.
- When multiple peers are configured, the first UI pass mounts the first peer in
  sorted peer-id order.
- Remote rows/cards show:
  - remote node name/id
  - freshness status
  - `Read-only` badge
  - remote Citizen/Ticket labels that cannot be mistaken for local rows
- Remote controls that would mutate state are absent or disabled.
- UI updates when the remote snapshot changes during a LiveView session.

Implementation should use the normal LiveView server-side refresh pattern
(`Process.send_after` / `Process.send_interval`) rather than a browser-only
JavaScript poller, so tests can inject peer snapshots and assert server-rendered
HTML state.

The UI should remain light-theme-compatible and use the existing Babs styling
and icon patterns. Do not introduce a separate dark/purple remote-node visual
system.

### Error Shape

`GET /api/v1/events` uses the Phase 17.1 JSON error shape:

```json
{"error": {"code": "invalid_cursor", "message": "Event cursor is invalid"}}
```

Stable new codes:

- `invalid_cursor`

Reused from Phase 17.1:

- `read_failed`

Config errors continue to use `config_error`.

## Implementation Plan

1. **RED/GREEN: event cursor and snapshot events**
   - Add unit tests for initial cursor, changed/unchanged snapshot hashes,
     invalid cursor handling, and path-safe payload projection.
   - Add `GET /api/v1/events` through a dedicated
     `BabsWeb.Api.V1.EventsController`.
   - Tests may use a cursor test helper or injectable cursor codec to construct
     known-hash cursor fixtures while the public cursor remains opaque.

2. **RED/GREEN: peer client boundary**
   - Add tests with a fake HTTP adapter for successful peer reads, unavailable
     peer, invalid JSON, stale freshness, and event cursor progression.
   - Include freshness boundary coverage for a snapshot exactly at the freshness
     window age.
   - Malformed peer responses must return an explicit unavailable/error status
     instead of crashing the caller.
   - Keep adapter injection explicit so BDD can run without live external nodes.

3. **RED/GREEN: UI remote read mount**
   - Add LiveView tests for configured peer display, read-only badges, disabled
     remote mutation controls, and refresh updates.
   - Prefer one mounted peer for this slice.

4. **BDD/E2E**
   - Add browser-harness coverage for a local node displaying a peer's changing
     Citizen/Ticket snapshots using isolated local fixtures or in-process fake
     endpoints.
   - Avoid public artifacts containing private hostnames, local paths, runtime
     Ticket data, or private IPs.

5. **Docs and roadmap**
   - Keep `BAB-2300` and `BAB-0000` in sync if implementation scope changes.
     The initial CHG already records Phase 17.1 as merged and adds `BAB-2264`.

6. **Review and validation**
   - Review this CHG with Trinity `fast-review` and fold blockers before code.
   - After implementation, run Trinity implementation review.
   - Follow `BAB-1503` / `COR-1616`, then `COR-1615` / `COR-1612` for the PR.

## Acceptance Criteria

- `GET /api/v1/events` returns initial and changed read snapshot events with an
  opaque cursor.
- Invalid event cursors return JSON 400 with code `invalid_cursor`.
- Resupplying the same event cursor while local snapshots are unchanged returns
  an empty `events` array.
- The cursor returned from an empty-events response can be resupplied and still
  returns an empty `events` array while snapshots are unchanged.
- Event payloads reuse explicit path-safe projections and expose no raw host
  paths or local runtime file paths.
- A configured peer can be fetched through the peer client with timeout,
  freshness, stale, and unreachable states.
- The local Citizens/Tickets UI can mount one configured peer and show remote
  read-only Citizen/Ticket data with freshness.
- Remote write/control buttons are absent or disabled in the remote sections.
- Tests cover unit, LiveView, and BDD/E2E-level behavior for remote snapshot
  refresh.
- No raw secrets, private hostnames, private IPs, local checkout paths, runtime
  Ticket data, or generated remote-node data are published in docs, PR body,
  comments, commits, tests, or fixtures.

## Validation Commands

```bash
mise exec -- mix test apps/babs_citizens/test/babs_citizens/federation_event_feed_test.exs apps/babs_citizens/test/babs_citizens/federation/peer_client_test.exs apps/babs/test/babs_web/controllers/api_v1_events_controller_test.exs apps/babs/test/babs_web/live/remote_peer_live_test.exs
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
npm run test:js
npm run test:bdd
af validate --root .
git diff --check
git diff -U0 | rg -n '^\+.*(100\.[0-9]{1,3}|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|/Users/[^[:space:]]+|api_token|secret|token)' || true
```

## Results

- Plan review:
  - Trinity fast-review R1 on 2026-05-09: GLM PASS. DeepSeek raw review found
    blockers around `node.snapshot` example/prose consistency and `read_failed`
    being listed as a new code. Folded both blockers plus advisories for
    deterministic snapshot hashes, event id format, unchanged cursor responses,
    unpaginated snapshot scope, config cache deferral, cursor test helpers,
    LiveView refresh pattern, `:inets` verification, adapter shape, and explicit
    `EventsController` placement.
  - Trinity fast-review R2 on 2026-05-09: GLM PASS and DeepSeek PASS with no
    blockers. Folded advisories for single-peer UI selection, stateless
    `occurred_at` semantics, cursor chain stability, freshness boundary tests,
    and malformed peer response handling. Marked CHG Approved.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-09 | Initial Phase 17.2 real-time remote reads CHG | Codex |
| 2026-05-09 | Fold Trinity R1 plan review blockers and advisories | Codex |
| 2026-05-09 | Mark Approved after Trinity R2 PASS/PASS and fold advisories | Codex |
