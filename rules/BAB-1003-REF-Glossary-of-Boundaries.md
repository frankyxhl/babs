# REF-1003: Glossary of Boundaries

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Partially Superseded

---

## ⚠️ Partially Superseded by v0.1 Scope Redefinition (2026-05-03)

This document was authored under the original 5-phase scope. v0.1 narrows boundaries:

- **Discord / Telegram boundaries are removed** (no Connector layer in v0.1; deferred indefinitely)
- **Tmux is now a lifecycle-owned boundary** — Babs creates and destroys tmux sessions per `BAB-1107` (not "attach-only")
- **Cross-node boundary is read-only** per `BAB-1109` (no bidirectional HTTP JSON-RPC A2A in v0.1)
- **Ticket filesystem (`tickets/`)** is a new boundary added in V0-M per `BAB-1111`
- **Two OTP apps** (`:babs` web + `:babs_citizens` lifecycle) per `BAB-1110` is a new internal boundary

Use this document for the boundaries still in scope (PTY → see `BAB-1110`; Phoenix Endpoint, SQLite, JSONL transcripts). For changed/added boundaries, see the linked ADRs.

A full rewrite will be done by Babs Citizens themselves post-Phase 1.

---

## What Is It?

Babs interacts with the outside world through a small number of well-defined boundaries. This document describes each boundary — its protocol, its owner module, the failure modes Babs must handle, and the contract that does NOT change. Concrete behavior on each boundary is in `BAB-1001` (Architecture Overview); this glossary fixes the **vocabulary and contracts** so that future code stays inside its lane.

---

## Boundary Inventory

```
                            ┌──────────────────────────────────┐
                            │           Babs (BEAM node)        │
                            │                                  │
   ┌─── Discord/Telegram ───►│ Connectors  ─►  ChannelWorker    │
   │   (HTTPS REST + WS)    │       │             │            │
   │                        │       │             ▼            │
   │                        │       └────────►  PaneSession ─┐  │
   ▼                        │                              ▼ │  │
 Tailscale peer  ── HTTP ──►│ A2A.HttpEndpoint                │  │
   ▲   (JSON-RPC)            │       │                       │  │
   │                        │       └────►  A2A.Router ◄─────┘  │
   │                        │                                  │
   │                        │                                  │
   │   Phoenix LiveView ◄───┤ BabsWeb.LiveView ◄─── PubSub      │
   │   (state UI)           │                                   │
   │                        │                                   │
   │   xterm.js Channel ◄───┤ TerminalChannel ─── direct ──►    │
   │   (raw PTY bytes)      │                              PaneSession ──► erlexec port ──► tmux/PTY
   │                        │                                   │
   │   AI CLI JSONL  ──read─┤ TranscriptTailer (read-only)      │
   │   (on disk)            └──────────────────────────────────┘
```

Each boundary section below answers the same five questions: **Protocol** (the wire format), **Owner** (the only module that may speak it), **Failure modes** (what can go wrong), **Contract** (what is fixed), **Out of scope** (what this boundary is not).

---

## 1. tmux / PTY (the AI CLI substrate)

| Field | Value |
|---|---|
| **Protocol** | erlexec port in `:pty` mode; bytes flow bidirectional (writes to PTY = `:exec.send/2`, reads = `{:stdout, os_pid, data}` messages) |
| **Owner** | `Babs.Tmux.Core` is the **only module** that calls `erlexec` or `System.cmd("tmux", ...)`. `Babs.Citizen.PaneSession` holds an erlexec PTY port handed out by `Tmux.Core`. |
| **Failure modes** | (a) erlexec port crash; (b) tmux session death; (c) AI CLI process exits inside pane; (d) pane resize race; (e) NIF-level crash taking down BEAM |
| **Contract** | One PaneSession owns one PTY handle to one tmux session. Concurrent writes are serialized via the PaneSession mailbox. Resize requests are absorbed and `:exec.pty_resize/2` is called. Death of the underlying tmux session triggers PaneSession death (supervisor restarts subtree per `BAB-1102`). |
| **Out of scope** | Spawning AI CLIs directly (we attach to existing tmux sessions; spawn lifecycle is human-managed today). Multi-pane within one session (one PaneSession = one pane). |

See `BAB-1103` (PTY method choice) and `BAB-1502` (stability validation) for depth.

---

## 2. Discord & Telegram (chat channels)

