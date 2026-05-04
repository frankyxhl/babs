# REF-3001: Discussion Tracker 2026-05-04

**Applies to:** BAB project
**Last updated:** 2026-05-04
**Last reviewed:** 2026-05-04
**Status:** Active

---

## What Is It?

Per-day session tracker for BAB project per **COR-1201**. Records discussion
items raised within today's session(s), including the current Phase 0 spike
state and any deferred validation work.

`next_d` = **D4** (next new topic gets D4)

---

## Active Items

| ID | Topic | Status | Notes |
|----|-------|--------|-------|
| D1 | Phase 0 Hardline PTY spike execution | Deferred | `spikes/hardline/` created with automated validation harness and manual Phoenix Channel -> xterm.js page. `quick10` preflight passed automated checks in `results/run-2026-05-04-015953/SUMMARY.md`. Web duplicate-output issue was reproduced through Computer Use and fixed by removing duplicate PubSub subscription in `Hardline.Web.PaneChannel`; current Tailscale page shows `dup:0`. Defaults changed from bash to zsh (`/bin/zsh -f`) for future validation runs. Web terminal now auto-fits the browser viewport via xterm FitAddon and sends Channel `resize` events to `:exec.winsz/3`; current Chrome check showed `size:243x52`. Trinity-style review with GLM, Gemini, and DeepSeek found validation-hardening issues; accepted fixes landed and post-review smoke passed in `results/run-2026-05-04-035909/SUMMARY.md`. Local implementation/preflight closeout is complete. User deferred the official 24-hour+ full validation until they have time, so the official Phase 0 gate remains pending. |
| D2 | Phase 1 pre-implementation decisions | Done | User agreed to clarify docs before implementation. Decisions: Phase 1 reads TOML from `citizens/citizen-<slug>.toml`, not SQLite; SQLite starts in Phase 3. `SourceWatcher` becomes dev-only `Babs.DevReloader` in `:babs`, watching and restarting `:babs_citizens` from outside the target app. Channel topic and PubSub topic are both `pane:<slug>` in Phase 1, so Channels must not duplicate-subscribe with `Phoenix.PubSub.subscribe/2`. Reload/BEAM restart only detaches/re-attaches erlexec and never kills tmux; explicit `stop_citizen/1` is the kill path. Seed configs are `citizen-clare.toml` (`claude`), `citizen-dylan.toml` (`codex`), and deterministic `citizen-sentinel.toml` (`/bin/zsh`) for Gate A. Gate A should be repeatable as `mix babs.gate_a`; Gate B dogfoods Clare implementing Phase 2. |
| D3 | Phase 0a Hardline Manager Console | Done | User wants a browser UI, not CLI commands, to manage multiple hardline tmux sessions over Tailscale: list running Babs-managed sessions, create new sessions, click to switch xterm view, and stop selected sessions. Captured as `BAB-2202` Phase 0a. It is an optional usability spike on `spikes/hardline/`, not a substitute for the deferred Phase 0 official 24h+ full validation and not an automatic authorization to start Phase 1. Trinity rules review with GLM/Gemini/DeepSeek passed in `.trinity/reviews/20260504-142316-rules`; non-blocking terminology findings were accepted and patched. Implemented in `spikes/hardline/`; Tailscale API smoke and Computer Use browser smoke passed, including UI stop of `demo-c` while `demo-b` survived. Final Trinity code review on `spikes/hardline/` passed with GLM, Gemini, and DeepSeek in `.trinity/reviews/20260504-153847-spikes-hardline` after fixing review findings; latest `mise exec -- mix test` passed with 36 tests, 0 failures. Current manager URL is `http://100.x.y.z:4010/`. |
| D4 | Phase 0b Hardline Full-Window Mode | Done | User wanted one tmux hardline opened in a separate full-size browser window from the current manager at `http://100.x.y.z:4010/`. Captured as `BAB-2203` PRP and `BAB-2204` CHG. Trinity plan review with GLM/Gemini/DeepSeek passed in `.trinity/reviews/20260504-160652-phase0b-trinity-review-packet.md`; advisories were incorporated before implementation. Implemented browser-only `/?session=<slug>&full=1` mode in `spikes/hardline/priv/static/index.html`, with a single active-session `Open Full` control, full-viewport terminal CSS, invalid-session error overlay, back-to-manager link, status dots, lucide icons, generated fruit/character slug suggestions, and static regression tests. The manager Shell dropdown now defaults new browser-created sessions to tmux's own shell and keeps `/bin/zsh -f` selectable as a fallback; the custom command field was removed from the browser form for simplicity. Local `mix format --check-formatted` passed and `mix test` passed with 45 tests, 0 failures. Tailscale Chrome smoke passed at `http://100.x.y.z:4010/?session=demo-a&full=1`, showing a full-viewport terminal and live tmux size `243x53`. Tailscale API smoke created temporary `shell-smoke` with blank command, confirmed tmux selected `zsh` with empty `pane_start_command`, then stopped the temporary session. |

