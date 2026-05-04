# CHG-2204: Phase 0b Hardline Full-Window Mode

**Applies to:** BAB project
**Last updated:** 2026-05-04
**Last reviewed:** 2026-05-04
**Status:** Completed
**Related:** `BAB-2203`, `BAB-2202`, `BAB-2200`

---

## What

Add a full-window browser mode to the Phase 0a Hardline manager spike.

The normal manager remains at:

```text
http://100.x.y.z:4010/
```

The new full-window mode opens one existing managed session at:

```text
http://100.x.y.z:4010/?session=<slug>&full=1
```

---

## Why

The Phase 0a manager is good for lifecycle operations, but its sidebar,
metadata grid, and status bar consume space when the operator wants to work in a
single tmux session. The user specifically asked for the previous single-pane
feel: a separate browser window with one tmux hardline at full size.

---

## Impact

Expected impact:

- adds browser-only mode selection in `spikes/hardline/priv/static/index.html`
- adds a single active-session `Open Full` control in the manager UI
- preserves existing API, Channel topics, tmux session naming, and stop semantics
- no production Babs code changes
- no official Phase 0 validation-gate change

Risk:

- browser layout regression in manager mode
- full-window URL may fail to select the requested session if session loading and
  URL parsing are not sequenced carefully
- multiple browser tabs attached to the same tmux session will share the same
  underlying pane stream, which is already allowed by Phase 0a

---

## Plan

1. Review `BAB-2203` and this CHG with Trinity GLM, Gemini, and DeepSeek before implementation.
2. Add full-mode URL parsing: `full=1` and `session=<slug>`.
3. Add CSS class/state to hide manager chrome and make `#terminal` fill the viewport.
4. Add an active-session `Open Full` button that calls
   `window.open(fullUrl(slug), "_blank")`.
5. Auto-select the requested session after `/api/sessions` loads.
6. Add visible handling for `full=1` invalid-session links and fall back to
   manager mode when `full=1` has no `session`.
7. Disable `Open Full` for dead active sessions and show session alive/dead
   state with a status dot.
8. Keep resize ownership unchanged; document simultaneous-tab resize contention
   as a Phase 0b limitation rather than adding backend arbitration.
9. Add static regression tests for the URL contract and full-mode UI hooks.
10. Run `mix format --check-formatted`, `mix test`, `git diff --check`, and `af validate`.
11. Restart the running hardline web server and smoke
    `/?session=<live-slug>&full=1`.

---

## Approval

Trinity plan review passed with GLM, Gemini, and DeepSeek in
`.trinity/reviews/20260504-160652-phase0b-trinity-review-packet.md`.
Advisory findings were incorporated into the PRP and implementation plan before
coding.

---

## Result

Implemented in `spikes/hardline/priv/static/index.html`.

Outcome:

- normal manager mode remains the default at `/`
- the active-session `Open Full` control launches `/?session=<slug>&full=1`
- full mode auto-selects the requested existing session after `/api/sessions`
  loads
- full mode hides manager chrome and makes xterm.js fill the browser viewport
- missing-session links show a visible full-window error with a back-to-manager
  affordance
- dead sessions cannot be opened in full mode from the manager UI
- new manager sessions default to tmux's own default shell through a Shell
  dropdown, with `/bin/zsh -f` preserved as an explicit fallback option
- the create form pre-fills an unused fruit/character slug and offers a shuffle
  button for another suggestion
- action buttons use lucide icons; the session list uses green/red status dots
- static regression tests added in
  `spikes/hardline/test/hardline/web/index_html_test.exs`

Validation:

- `mise exec -- mix format --check-formatted` passed
- `mise exec -- mix test` passed: 45 tests, 0 failures
- Tailscale browser smoke passed at
  `http://100.x.y.z:4010/?session=demo-a&full=1`; Chrome showed the
  full-viewport terminal with only the `Manager` back link, and tmux reported
  the live zsh pane at `243x53`
- Tailscale API smoke created temporary `shell-smoke` with blank command; tmux
  reported `pane_current_command=zsh` and empty `pane_start_command`, proving
  tmux chose the first-window shell. The temporary session was stopped afterward.
- `git diff --check` passed
- `af validate` passed

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-04 | Initial proposed CHG for Phase 0b full-window hardline mode | Codex |
| 2026-05-04 | Recorded Trinity GLM/Gemini/DeepSeek plan-review approval and incorporated advisories before implementation | Codex |
| 2026-05-04 | Marked implemented after full-window UI mode and static regression tests passed local validation | Codex |
| 2026-05-04 | Recorded Tailscale full-window browser smoke and final validation commands | Codex |
| 2026-05-04 | Added manager Shell dropdown to use tmux default shell by default while keeping `/bin/zsh -f` selectable | Codex |
| 2026-05-04 | Recorded live blank-command API smoke for tmux-default first-window shell behavior | Codex |
| 2026-05-04 | Refined manager UI with icons, status dots, single active `Open Full`, removed custom command field, and generated slug suggestions | Codex |
