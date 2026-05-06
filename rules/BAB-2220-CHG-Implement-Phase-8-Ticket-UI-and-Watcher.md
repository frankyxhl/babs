# CHG-2220: Implement Phase 8 Ticket UI and Watcher

**Applies to:** BAB project
**Last updated:** 2026-05-06
**Last reviewed:** 2026-05-06
**Status:** Approved
**Date:** 2026-05-06
**Requested by:** Operator
**Priority:** High
**Change Type:** Normal

---

## What

Implement Phase 8 from `BAB-2217` and the PR B slice from `BAB-2218`:

- Add a read-only `/tickets` browser list page grouped by Ticket state.
- Add a read-only `/tickets/<id>` browser detail page.
- Link `/citizens` and `/tickets` without weakening terminal socket-token
  behavior.
- Render Ticket frontmatter summary, Markdown body, history timeline, warnings,
  and invalid runtime files.
- Add a filesystem watcher for the configured Ticket root and broadcast change
  notifications so LiveView pages refresh without a page reload.
- Add browser-harness BDD coverage for list/detail/manual-edit refresh.
- Add semantic icons to Phase 8 browser action buttons and cross-navigation
  buttons, following `BAB-1004`'s Lucide/Phosphor icon guidance.

This CHG does not add assignment, state transition buttons, approval/reject,
comment forms, terminal injection, or `bb ticket` over UDS. Those remain
Phase 9-12 work.

Authority references for this CHG are `BAB-2217`, `BAB-2218`, `BAB-2219`,
`BAB-1111`, `BAB-1110`, `BAB-1106`, `BAB-1004`, and `BAB-1503`.

## Why

Phase 7 created the durable Ticket/Billboard data model, but the operator still
has to inspect files or use the temporary Mix command bridge. Phase 8 makes the
Billboard visible from the browser while keeping all writes out of scope.

The watcher matters because the Ticket root is intentionally human-editable.
Manual edits must be treated as first-class changes: the browser should update,
invalid files should be visible, and the UI should not silently hide drift in
the runtime data.

## Impact Analysis

- **Systems affected:** `:babs_citizens` supervision, Ticket watcher module,
  `Babs.Citizens.Tickets` read API if a small read-model helper is needed,
  Babs web routes/controllers/LiveViews, static browser tests, roadmap/index
  docs, and discussion tracker.
- **Dependencies:** Add `:file_system` to `:babs_citizens` while retaining it
  in `:babs` for `Babs.DevReloader`. Reuse the existing Phoenix PubSub server
  `Babs.Citizens.PubSub`.
- **Data affected:** Runtime Ticket files under the configured Ticket root.
  Phase 8 reads and watches the root but does not mutate Ticket state.
- **Security/privacy:** Public PR text must not include private IPs, local
  absolute paths, credentials, or machine-specific URLs. UI error text must use
  existing redacted Ticket/Citizen error rendering and must not leak raw host
  paths when avoidable.
- **UX impact:** Adds an operations-style Ticket browser. No landing page,
  decorative hero, or card-in-card composition. UI density should match
  `/citizens` and the Hardline manager console.
- **Rollback plan:** Revert the Phase 8 implementation commit. Ticket files
  remain valid Phase 7 runtime data because Phase 8 is read-only.

## Implementation Plan

1. **RED: Ticket UI read-model tests**
   - Add `BabsWeb.TicketsLiveTest` with isolated temporary Ticket roots.
   - Create Tickets through `Babs.Citizens.Tickets.Api` rather than fixtures
     with hand-written YAML where possible.
   - Assert `/tickets` groups Tickets into Billboard, In Progress, Pending
     Approval, Closed, Cancelled, and Invalid sections.
   - Assert ordering is stable by priority, `updated_at`, then ID, matching the
     PRP's dense operational list requirement.
   - Assert invalid markdown and orphan history files appear as concise error
     rows instead of crashing or disappearing.
   - Assert navigation/action buttons include semantic icon elements and
     accessible labels or titles before the icon implementation is added.

2. **GREEN: `/tickets` list**
   - Add route/controller plumbing for `/tickets` using the existing
     `live_render` controller pattern unless a LiveView router conversion is
     needed for a clear reason.
   - Add `BabsWeb.TicketsLive`.
   - Reuse Phase 7 `Api.list_tickets/1`; add a web-only presenter module if
     grouping, labels, and icon metadata would otherwise clutter the LiveView.
   - Show compact counts and state groups:
     Billboard, In Progress, Pending Approval, Closed, Cancelled, Invalid.
   - Render an empty state when the Ticket root has no valid or invalid Ticket
     files.
   - Treat invalid rows as informational in Phase 8; do not link malformed
     files to a detail page until a later editable/error-detail flow exists.
   - Add a manual refresh button as a fallback even though the watcher is the
     primary update path.

