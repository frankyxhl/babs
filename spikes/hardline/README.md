# Hardline Phase 0 Spike

This sub-project validates the Phase 0 PTY substrate for Babs.

It is intentionally isolated from the future production umbrella. The first
goal is to verify that `erlexec` can build and that the tmux attach path can be
tested under RED/GREEN/REFACTOR before the long-running empirical scenarios.

## Current Status

The harness now has:

- `mix hardline.validate` for automated tmux / erlexec scenarios
- `mix hardline.web` for the Phase 0a browser Hardline manager console and
  manual Phoenix Channel -> xterm.js byte-path check
- `npm run test:browser` for the Phase 0c JavaScript, DOM, and Playwright E2E
  browser harness
- per-run artifacts under `results/run-YYYY-MM-DD-HHMMSS/`

Local closeout status: implementation and short-run preflight are complete.
The official Phase 0 validation gate remains deferred until the future full
long run produces a pass/fail decision.

The short smoke profile is only a harness check. It does **not** satisfy
`BAB-1502`; the official Phase 0 decision requires the full profile plus the
manual browser validation.

The latest local preflight is:

- `results/run-2026-05-04-015953/SUMMARY.md`
- profile: `quick10`
- automated result: provision, soak, chaos, resize, slow-reader, and
  detach/reattach all passed
- status: `INCOMPLETE`, intentionally, because the official long run and
  30-minute manual browser confirmation are still pending

After switching the default workload shell from bash to zsh, a smoke run also
passed:

- `results/run-2026-05-04-033741/SUMMARY.md`
- profile: `smoke`
- default workload shell recorded in the handoff notes: `/bin/zsh -f`

After the Trinity review hardening pass, another smoke run passed:

- `results/run-2026-05-04-035909/SUMMARY.md`
- profile: `smoke`
- automated result: provision, soak, chaos, resize, slow-reader, and
  detach/reattach all passed under stricter pass/fail checks
- status: `INCOMPLETE`, intentionally, because the official long run and
  30-minute manual browser confirmation are still pending

Phase 0a manager-console work is complete in this spike. Official Phase 0 Step
3/4/5 are still deferred, not complete: no final full-run `SUMMARY.md`, ADR
validation CHG entries, or Phase 1 SEED start until the future full run
produces a pass/fail decision.

Phase 0b full-window mode is also implemented. From the manager, click
`Open Full` for a managed session, or open a URL directly:

```text
http://100.x.y.z:4010/?session=<slug>&full=1
```

Full-window mode is browser-only. It reuses the existing `pane:<slug>` Channel,
does not create or stop tmux sessions, and keeps resize events on the existing
`:exec.winsz/3` path.

Current Tailscale smoke passed at
`http://100.x.y.z:4010/?session=demo-a&full=1`; Chrome rendered the terminal
as the full browser content area with only the `Manager` back link visible, and
tmux reported the live zsh pane at `243x53`.

Shell-preset smoke also passed: a temporary `shell-smoke` session created with
blank command reported `pane_current_command=zsh` and empty
`pane_start_command`, proving tmux selected its own first-window shell. The
temporary smoke session was stopped afterward.

Phase 0c browser test-hardening work is complete. The manager JavaScript now
lives in static ES modules under `priv/static/js/`; `index.html` keeps the HTML,
CSS, CDN libraries, and module boot script. Local browser validation added pure
JavaScript tests plus Playwright DOM/E2E coverage for create, select, type,
full-window, refresh, stop, and missing-session workflows. This is still an
optional testing/refactor phase and does not complete the official Phase 0
24-hour validation gate.

## Current Toolchain

- Erlang/OTP 28.5 via the repository `.mise.toml`
- Elixir 1.19.5-otp-28 via the repository `.mise.toml`
- tmux 3.6a
- erlexec locked at 2.3.0 by `mix.lock`
- Node.js 25.x for the Phase 0c browser test harness
- Playwright 1.59.x using local Google Chrome by default
- default automated validation workload shell: `/bin/zsh -f`
- default browser-created manager session shell: tmux default shell

