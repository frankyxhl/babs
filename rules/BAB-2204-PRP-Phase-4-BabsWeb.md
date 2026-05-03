# PRP-2204: Phase 4 — BabsWeb (LiveView + React + xterm.js)

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Draft
**Depends on:** Phase 3 (`BAB-2203`) — Connectors operational; Phase 2 — A2A + transcripts; Phase 0/1 — supervision tree
**Implements:** `BAB-1004` (UI Design Spec), `BAB-1106` (LiveView/Channels split ADR)

---

## What Is It?

The web phase. Builds the BabsWeb endpoint, the four LiveView modules, the TerminalChannel, the React-via-LiveView-hooks layer, and the xterm.js integration — implementing the visual design defined in `BAB-1004`.

---

## Problem

Phases 0-3 give Babs a working runtime, but operators interact with it via `iex`, `tmux attach`, and Discord. There is no overview view, no per-citizen dashboard, no unified terminal access from a browser. Phase 4 closes that gap.

---

## Proposed Solution

### Scope

```
lib/
├── babs_web/
│   ├── endpoint.ex
│   ├── router.ex
│   ├── telemetry.ex
│   ├── live/
│   │   ├── dashboard_live.ex      (View 1 in BAB-1004)
│   │   ├── citizen_live.ex        (View 2)
│   │   ├── full_terminal_live.ex  (View 3)
│   │   ├── ops_live.ex            (View 4)
│   │   └── diagram_live.ex        (View 5)
│   ├── channels/
│   │   └── terminal_channel.ex    (raw PTY bytes per BAB-1106)
│   ├── components/
│   │   ├── citizen_card.ex        (Phoenix Component)
│   │   ├── status_pill.ex
│   │   ├── action_button.ex
│   │   └── transcript_view.ex
│   └── hooks/                      (LiveView JS hooks bridging React)
│       ├── a2a_graph.ex            (mounts the A2AGraph React component)
│       ├── excalidraw.ex           (mounts the Excalidraw React component)
│       └── sparkline.ex            (mounts a chart component)
└── babs_web.ex

assets/
├── package.json                    (esbuild + tailwind + react)
├── tailwind.config.js              (palette from BAB-1004)
├── js/
│   ├── app.js                      (LiveView socket bootstrap)
│   ├── hooks/
│   │   ├── terminal.js             (xterm.js mount + Channel wiring)
│   │   ├── a2a_graph.js            (React mount: A2AGraph)
│   │   ├── excalidraw.js           (React mount)
│   │   └── sparkline.js            (React mount)
│   └── components/
│       ├── A2AGraph.tsx            (React + d3 / cytoscape)
│       ├── Excalidraw.tsx          (Excalidraw embed)
│       └── Sparkline.tsx           (lightweight chart)
└── css/
    └── app.css                     (Tailwind base + globals)
```

### Visual implementation

Strict adherence to `BAB-1004`:
- Color palette: Tailwind tokens generated from `BAB-1004` §"Color palette" — `bg-base`, `bg-surface`, `bg-surface-elevated`, `border-subtle`, `text-primary`, `text-secondary`, `text-tertiary`, `accent`, `accent-cyan`, `status-idle/typing/waiting/paused/dead`
- Typography: Inter for chrome, JetBrains Mono for monospace; Tailwind's `font-sans` and `font-mono` mapped accordingly
- Layout: 240px sidebar, 40px header, 24px status bar; main content fills the remainder
- All five views per the wireframes in `BAB-1004`

### LiveView wiring

- Each LiveView subscribes to relevant PubSub topics on `Babs.PubSub`:
  - DashboardLive: `dashboard:summary` (aggregate, refreshed every 1s)
  - CitizenLive: `citizen:#{name}:status` and `citizen:#{name}:transcript`
  - OpsLive: `dashboard:summary` + `a2a:recent`
- Operator actions (Restart, Send, Pause) translate to typed `GenServer.call` to the relevant `Citizen.Server` or `A2A.Router` — never DOM-mutated state

