# PRP-2214: Phase 5 Multi-Citizen Index and Tab Navigation

**Applies to:** BAB project
**Last updated:** 2026-05-06
**Last reviewed:** 2026-05-06
**Status:** Approved

---

## What Is It?

Phase 5 adds the browser navigation layer that makes Babs usable as a
multi-Citizen console instead of a one-terminal-at-a-time URL switcher.

It introduces:

- `/citizens`, an index page listing all durable Citizens from SQLite.
- Status badges that combine durable SQLite status with live Hardline presence.
- A tab/navigation strip for switching between active Citizen terminals.
- A preserved full-window terminal mode for focused terminal work.
- Concurrent-Hardline validation proving at least three Citizens can run without
  leaking PTY/file descriptors.

Phase 5 does not create new lifecycle actions. Stop/start/restart remains Phase
6.

---

## Problem

Phase 4 lets the operator create a new Citizen from the browser, but the running
UI still behaves like a bootstrap terminal:

- `/` routes to a single default Citizen instead of a fleet view.
- The operator must know or copy the exact `/citizens/<slug>` URL to switch.
- There is no page that answers "which Citizens exist, which are up, and which
  can I open now?"
- There is no app-level tab/navigation affordance between several active
  Citizens.
- We have not yet validated the Phase 5 concurrency claim: three or more
  Hardlines can run concurrently with stable file descriptor counts.

Without this phase, Phase 6 lifecycle controls have no natural surface to attach
to, and the flywheel remains awkward because the operator cannot manage a small
fleet from the browser alone.

## Proposed Solution

### Scope

In scope:

- Add `GET /citizens` before `GET /citizens/:slug`.
- Add a LiveView index, tentatively `BabsWeb.CitizensLive`, rendered through the
  existing controller/live_render style unless implementation proves direct
  LiveView routing is cleaner.
- Change `GET /` to redirect to `/citizens` once the index exists. The previous
  root-to-sentinel redirect was a bootstrap convenience and should stop being
  the main entry point after a fleet view exists.
- List all rows from `Babs.Citizens.Catalog.list_citizens/0`, ordered
  consistently by slug.
- Show each Citizen's display name, slug, CLI label, cwd summary, durable
  status, live Hardline status, and last error only when status is failed.
- Map CLI fields to user-facing labels using the Phase 4 preset vocabulary:
  `shell`, `claude`, `codex`, `droid`, `pi`, and `copilot-cli`; do not expose
  env values.
- Add runtime status dots/badges:
  - `up`: SQLite `running` and `Lifecycle.lookup(slug)` succeeds.
  - `reattaching`: SQLite `running` but no live pane is currently registered.
  - `stopped`: SQLite `stopped`.
  - `failed`: SQLite `failed`.
- These are runtime labels, not new `BAB-1004` canonical UI states. They map to
  existing UI states as: `up -> idle`, `reattaching -> waiting`,
  `stopped -> paused`, and `failed -> dead`.
- Refresh index status periodically while connected. A simple LiveView
  `Process.send_after/3` tick every 1 second is acceptable for Phase 5;
  introducing a PubSub status event bus can wait until there is a concrete need.
- Add a tab strip to terminal pages so the operator can switch Citizens without
  returning to the index.
- Preserve `socket_token` query/session state across `/citizens`, `/citizens/new`,
  terminal links, tab links, and full-window links.
- Preserve full-window terminal mode. Recommended route shape:
  `/citizens/<slug>?full=1` renders the current pure xterm viewport with only
  the connection badge; default `/citizens/<slug>` may include the tab chrome.
- Add stable `data-testid` selectors for index rows, status badges, tab links,
  full-window links, and terminal roots.
- Add unit, LiveView/controller, browser-harness BDD, existing E2E smoke, and fd
  stability coverage.

Out of scope:

- Stop/start/restart buttons; Phase 6 owns lifecycle controls.
- Rendering multiple xterm instances simultaneously in one DOM. Phase 5
  validates concurrent backend Hardlines and browser navigation between them,
  not a tiled multi-terminal frontend.
- Ticket/billboard UI.
- Role editing, Mayor, Inspector, assignment, or ticket routing.
- Browser env editing or secret storage.
- A React/SPA rewrite. LiveView plus the existing xterm Channel client remains
  the frontend model per `BAB-1106`.

