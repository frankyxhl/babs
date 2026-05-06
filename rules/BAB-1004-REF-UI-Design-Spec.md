# REF-1004: UI Design Spec

**Applies to:** BAB project
**Last updated:** 2026-05-06
**Last reviewed:** 2026-05-06
**Status:** Active

---

## What Is It?

The visual and interaction design contract for BabsWeb. Concrete enough to drive (a) UI mockup generation by image models, (b) actual implementation in Phase 4. Defines: visual identity, layout primitives, per-view specifications, component library, state vocabulary, and image-generation prompt templates.

This is a **text design spec** — no Figma, no images. The intent is precision-by-description: a competent designer or image model should be able to produce coherent mockups from these words alone.

---

## Visual Identity

**Mood**: An operations console for a small fleet. Calm, dark, dense. Not a flashy product UI; the user is an operator watching agents work, not a casual visitor. Visual reference points: tmux + VS Code Dark+ + a touch of operations dashboard (Grafana / Linear). Bat-Family thematic restraint — purple as accent, never centerpiece.

**Color palette** (dark theme — default and only theme for v1):

| Role | Description | Concrete (hex) |
|---|---|---|
| Background base | Near-black, slightly cool | `#0d0d10` |
| Surface (panels, cards) | Elevated by ~6% | `#16161b` |
| Surface elevated (hover, active) | Elevated by ~10% | `#1d1d24` |
| Border subtle | Barely-visible separation | `#2a2a30` |
| Border emphasis | Active/focused outlines | `#3d3d45` |
| Text primary | Warm off-white | `#e8e8e8` |
| Text secondary | Muted gray | `#9c9caa` |
| Text tertiary | More muted | `#6c6c78` |
| Accent primary (Babs purple) | Barbara Gordon's signature; for active states, brand chrome | `#a78bfa` |
| Accent secondary (cyan) | For interactive elements not in the active state | `#67e8f9` |
| Status: idle / healthy | Calm green | `#4ade80` |
| Status: typing / working | Warm amber | `#fbbf24` |
| Status: waiting / paused | Soft blue | `#60a5fa` |
| Status: error / dead | Restrained red | `#f87171` |
| Terminal background | Pure black for xterm canvas | `#000000` |

**Typography**:

- **UI sans**: Inter (or system: SF Pro on macOS, Segoe UI on Windows). Weights 400 / 500 / 600.
- **Monospace**: JetBrains Mono — used for transcripts, terminal, citizen names in lists, and any data-dense table cell.
- **Sizes**: Body 14px, secondary 12px, headings 16/20/24px, terminal 13px (configurable).
- **Letter-spacing**: Slight tracking on uppercase labels (`+0.05em`); none on body.

**Density**: High. Operators want to see many citizens at once, not large empty whitespace. Comfortable padding inside cards (16-20px), tight padding inside list rows (8-12px vertical).

**Iconography**: Lucide / Phosphor outline icons at 16px; status dots are 8px solid circles. Every action button must include a relevant semantic icon. Avoid emojis except for status legends.

**Motion**: Restrained. State transitions fade in 120-180ms. No bounce, no spring. Terminal output is real-time (no animation).

---

## Global Layout

```
┌────────────────────────────────────────────────────────────────────┐
│ ▌ Babs            🟣 4 alive  🟡 1 typing  🔴 0 dead   ⌘K   ⚙ ▾   │ ← Header (40px)
├──────────┬─────────────────────────────────────────────────────────┤
│          │                                                         │
│  ◇ Dash  │                                                         │
│  ⊞ Citizens                                                        │
│  ▦ Ops   │                Main content area                        │
│  ⌬ Diag  │              (route-dependent)                          │
│          │                                                         │
│  ── citizens (list) ───                                            │
│  ● relay         idle                                              │
│  ◐ summary       typing                                            │
│  ● dashboard     idle                                              │
│  ◐ scheduler     waiting                                           │
│                                                                    │
├──────────┴─────────────────────────────────────────────────────────┤
│ Babs v0.1.0 · node: laptop · uptime 4h22m · 12 A2A/min            │ ← Status bar (24px)
└────────────────────────────────────────────────────────────────────┘
```

**Header (40px tall, full width):**
- Left: Babs logomark (small purple `▌` glyph) + name in Inter 600
- Center-left: live status pills (counts of citizens by state)
- Center-right: command palette trigger (`⌘K`)
- Right: settings menu

**Sidebar (240px wide, collapsible to 60px on small screens):**
- Top: route navigation (Dashboard, Citizens, Ops, Diagram)
- Below: live citizen list with status dot + name + state label

**Main content area**: route-dependent, flexible width.

