# PRP-2203: Phase 0b — Hardline Full-Window Mode Spike

**Applies to:** BAB project
**Last updated:** 2026-05-04
**Last reviewed:** 2026-05-04
**Status:** Implemented
**Depends on:** `BAB-2202` Phase 0a Hardline Manager Console
**Does not replace:** `BAB-2200` official 24h+ full validation

---

## What Is It?

Phase 0b is a small usability spike on top of the Phase 0a browser manager:
open any managed tmux hardline in a separate browser tab or window where xterm.js
uses the full viewport.

It exists because the manager console is useful for creating, listing, and
stopping sessions, but a day-to-day terminal should sometimes feel like the old
single-pane page: no sidebar, no create form, no metadata grid, just the active
hardline filling the browser window.

---

## Problem

The Phase 0a manager uses a split layout:

- left sidebar: session list and create form
- right pane: toolbar, metadata grid, terminal, status bar

That is appropriate for session management, but it costs screen space when the
operator wants to work in one tmux session for a while, especially over Tailscale
from a remote browser.

---

## Proposed Solution

Add a browser-only full-window mode to `spikes/hardline/priv/static/index.html`.

The manager keeps its existing layout. The active-session toolbar exposes a
single `Open Full` action that opens:

```text
/?session=<slug>&full=1
```

In `full=1` mode:

- the page auto-selects the requested managed session
- the terminal occupies the full browser viewport
- sidebar, create form, metadata grid, toolbar buttons, and status bar are hidden
- the page still uses the same Phoenix Channel topic: `pane:<slug>`
- terminal resize still calls the existing Channel `resize` event and `:exec.winsz/3`
- refreshing the full-window tab reconnects to the same tmux session
- deep-linking to a missing session shows a visible full-window error instead
  of a blank terminal
- `Open Full` is disabled when the active session is reported as not alive
- a small back-to-manager affordance is available in full mode for error or
  escape handling

Known Phase 0b limitation: if multiple browser tabs are attached to the same
`pane:<slug>`, each tab can send resize events for its own viewport. Phase 0b
does not introduce primary-viewer ownership; backend arbitration is deferred to
Phase 1 or later if it proves necessary.

---

## Non-Goals

- No new tmux lifecycle semantics.
- No additional web server port.
- No production Babs UI work.
- No formal Playwright E2E suite in this phase.
- No replacement for Phase 0 official full validation.

---

## Implementation Plan

1. Add URL-mode parsing in the static manager page: `full=1` and `session=<slug>`.
2. Add CSS for full-window mode so `#terminal` fills `100vh`.
3. Add one active-toolbar `Open Full` button.
4. Auto-select the requested session after `/api/sessions` loads.
5. Preserve existing create/list/switch/stop behavior in normal manager mode.
6. Add lightweight regression tests that assert the static UI contains the full-mode contract.
7. Restart the running `hardline.web` server and smoke the full-window URL over Tailscale.

---

## Acceptance

This PRP is done when:

- The manager page still works at `http://100.x.y.z:4010/`.
- Clicking `Open Full` for a live managed slug opens a separate tab/window at
  `http://100.x.y.z:4010/?session=<slug>&full=1`.
- The full-window page auto-connects to `pane:<slug>` without creating a new
  tmux session.
- In full-window mode, the terminal fills the browser viewport and the manager
  sidebar/metadata/status controls are hidden.
- Browser refresh reconnects to the same managed tmux session.
- `/?session=nosuch&full=1` shows a visible error and does not silently remain
  blank.
- `/?full=1` without `session` falls back to normal manager mode.
- The session list shows alive/dead state with a status dot rather than text.
- `Open Full` is disabled when the active session is not alive.
- Full-window CSS overrides the manager body grid so the terminal reaches all
  four viewport edges with no manager chrome.
- `mix format --check-formatted` and `mix test` pass in `spikes/hardline/`.

---

## Implementation Result (2026-05-04)

Phase 0b is implemented in `spikes/hardline/priv/static/index.html`.

Validation evidence:

- Trinity plan review with GLM, Gemini, and DeepSeek passed in
  `.trinity/reviews/20260504-160652-phase0b-trinity-review-packet.md`
- `mise exec -- mix format --check-formatted` passed
- `mise exec -- mix test` passed: 45 tests, 0 failures
- Static regression tests cover the full-window URL contract, manager-launched
  `Open Full` control, disabled dead-session behavior, full-mode CSS hooks,
  invalid-session error affordances, icon usage, status dots, shell presets,
  and generated slug suggestions
- The manager create form now offers a Shell dropdown: `Default tmux shell`
  omits the tmux command so the first window behaves like later tmux-created
  windows, while `/bin/zsh -f` remains available as a fast-shell fallback
- The manager create form now pre-fills an unused fruit/character slug and
  exposes a shuffle button to suggest another slug without typing
- Running Tailscale API smoke created temporary `shell-smoke` with blank
  command; tmux reported `pane_current_command=zsh` and empty
  `pane_start_command`, confirming tmux selected its own default shell. The
  temporary smoke session was stopped afterward.
- Running Tailscale server smoke passed at
  `http://100.x.y.z:4010/?session=demo-a&full=1`; Chrome rendered the
  terminal as the full browser content area with only the `Manager` back link
  visible, and tmux resized the live zsh pane to `243x53`
- `git diff --check` and `af validate` passed

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-04 | Initial draft: separate full-window browser mode for one managed hardline session | Codex |
| 2026-05-04 | Incorporated Trinity plan-review advisories: invalid-session handling, disabled dead-session full links, row event propagation, full-body CSS override, back-to-manager affordance, and resize-contention limitation | Codex |
| 2026-05-04 | Implemented Phase 0b full-window mode and added static regression coverage; local format/test passed with 39 tests | Codex |
| 2026-05-04 | Recorded Tailscale Chrome smoke for `demo-a` full-window mode and final repository validation checks | Codex |
| 2026-05-04 | Added manager Shell dropdown so new browser sessions default to tmux's own shell while preserving `/bin/zsh -f` fallback; local tests passed with 43 tests | Codex |
| 2026-05-04 | Recorded live Tailscale API smoke proving blank-command sessions let tmux choose the first-window shell | Codex |
| 2026-05-04 | Refined manager UI: icon buttons, single active `Open Full`, status dots, no custom command field, and generated slug suggestions; local tests passed with 45 tests | Codex |