### UX Contract

`/citizens` is an operations page, not a landing page.

The first viewport should show:

- A compact header with Babs, total count, up count, stopped count, failed count,
  and a `New Citizen` link.
- A dense Citizen table/list with green/amber/gray/red status dots.
- For each Citizen: slug, display name, CLI label, status, cwd summary, and
  links for `Open` and `Full`.
- Empty state: if no rows exist, show a compact empty message and a link to
  `/citizens/new`.

The default terminal page may gain a top tab bar:

- Active Citizen tab highlighted.
- Other Citizens shown as tabs/links with their status dots, ordered by slug to
  match the index.
- A `Full` icon/link opens the same Citizen with `?full=1`.
- A `Citizens` link returns to the index.
- The terminal itself must still fit the remaining viewport without text or
  chrome overlap.
- When only one Citizen exists, keep the compact chrome visible with the
  `Citizens` link, the single active tab, and the `Full` link. This keeps the
  page structure stable and avoids a separate one-Citizen layout.

Full-window mode must remain as close as possible to the Phase 4 terminal: black
xterm surface filling the viewport, stable FitAddon sizing, and no navigation
chrome that steals meaningful terminal height.

Operator decision on 2026-05-06: use this "Option A" terminal model. Default
`/citizens/<slug>` gets the compact tab chrome; `/citizens/<slug>?full=1`
preserves the pure full-window terminal for focused work.

### Proposed Design

#### 1. Add a Read Model Boundary

Add a small query/status boundary rather than scattering status logic through
LiveViews. A candidate module is `Babs.Citizens.StatusSnapshot` in
`:babs_citizens`.

The boundary returns a list of display-safe structs/maps:

```elixir
%{
  id: record.id,
  slug: record.slug,
  display_name: record.display_name,
  cli_label: "codex",
  cwd_label: ".../workspaces/dylan",
  durable_status: "running",
  live_status: :up | :reattaching | :stopped | :failed,
  last_error: redacted_or_nil
}
```

Rules:

- It may call `Catalog.list_citizens/0` and `Lifecycle.lookup/1`.
- It must not start, stop, or mutate any Citizen.
- It must not expose env maps.
- CLI labels:
  - `cli = "/bin/zsh"` and `cli_args = ["-f"]` -> `shell`
  - `cli = "claude"` -> `claude`
  - `cli = "codex"` -> `codex`
  - `cli = "droid"` -> `droid`
  - `cli = "pi"` -> `pi`
  - `cli = "gh"` and `cli_args = ["copilot"]` -> `copilot-cli`
  - otherwise -> `Path.basename(cli)` plus a generic marker such as `custom`
- Cwd labels:
  - if cwd is under the configured workspace root, display
    `workspaces/<relative>`.
  - otherwise display the final path segment prefixed with `.../`, and place
    the full cwd in a `title` attribute.
  - never include env values in display data.
- Runtime status labels map to `BAB-1004` visual states:
  - `up` uses the `idle` green visual treatment.
  - `reattaching` uses the `waiting` blue visual treatment.
  - `stopped` uses the `paused` gray visual treatment.
  - `failed` uses the `dead` red visual treatment.

This keeps LiveViews declarative and gives tests a pure place to verify status
mapping.

#### 2. Add `/citizens` Index

Route shape:

```elixir
get("/", TerminalController, :index)
get("/citizens", TerminalController, :citizens)
get("/citizens/new", TerminalController, :new)
get("/citizens/:slug", TerminalController, :show)
head("/citizens/:slug", TerminalController, :head)
```

Recommended behavior:

- `TerminalController.index/2` redirects to `/citizens`.
- `TerminalController.citizens/2` renders `BabsWeb.CitizensLive` and passes any
  validated socket token into the LiveView session.
- `/citizens/new` keeps the final Phase 4 implementation behavior from
  `BAB-2213`: the route goes through `TerminalController.new/2`; if a running
  Citizen with slug `new` exists, the terminal wins, otherwise the controller
  renders `BabsWeb.NewCitizenLive`.
- `/citizens/:slug` remains the terminal route.