3. **RED/GREEN: `/tickets/<id>` detail**
   - Add `BabsWeb.TicketLive`.
   - Render state badge, title, frontmatter summary, Markdown body, warnings,
     and history timeline.
   - For Phase 8, render Markdown body as escaped pre-wrapped text to avoid XSS
     and avoid adding a Markdown sanitizer dependency; revisit sanitized HTML
     Markdown rendering in a later UI polish CHG if needed.
   - Link detail back to `/tickets` and to `/citizens`.
   - Missing or invalid IDs render a controlled not-found/error state rather
     than crashing.
   - Keep assignment controls/comment box absent or visibly disabled because
     those capabilities begin in later phases.

4. **RED/GREEN: Ticket filesystem watcher**
   - Add `Babs.Citizens.Tickets.Watcher` under `:babs_citizens`.
   - Add the `:file_system` dependency to `:babs_citizens`, because `BAB-1110`
     assigns the Ticket watcher to the Citizen runtime boundary. Keep
     `:file_system` in `:babs` for `Babs.DevReloader`.
   - Watch the configured Ticket root, tolerate a missing root at boot, and
     retry or start cleanly once the root exists.
   - Mirror the existing `Babs.DevReloader` watcher/debounce shape where
     practical: `FileSystem.start_link`, `FileSystem.subscribe`, and
     `Process.send_after` debounce.
   - If the root is missing at boot, retry with a bounded polling interval such
     as 1s until the root exists instead of permanently disabling the watcher.
   - Debounce filesystem events with a window no greater than 250ms so the
     browser can meet the Phase 8 one-second refresh acceptance criterion.
   - Broadcast a single refresh message on a Ticket PubSub topic such as
     `"tickets"`.
   - Include the changed root and changed paths in the payload for diagnostics,
     but keep LiveViews free to refresh by re-reading the source of truth.
     Treat payload paths as internal only; do not render raw root/path values in
     browser HTML.
   - Validate the watcher contract from `BAB-2217`: markdown edits, history
     edits, newly created Ticket files, and malformed files all trigger a
     refresh without hiding invalid runtime data.
   - Subscribe connected Ticket LiveViews to the topic and refresh assigns on
     watcher messages.
   - Add ExUnit coverage for watcher broadcasts and LiveView refresh behavior
     after manual file edits.

5. **GREEN: navigation, icons, and socket-token safety**
   - Add `/tickets` links from `/citizens` and reciprocal links from Tickets UI.
   - Add Tickets to the global/navigation surface implied by `BAB-1004` where
     that surface currently exists in BabsWeb; if the full sidebar is still not
     implemented, add the equivalent visible operations navigation alongside
     `/citizens`.
   - Preserve existing terminal link token behavior by threading
     `socket_token` only through existing terminal/Citizen paths.
   - Add a small shared icon helper/component for the limited Phase 8 icon set
     if the repo still has no icon library. Use semantic labels/tooltips for
     icon-only controls.
   - Use icons for Ticket action/navigation buttons such as list, open, back,
     refresh, create placeholder, filter/group, and Citizens cross-link.
   - Keep layout dimensions stable on desktop and mobile.

6. **RED/GREEN: BDD and E2E**
   - Add browser-harness BDD scenarios for:
     - manually created open unassigned Ticket appears on `/tickets`;
     - external edit refreshes `/tickets` without browser reload;
     - Ticket detail renders body and history;
     - malformed Ticket file is visible in the Invalid section;
     - Ticket navigation buttons expose accessible icon labels.
   - Keep existing Playwright E2E smoke passing.
   - Avoid using private network URLs in BDD, PR bodies, or committed docs.

7. **Docs and closeout**
   - Mark Phase 7 as merged in `BAB-2300` and `BAB-3003`.
   - Record Phase 8 implementation and validation facts in this CHG before PR.
   - Update `BAB-0000` for this CHG.
   - Run Trinity fast-review with GLM and DeepSeek before implementation and
     again for the implementation diff before PR.

## Validation Plan

