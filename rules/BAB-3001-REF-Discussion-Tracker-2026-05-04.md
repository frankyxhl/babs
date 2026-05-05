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

`next_d` = **D9** (next new topic gets D9)

---

## Active Items

| ID | Topic | Status | Notes |
|----|-------|--------|-------|
| D1 | Phase 0 Hardline PTY spike execution | Deferred | `spikes/hardline/` created with automated validation harness and manual Phoenix Channel -> xterm.js page. `quick10` preflight passed automated checks in `results/run-2026-05-04-015953/SUMMARY.md`. Web duplicate-output issue was reproduced through Computer Use and fixed by removing duplicate PubSub subscription in `Hardline.Web.PaneChannel`; current Tailscale page shows `dup:0`. Defaults changed from bash to zsh (`/bin/zsh -f`) for future validation runs. Web terminal now auto-fits the browser viewport via xterm FitAddon and sends Channel `resize` events to `:exec.winsz/3`; current Chrome check showed `size:243x52`. Trinity-style review with GLM, Gemini, and DeepSeek found validation-hardening issues; accepted fixes landed and post-review smoke passed in `results/run-2026-05-04-035909/SUMMARY.md`. Local implementation/preflight closeout is complete. User deferred the official 24-hour+ full validation until they have time, so the official Phase 0 gate remains pending. |
| D2 | Phase 1 pre-implementation decisions | Done | User agreed to clarify docs before implementation. Decisions: Phase 1 reads TOML from `citizens/citizen-<slug>.toml`, not SQLite; SQLite starts in Phase 3. `SourceWatcher` becomes dev-only `Babs.DevReloader` in `:babs`, watching and restarting `:babs_citizens` from outside the target app. Channel topic and PubSub topic are both `pane:<slug>` in Phase 1, so Channels must not duplicate-subscribe with `Phoenix.PubSub.subscribe/2`. Reload/BEAM restart only detaches/re-attaches erlexec and never kills tmux; explicit `stop_citizen/1` is the kill path. Seed configs are `citizen-clare.toml` (`claude`), `citizen-dylan.toml` (`codex`), and deterministic `citizen-sentinel.toml` (`/bin/zsh`) for Gate A. Gate A should be repeatable as `mix babs.gate_a`; Gate B dogfoods Clare implementing Phase 2. |
| D3 | Phase 0a Hardline Manager Console | Done | User wants a browser UI, not CLI commands, to manage multiple hardline tmux sessions over Tailscale: list running Babs-managed sessions, create new sessions, click to switch xterm view, and stop selected sessions. Captured as `BAB-2202` Phase 0a. It is an optional usability spike on `spikes/hardline/`, not a substitute for the deferred Phase 0 official 24h+ full validation and not an automatic authorization to start Phase 1. Trinity rules review with GLM/Gemini/DeepSeek passed in `.trinity/reviews/20260504-142316-rules`; non-blocking terminology findings were accepted and patched. Implemented in `spikes/hardline/`; Tailscale API smoke and Computer Use browser smoke passed, including UI stop of `demo-c` while `demo-b` survived. Final Trinity code review on `spikes/hardline/` passed with GLM, Gemini, and DeepSeek in `.trinity/reviews/20260504-153847-spikes-hardline` after fixing review findings; latest `mise exec -- mix test` passed with 36 tests, 0 failures. Current manager URL is `http://100.x.y.z:4010/`. |
| D4 | Phase 0b Hardline Full-Window Mode | Done | User wanted one tmux hardline opened in a separate full-size browser window from the current manager at `http://100.x.y.z:4010/`. Captured as `BAB-2203` PRP and `BAB-2204` CHG. Trinity plan review with GLM/Gemini/DeepSeek passed in `.trinity/reviews/20260504-160652-phase0b-trinity-review-packet.md`; advisories were incorporated before implementation. Implemented browser-only `/?session=<slug>&full=1` mode in `spikes/hardline/priv/static/index.html`, with a single active-session `Open Full` control, full-viewport terminal CSS, invalid-session error overlay, back-to-manager link, status dots, lucide icons, generated fruit/character slug suggestions, and static regression tests. The manager Shell dropdown now defaults new browser-created sessions to tmux's own shell and keeps `/bin/zsh -f` selectable as a fallback; the custom command field was removed from the browser form for simplicity. Local `mix format --check-formatted` passed and `mix test` passed with 45 tests, 0 failures. Tailscale Chrome smoke passed at `http://100.x.y.z:4010/?session=demo-a&full=1`, showing a full-viewport terminal and live tmux size `243x53`. Tailscale API smoke created temporary `shell-smoke` with blank command, confirmed tmux selected `zsh` with empty `pane_start_command`, then stopped the temporary session. |
| D5 | Phase 0c Hardline Browser Test Harness | Done | User flagged that `index.html` had too much inline JavaScript and asked to improve BDD/E2E coverage. Captured as `BAB-2205` PRP and `BAB-2206` CHG. Implemented as a testing/refactor-only phase: manager browser logic moved into `priv/static/js/hardline_core.js`, `hardline_manager.js`, and `hardline_boot.js`; stable `data-testid` hooks were added; Node pure-JS tests and Playwright DOM/E2E tests cover create/select/type/full/refresh/stop/missing-session workflows with isolated `babs-e2e-*` tmux prefixes. Local validation passed: `npm run test:js` 9 tests, `npm run test:e2e` 10 Playwright tests, and `mise exec -- mix test` 59 tests. No new UI features and no Phase 0 official validation gate change. |
| D6 | Phase 1 readiness document sync | Done | User cannot run the official 24-hour Phase 0 validation now, so Phase 1 production code remains blocked, but safe prep continued. The previously discussed Phase 1 decisions were applied to the authoritative docs: Clare/Dylan/Sentinel replace Alex/Morgan; Phase 1 reads `citizens/citizen-<slug>.toml` and uses configured `workspaces/<slug>/`; SQLite remains Phase 3 authority; `Babs.DevReloader` lives in `:babs` outside the `:babs_citizens` target app; Channel/PubSub topic is `pane:<slug>` and Channels must not duplicate-subscribe; reload/BEAM restart detach and reattach only, while explicit stop is the tmux kill path. No Phase 1 implementation was started. |
| D7 | Phase 2 local web server session | Active | For user validation of the Phase 2 branch, Phoenix is run from `/Users/frank/Projects/babs-phase2-reconcile` inside detached tmux session `babs-phase2-web` with `BABS_HTTP_IP=0.0.0.0 mise exec -- mix phx.server`. It listens on `*:4000` and is reachable locally at `http://127.0.0.1:4000/citizens/sentinel` or over Tailscale as `http://100.x.y.z:4000/citizens/sentinel` while the tmux session is alive. Check it with `tmux capture-pane -pt babs-phase2-web`, `lsof -nP -iTCP:4000 -sTCP:LISTEN`, and `curl -I http://127.0.0.1:4000/citizens/sentinel`. Stop it with `tmux kill-session -t babs-phase2-web` when no longer needed. Do not record real Tailscale IPs in public docs or PRs. |
| D8 | Configurable Citizen workspace root | Proposed | User does not want durable Citizen workspaces implicitly stored under whichever repo/worktree path launched Babs, because that makes test, phase, and production state ambiguous. Captured as `BAB-2209` Phase 2a PRP: add `BABS_WORKSPACE_ROOT` / `:babs_citizens, :workspace_root`, resolve relative citizen `cwd` values under that root, migrate seeds to `cwd = "<slug>"`, preserve absolute `cwd` overrides, and keep `citizens/citizen-<slug>.toml` lookup rooted at `BABS_ROOT` / `config_dir`. No implementation started. Public docs intentionally use placeholders rather than real local filesystem paths. |

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
- Optional Phase 0c is complete as `BAB-2205`/`BAB-2206`: testing and
  refactoring only, with JavaScript extraction, JS/DOM tests, and Playwright
  BDD-style E2E coverage. It does not replace the official Phase 0 full-run
  validation gate.
