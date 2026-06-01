# CHG-2277: Citizen Home Read Tab

**Applies to:** BAB project
**Last updated:** 2026-06-01
**Last reviewed:** 2026-06-01
**Status:** Approved
**Date:** 2026-06-01
**Requested by:** @frankyxhl via GitHub issue #88
**Priority:** P2
**Change Type:** Normal

---

## What

Implement `BAB-2271` Phase 2 slice 2.5 / GitHub issue #88 by adding a Citizen
Knowledge Home read surface to `/citizens/:slug`.

The slice changes the existing Citizen detail route from a pure terminal shell
into a tabbed page whose first tab is a read-only Home view:

- A "Home" tab renders the Citizen's `Readme.md` through
  `Babs.Knowledge.Markdown`.
- The tab lists other root-level Knowledge markdown files returned by
  `Babs.Knowledge.list/2`.
- The LiveView subscribes to `Babs.Knowledge.Watcher.topic/0` and refreshes when
  it receives `{:knowledge_changed, slug, _name}` for the active Citizen.
- The existing terminal UI remains available from the same route via a
  "Terminal" tab and the existing "Full" terminal link.

## Why

Phase 2's Knowledge Home has safe file resolution, markdown CRUD, markdown
rendering, and filesystem watcher support, but no operator-facing UI. The
operator needs a browser surface to read a Citizen's durable standing context
before later slices add edit mode, multi-note picking, and prompt injection.

## Impact Analysis

- **Systems affected:** `BabsWeb.TerminalLive`, `BabsWeb.TerminalController`,
  Citizen route tests, LiveView tests, this CHG, and the document index.
- **Runtime behavior:** `/citizens/:slug` defaults to the Home tab when not in
  full-terminal mode. `?tab=terminal` or the Terminal tab shows the existing
  embedded terminal. `?full=1` keeps the pure full-terminal mode and takes
  precedence over any `tab` or `file` query parameter.
- **Citizen availability:** this slice deliberately keeps the existing
  `Lifecycle.lookup/1` route gate. The route still hosts terminal chrome,
  lifecycle controls, Citizen tab state, and PaneChannel-backed terminal
  behavior, all of which are designed around a live or registered Citizen
  session. Splitting `/citizens/:slug` into a stopped-Citizen file reader and a
  live terminal route is valid future work, but it is outside this read-tab
  slice. Until that follow-up, stopped Citizens keep the current 404 response.
- **Knowledge behavior:** the read tab uses the existing `Babs.Knowledge`
  boundary and only displays logical file names. It must not expose absolute
  host paths or raw resolver errors.
- **Markdown behavior:** rendered HTML is the sanitized output from
  `Babs.Knowledge.Markdown.render/1`. Invalid markdown render errors show a
  friendly failure state instead of crashing.
- **PubSub behavior:** the connected LiveView subscribes with `connected?/1`
  before calling `Phoenix.PubSub.subscribe/2`. Only events for the current
  Citizen slug trigger a reload.
- **Out of scope:** browser editing/saving (`#89`), multi-note directories and
  nested note picking (`#90`), default `Readme.md` seeding (`#91`), and prompt
  injection (`#93`).
- **Rollback plan:** remove the Home tab state/rendering/tests and restore
  `/citizens/:slug` to rendering only `BabsWeb.TerminalLive`; remove this CHG
  and index entry.

## Acceptance Criteria

- [x] `/citizens/:slug` exposes a Home tab/section rendering `Readme.md` as
      sanitized HTML.
- [x] Other root-level Knowledge markdown files are listed by name and are
      clickable to view within the read tab.
- [x] The LiveView subscribes to the Knowledge PubSub topic and re-renders on
      `{:knowledge_changed, slug, _}` for the active slug.
- [x] Missing `Readme.md` shows a friendly empty state, not a crash.
- [x] Knowledge list/read/render failures show friendly states without raw error
      tuples or host paths.
- [x] Existing terminal route behavior remains available, including full mode.
- [x] LiveView tests cover render, alternate file selection, empty state, and
      live refresh.