#### 3. Add Tab Navigation to Terminal Pages

`BabsWeb.TerminalLive` should receive enough session state to decide whether to
render full-window mode.

Suggested contract:

- `full? = params["full"] in ["1", "true"]`
- `full? == true`: render the existing pure terminal layout.
- `full? == false`: render a compact top chrome with tabs and a terminal area
  sized as `calc(100vh - chrome_height)`.

The terminal tab chrome should use the same `StatusSnapshot` read model as the
index to avoid duplicated status logic.

The xterm bootstrap should still mount exactly one terminal instance on the
page. Phase 5 should not attempt a multi-xterm tabbed component that keeps
hidden terminals alive in the DOM.

FitAddon sizing remains part of the contract:

- expose the chrome height as a CSS variable or stable measured value.
- keep the terminal container at a stable `calc(100vh - <chrome-height>)`.
- call the existing terminal resize path after mount and on window resize.
- do not let tab labels, status badges, or loading text resize the terminal
  container after xterm opens.

#### 4. Preserve Auth Token Routing

The Phase 4 socket-token regression showed this is easy to break. Phase 5 must
centralize URL generation for index links, tab links, `New Citizen`, and `Full`
links so `socket_token` is preserved when present and omitted when blank.

Recommended implementation hook: add a small web helper such as
`BabsWeb.CitizenPath` or equivalent that builds `/citizens`, `/citizens/new`,
`/citizens/<slug>`, and `?full=1` variants with optional `socket_token`.
LiveViews and controllers should call this helper rather than hand-writing query
strings in multiple modules.

Tests must cover:

- `/citizens?socket_token=token` includes terminal links with the token.
- `/citizens/<slug>?socket_token=token` tab links preserve the token.
- `/citizens/<slug>?socket_token=token&full=1` keeps full-window mode and token.

#### 5. Concurrent Hardline / FD Stability Validation

Add a fast validation path and a full validation path.

Fast PR validation:

- Use deterministic `shell` Citizens.
- Ensure at least three Citizens are running simultaneously.
- Open/switch each terminal and send a unique marker exactly once.
- Sample `lsof` for the BEAM OS process before and after the switch loop.
- Default fast smoke: at least 3 switch/input cycles across 3 Citizens. While
  terminals are connected, final fd count must be no more than baseline + 12;
  after browser cleanup, fd count must return to baseline + 4.
- Fail on unbounded descriptor growth, orphaned tmux sessions for test slugs, or
  duplicate marker injection.
- Keep default duration short enough for normal PR validation.

Full operator validation:

- Same scenario with `BABS_FD_STABILITY_SECONDS=1800` or equivalent for a 30
  minute run.
- Phase 5 records the command and expected pass criteria, but the 30 minute run
  is not a Phase 5 merge blocker.
- Operator decision on 2026-05-06: defer the 30 minute full run until Phase 6 or
  the M2 gate, after stop/start/restart lifecycle controls exist. Phase 5 should
  prioritize getting the multi-Citizen browser experience usable first.

The implementation should prefer a browser-harness BDD scenario, with a Mix task
only if needed for fd sampling. Browser-harness setup/teardown must clean up
browser processes/tabs reliably because previous browser automation left many
blank Chrome tabs.

### TDD / Test Plan

RED first:

1. Unit tests for the status snapshot mapping:
   - running + live pane -> `:up`
   - running + missing pane -> `:reattaching`
   - stopped -> `:stopped`
   - failed -> `:failed`
   - env values never appear in display data
   - `gh` plus `["copilot"]` labels as `copilot-cli`
2. Controller/LiveView tests:
   - `/` redirects to `/citizens`
   - `/citizens` renders all SQLite Citizens sorted by slug
   - status badges and counts render with stable test ids
   - empty state renders when no citizens exist
   - socket token is preserved in index links
   - `/citizens/new` Phase 4 behavior remains intact
   - a status change between refresh ticks is reflected on the next tick
3. TerminalLive tests:
   - default terminal renders tab chrome and active tab
   - `?full=1` renders pure full-window terminal without tab chrome
   - tab links preserve socket token
   - terminal root and scripts remain present in both modes
   - single-Citizen tab chrome remains stable
