# ADR-1104: A2A — BEAM-native Intra-node, HTTP JSON-RPC Inter-node

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Accepted

---

## What Is It?

How citizens delegate work to other citizens. **Two transports, intentionally split**:

- **Same BEAM node** — direct OTP calls via Registry + `GenServer.call` (and `cast`/PubSub for fire-and-forget)
- **Different node** (over Tailscale) — HTTP JSON-RPC via `Babs.A2A.HttpEndpoint`

`:erpc` (Erlang distribution) is **not** the inter-node primary. It is reserved as a possible future optimization once Tailscale + epmd reliability is independently validated.

---

## Context

A2A has two natural design questions:

1. **Intra-node:** use HTTP, or use BEAM-native (`GenServer.call` / `Phoenix.PubSub`)?
2. **Inter-node:** use HTTP, or use distributed Erlang (`:erpc.call/4`, `:rpc.call/4`)?

The three-model architecture review (Codex, DeepSeek, +1 self-design) reached different conclusions on the inter-node question — Codex recommended `:erpc` primary; DeepSeek recommended HTTP primary. This ADR resolves that.

---

## Decision

### Intra-node: BEAM-native via `Babs.A2A.Router`

Citizens call `Babs.A2A.Router.dispatch(target_id, payload)`. The router:
1. Looks up `target_id` in `Babs.Registry`
2. If on this node → `GenServer.call(pid, {:a2a, payload})` (or `cast` for one-way)
3. If on another node → see inter-node path below

Synchronous request/response uses `call`. Fire-and-forget uses `cast`. Multi-citizen broadcast uses `Phoenix.PubSub`.

### Inter-node: HTTP JSON-RPC via `Babs.A2A.HttpEndpoint`

Cross-node delegation goes through:
1. Local Router resolves target node from registry (citizen → host mapping)
2. POST `/a2a` (JSON-RPC envelope) to the peer's `Babs.A2A.HttpEndpoint`
3. Peer's endpoint dispatches locally via the same Router

The HTTP endpoint runs on a Bandit-served port (9001 by default; configurable per node). JSON-RPC 2.0 envelope with project-specific method names and payload shapes.

### Why HTTP, Not `:erpc`, for Inter-node

Three reasons:

1. **Operational debuggability.** `curl` works. Tailscale ACLs can be expressed as port allowlists. Captured payloads are human-readable JSON. `:erpc` opaque binary over distributed-Erlang is harder to inspect and ACL.

2. **Tailscale + epmd is unproven for our use case.** epmd needs a fixed port (4369 by default) plus dynamic listener ports per node. Tailscale ACLs and node naming churn (laptop sleeps, IP changes) interact with distributed Erlang's cookie + node-name discovery in ways that are reportedly fragile in mesh-networked environments. HTTP-over-Tailscale is the conservative choice; distributed Erlang would need its own validation effort before we depend on it for the primary A2A path.

3. **Boundary contract = HTTP forever, anyway.** Even if `:erpc` worked perfectly between BEAM nodes, we still need an HTTP endpoint for non-BEAM clients (future tools in other languages, scripts, integrations). The HTTP path is mandatory; `:erpc` would be additive complexity, not a replacement.

`:erpc` may be reconsidered in a future ADR if (a) Tailscale + distributed Erlang health is independently validated for 30+ days under real load, and (b) intra-cluster A2A latency becomes a measured bottleneck (not a hypothetical one).

---

## Consequences

**Positive:**
- Intra-node A2A is GenServer.call (~microseconds) rather than HTTP round-trip
- Inter-node A2A uses a well-understood transport with no novel failure modes
- HTTP boundary serves as both BEAM↔BEAM and BEAM↔non-BEAM contract
- One JSON-RPC schema works for every external integration regardless of language

**Negative:**
- Inter-node calls are slower than `:erpc` would be (estimated 1-5ms HTTP vs ~0.5ms `:erpc` on a healthy mesh). This is well below A2A's actual latency budget (citizens process tasks over seconds-to-minutes, not microseconds).
- Two transports to maintain. Mitigated by `Router` being the only place that branches on local-vs-remote.

**Neutral:**
- Tailscale stays the only cross-node networking primitive; no need to expose distributed-Erlang ports.

---

## Rejected Alternatives

### Alt 1 — `:erpc` as inter-node primary (Codex's proposal)

Native distributed Erlang for cross-node calls; HTTP only as a non-BEAM client adapter.

**Rejected because:** Codex's own architecture review identified Tailscale+`:erpc` as the #1 risk in their own design. Choosing the highest-risk option as primary is incoherent during early build, when we should be eliminating risk in known places before introducing it in new ones.

### Alt 2 — HTTP everywhere (intra-node too)

Treat A2A as HTTP regardless of where the target lives.

**Rejected because:** the entire reason to build on BEAM is the native concurrency and process model. Routing intra-node calls through HTTP throws away the runtime's main advantage for no design benefit. The complexity of having two transports (a single branch in `Router`) is small compared to the latency wins.

### Alt 3 — `Phoenix.PubSub` as the only A2A transport

Treat A2A as fan-out broadcasts; subscribers handle.

**Rejected because:** A2A has request/response semantics ("delegate this and give me the result"). PubSub is fire-and-forget. We use PubSub for *broadcasts* (status updates, transcript deltas) but not for the synchronous-call A2A path. Mixing them is a recipe for losing replies.

### Alt 4 — gRPC inter-node

Use gRPC + protobuf instead of HTTP JSON-RPC.

**Rejected because:** JSON-RPC over HTTP is debuggable from a shell with `curl`, requires no IDL/codegen pipeline, and is sufficient for our payload sizes. gRPC's wins (streaming, strong typing) are not where this protocol's pain is. Reserved for a future protocol-versioning ADR if and when payload size or schema discipline becomes a real problem.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial version — split intra/inter, HTTP for inter (not :erpc) | Claude Code |
| 2026-05-03 | Reframe to from-scratch (drop "Python relay migration compatibility" justification) | Claude Code |