- Phase 1 readiness docs are synchronized for later implementation, but
  production Phase 1 code remains blocked until the official Phase 0 gate is
  resolved or explicitly waived in a future decision.
- Phase 2 PR validation server is currently managed by detached tmux session
  `babs-phase2-web`, started from `/Users/frank/Projects/babs-phase2-reconcile`
  with `BABS_HTTP_IP=0.0.0.0 mise exec -- mix phx.server`.
  Use `tmux capture-pane -pt babs-phase2-web` to inspect logs and
  `tmux kill-session -t babs-phase2-web` to stop it.
- Configurable workspace root is now captured as `BAB-2209` Phase 2a PRP for
  future implementation. Do not implement it until the PRP is reviewed/accepted.

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
| 2026-05-04 | Added D5 and `BAB-2205`/`BAB-2206` proposed Phase 0c browser test harness plan | Codex |
| 2026-05-04 | Marked D5 done after Phase 0c JS extraction, Node pure-JS tests, Playwright DOM/E2E tests, and 59-test ExUnit validation passed | Codex |
| 2026-05-04 | Added D6 Phase 1 readiness document sync and reiterated that Phase 1 implementation remains blocked by the deferred official Phase 0 gate | Codex |
| 2026-05-05 | Added D7 for the Phase 2 detached tmux web-server session and safe Tailscale validation notes without recording real private IPs | Codex |
| 2026-05-05 | Added D8 and `BAB-2209` draft PRP for configurable Citizen workspace root | Codex |
