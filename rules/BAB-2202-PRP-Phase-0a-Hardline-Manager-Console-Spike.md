# PRP-2202: Phase 0a — Hardline Manager Console Spike

**Applies to:** BAB project
**Last updated:** 2026-05-04
**Last reviewed:** 2026-05-04
**Status:** Implemented
**Depends on:** `BAB-2200` Phase 0 spike implementation/preflight
**Does not replace:** `BAB-2200` official 24h+ full validation

---

## What Is It?

Phase 0a is a usability spike on top of `spikes/hardline/`: a single browser console that can create, list, switch between, and explicitly stop multiple Babs-managed tmux-backed hardlines.

It exists because the Phase 0 web page proved the byte path, but operating it through one CLI process per tmux session is awkward over Tailscale. The console lets the operator manage hardline sessions from the browser before Phase 1 production Babs exists.

---

## Problem

The current Phase 0 web runner is one-process / one-pane:

- `mix hardline.web --port 4010 --session <name>` creates one tmux session at startup
- browser refresh reconnects to that same session
- creating a second session requires another CLI command and another port
- listing and closing sessions requires manual `tmux` commands

This is acceptable for a validation spike, but it is inconvenient enough that it slows iteration and hides useful product requirements for Phase 1/4.

---

## Proposed Solution

Upgrade `Hardline.Web` into a small manager console while keeping it inside the isolated `spikes/hardline/` sub-project.

### Scope

One web server, usually:

```sh
mix hardline.web --host 100.x.y.z --port 4010
```

The browser UI provides:

- Session list for Babs-managed tmux sessions only
- Create session form: `slug`, optional command, default `/bin/zsh -f`
- Click-to-switch terminal view
- Explicit stop button with confirmation
- Visible metadata: tmux session name, tmux session ID, pane PID, command, connection state

### Naming and Safety

- Manager-created sessions use prefix `babs-hardline-<slug>`.
- The manager may reattach/list/kill only sessions matching that prefix.
- It MUST NOT list or kill operator-owned tmux sessions, including ordinary sessions and the tmux session running the web server itself.
- Browser refresh must not create or stop tmux sessions.
- `Hardline.Web.PaneServer.terminate/2` continues to detach only; UI stop is the only web path that calls `tmux kill-session`.

### Data Flow

- `Hardline.Web.Manager` owns the session registry and tmux lifecycle calls.
- Each active hardline has one `Hardline.Web.PaneServer`, which attaches to the tmux session and publishes bytes to `pane:<slug>`.
- The browser joins one pane topic at a time. Switching panes leaves the previous topic and joins the selected topic.
- Optional but preferred: on switch, use `tmux capture-pane` to replay the last visible screen so the terminal does not appear blank until new bytes arrive.

### Non-Goals

- No production `:babs` / `:babs_citizens` umbrella work.
- No SQLite, TOML citizen config, or transcript persistence.
- No multi-user auth beyond current Tailscale/local network assumptions.
- No replacement for the Phase 0 official full validation run.

---

## Implementation Plan

1. Add `Hardline.Web.Manager` GenServer to track Babs-managed sessions and supervise/stop `PaneServer` instances.
2. Add tmux helpers in `Hardline.Runner` for prefixed listing, session metadata, explicit kill, and optional `capture-pane`.
3. Replace the static single-pane index with a manager UI: session list, create form, terminal view, stop button, status bar.
4. Add HTTP or Channel control API for `list`, `create`, `select`, and `stop`; keep terminal bytes on `pane:<slug>`.
5. On web server startup, scan existing `babs-hardline-*` tmux sessions and reattach them without creating duplicates.
6. Add tests for slug validation, prefixed-only kill behavior, startup reattach, and refresh/no-new-session behavior.
7. Run browser smoke over Tailscale: create two sessions, switch between them, refresh browser, stop one, verify the other survives.

---

## Acceptance

This PRP is done when:

- Starting `mix hardline.web --host 100.x.y.z --port 4010` opens a manager console at `http://100.x.y.z:4010/`
- Creating `demo-a` and `demo-b` from the browser creates tmux sessions `babs-hardline-demo-a` and `babs-hardline-demo-b`
- Clicking between `demo-a` and `demo-b` switches the xterm.js view without creating new tmux sessions
- Browser refresh preserves the session list and reconnects without changing tmux session ID or pane PID
- Stop kills only the selected `babs-hardline-*` tmux session and removes it from the list
- An unmanaged tmux session remains invisible to the UI and cannot be killed by the manager
- Restarting the web server reattaches existing `babs-hardline-*` sessions without duplicate tmux creation
- `mix test` and `mix format --check-formatted` pass in `spikes/hardline/`

### Implementation Result (2026-05-04)

Phase 0a is implemented in `spikes/hardline/`.

Validation evidence:

- `mise exec -- mix format --check-formatted` passed
- `mise exec -- mix test` passed: 36 tests, 0 failures after post-review hardening
- Tailscale web server restarted at `http://100.x.y.z:4010/`
- HTTP smoke created `babs-hardline-demo-a` and `babs-hardline-demo-b`
- stop smoke killed only `babs-hardline-demo-a`; `babs-hardline-demo-b` and unmanaged `babs-web-test-1777867192` stayed alive
- web-server restart reattached `babs-hardline-demo-b` with unchanged tmux session `$215` and pane PID `17125`
- Computer Use browser smoke confirmed the manager UI loads, lists sessions, switches to `demo-b`, creates `demo-c`, connects xterm.js with `dup:0`, and stops `demo-c` through the UI while `demo-b` survives
- Trinity code review with GLM, Gemini, and DeepSeek passed on `spikes/hardline/` in `.trinity/reviews/20260504-153847-spikes-hardline`; earlier blocking findings were fixed before final approval

---

## Open Questions

- **Default prefix**: use `babs-hardline-` for clarity, or reuse the current `babs-web-` prefix? Default: `babs-hardline-`.
- **Default command**: keep `/bin/zsh -f` for deterministic shell sessions, or allow a dropdown for `zsh`, `claude`, `codex`? Default: start with freeform command defaulting to `/bin/zsh -f`.
- **Screen replay on switch**: implement `tmux capture-pane` in Phase 0a or defer until Phase 2 transcript persistence? Default: implement capture-pane because it materially improves switching usability.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-04 | Initial draft: browser-managed multi-hardline console for Phase 0a; one web port, multiple Babs-managed tmux sessions, create/list/switch/stop from browser | Codex |
| 2026-05-04 | Implemented Phase 0a in `spikes/hardline/`; added manager backend/API/UI, tests, Tailscale smoke, browser smoke, and validation evidence | Codex |
| 2026-05-04 | Recorded final Trinity GLM/Gemini/DeepSeek code-review approval after post-review hardening and 36-test pass | Codex |
