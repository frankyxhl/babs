# ADR-1106: LiveView for State UI; React for Complex Widgets; Phoenix Channels + xterm.js for Raw PTY Bytes

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Accepted

---

## What Is It?

The Babs web frontend has **three distinct rendering layers**, each chosen for a specific access pattern:

1. **Phoenix LiveView** — default for all stateful UI (dashboard, status, ops, diagram views)
2. **React** (mounted inside LiveView via hooks) — for complex client-side interactions that exceed LiveView's natural sweet spot
3. **xterm.js + Phoenix Channels** — for raw PTY byte streams; Channel↔PaneSession messaging **bypasses Phoenix.PubSub**

This split exists because the three layers' access patterns differ by orders of magnitude in update frequency and interactivity model.

---

## Context

Phoenix provides two real-time primitives:

- **LiveView** — stateful, server-rendered UI; the framework diffs HTML on the server, sends DOM patches to the browser. Optimized for "data changes → UI updates" workflows.
- **Channels** — bidirectional WebSocket message-passing. Topic-scoped, broker-mediated by `Phoenix.PubSub`. Optimized for chat-like and event-streaming use cases.

The dashboard has two distinct interaction modes:

1. **State viewing** — dashboard panels showing citizen status, recent messages, system metrics. Mostly server-driven; user clicks switch citizens, expand sections, etc.
2. **Terminal streaming** — xterm.js in the browser pipes keystrokes into a citizen's tmux pane and renders the pane's bytes back. Bidirectional, high-frequency, latency-sensitive.

Mixing these into one mechanism (everything LiveView, or everything Channel) is wrong: LiveView's diff cost on byte-stream traffic is wasteful, and Channels for state UI re-creates the imperative-DOM problem we're trying to escape.

---

## Decision

### LiveView — state UI

All non-terminal UI is LiveView:
- `BabsWeb.DashboardLive` — citizen list, recent activity, status grid
- `BabsWeb.CitizenLive` — single-citizen detail (status, transcript, channels)
- `BabsWeb.OpsLive` — system metrics, restart/compact controls, A2A graph
- `BabsWeb.DiagramLive` — Excalidraw integration view

LiveView subscribes to `Phoenix.PubSub` topics:
- `citizen:#{id}:status` — state transitions
- `citizen:#{id}:transcript` — new transcript lines
- `dashboard:summary` — aggregate metrics

`PaneSession` and `Citizen.Server` broadcast to these topics on state change. LiveView only re-renders changed regions via the diff mechanism.

### React — complex widgets embedded in LiveView

For UI that LiveView handles awkwardly (custom drag-drop, canvas rendering, complex graph visualization, third-party JS components), Babs uses React components mounted inside LiveView via the `phx-hook` mechanism (or a library such as `live_react`).

Concrete uses:

- **A2A relationship graph** — interactive node-edge visualization of citizens and their delegation history
- **Excalidraw integration** (interactive diagramming surface)
- **Charts and metrics** — recharts/visx-style time-series widgets
- **Any future widget** that benefits from a rich npm ecosystem

The contract:

- React components live in `assets/js/components/`, built by Phoenix's esbuild/vite pipeline
- LiveView passes data to a hooked DOM element via `data-*` attributes; the React component reads those, renders, and pushes events back to LiveView via `pushEvent`
- React state stays *local* to the component; canonical state always lives server-side in LiveView
- Components are **opt-in**: a feature is built in LiveView first; React is reached for only when a concrete LiveView limitation is hit

This keeps the default mental model "everything is server-rendered Elixir" while leaving an escape hatch for the cases where it isn't a good fit.

### Phoenix Channels + xterm.js — raw PTY bytes

Terminal streaming uses a Phoenix Channel paired with xterm.js in the browser:

- `BabsWeb.TerminalChannel` joins on topic `"terminal:#{citizen_id}"`
- On `join`, looks up the citizen's `PaneSession` and stores the PID in `socket.assigns`
- On `"input"` message → `PaneSession.write(pid, data)` (direct GenServer call, no PubSub)
- `PaneSession` sends `{:pty_output, bytes}` directly to the Channel process (registered on join), which `push`es to the browser
- On `"resize"` → `PaneSession.resize(pid, {cols, rows})`
- Browser side: xterm.js (the de-facto terminal emulator library used by VS Code, Replit, code-server, etc.) consumes the bytes, renders ANSI / colors / cursor as a real terminal, captures keyboard input, and emits `"input"` and `"resize"` messages back through the Channel

xterm.js is **client-side only**. It is not a React component (it manages its own DOM region) and does not pass through LiveView. The Channel is the entire backend contract.

**The terminal data path bypasses Phoenix.PubSub entirely.** PTY bytes go Channel ↔ PaneSession with no broker in between.

### Why Bypass PubSub for Terminal Bytes

PubSub is great for many-to-many fan-out. Terminal bytes are 1-to-1: this Channel ↔ this PaneSession. Routing through PubSub for every keystroke means:
- Extra hop through the PubSub registry
- Tracking which Channel subscribed to which topic (when the citizen_id matters per-connection)
- Wasted CPU broadcasting to a topic with one subscriber

Direct messaging is faster, simpler, and matches the actual access pattern. PubSub is for *broadcasts*; this isn't a broadcast.

---

## Consequences

**Positive:**
- Dashboard rendering uses dramatically less code than equivalent imperative DOM patterns would require
- Terminal latency is one BEAM-message hop (microseconds), not Channel→PubSub→Channel→browser
- Reconnection is handled by Phoenix's connection lifecycle (LiveView and Channel both auto-reconnect)
- Two clearly separated mechanisms — easy to know which one to use for new features

**Negative:**
- Two mechanisms means developers need to know both. Mitigated by clear rule: state UI = LiveView, byte streams = Channel.
- Direct Channel↔PaneSession messaging means PaneSession needs to handle Channel-process death (Channel goes away when browser disconnects). Handled by `Process.monitor/1` in PaneSession.

---

## Rejected Alternatives

### Alt 1 — LiveView everywhere

Render the terminal inside a LiveView; xterm.js binds to a server-pushed event stream.

**Rejected because:**
- LiveView diffs HTML structures; PTY output is binary bytes (escape codes, color sequences). Diffing them as HTML strings is wasteful.
- The xterm.js → PTY input direction needs raw bytes, not LiveView events. Mixing the two creates an awkward dual API.
- LiveView's per-update cost is ~milliseconds for the diff; per-keystroke that's noticeable lag.

### Alt 2 — Channels everywhere (no LiveView), full SPA frontend

Build a full SPA (React/Svelte/Vue + TypeScript) that subscribes to many Channel topics for state updates; backend exposes only Channels and REST.

**Rejected because:**
- LiveView already solves the state-sync, diff, and reconnection problem; reproducing it in a SPA means reinventing several wheels for cosmetic gain
- Splits the mental model into two technology stacks (Elixir backend + JS/TS frontend) for the *common* case (most pages are state UI), even though only a minority of widgets need it
- React-via-LiveView-hooks (above) gives us the SPA escape hatch where it matters without paying the split-stack cost everywhere

### Alt 3 — Terminal bytes via PubSub

Have PaneSession publish to `"citizen:#{id}:pty_output"` and the Channel subscribe.

**Rejected because:**
- One-to-one access pattern doesn't justify a broker
- Adds latency for no benefit
- Subscriber lifecycle (Channel join/leave) becomes coupled to PubSub topic management

If we *did* have multiple browsers viewing the same terminal simultaneously (rare; usually a single operator at a time), we'd add a `tee` worker that fan-outs from PaneSession to multiple Channels, not put PubSub between every keystroke.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial version — LiveView for state, Channels for bytes, no PubSub on terminal hot path | Claude Code |
| 2026-05-03 | Add React-via-LiveView-hooks layer for complex widgets; explicitly name xterm.js as the browser terminal renderer | Claude Code |