**Status bar (24px tall, full width):**
- Babs version, current node name, uptime, A2A throughput

---

## View 1 — Dashboard (`/`)

The home overview. A grid of citizen cards plus a recent-activity feed.

```
┌──── Citizens (4) ───────────────────────────────────────────────┐
│                                                                 │
│  ┌─ relay ────────┐  ┌─ summary ──────┐  ┌─ dashboard ────┐    │
│  │ ● idle         │  │ ◐ typing       │  │ ● idle         │    │
│  │                │  │                │  │                │    │
│  │ 23 msgs/h      │  │ 4 msgs/h       │  │ —              │    │
│  │ Discord, TG    │  │ Discord        │  │ Web only       │    │
│  │                │  │                │  │                │    │
│  │ last: 12s ago  │  │ last: 2s ago   │  │ last: idle 1h  │    │
│  └────────────────┘  └────────────────┘  └────────────────┘    │
│                                                                 │
│  ┌─ scheduler ────┐                                             │
│  │ ◐ waiting      │                                             │
│  │                │                                             │
│  │ —              │                                             │
│  │ A2A only       │                                             │
│  │                │                                             │
│  │ next: 5m       │                                             │
│  └────────────────┘                                             │
└─────────────────────────────────────────────────────────────────┘

┌──── Recent Activity ────────────────────────────────────────────┐
│ 14:23:02  relay        ← Discord #general "what's the weather?"│
│ 14:23:04  relay        → Discord #general "the weather is..."  │
│ 14:21:50  summary      ← A2A from relay  "summarize last 1h"   │
│ 14:21:53  summary      → A2A reply "summary: ..."              │
│ ...                                                             │
└─────────────────────────────────────────────────────────────────┘
```

**Citizen card** (~280px wide):
- Header row: status icon (◐/●/◯/✕) + citizen name in monospace + state label
- Stats row: messages-per-hour count + connectors badge list
- Footer row: timestamp of last activity (relative)
- Hover: subtle elevation + cyan border-emphasis
- Click: navigate to Citizen Detail

**Recent activity list**:
- One row per A2A or external message
- Columns: timestamp · citizen · direction arrow · summary
- Direction arrows: `←` inbound, `→` outbound, `⇄` A2A
- Truncate text after ~80 chars; full text on hover

---

## View 2 — Citizen Detail (`/citizens/:name`)

Per-citizen deep view. Three panels arranged left-to-right.

```
┌─ relay ─────────────────────────────────────────────────────────────┐
│ ● idle · Discord #general, #random · Telegram @relaybot             │
│ skills: respond, search, summarize · uptime 4h12m · A2A 23/h        │
├──────────────┬──────────────────────────┬───────────────────────────┤
│  Channels    │   Transcript             │   Terminal                │
│              │                          │                           │
│  ─ inbox ─   │   [user] hello           │  > _                      │
│  ⊙ Discord   │   [assistant] hi! how    │                           │
│   #general   │     can I help?          │                           │
│   #random    │   [tool_use] search(...) │  (xterm.js canvas         │
│              │   [tool_result] ...      │   filling the panel)      │
│  ⊙ Telegram  │                          │                           │
│   @relaybot  │   ▌                      │                           │
│              │                          │                           │
│  ─ A2A ─     │                          │                           │
│  ↪ summary   │                          │                           │
│  ↪ scheduler │                          │                           │
└──────────────┴──────────────────────────┴───────────────────────────┘
```

**Panel 1 — Channels (240px)**:
- Inbox section: Connector entries grouped by platform
- Each entry shows: platform icon + handle/channel name + small unread count if any
- A2A section: list of citizens this one delegates to / receives from

**Panel 2 — Transcript (flexible width, takes most space)**:
- Live-tailed from JSONL; renders user/assistant/tool_use/tool_result blocks
- Roles colored: user = primary text, assistant = primary purple `#a78bfa`, tool = secondary cyan, system = tertiary
- Monospace; 13px; soft line wrapping
- Auto-scroll to bottom unless user scrolled up (then a "Jump to live" pill appears)

**Panel 3 — Terminal (~400px or 40 cols)**:
- Live xterm.js view of the citizen's tmux pane
- Black background, faint border
- Header: `tmux: relay` label + cols×rows indicator
- Resizable handle on left edge

**Above the panels — status header bar**:
- Citizen name (large, monospace)
- Status pill + connectors + skills tags + uptime + A2A rate
- Action buttons (right-aligned): Restart, Compact, Send Message, Pause

---

## View 3 — Full Terminal (`/citizens/:name/terminal`)