Required local validation for Phase 8:

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`
- `mise exec -- mix test --cover`
- `npm run test:js`
- `npm run test:bdd`
- `npm run test:e2e`
- `mise exec -- mix babs.gate_a`
- `af validate --root .`
- `git diff --check`
- Privacy/runtime artifact scan over changed files
- Trinity fast-review with GLM and DeepSeek
- GitHub Codex review loop, maximum five rounds

Coverage expectations remain:

- `:babs_citizens >= 80%`
- `:babs >= 75%`

No 24-hour stability validation is required in Phase 8 unless the operator
explicitly makes time available.

## Implementation Results

Implemented locally on branch `codex/m3-phase-8-ticket-ui`:

- Added `Babs.Citizens.Tickets.Watcher` under `:babs_citizens`, supervised by
  the Citizen runtime, using `:file_system`, PubSub topic `"tickets"`, a
  250ms-or-less debounce, retry for missing roots, and macOS `/private/var`
  path normalization.
- Added `/tickets` and `/tickets/<id>` controller routes and LiveViews.
- Added `BabsWeb.TicketPath`, `BabsWeb.TicketPresenter`, and `BabsWeb.Icon`.
- Added Ticket list grouping for Billboard, In Progress, Pending Approval,
  Closed, Cancelled, and Invalid.
- Added read-only Ticket detail rendering for frontmatter, escaped Markdown
  body text, warnings, and history.
- Added `/citizens` ↔ `/tickets` navigation and semantic icons on Ticket and
  Citizen action/navigation buttons.
- Added ExUnit coverage for Ticket list/detail/error rendering, icon-labeled
  controls, watcher PubSub refresh for list and detail pages, and missing-root
  watcher retry.
- Added browser-harness BDD scenarios for manual Ticket list visibility,
  external edit refresh, detail history rendering, malformed Ticket visibility,
  and icon-labeled navigation.
- Updated optional seed CLI browser smoke to skip stopped Citizens explicitly,
  matching the operator's CPU-saving stopped-Citizen workflow.
- Addressed Trinity implementation review advisories by adding an Open group
  for manually edited `state: open` Tickets with assignees, adding detail-page
  PubSub refresh coverage, and documenting macOS `/private/var` watcher path
  normalization.

## Validation Results

Local validation passed:

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`: 161 `:babs_citizens` tests and 57 `:babs` tests,
  0 failures.
- `mise exec -- mix test --cover`: `:babs_citizens` 82.62%, `:babs` 84.39%.
- `npm run test:js`: 8 tests, 0 failures.
- `npm run test:bdd`: PASS, including the four Phase 8 Ticket scenarios.
- `npm run test:e2e`: 4 passed, 2 skipped because optional Clare/Dylan live
  seed Citizens were stopped.
- `mise exec -- mix babs.gate_a`
- `af validate --root .`: 116 documents checked, 0 issues.
- `git diff --check`
- Privacy/runtime artifact scan over changed files found no public private IP,
  credential, token, or host-path leak. The only matches were dummy test query
  params, existing roadmap text about secret redaction, and internal macOS path
  normalization code.

## Acceptance Criteria

- `/tickets` lists valid Tickets grouped by state and shows invalid Ticket
  files as visible errors.
- `/tickets/<id>` renders Ticket title, state, frontmatter summary, body,
  warnings, and history.
- Manual edits to Ticket markdown or history refresh connected Ticket pages
  without page reload.
- `/citizens` and `/tickets` link to each other.
- Phase 8 browser buttons include semantic icons and accessible labels/tooltips.
- Terminal routes keep existing socket-token behavior.
- Browser-harness BDD covers list, detail, manual-edit refresh, and malformed
  file visibility.
- Local validation and Trinity implementation review pass before PR.

## Open Questions

None. Assignment controls, comments, approval/reject, terminal notifications,
and full multi-CLI dogfood are explicitly deferred to Phase 9-12 by
`BAB-2218`.

## Review Results

- R1 `.trinity/reviews/20260506-120612-rules-BAB-2220-CHG-Implement-Phase-8-Ticket-UI-and-Watcher.md`:
  DeepSeek PASS 9.01/10 with advisories. GLM failed due the exhausted
  `glm-5.1` Droid model alias before the operator switched Trinity to
  `custom:GLM-5.1-(Z.AI)-0`. Folded DeepSeek advisories into this CHG:
  explicit `BAB-1004` icon guidance, watcher dependency boundary, debounce
  window, watcher validation contract, and RED/GREEN step labels.
- R2 `.trinity/reviews/20260506-121740-rules-BAB-2220-CHG-Implement-Phase-8-Ticket-UI-and-Watcher.md`:
  GLM PASS 9.08/10 with advisories only after switching Trinity GLM to
  `custom:GLM-5.1-(Z.AI)-0` and raising timeout to 900s. Folded advisories into
  this CHG: icon RED assertions, `BAB-1004` navigation coverage, escaped-text
  Markdown decision, watcher retry/debounce alignment with `Babs.DevReloader`,
  watcher path-safety, empty state, invalid-row behavior, and retaining
  `:file_system` in `:babs`.
- Implementation review `.trinity/reviews/20260506-124952-.`: GLM PASS and
  DeepSeek PASS with advisories only. Fixed actionable low-cost advisories:
  manually edited `open` Tickets with assignees now appear in an Open group,
  Ticket detail has PubSub refresh coverage, and watcher path normalization has
  an explanatory comment. CSS extraction and broader error-handling tightening
  remain deferred polish.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-06 | Initial Phase 8 Ticket UI and watcher CHG draft | Codex |
| 2026-05-06 | Fold in DeepSeek plan-review advisories for icon guidance, watcher dependency/debounce/validation contract, and RED/GREEN labels | Codex |
| 2026-05-06 | Mark CHG approved after GLM PASS and fold in advisory clarifications | Codex |
| 2026-05-06 | Record local Phase 8 implementation and validation results | Codex |
| 2026-05-06 | Record Trinity implementation review pass and advisory fixes | Codex |