- [x] Validation passes: focused LiveView tests, `mix format --check-formatted`,
      `mix compile --warnings-as-errors`, `mix test`, `npm run test:js`,
      `af validate --root .`, and `git diff --check`.

## Implementation Plan

1. Extend `BabsWeb.TerminalLive` session state with a page tab:
   - `home` for the default read tab.
   - `terminal` for the embedded terminal tab.
   - `full` mode remains a separate pure terminal render and must not load Home
     chrome.
   - missing `tab` and `file` session keys must default to `home` and
     `Readme.md` so existing direct LiveView tests and controller callers keep
     working.
2. Convert `/citizens/:slug` from controller `live_render/3` to a router-mounted
   LiveView route so `<.link patch={...}>` and `handle_params/3` are valid on
   connected navigation. Add a small `BabsWeb.CitizenTerminalGate` plug ahead of
   the live route to preserve the existing `Lifecycle.lookup/1` 404 behavior for
   unknown Citizens. Keep `TerminalController.new/2`'s legacy terminal render
   working by passing a router option to its `live_render/3` call now that
   `TerminalLive` exports `handle_params/3`.
3. Extend `BabsWeb.CitizenPath.terminal/3` with optional `tab:` and `file:`
   query parameters alongside the existing `full?:` option. `full?: true`
   suppresses `tab:` and `file:` in generated URLs.
4. Add `handle_params/3` to `TerminalLive` for non-full URL-driven state:
   - `mount/3` assigns safe defaults; `handle_params/3` immediately overrides
     from URL params on initial navigation and later LiveView patch navigation,
     causing at most one harmless re-render.
   - if `socket.assigns.full?` is true, `handle_params/3` is a no-op for tab
     and file state.
   - parse `tab` from params on mount and on LiveView patch navigation. Only
     `"home"` and `"terminal"` are accepted; any other value falls back to
     `"home"`.
   - parse and validate `file` from params on mount and on patch navigation.
   - use `<.link patch={...}>` for Home file links so selection updates the URL
     and re-renders without remounting the LiveView.
   - treat URL params as authoritative after mount.