| Field | Value |
|---|---|
| **Protocol** | HTTPS REST (outbound: send message, edit, react) + Discord Gateway WebSocket or HTTPS polling (inbound). Telegram: HTTPS REST + long-polling. |
| **Owner** | `Babs.Connectors.DiscordREST`, `Babs.Connectors.TelegramREST`, plus per-platform poller/gateway processes. ChannelWorker is the **consumer** of inbound messages, not the protocol owner. |
| **Failure modes** | Auth token rotation/expiry, rate-limit (429), gateway disconnect, partial message (Discord truncation at 2000 chars), file upload size limits, network partition |
| **Contract** | Connectors expose typed inbound `{:message, channel, author, text, timestamp, ids}` events to subscribed ChannelWorkers. Outbound calls return `{:ok, message_id}` or typed errors (`:rate_limited`, `:unauthorized`, `:network`). Connectors handle reconnect/backoff internally; consumers do NOT see transient connection failures. |
| **Out of scope** | Voice channels, video, embeds beyond simple text+links, complex Discord interactions (modals, slash commands at the bot level — Babs citizens don't host bots, they relay through one). |

---

## 3. Browser ⇄ State UI (Phoenix LiveView)

| Field | Value |
|---|---|
| **Protocol** | Phoenix LiveView over WebSocket. Server holds canonical state and sends DOM patches; client sends events (`phx-click`, `phx-change`, etc.). Reconnection handled by LiveView framework. |
| **Owner** | `BabsWeb.*Live` modules (DashboardLive, CitizenLive, OpsLive, DiagramLive). State subscriptions go through `Phoenix.PubSub`. |
| **Failure modes** | WebSocket disconnect (transient), session timeout, large LiveView state pushing reconnection over its budget, malformed event payload from a hostile/buggy client |
| **Contract** | LiveViews subscribe to topics on `Babs.PubSub` (e.g., `citizen:#{id}:status`, `dashboard:summary`). They never mutate citizen state directly — operator actions are sent via typed `GenServer.call` to `Citizen.Server` or `A2A.Router`. The browser sees declarative HTML; no imperative DOM manipulation. |
| **Out of scope** | Real-time terminal byte streams (use the Channel boundary). Heavy computation in `handle_event` (push to a Task or GenServer). |

See `BAB-1106` for the LiveView vs Channel split rationale.

---

## 4. Browser ⇄ Terminal (Phoenix Channel, raw PTY bytes)

| Field | Value |
|---|---|
| **Protocol** | Phoenix Channel over WebSocket. Topic `terminal:#{citizen_id}`. Inbound: `{"input": <utf-8 bytes>}`, `{"resize": [cols, rows]}`. Outbound: `{"output": <base64 bytes>}`. xterm.js handles terminal emulation client-side. |
| **Owner** | `BabsWeb.TerminalChannel`. Direct messaging to `Babs.Citizen.PaneSession` (no PubSub). |
| **Failure modes** | Browser disconnect, browser tab freeze (unbounded buffering), keystroke flooding, resize event storms, PaneSession death mid-stream |
| **Contract** | Channel join authenticates and stores PaneSession PID in `socket.assigns`. PaneSession monitors the Channel process so it can drop the registration if the browser disconnects. Output bytes are sent via direct Erlang messages, not PubSub broadcast. **Per `BAB-1106`, this is the hot path that bypasses PubSub** — keystroke latency is one BEAM hop. |
| **Out of scope** | Multiple concurrent terminal viewers on the same citizen (rare; if needed, a fan-out worker tees PaneSession output to multiple Channels — does NOT introduce PubSub). |

---

## 5. Tailscale Peers ⇄ A2A (cross-machine agent delegation)

| Field | Value |
|---|---|
| **Protocol** | HTTPS POST to `/a2a` on a peer's `Babs.A2A.HttpEndpoint`. JSON-RPC 2.0 envelope. Project-specific method names and payload shapes; spec lives in `BAB-1104`. |
| **Owner** | Outbound: `Babs.A2A.Router` (resolves remote target, picks transport). Inbound: `Babs.A2A.HttpEndpoint` (Bandit on a configurable port, default 9001). |
| **Failure modes** | Tailscale partition (peer unreachable), peer down, peer's citizen does not exist, payload schema drift across versions, slow peer (timeout) |
| **Contract** | Cross-node calls are HTTP, **never** distributed Erlang (`:erpc`). See `BAB-1104`. The endpoint authenticates via Tailscale's network identity; no separate auth tokens. Errors are typed JSON-RPC error responses. Timeouts return `:timeout` to the calling citizen, which decides retry policy. |
| **Out of scope** | Same-node A2A (use `A2A.Router` direct path; never round-trips through HTTP). Streaming responses (today's A2A is request/response; streaming would need a new ADR). |

---

## 6. AI CLI JSONL Transcripts (read-only file system)

| Field | Value |
|---|---|
| **Protocol** | File system read; incremental tail via `File.stream!` + position tracking; mtime-based change detection. JSONL format (one JSON object per line); schema is **the AI CLI's contract**, not Babs's. |
| **Owner** | `Babs.Citizen.TranscriptTailer` — one per citizen. Reads only; never writes. |
| **Failure modes** | File rotation (Claude rotates at session boundaries), file truncation, malformed JSON line, partial line at read time, file moved/deleted, mtime not updating despite content append (rare FS bug) |
| **Contract** | TranscriptTailer is read-only. Bytes flow OUT only (parsed events broadcast on `Babs.PubSub` topic `citizen:#{id}:transcript`). Babs never speaks JSONL to upstream tools — they consume the same files Babs reads. Babs's parser handles **mixed `type` and `role` fields** seen in Claude's format and is tolerant of unknown fields (forward-compat for new AI CLI versions). |
| **Out of scope** | Writing transcripts (the AI CLI does that). Renaming/cleanup (out-of-band tool). Cross-session transcript stitching (separate concern). |

---

## What Boundaries Babs Does NOT Have (and shouldn't acquire)

- **Direct AI API calls** — Babs talks to AI CLIs, not to Anthropic/OpenAI/Google APIs. The CLI is the boundary.
- **Database other than SQLite** — see `BAB-1105`. PostgreSQL/Redis would be a new boundary requiring a new ADR.
- **Message broker (Kafka/NATS/RabbitMQ)** — A2A is HTTP for inter-node and direct OTP for intra-node. No broker.
- **Distributed Erlang clustering** — explicitly rejected as inter-node primary in `BAB-1104`.
- **Slack/Matrix/IRC** — would each be a new Connector boundary; today's set is Discord + Telegram only.
- **Webhook receivers from third-party services** — not in scope; could be added as a future Connector.

When a future feature looks like it needs a new boundary, **first check this glossary**. If the boundary is on the "does NOT have" list, the change requires a PRP + ADR, not just code.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial version — six boundaries documented; "does NOT have" list seeded | Claude Code |
| 2026-05-03 | Drop "Python relay migration compatibility" framing on A2A boundary | Claude Code |