`BAB-2200` notes that `erlexec ~> 2.3` did not exist when the PRP was drafted.
Hex now reports `erlexec 2.3.0` as published on 2026-04-23, so this spike is
validating the currently resolved package rather than the older 2.2 line.

## Commands

From this directory:

```sh
mise exec -- mix deps.get
mise exec -- mix compile
mise exec -- mix test
```

Browser test harness:

```sh
npm install
npm run test:js
npm run test:e2e
```

`npm run test:browser` runs both browser layers. `test:e2e` starts
`mix hardline.web` on `127.0.0.1:4110` by default with a unique
`babs-e2e-*` tmux prefix, creates only temporary managed sessions under that
prefix, and cleans them up after the run. Override the defaults only for local
port conflicts or browser availability:

```sh
HARDLINE_E2E_PORT=4111 npm run test:e2e
HARDLINE_E2E_CHANNEL=managed npm run test:e2e
```

`HARDLINE_E2E_CHANNEL=managed` omits the explicit Chrome channel and uses
Playwright's managed Chromium installation.

Short smoke run:

```sh
mise exec -- mix hardline.validate --profile smoke
```

This should finish in under a minute and produce an `INCOMPLETE` summary because
the browser check is intentionally manual.

By default the automated validation starts an interactive zsh shell with a
background `BABS_TICK` loop so the PTY has steady output while still accepting
input. Override it only for targeted checks:

```sh
mise exec -- mix hardline.validate --profile smoke --command "/bin/zsh -f"
```

10-minute preflight:

```sh
mise exec -- mix hardline.validate --profile quick10
```

This runs the same scenario categories as the full profile, but compressed to
about 10 minutes with two tmux sessions. Treat it as a confidence check before
committing to the official long run, not as a Phase 0 pass.

Phase 0a Hardline manager console:

```sh
mise exec -- mix hardline.web --port 4010
```

For Tailscale access from another machine, bind to this host's Tailscale IP:

```sh
mise exec -- mix hardline.web --host 100.x.y.z --port 4010
```

Open `http://localhost:4010/` for local access, or
`http://100.x.y.z:4010/` when bound to a Tailscale IP.

The page is a browser manager for Babs-managed tmux sessions:

- create a session with a slug such as `demo-a`
- the tmux session name becomes `babs-hardline-demo-a`
- the slug field is prefilled with an unused fruit/character suggestion, and
  the shuffle button suggests another slug
- the Shell dropdown defaults to tmux's own default shell, matching new tmux
  windows; `/bin/zsh -f` remains available when a minimal shell is useful
- create more sessions and click the left-side list to switch terminals
- stop a selected session with the Stop button
- browser refresh must not create a new tmux session or change the selected
  tmux session ID / pane PID

Only sessions with prefix `babs-hardline-` are managed by the UI. Ordinary tmux
sessions and the `hardline-web-server` tmux session are intentionally invisible
to the manager.

For each selected session, type into the terminal and confirm:

- the terminal grid fits the current browser viewport and the status bar's
  `size:` value changes when the browser is resized
- shell output renders in xterm.js
- input reaches the tmux-backed shell
- ANSI/cursor behavior looks sane for 30 minutes
- browser reload reconnects within about 2 seconds
- the status bar keeps `dup:0` while typing and pasting

The page uses `@xterm/xterm@5.5.0`, `@xterm/addon-fit@0.10.0`, and
`phoenix@1.8.5` from jsDelivr. If CDN access is unavailable, vendor those
assets before running the official browser check.

Quick manual browser preflight after creating/selecting a session:

```sh
printf 'BABS_XTERM_OK\n'
echo OK
```

Each command should render once. If characters or output duplicate, check the
status bar's `dup:` counter; any value above zero means the browser received a
duplicate output event and the Channel/PubSub path needs investigation before
the official run.