---

## Notes for Next Session

- Current browser validation URL while the detached server is running:
  `http://100.x.y.z:4010/`
- User-side quick check: paste `printf 'BABS_XTERM_OK\n'` and confirm it renders
  exactly once, with the status bar showing `dup:0`.
- Full official Phase 0 remains pending: run `mix hardline.validate --profile full`,
  complete the 30-minute browser check, then record CHG entries against
  `BAB-1103`, `BAB-1106`, and `BAB-1110`.
- Step 3/4/5 from the remaining-work list are marked deferred rather than done:
  no official complete `SUMMARY.md`, ADR CHG validation entries, or Phase 1 SEED
  start until the full run produces a pass/fail decision.
- Phase 1 SEED (`BAB-2201`) should not start until Phase 0 has an official
  full-run pass/fail decision.
- Current state is intentionally parked: local Phase 0 coding/preflight is
  complete, official Phase 0 validation is deferred.
- Trinity reviewers' explicit PubSub subscription finding was rejected: Phoenix
  Channels already subscribe joined topics, and explicit subscription caused the
  duplicate-output bug.
- Phase 1 docs were synchronized before implementation so `BAB-2201`,
  `BAB-1110`, `BAB-1106`, `BAB-1107`, `BAB-1112`, `BAB-1002`, and `BAB-2300`
  use the same TOML/slug/DevReloader/Clare-Dylan-Sentinel conventions.
- Optional Phase 0a is now tracked as `BAB-2202`: one browser manager console
  for multiple `babs-hardline-*` tmux sessions, including create/list/switch/stop.
- Phase 0a implementation is running at `http://100.x.y.z:4010/`.
  Existing managed smoke session: `demo-a`. It can be stopped from the UI when
  no longer needed.
- Phase 0b full-window mode can be opened as
  `http://100.x.y.z:4010/?session=demo-a&full=1` for an existing managed
  session, or via the manager's `Open Full` button.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-04 | Initial version | — |
| 2026-05-04 | Added D1 for Phase 0 Hardline execution, quick10 preflight status, Web duplicate-output fix, and deferred full-run notes | Codex |
| 2026-05-04 | Recorded zsh default workload switch and marked official Step 3/4/5 as deferred pending the future full run | Codex |
| 2026-05-04 | Added browser auto-fit resize path note for Channel -> xterm validation page | Codex |
| 2026-05-04 | Parked D1 as local implementation/preflight complete with official full validation deferred | Codex |
| 2026-05-04 | Recorded Trinity-style code review outcome and post-review validation hardening smoke run | Codex |
| 2026-05-04 | Added D2 Phase 1 pre-implementation decisions and noted related doc synchronization scope | Codex |
| 2026-05-04 | Added D3 and `BAB-2202` Phase 0a Hardline Manager Console proposal | Codex |
| 2026-05-04 | Recorded Trinity review pass for Phase 0a / rules diff and accepted non-blocking terminology fixes | Codex |
| 2026-05-04 | Marked D3 done after Phase 0a manager implementation, automated tests, Tailscale API smoke, and Computer Use browser smoke passed | Codex |
| 2026-05-04 | Recorded final Trinity GLM/Gemini/DeepSeek code-review approval for `spikes/hardline/` after post-review hardening and 36-test pass | Codex |
| 2026-05-04 | Added D4 Phase 0b full-window hardline mode, recorded Trinity plan review, implementation, and 39-test local validation | Codex |
| 2026-05-04 | Recorded Phase 0b Tailscale Chrome smoke for live `demo-a` full-window mode | Codex |
| 2026-05-04 | Added manager Shell dropdown so browser-created sessions use tmux default shell by default and `/bin/zsh -f` remains selectable | Codex |
| 2026-05-04 | Recorded live Tailscale shell-preset smoke and removed temporary `shell-smoke` session | Codex |
| 2026-05-04 | Refined Phase 0b manager UI with icon buttons, status dots, single active `Open Full`, and generated slug suggestions | Codex |