Same as Citizen Detail's Panel 3, but full-width and full-height. xterm.js canvas filling the viewport minus a 24px top bar (citizen name + close button) and the global status bar.

For when the operator wants to actually drive the AI CLI like a normal terminal.

---

## View 4 — Ops (`/ops`)

System-level controls and metrics.

```
┌─ Cluster ─────────────────────────────────────────────────────────┐
│ Local node: laptop                       Active citizens: 4 / 4   │
│ Tailscale peers: 0                        Uptime: 4h 22m           │
│                                                                   │
│ ┌─ A2A Throughput ──────┐  ┌─ PTY Bytes ──────────┐               │
│ │   sparkline last 1h   │  │   sparkline last 1h  │               │
│ └───────────────────────┘  └──────────────────────┘               │
│                                                                   │
│ ┌─ Memory ──────────────┐  ┌─ Process Count ──────┐               │
│ │   sparkline           │  │   sparkline          │               │
│ └───────────────────────┘  └──────────────────────┘               │
└───────────────────────────────────────────────────────────────────┘

┌─ Citizen Controls ────────────────────────────────────────────────┐
│  relay      ● idle    [Restart] [Compact] [Send] [Logs] [Pane]   │
│  summary    ◐ typing  [Restart] [Compact] [Send] [Logs] [Pane]   │
│  dashboard  ● idle    [Restart] [Compact] [Send] [Logs] [Pane]   │
│  scheduler  ◐ waiting [Restart] [Compact] [Send] [Logs] [Pane]   │
└───────────────────────────────────────────────────────────────────┘

┌─ A2A Recent ──────────────────────────────────────────────────────┐
│ 14:23:02  relay → summary    "summarize last 1h"     200ms  ✓    │
│ 14:21:50  scheduler → relay  "ping"                   12ms  ✓    │
│ ...                                                               │
└───────────────────────────────────────────────────────────────────┘
```

**Cluster panel**: this node + Tailscale peers (when present) + four key sparkline metrics.
**Citizen Controls**: one row per citizen with action buttons; rows are dense.
**A2A Recent**: scrolling log of recent A2A calls with latency and success indicator.

---

## View 5 — Diagram (`/diagram`)

Excalidraw integration for whiteboard-style notes / planning. Embedded as a React component via LiveView hook. Babs side stores files; rendering is the Excalidraw library.

Visually: Excalidraw's own canvas, with the Babs sidebar still visible. Header shows: file name, last saved, save button, share-link button.

---

## Component Library

### Status Pill

```
┌──────────────┐
│ ● idle       │
└──────────────┘
```

- 8px solid status dot + space + label
- Background: `surface elevated` with 1px border in matching status color at 20% alpha
- Padding: 4px 10px
- Border-radius: 4px

### Citizen Card

(see Dashboard mockup above) — height ~120px, clickable, hover-elevated

### Action Button

- Default: icon + short label, secondary text color, 6px padding,
  hover→primary text
- Icon-only buttons are allowed only for dense repeated controls and must have
  an accessible label/tooltip
- Primary: filled with `Babs purple` accent, white text, used for confirmation actions
- Destructive: filled with status:error color, used for restart/kill

### Toast / Notification

Lower-right corner, max 3 stacked, auto-dismiss 4s for info / 8s for error. Each toast: status dot + title + body, with a manual close.

### Command Palette (`⌘K`)

Centered modal, 600px wide, dim backdrop. Search input on top; results below. Search is fuzzy across: citizen names, view names, action names, recent A2A targets. Navigable by keyboard (↑↓ + Enter).

### Empty States

- Empty Dashboard: "No citizens yet. Add one with `bb citizen add <name>` or via Ops."
- Empty Transcript: "No transcript yet. The citizen hasn't said anything since you've been watching."
- Empty A2A log: "No recent A2A activity."

All empty states use the `text tertiary` color and a small relevant icon.

---

## State Vocabulary

| State | When | Visual |
|---|---|---|
| `idle` | Citizen is alive, not processing | Green dot, `●` |
| `typing` | AI CLI is generating output | Amber dot, `◐` (animated half-fill) |
| `waiting` | Awaiting A2A response or scheduled tick | Blue dot, `◯` |
| `paused` | Operator-paused | Gray dot, `◌` |
| `dead` | Process crashed, supervisor restart pending | Red dot, `✕` |

These five states are exhaustive. Anything novel must be reduced to one of these or a new state must be added by ADR.

---

## Image-Generation Prompt Templates

Concrete prompts the operator can feed to DALL-E / Midjourney / Stable Diffusion for each view. Use these as starting points; iterate on specifics.

### Dashboard prompt