4. Browser-harness BDD:
   - create or seed three shell Citizens
   - visit `/citizens`, verify list/status
   - click through tabs/open links, verify each terminal connects
   - send marker to each terminal exactly once
   - verify no browser automation residue remains after cleanup
5. FD stability:
   - fast descriptor sampling included in PR validation
   - 30 minute command documented but deferred to Phase 6/M2

Validation gates:

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`
- `mise exec -- mix test --cover`
- coverage should not regress below `:babs_citizens >= 80%` and `:babs >= 75%`
- `npm run test:js`
- browser-harness BDD for Phase 5 navigation/concurrency
- existing Playwright smoke remains unless a browser-harness scenario covers the
  exact same workflow, in which case the duplicate Playwright scenario may be
  removed in the same commit
- `mise exec -- mix babs.gate_a`
- `af validate --root .`
- `git diff --check`

Stable selector convention:

- `data-testid="citizen-row-<slug>"`
- `data-testid="citizen-status-<slug>"`
- `data-testid="citizen-open-<slug>"`
- `data-testid="citizen-full-<slug>"`
- `data-testid="citizen-tab-<slug>"`
- `data-testid="citizens-empty-state"`

### Review Plan

Before implementation:

- Review this PRP with Trinity fast-review using GLM and DeepSeek, unless the
  operator chooses a different reviewer set.
- Record approval or required revisions in this PRP.
- After approval, write a Phase 5 CHG with the concrete implementation plan.

During PR:

- Use the GitHub Codex review loop per `COR-1615`, capped at the operator's
  current maximum of five rounds.
- Do not trigger duplicate review requests for the same head.
- Match any review result to the current head before treating it as current.

## Decisions

1. `/` redirects to `/citizens` after Phase 5 lands.
2. Default `/citizens/<slug>` uses Option A: compact tab chrome plus the
   terminal. `/citizens/<slug>?full=1` preserves the pure full-window terminal.
3. Phase 5 includes fast fd validation only. The 30 minute fd stability run is
   documented but deferred to Phase 6 or the M2 gate, after lifecycle controls
   exist.
4. Phase 5 BDD uses browser-harness by preference. Existing Playwright smoke can
   remain as legacy coverage unless explicitly replaced.

## Review Results

Trinity fast-review R1 on 2026-05-06 used `glm` and `deepseek` in parallel via
Trinity 3.1.0:

- GLM returned FIX with two blockers: clarify why `/citizens/new` routes through
  `TerminalController.new/2`, and map Phase 5 runtime status labels to
  `BAB-1004` canonical UI states.
- DeepSeek returned PASS with CHG-phase recommendations for CLI labels, cwd
  display, tab ordering, single-Citizen chrome, tick-transition testing,
  Playwright replacement criteria, roadmap acceptance, and validation command
  wording.
- This revision resolves the GLM blockers and folds in the low-cost DeepSeek
  recommendations. Re-review is required before marking the PRP approved.

Trinity fast-review R2 on 2026-05-06 used `glm` and `deepseek` in parallel via
Trinity 3.1.0:

- GLM returned PASS with no blockers.
- DeepSeek returned PASS with advisories only.
- CHG-phase advisories to carry forward: define the fd baseline sampling moment,
  document that `reattaching` can include stale `running` rows until heartbeat or
  Phase 6 lifecycle audit exists, consider explicit `HEAD /citizens`, test the
  custom CLI-label fallback, and note that `typing` is intentionally not wired
  in Phase 5.
- PRP approved; proceed to Phase 5 CHG.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-06 | Initial draft for Phase 5 prep | Codex |
| 2026-05-06 | Resolve operator decisions: root redirects to `/citizens`, terminal Option A, defer 30 minute fd run to Phase 6/M2, prefer browser-harness BDD | Codex |
| 2026-05-06 | Address Trinity fast-review R1 findings: route rationale, status visual-state mapping, CLI/cwd display rules, tab ordering, tick tests, fd thresholds, socket-token helper, selector convention, and Playwright replacement criteria | Codex |
| 2026-05-06 | Trinity fast-review R2 passed with GLM and DeepSeek; mark PRP Approved and carry advisories to Phase 5 CHG | Codex |