### TerminalChannel + xterm.js

Per `BAB-1106`:
- Channel topic `terminal:#{citizen_name}`
- On join: lookup `PaneSession`, store PID in `socket.assigns`, register as output listener
- xterm.js client (in `assets/js/hooks/terminal.js`) sends `input` and `resize` events; receives `output` pushes
- **No PubSub between Channel and PaneSession** — direct messaging

### React mounts

Three React components in v1:
1. **A2AGraph** — interactive node-edge graph of citizens and recent A2A flows
2. **Excalidraw** — embeds the official Excalidraw component for the Diagram view
3. **Sparkline** — small time-series chart used in OpsLive's cluster panel (alternative: pure SVG in LiveView, no React, if simpler)

Mount pattern: LiveView renders a `<div phx-hook="A2AGraph" data-payload={...} />`; the JS hook mounts the React component into that div, reads props from `data-*`, pushes events back via `pushEvent`.

### Authentication / authorization

- Phase 4 v1 is **single-operator** — no login UI, no multi-user. The web endpoint binds to `127.0.0.1` only by default; for Tailscale-network access, operator opts in via config.
- Future multi-user / auth flow → separate PRP

### Out of scope for Phase 4

- Mobile-responsive layouts (per `BAB-1004` "What This Spec Does NOT Define")
- Onboarding / first-run UI
- Theme switching (dark only in v1)
- WebRTC, voice, video
- Notifications API integration (in-app toasts only)

### Acceptance

Phase 4 is done when:

- All five views render and look like the `BAB-1004` mockups (verified via screenshot diff or operator review)
- Dashboard shows a live citizen list; clicking a card navigates to Citizen Detail
- Citizen Detail shows live transcript scrolling; terminal panel accepts keystrokes that round-trip to the tmux pane within ~50ms
- Ops view shows live sparklines; Restart button on a citizen actually triggers `CitizenSupervisor` restart
- Diagram view embeds Excalidraw; saved drawings persist (file-system or SQLite — decided during implementation)
- Browser disconnect → LiveView and Channel both auto-reconnect; state is consistent on reconnect
- A keystroke flood (typing fast) does not back up the LiveView render queue (terminal bypasses LiveView, so this validates the architectural claim)

### Implementation Plan

1. `mix phx.new --app babs --module Babs --no-ecto --no-mailer --no-tailwind` (custom Tailwind needed); merge into existing umbrella
2. Tailwind config from `BAB-1004` palette
3. `BabsWeb.Endpoint`, `Router`, basic layout components
4. `DashboardLive` — first; surface live citizen list using PubSub
5. `CitizenLive` — adds transcript panel
6. `TerminalChannel` + xterm.js hook — most-risk piece, validate end-to-end early
7. `OpsLive` + sparklines (start with pure-SVG in LiveView; React-ify if needed)
8. `DiagramLive` + Excalidraw React mount
9. `FullTerminalLive` — easy after CitizenLive's terminal works
10. Polish pass against `BAB-1004` mockups (spacing, typography, density)

---

## Open Questions

- **React build pipeline**: Phoenix's default esbuild vs Vite vs full webpack? **Default**: esbuild (Phoenix native); add a separate React/JSX entrypoint via esbuild plugin.
- **A2A graph viz library**: d3, cytoscape, react-flow? **Default**: react-flow (highest-level, most maintenance-friendly).
- **Excalidraw**: official `@excalidraw/excalidraw` package or self-host? **Default**: npm package, bundled with Babs's assets.
- **Sparklines**: pure SVG in LiveView (zero JS, fewer deps) or React (more flexible)? **Default**: pure SVG in LiveView for v1; revisit if interactivity needed.
- **Hot reload during dev**: `mix phx.server` works out of the box for LiveView; React hot-reload via esbuild's watch mode. Confirmed working.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial draft | Claude Code |