When validating through Tailscale on this machine, the current pattern is:

```sh
tmux new-session -d -s hardline-web-server \
  'cd /Users/frank/Projects/babs/spikes/hardline && mise exec -- mix hardline.web --host 100.x.y.z --port 4010'
```

Then open `http://100.x.y.z:4010/` from the remote browser. Stop it with:

```sh
tmux kill-session -t hardline-web-server
```

Official long validation:

```sh
mise exec -- mix hardline.validate --profile full
```

Run this form if the browser check has not been completed yet; the generated
`SUMMARY.md` will remain `INCOMPLETE` until Web is confirmed.

For the official pass/fail artifact, complete the browser check separately for
the required 30 minutes first, then use the operator confirmation flag so the
generated `SUMMARY.md` records a complete decision:

```sh
mise exec -- mix hardline.validate --profile full --web-confirmed
```

The full profile runs:

- 5 tmux sessions
- 24-hour steady-state soak
- 12-hour chaos phase with intentional erlexec port kills
- 1-hour resize storm using `:exec.winsz/3`
- 1-hour slow-reader simulation
- 3 detach/reattach runs

## Reading Results

Each run writes:

- `events.log` — timestamped observer log
- `SUMMARY.md` — scenario table, results, and Phase 1 handoff notes

Phase 0 is not complete until a full run's `SUMMARY.md` exists and CHG entries
are added to `BAB-1103`, `BAB-1106`, and `BAB-1110`.

## Post-Review Hardening

A Trinity-style review was run with GLM, Gemini, and DeepSeek reviewers after
local closeout. The actionable fixes landed in the harness:

- Web `PaneServer` termination detaches erlexec but no longer kills the tmux
  session; tmux cleanup is explicit.
- `Runner.collect_until/3` preserves unrelated mailbox messages instead of
  discarding them.
- bidirectional sentinel checks split the generated output token so shell echo
  cannot satisfy the proof.
- soak, resize, and slow-reader phases now fail on relevant port downs or resize
  errors instead of only checking tmux survival.
- `--web-confirmed` is accepted only with `--profile full`.
- browser duplicate tracking is bounded and keyed by a server stream id.
- browser output uses streaming `TextDecoder` so multibyte UTF-8 split across
  chunks is not corrupted.

Reviewers also flagged missing explicit PubSub subscription in
`Hardline.Web.PaneChannel`; that finding is rejected. Phoenix subscribes a
Channel process to its joined topic, and the previous explicit subscription was
the source of duplicate output delivery.

A later Trinity code review of the full `spikes/hardline/` scope passed with
GLM, Gemini, and DeepSeek after additional hardening:

- `Runner.collect_until/3` enforces a hard timeout even under continuous stdout.
- validation provisioning preserves started tmux sessions in failure contexts so
  cleanup can stop them.
- resize polling drains queued stdout/port-down events instead of skipping
  zero-second polls.
- `Hardline.Web.Manager` prunes dead `PaneServer` processes and reattaches live
  managed tmux sessions.
- `erlexec` is explicitly constrained to `~> 2.3`.
- latest local checks after Phase 0b UI refinements: `mix format --check-formatted`
  passed and `mix test` passed with 45 tests, 0 failures.

## Phase 0c Browser Harness

Phase 0c extracted the browser manager from inline HTML into:

- `priv/static/js/hardline_core.js` — pure URL, command, slug, status, and
  full-mode helper logic
- `priv/static/js/hardline_manager.js` — DOM, API, Phoenix Channel, xterm.js,
  FitAddon, and lucide wiring
- `priv/static/js/hardline_boot.js` — module boot entrypoint used by
  `index.html`

Validation:

- `npm run test:js` passed: 9 pure JavaScript tests
- `npm run test:e2e` passed: 10 Playwright DOM/E2E tests
- `mise exec -- mix test` passed: 59 tests, 0 failures