5. Add a small Home loading boundary inside `TerminalLive`:
   - track the selected Home file in the URL as `?file=<name>`, defaulting to
     `Readme.md`. Only root-level names returned by `Babs.Knowledge.list/2` are
     linked from this slice.
   - validate manual `?file=` values before reading: accept only root-level
     markdown basenames without `/`, `\`, or `..`, and only if the name appears
     in the current `Babs.Knowledge.list/2` result. Invalid or unknown names
     fall back to `Readme.md` with no raw error details.
   - if `Babs.Knowledge.list/2` returns an error while validating `?file=`,
     show the list error state, fall back to `Readme.md` for the content panel,
     and let the normal read/render error mapping decide the content state.
   - read `Readme.md` by default, or the selected root-level markdown file.
   - call `Babs.Knowledge.list(slug)` for root-level files.
   - call `Babs.Knowledge.read/2` and `Babs.Knowledge.Markdown.render/1`.
     Use only the returned `%{html: html}` value for rendered output; ignore
     frontmatter in this slice.
   - map missing files and render/read failures to friendly UI states without
     leaking host-local paths.
   - friendly error mapping:
     - `{:not_found, _}` -> "This file does not exist yet."
     - manual invalid or unknown `?file=` values -> silent fallback to
       `Readme.md`.
     - list failures, including `{:redacted_io_error, _}` and
       `{:unsafe_symlink, _}` -> "Unable to read knowledge files."
     - read failures other than missing files -> "Unable to read this knowledge
       file."
     - `{:invalid_frontmatter, _}`, `{:invalid_markdown, _}`, and
       `{:render_failed, _}` -> "Unable to render this knowledge file."
     - `{:ok, []}` from `Babs.Knowledge.list/2` -> friendly "No knowledge files
       yet" list state, while the selected `Readme.md` panel still uses the
       missing-file empty state.
6. Subscribe in connected mount:
   - `Phoenix.PubSub.subscribe(Babs.Citizens.PubSub, Babs.Knowledge.Watcher.topic())`
     only when `connected?(socket)` and not full-terminal mode.
   - handle `{:knowledge_changed, slug, name}` in a dedicated `handle_info/2`
     clause, separate from the existing `:refresh_terminal_tabs` handler.
   - ignore the message unless `not socket.assigns.full?` and
     `slug == socket.assigns.slug`.
   - when the Home tab is active, reload the whole Home state: root-level file
     list, selected-file validity, selected content, and rendered HTML. This is
     intentional even when `name` is not the selected file, because a list item
     may have been created, removed, or renamed.
   - if a PubSub-triggered reload hits a list/read/render failure, show the same
     friendly error state as initial load rather than preserving stale content.
   - when the Terminal tab is active, do not reload Home content; the next Home
     navigation will load from disk.
   - ignore changes for other slugs.
   - keep the existing `:refresh_terminal_tabs` behavior active on both Home and
     Terminal tabs so Citizen tab chrome continues to update.
7. Render the Home tab in the existing terminal page theme:
   - compact top nav with `Citizens`, Citizen tabs, `Home`, `Terminal`, and
     `Full`.
   - extend the existing nav grid with a page-tab segment between the Citizens
     link and Citizen tabs.
   - Home and Terminal are mutually exclusive page tabs visually, but the
     terminal `#terminal` container remains mounted with `phx-update="ignore"`
     and is hidden with CSS while Home is active. Use
     `visibility: hidden; height: 0; min-height: 0; overflow: hidden;
     pointer-events: none;` for the inactive terminal pane, not
     `display: none`. Restoring the Terminal tab restores the normal terminal
     height, which triggers the existing `ResizeObserver` in
     `terminal_client.js` so `fit.fit()` and the channel resize push run without
     adding a new hook. This preserves `terminal_boot.js`, xterm state, and
     PaneChannel behavior across tab switches.
   - Home panel with title, sanitized body, root-level Knowledge file list, and
     friendly empty/error states.
   - Terminal tab keeps the existing xterm mount and lifecycle controls.
   - use the existing dark terminal page variables; this slice does not introduce
     a separate light-theme island inside `TerminalLive`.
   - while Home is active, PaneChannel output can still accumulate in xterm's
     scrollback buffer. This is an accepted trade-off for preserving terminal
     state across tab switches and matches the existing always-mounted terminal
     behavior.
   - lifecycle redirects should preserve the current page tab when returning to
     the same Citizen. For example, a restart from the Terminal tab should
     redirect back to `?tab=terminal`; full mode continues preserving only
     `full=1`.
8. Add focused LiveView tests in
   `apps/babs/test/babs_web/live/terminal_live_test.exs`:
   - use real temporary filesystem fixtures by setting `:babs_citizens`
     `:root`, `:workspace_root`, and `:knowledge_root` during tests, then
     writing markdown files under `<knowledge_root>/<slug>/`.
   - default `/citizens/:slug` renders the Home tab with rendered `Readme.md`.
   - `?tab=terminal` renders the existing embedded terminal.
   - `?full=1&tab=home&file=Other.md` ignores `tab` and `file` and renders the
     pure terminal.
   - clicking a listed markdown file uses LiveView patch navigation and renders
     that file without losing the terminal DOM.
   - missing `Readme.md` renders an empty state.
   - an empty Knowledge list renders a friendly list empty state.
   - the combined default state with an empty Knowledge list and missing
     `Readme.md` renders both friendly empty states.
   - invalid manual `?file=notes/secret.md` or `?file=../etc/passwd` falls back
     to `Readme.md` without leaking raw errors.
   - unreadable/list/render failures render friendly messages without raw error
     tuples or host paths.
   - lifecycle restart from the Terminal tab preserves `?tab=terminal` on the
     same-Citizen redirect; stop keeps the existing redirect to `/citizens`.
   - broadcasting `{:knowledge_changed, slug, "Readme.md"}` refreshes the Home
     tab; broadcasting another file for the same slug refreshes the file list;
     broadcasting another slug does not.
9. Run RED focused tests before implementation, implement to GREEN, then run
   the full validation stack and Trinity implementation review.

## References

