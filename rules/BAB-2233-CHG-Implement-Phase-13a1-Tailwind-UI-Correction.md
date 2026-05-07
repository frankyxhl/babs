# CHG-2233: Implement Phase 13a1 Tailwind UI Correction

**Applies to:** BAB project
**Last updated:** 2026-05-07
**Last reviewed:** 2026-05-07
**Status:** Completed
**Date:** 2026-05-07
**Requested by:** Operator
**Priority:** High
**Change Type:** Normal

---

## What

Implement the first Phase 13a delivery slice: replace the ad-hoc
inline-styled kitchen-sink spike with a Tailwind-backed BabsWeb UI foundation.

This CHG does not implement the full multi-turn Ticket model or direct CLI
backend. It prepares the UI foundation those slices need:

- install and validate the Phoenix Tailwind CSS asset pipeline for `apps/babs`;
- add Babs light-theme design tokens and reusable component classes;
- load the generated stylesheet from the root layout;
- refactor `/dev/kitchen-sink` away from large inline CSS into semantic HEEx
  plus shared classes;
- keep terminal canvases dark inside a light product shell;
- add tests or build checks proving the kitchen sink uses the asset pipeline and
  still renders the required Ticket chat/status/control states.

## Why

The operator rejected the first kitchen-sink palette as visually weak. The repo
also currently has no real Tailwind pipeline despite `BAB-1004` expecting
Tailwind tokens. Continuing to polish Ticket chat with inline CSS would compound
style drift and make a later theme selector harder.

Phase 13a needs a stable, inspectable UI system before production Ticket-detail
chat is rebuilt. This slice makes `/dev/kitchen-sink` the reviewable design
system preview for later multi-turn Ticket UI work.

## Impact Analysis

- **Systems affected:** `apps/babs` static assets, root layout, LiveView
  kitchen-sink route, UI tests, `BAB-1004`, `BAB-2232`, and the Phase 13a
  validation path.
- **Runtime impact:** generated CSS is served from existing `Plug.Static` under
  `/css`. Existing vendored JS and xterm CSS remain unchanged.
- **User impact:** `/dev/kitchen-sink` becomes the operator-facing UI preview
  for light-theme components. Production Ticket behavior is unchanged in this
  CHG unless needed to load the shared stylesheet.
- **Rollback plan:** remove the Tailwind dependency/config/assets, revert the
  root layout stylesheet link and kitchen-sink refactor, and keep or remove the
  temporary inline kitchen-sink spike. No database migration is involved.
- **Privacy/security:** no public URLs, local machine paths, tokens, or
  Tailscale addresses are added to public-facing UI strings or docs.

## Implementation Plan

1. Add `{:tailwind, "~> 0.4.1", runtime: Mix.env() == :dev}` to `apps/babs`.
2. Configure Tailwind in `config/config.exs` with input under
   `apps/babs/assets/css/app.css` and output under
   `apps/babs/priv/static/css/app.css`.
3. Add a dev watcher and root Mix aliases for `assets.setup`, `assets.build`,
   and `assets.deploy` as appropriate for the umbrella layout.
4. Use Tailwind v4 CSS-first configuration in
   `apps/babs/assets/css/app.css`; do not add a `tailwind.config.js` unless a
   later dependency explicitly requires the legacy config shape. Add explicit
   `@source` directives for Babs LiveView modules/templates so Tailwind scans
   only intended project files.
5. Create `apps/babs/assets/css/app.css` with Tailwind import/theme directives,
   Babs CSS variables, and shared component classes inspired by Tailwind UI
   Application UI, shadcn neutral tokens, and Petal Components.
6. Update `BabsWeb.Layouts.root/1` to load `/css/app.css` while keeping the
   existing LiveView boot scripts in individual views for now.
7. Refactor `BabsWeb.KitchenSinkLive` to remove the large inline `<style>` block
   and use shared classes/data test ids.
8. Add/adjust tests that assert the kitchen-sink route links the stylesheet,
   renders light-theme data attributes, contains icon-bearing controls, and
   exposes representative Ticket chat/status states.
9. Run formatting, `mix deps.get`, Tailwind build, focused LiveView tests, full
   ExUnit, `af validate`, `git diff --check`, and a local HTTP smoke for
   `/dev/kitchen-sink`.
10. Run Trinity fast-review for the implementation diff before PR.

## Acceptance Criteria

- `/dev/kitchen-sink` returns 200 and visually uses the generated app stylesheet,
  not a large inline CSS block.
- The page defaults to light theme and includes a working local dark-preview
  selector for future theme-selector work.
- The page includes examples for buttons with icons, status badges, Ticket state
  side rail, Ticket chat rows, forms/errors, and terminal-in-light-shell.
- Existing terminal/xterm styling remains available.
- Test/build validation proves Tailwind CSS can be regenerated from source.
- Existing Babs tests continue to pass.

## Implementation Outcome

- Added Phoenix Tailwind integration with `tailwind` `~> 0.4.1`, root
  `assets.setup` / `assets.build` / `assets.deploy` aliases, dev watcher, and
  CSS live reload.
- Added `apps/babs/assets/css/app.css` as the Tailwind v4 CSS-first source and
  committed generated `apps/babs/priv/static/css/app.css`.
- Loaded `/css/app.css` from the root layout.
- Added runtime config for `:babs, :kitchen_sink_enabled`; dev/test default to
  enabled, production/default fallback is disabled.
- Added `/dev/kitchen-sink` before parameterized routes and kept it gated by
  config.