```
A dark-mode web application UI screenshot, operations console aesthetic.
Header bar at top showing "Babs" wordmark on the left in white sans-serif,
center-shows status pills "4 alive · 1 typing · 0 dead" in soft greens,
ambers, reds. Left sidebar 240px wide with navigation items "Dashboard,
Citizens, Ops, Diagram" and a list of citizens below with small status
dots. Main area shows a 3-column grid of citizen cards: each card has a
status icon, citizen name in monospace JetBrains Mono, message count,
connector badges (Discord, Telegram), and last-activity timestamp. Below
the grid is a "Recent Activity" log with timestamped rows. Color palette:
near-black background #0d0d10, surface panels #16161b, subtle borders,
white text, muted gray secondary text, soft purple accent #a78bfa for
active states. Inter font for UI, JetBrains Mono for citizen names.
High information density. No emojis. Operations console feel, not flashy.
```

### Citizen Detail prompt

```
A dark-mode web application showing a single AI agent's live state. Top
header shows citizen name "relay" in large monospace, status pill "idle"
with green dot, connector badges for Discord channels and Telegram. Three
panels below side-by-side: left "Channels" (240px) listing inbox sources;
center "Transcript" (flexible) showing colored chat messages — user in
warm white, assistant in soft purple #a78bfa, tool_use in cyan; right
"Terminal" (~400px) with a black-background xterm canvas showing a tmux
prompt and command output. Overall palette dark, near-black background
#0d0d10, panel surfaces slightly elevated #16161b, restrained accents.
JetBrains Mono for transcript and terminal, Inter sans for chrome. Dense
operations-console feel. No flashy graphics.
```

### Ops prompt

```
A dark-mode operations console showing cluster metrics. Top section
"Cluster" with sparkline charts: A2A Throughput, PTY Bytes, Memory,
Process Count — all in a 2x2 grid, lines in soft purple and cyan on
near-black background. Middle section "Citizen Controls" — a dense table
where each row is a citizen with status dot, name in monospace, state
label, and action buttons "Restart, Compact, Send, Logs, Pane".
Bottom section "A2A Recent" — log lines with timestamps, citizen names,
arrow direction, message preview, latency, and a success checkmark. Dark
palette #0d0d10 base, #16161b surfaces, white text on near-black, muted
secondary, purple #a78bfa accent on active items. Inter font UI, JetBrains
Mono for citizen names. Dense. Linear-app or Grafana aesthetic.
```

### Full Terminal prompt

```
A dark-mode full-screen terminal view of a tmux session running Claude
CLI. Top status bar shows "tmux: relay · 120×36" in monospace and a close
button on the right. The rest of the viewport is a black-background xterm
emulator with realistic ANSI-colored output: green prompt lines, yellow
warnings, default white text. Beneath, a 24px Babs status bar shows
version, node name, uptime, A2A throughput. Look feels like VS Code's
integrated terminal at full screen. JetBrains Mono throughout. Almost
purely terminal, with a thin chrome.
```

---

## Implementation Notes for Phase 4

(For BAB-2204 PRP — non-binding here, just hooks into the spec.)

- **LiveView modules**: `BabsWeb.DashboardLive`, `BabsWeb.CitizenLive`, `BabsWeb.OpsLive`, `BabsWeb.DiagramLive`
- **React components** (mounted via `phx-hook`): A2A graph viz on Ops view, Excalidraw embed on Diagram view, sparkline charts on Ops cluster panel
- **xterm.js**: bundled in `assets/`; mounted in Citizen Detail panel 3 and Full Terminal view; Channel topic `terminal:#{citizen_id}`
- **Tailwind config**: project's color palette mapped to Tailwind tokens (`bg-base`, `bg-surface`, `text-primary`, etc.) for consistency
- **No light theme in v1** — design only against dark; a light theme is a separate project if ever needed

---

## What This Spec Does NOT Define

- Mobile-responsive layouts (v1 is desktop-only; the operations console doesn't need a phone view)
- Onboarding flows / first-run experience (deferred until there's a "first run" — v1 assumes the operator already knows what they're doing)
- Multi-user / collaboration features (v1 is single-operator; permissions are out of scope)
- Localization (English-only v1)
- Accessibility audit (v1 should be keyboard-navigable and screen-reader-friendly by default LiveView/HTML semantics, but no formal WCAG conformance work is scheduled)

When any of these become real needs, file a PRP — they each warrant their own design pass, not a paragraph in this spec.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial version — visual identity, layouts for 5 views, component library, image-gen prompts | Claude Code |
| 2026-05-06 | Require semantic icons on action buttons, with accessible labels for icon-only dense controls | Codex |