- `BAB-2271` - Operator Dashboard Panels, Phase 2 Citizen Knowledge Home.
- `BAB-2273` - Knowledge Root Resolution.
- `BAB-2274` - Knowledge Markdown CRUD.
- `BAB-2275` - Knowledge Markdown Render.
- `BAB-2276` - Knowledge FileSystem Watcher.
- GitHub issue #88 - Citizen Home read tab on `/citizens/:slug`.
- `Babs.Knowledge`, `Babs.Knowledge.Markdown`, and
  `Babs.Knowledge.Watcher`.
- `BabsWeb.TerminalLive` - current `/citizens/:slug` LiveView shell.

## Review Plan

- **Plan review:** Trinity with providers `glm,deepseek,minimax` before code.
- **Implementation review:** Trinity with providers `glm,deepseek,minimax`
  before PR.
- **PR review:** GitHub Codex review loop per `COR-1615`.

## Validation Results

- 2026-06-01 plan review R1:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2277-CHG-Citizen-Home-Read-Tab.md`
  produced a PASS synthesis, but raw GLM output returned `FAIL` with blockers
  around file selection, PubSub refresh scope, and `full=1` precedence. This
  revision defined `?file=`, whole-Home refresh behavior, and full-mode
  precedence.
- 2026-06-01 plan review R2:
  the same Trinity command produced a PASS synthesis, but raw GLM/DeepSeek
  output identified high-priority design gaps around `handle_params/3`, xterm
  destruction on tab switch, manual `?file=` validation, `unsafe_symlink`
  mapping, error tests, and theme consistency. This revision added LiveView
  patch navigation, always-mounted terminal DOM, `CitizenPath` tab/file support,
  explicit validation/error mapping, and filesystem-based test strategy.
- 2026-06-01 plan review R3:
  the same Trinity command produced a PASS synthesis, but raw GLM output still
  requested an explicit xterm hiding strategy and a rationale for keeping the
  existing `Lifecycle.lookup/1` route gate. This revision specified
  visibility/height-based hiding that preserves ResizeObserver behavior and
  recorded the route-gate rationale as intentional slice scope.
- 2026-06-01 final plan review:
  the same Trinity command passed with no blocking findings in raw provider
  output; synthesis at
  `.trinity/reviews/20260601-123544-rules-BAB-2277-CHG-Citizen-Home-Read-Tab.md/synthesis.md`.
  Non-blocking findings were folded into the implementation plan: list-failure
  validation behavior, full-mode `handle_params/3` no-op, refresh failure state,
  and lifecycle tab-preservation test coverage.
- 2026-06-01 RED:
  `mise exec -- mix test apps/babs/test/babs_web/live/terminal_live_test.exs`
  failed with 9 expected failures for the missing Home tab/read/list/refresh
  behavior and lifecycle tab preservation.
- 2026-06-01 GREEN focused:
  `mise exec -- mix test apps/babs/test/babs_web/live/terminal_live_test.exs apps/babs/test/babs_web/controllers/terminal_controller_test.exs apps/babs/test/babs_web/citizen_path_test.exs`
  passed: 39 tests, 0 failures.
- 2026-06-01 GREEN full:
  `mise exec -- mix test` passed: `babs_citizens` 568 tests, 0 failures;
  `babs` 165 tests, 0 failures.
- 2026-06-01 validation stack:
  `mise exec -- mix format --check-formatted` passed;
  `mise exec -- mix compile --warnings-as-errors` passed;
  `npm run test:js` passed with 19 tests, 0 failures;
  `af validate --root .` passed with 202 documents checked, 0 issues found;
  `git diff --check` passed.
- 2026-06-01 implementation review:
  final Trinity review
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope issue-88-citizen-home-implementation-final-v2`
  passed with synthesis `3/3 PASS · 0 FIX · 0 FAIL` at
  `.trinity/reviews/20260601-130928-issue-88-citizen-home-implementation-final-v2/synthesis.md`.
  Earlier non-blocking implementation-review findings were addressed before
  this final pass: removed dead controller action, removed unused CSS, skipped
  Home reload while Terminal is active, added Readme-link/PubSub-terminal
  tests, and made invalid `CitizenPath.terminal/3` tab options explicit.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-06-01 | Initial version | Codex |