- Refactored `BabsWeb.KitchenSinkLive` out of inline CSS into semantic HEEx plus
  shared classes.
- Added kitchen-sink coverage for icon buttons, badges, Ticket rail, Ticket
  chat, forms, terminal-in-light-shell, tabs, tables, empty states, and modal
  previews.
- Added focused tests for the enabled stylesheet path, disabled 404 path, theme
  toggle round-trip, and representative component states.

Source CSS changes require regenerating the tracked CSS artifact with:

```bash
mise exec -- mix assets.build
```

## Validation

- `mise exec -- mix deps.get`
- `mise exec -- mix assets.build`
  - Tailwind CSS v4.1.12 generated `apps/babs/priv/static/css/app.css`.
- `mise exec -- mix test apps/babs/test/babs_web/controllers/terminal_controller_test.exs apps/babs/test/babs_web/live/kitchen_sink_live_test.exs`
  - 14 tests, 0 failures.
- `mise exec -- mix test apps/babs/test/babs_web`
  - 74 tests, 0 failures.
- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`
  - `babs_citizens`: 251 tests, 0 failures.
  - `babs`: 78 tests, 0 failures.
- `af validate --root <repo-root>`
  - 140 documents checked, 0 issues found.
- `git diff --check`
- Restarted `babs-web-main` tmux server on `0.0.0.0:4000`.
- HTTP smoke:
  - `GET /dev/kitchen-sink` -> 200.
  - `GET /css/app.css` -> 200.
  - HTML contains `/css/app.css`, `data-testid="kitchen-sink"`, and no inline
    `<style>` block.
  - CSS contains Tailwind v4.1.12 header and `--color-babs-accent: #0969da`.
- Local Playwright screenshot smoke captured a 1280x1752 PNG; the artifact was
  not committed.

## Plan Review

- R1 Trinity fast-review:
  `.trinity/reviews/20260507-120108-BAB-2233-Phase-13a.1-Tailwind-UI-correction-CHG-plus-BAB-1004-BAB-2232-BAB-2300-UI-route-diffs`
  - GLM PASS.
  - DeepSeek reported blocking scope mismatch and missing disabled-route test.
  - Fixes folded in: `BAB-2232` implementation slices now split Tailwind UI
    foundation from multi-turn Ticket work, and `/dev/kitchen-sink` disabled
    404 has controller coverage.
- R2 Trinity fast-review:
  `.trinity/reviews/20260507-120935-BAB-2233-Phase-13a.1-Tailwind-UI-correction-CHG-R2-after-scope-split-and-kitchen-sink-404-test`
  - GLM PASS.
  - DeepSeek PASS.
  - Advisories to carry into implementation: make the kitchen-sink theme test
    less attribute-order dependent, fix the terminal `<pre>` indentation
    artifact, and include tabs/tables/empty states/modals before closing this
    CHG.

## Code Review

- R1 Trinity implementation review:
  `.trinity/reviews/20260507-122454-BAB-2233-implementation-diff-Phoenix-Tailwind-asset-pipeline-and-Tailwind-backed-kitchen-sink`
  - GLM reported FIX on accent color, redundant script tag, and brittle test
    assertion.
  - DeepSeek PASS with advisories.
  - Folded fixes: restored the reviewed accent token at the time, moved
    kitchen-sink default to config with runtime fallback `false`, and made the theme test
    attribute-order independent. The per-view `live_boot.js` script remains by
    existing Babs convention; moving all LiveViews to a root boot script is a
    later shared cleanup, not part of this CHG.
- R2 Trinity implementation review:
  `.trinity/reviews/20260507-123828-BAB-2233-implementation-diff-R2-after-accent-token-and-kitchen-sink-config-fixes`
  - GLM PASS.
  - DeepSeek PASS.
  - Remaining advisories are non-blocking: visual smoke existing pages after the
    global Tailwind preflight, document generated CSS expectations, and defer a
    real dark-theme spec to a later CHG.

### Post-review Visual Correction

After manual review, the default purple accent was rejected as visually too
dominant. `BAB-1004` and the Tailwind tokens now use a neutral GitHub-like
light theme with operations blue `#0969da` as the primary action/active-state
color and teal `#0f766e` as the secondary data accent.

Correction validation:

- `mise exec -- mix assets.build`
- `rg "7c3aed|a78bfa|purple|violet" apps/babs/priv/static/css/app.css apps/babs/assets/css/app.css`
  - No runtime CSS matches.
- `rg "#0969da|--color-babs-accent" apps/babs/priv/static/css/app.css apps/babs/assets/css/app.css`
  - Source and generated CSS both use operations blue.
- `mise exec -- mix test apps/babs/test/babs_web/controllers/terminal_controller_test.exs apps/babs/test/babs_web/live/kitchen_sink_live_test.exs`
  - 14 tests, 0 failures.

## References

- `BAB-1004` UI Design Spec
- `BAB-1503` Phase Delivery Workflow
- `BAB-2232` Phase 13a PRP
- Tailwind CSS official Phoenix installation guide
- Tailwind UI Application UI
- shadcn/ui component/token references
- Petal Components
- Tremor dashboard component references

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-07 | Initial version | — |
| 2026-05-07 | Define Phase 13a.1 Tailwind-backed UI correction scope, plan, rollback, and acceptance criteria | Codex |
| 2026-05-07 | Fold Trinity R1 blockers and record R2 GLM/DeepSeek PASS for plan approval | Codex |
| 2026-05-07 | Complete Tailwind UI foundation implementation, validation, HTTP smoke, screenshot artifact, and Trinity implementation PASS | Codex |
