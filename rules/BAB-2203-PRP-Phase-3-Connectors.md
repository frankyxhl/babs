# PRP-2203: Phase 3 — Connectors (Discord & Telegram)

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Draft
**Depends on:** Phase 2 (`BAB-2202`) — A2A + Citizen subtree + transcripts working

---

## What Is It?

The phase that connects Babs to external chat surfaces: Discord and Telegram. Adds the `Babs.Connectors.*` supervision branch and per-citizen `ChannelWorker`s. Exit criterion: a Discord message in a configured channel reaches a citizen's tmux pane, the citizen replies, and the reply lands back in Discord.

---

## Problem

Phases 1-2 give us a citizen runtime, but it has no inbound traffic except from `iex`. Real value emerges when citizens relay between humans and AI CLIs across chat platforms. Phase 3 adds that.

This phase is also where Connectors-as-a-boundary (per `BAB-1003`) gets validated under real auth, real rate limits, real network flake. Findings here may inform a CHG to `BAB-1003`.

---

## Proposed Solution

### Scope

```
lib/babs/
├── connectors/
│   ├── supervisor.ex          (top-level supervisor for all Connectors)
│   ├── discord/
│   │   ├── rest.ex            (HTTPS REST client: send, edit, react)
│   │   ├── gateway.ex         (Discord Gateway WebSocket handler — or polling fallback)
│   │   └── poller.ex          (alternative inbound: HTTPS long-poll if Gateway is heavy)
│   ├── telegram/
│   │   ├── rest.ex            (HTTPS REST: send, edit)
│   │   └── poller.ex          (Telegram getUpdates long-polling)
│   └── relay_config.ex        (reads relay_config table from Phase 2 SQLite)
└── citizen/
    └── channel_worker.ex      (one per (citizen × external channel) pair)

priv/repo/migrations/
└── 20260601_create_relay_config.exs
```

### relay_config schema

```elixir
schema "relay_config" do
  field :platform, :string         # "discord" | "telegram"
  field :channel_id, :string       # platform-specific channel id
  field :target_citizen, :string   # citizen name in registry
  field :ai_type, :string          # "claude" | "codex" | etc — drives prompt detection
  field :prompt_pattern, :string   # regex for "AI is at prompt" detection
  field :enabled, :boolean
  timestamps()
end
```

### ChannelWorker behavior

One GenServer per (citizen × external channel). On start:

1. Subscribes to inbound events from the relevant Connector for its `channel_id`
2. On inbound message:
   - Format the inject text per `ai_type` (Claude vs Codex have different paste expectations)
   - Call `Babs.Citizen.PaneSession.inject(target_citizen, formatted)`
   - Track the message id for reply correlation
3. Subscribes to PubSub topic `citizen:#{target_citizen}:transcript`
4. On transcript event matching the response pattern:
   - Format outbound (de-color, trim)
   - Call `Connectors.Discord.REST.send_message/3` (or Telegram equivalent)
   - Update `task_history` (audit)

### Out of scope for Phase 3

- Web — Phase 4
- Slack / Matrix / IRC — separate connectors per platform (each is a future PRP)
- Voice / video — out of project scope per `BAB-1003`
- File uploads beyond simple attachments — defer to Phase 5+
- Multi-user threading inside a single Discord channel — first-pass behavior is "all messages in channel go to the citizen, all citizen replies post to that channel"

### Acceptance

Phase 3 is done when:

- A Discord message in a configured channel arrives at the citizen's tmux pane within ~3s
- The citizen's reply (detected via TranscriptTailer + prompt pattern) arrives back in Discord within ~3s after the AI finishes typing
- Same flow works for Telegram
- Disconnecting the network for 60s and reconnecting → Connectors auto-recover; queued messages get processed in order
- Discord rate-limit (HTTP 429) is handled with backoff; no message is lost or duplicated
- Test suite includes mocks for both Connectors and a unit-tested ChannelWorker against fake transcript events

### Implementation Plan

1. Pick a Discord client library: hand-rolled HTTPS+WS or `Nostrum`. **Tentative**: hand-rolled HTTPS REST + Discord Gateway via `:gun` or `Mint.WebSocket`. Decision deferred to PRP review.
2. Implement `Connectors.Discord.REST` (send, edit, react, fetch_messages)
3. Implement `Connectors.Discord.Gateway` OR `Connectors.Discord.Poller` (pick one based on operational simplicity)
4. Implement `Connectors.Telegram.REST` and `Connectors.Telegram.Poller`
5. `relay_config` schema + migration + seed
6. `Connectors.Supervisor` boots all enabled rows
7. `ChannelWorker` GenServer
8. End-to-end manual test: send a Discord message, watch it round-trip
9. Chaos: kill the Gateway connection mid-message; confirm recovery
10. Update `task_history` to log every relay message round-trip

---

## Open Questions

- **Discord Gateway vs polling**: Gateway is more elegant but introduces a long-lived WebSocket. Polling is heavier on the API but simpler to operate. **Default**: Gateway, with polling as a `:fallback` config option for development environments where Gateway has been flaky.
- **Reply detection precision**: how confidently can TranscriptTailer + prompt pattern detect "the AI just finished a complete reply"? **Default**: ai_type-specific patterns + a debounce timer (no new lines for 1.5s = reply complete). Tune in real-world testing.
- **Multiple citizens per channel**: ever needed? **Default**: no — `relay_config` enforces one citizen per channel. Multi-citizen channels are a Phase 5+ feature if a real use case appears.
- **Bot-level features (Discord modals, slash commands at the bot layer)**: out of scope per `BAB-1003`. Confirmed.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial draft | Claude Code |
