# CHG-2265: Implement Phase 17.3 Mobile PWA Shell

**Applies to:** BAB project
**Last updated:** 2026-05-09
**Last reviewed:** 2026-05-09
**Status:** Approved
**Date:** 2026-05-09
**Requested by:** Operator
**Priority:** High
**Change Type:** Feature

---

## What

Implement **Phase 17.3: Mobile/PWA shell** from `BAB-2245`.

Phase 17.1 added node identity plus read-only APIs. Phase 17.2 added cursored
remote reads and mounted one configured peer in the local Citizens/Tickets UI.
This slice makes that browser surface usable from a phone and adds the safe PWA
shell metadata needed for installability where the browser origin permits it:

- add a web app manifest and installable icon assets;
- add conservative service-worker shell caching for static assets only;
- register the service worker only when the browser exposes service-worker
  support in a secure context;
- make Tickets, Citizens, remote read sections, and full terminal views usable
  at phone viewport widths;
- add browser-harness mobile viewport coverage.

Out of scope:

- Remote write/control endpoints. That remains Phase 17.4.
- Remote operation end-to-end hardening. That remains Phase 17.5.
- Offline Ticket/Citizen mutation, write queues, push notifications, background
  sync, or offline-first semantics.
- Public-internet deployment, auth, or TLS certificate management.
- A full theme-selector implementation.
- A full product-wide layout rewrite. This slice may improve the touched
  Tickets/Citizens/terminal views, but it should not refactor unrelated LiveViews.

Depends on:

- `BAB-2245` Phase 17 Mobile and Federated Control PRP.
- Phase 17.2 merged via PR #57 / merge commit `d4d7b03`: cursored remote reads
  and remote peer sections.
- `BAB-1004` light-first UI design amendment. This CHG also reconciles
  `BAB-1004`'s older "desktop-only / mobile not defined" note: Phase 17 now
  owns phone-viewport requirements through `BAB-2245`, so the old note is
  historical rather than authoritative for this slice.
- `BAB-1100` and `BAB-1106`: Phoenix LiveView remains the default for state UI;
  xterm.js plus Channels remains the terminal byte path.

## Why

The federation work is useful only if the operator can use Babs away from the
desktop. Phase 17.3 should make the existing local and read-only remote surfaces
practical on a phone before remote writes are introduced. This keeps the next
Phase 17 slices safer: remote write/control can be tested from the same mobile
surface that will eventually operate configured peers.

The PWA shell also needs to be explicit about browser security constraints.
Service workers require secure contexts in modern browsers; a Tailscale HTTP URL
may still be excellent for live mobile usage but should degrade gracefully when
the browser refuses service-worker registration.

## Impact Analysis

- **Systems affected:** BabsWeb root layout, static asset serving, browser boot
  JavaScript, PWA static files, Citizens/Tickets/terminal LiveViews, browser BDD
  tests, roadmap docs.
- **Runtime behavior:** Existing desktop use should remain unchanged except for
  added manifest links and harmless service-worker registration on secure
  origins.
- **Persistence:** No schema migration. The service worker may cache static
  shell assets in the browser only.
- **Security/privacy:** No remote writes. No private hostnames, private IPs,
  local checkout paths, tokens, or runtime Ticket data may appear in committed
  docs, fixtures, PR bodies, or review packets.

## Design

### PWA Manifest And Icons

Add a static manifest such as `/manifest.webmanifest` with:

- `name`: `Babs`
- `short_name`: `Babs`
- `start_url`: `/`
- `scope`: `/`
- `display`: `standalone`
- light theme/background colors matching `BAB-1004`
- 192px and 512px icon entries
- maskable icon purpose where supported

Add deterministic Babs icon assets under `priv/static/icons/`. Prefer PNG
launcher icons for broad installability and keep an SVG source asset if useful
for maintainability.

The root layout should add:

- `<link rel="manifest" href="/manifest.webmanifest">`
- `<meta name="theme-color" content="#f6f8fa">`
- `<meta name="apple-mobile-web-app-capable" content="yes">`
- `<meta name="apple-mobile-web-app-title" content="Babs">`
- `<link rel="apple-touch-icon" sizes="180x180" href="/icons/babs-180.png">`

Use `#f6f8fa` for manifest `background_color` / browser theme color and
`#ffffff` where a surface color is needed, matching `BAB-1004`.

### Safe Service Worker

Add `/sw.js` as a small hand-written service worker.

Rules:

- cache only static shell assets that are safe to reuse:
  - manifest
  - CSS
  - JavaScript boot/vendor files
  - icons
- use a named versioned cache such as `babs-shell-v1`, and remove old Babs shell
  caches on activation. The cache name must be bumped whenever cached shell
  assets change, unless the implementation ties the cache name to a build
  revision/hash;
- use network-first behavior for document navigations so LiveView pages and
  Ticket/Citizen state are not served as stale offline application state;
- do not intercept WebSocket, `/live`, `/socket`, or `/api/v1/*` as cache-first;
- do not queue or replay mutations;
- keep registration failure non-fatal.

Serve the service-worker script with update-friendly cache headers. If
`Plug.Static` cannot set a suitable per-file header, add a minimal
`BabsWeb.PwaController.service_worker/2` route for `/sw.js` that serves the
script with `Cache-Control: no-cache`.

Register the service worker from the browser boot path only when:

- `navigator.serviceWorker` exists; and
- `window.isSecureContext` is true.

If those conditions are false, the registration path should silently no-op. This
allows normal mobile browser usage over a plain local-network or Tailscale HTTP
URL even when full PWA installability is unavailable.

Reference material checked on 2026-05-09:

- MDN Web App Manifest documentation:
  `https://developer.mozilla.org/en-US/docs/Web/Manifest`
- MDN Making PWAs installable:
  `https://developer.mozilla.org/en-US/docs/Web/Progressive_web_apps/Guides/Making_PWAs_installable`
- MDN Service Worker usage / secure context note:
  `https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API/Using_Service_Workers`
- web.dev install criteria:
  `https://web.dev/articles/install-criteria`

### Mobile Layout

Phone viewport target for this slice:

- width: 360-430 CSS px
- height: 720-932 CSS px
- touch target minimum: roughly 44px for primary controls where density allows

Minimum acceptance by view:

- Tickets index:
  - header actions wrap without horizontal overflow;
  - count cards collapse to a readable narrow grid;
  - Ticket rows stack into readable blocks;
  - remote Ticket section remains visibly remote/read-only.
- Citizens index:
  - lifecycle controls wrap into rows without clipped text;
  - Open/Full/Start/Stop/Restart remain reachable by touch;
  - imported/detach-only labels remain visible;
  - remote Citizen section remains visibly remote/read-only.
- Full terminal view:
  - `full=1` still fills the phone viewport without extra page chrome;
  - non-full terminal chrome wraps without covering the xterm surface;
  - xterm resize behavior remains covered by the existing terminal BDD.

Use the existing light-first design tokens where possible. Do not add a new
purple/dark mobile-specific palette. Terminal canvases may remain black.

Existing production LiveViews still contain inline `<style>` blocks in a few
places. This slice should not perform a full product-wide style migration, but
it must not add more hardcoded dark/purple page palettes. For the touched
Tickets/Citizens mobile surfaces:

- route new shared PWA/mobile helpers through `apps/babs/assets/css/app.css`
  where practical;
- convert the touched Tickets/Citizens index page palette to the light-first
  `BAB-1004`/`--ks-*` token values instead of retaining `color-scheme: dark`;
- leave the full terminal canvas dark/black, because terminal rendering is the
  explicit exception in `BAB-1004`;
- defer a full inline-style-to-Tailwind migration for unrelated views.

### Browser Tests

Add a browser-harness BDD scenario such as `mobile pwa shell` that:

- sets a phone-sized viewport;
- opens `/tickets` and asserts no horizontal overflow plus visible primary
  navigation/actions;
- opens `/citizens` and asserts no horizontal overflow plus visible lifecycle
  controls;
- opens one full terminal route and asserts the terminal fills the viewport;
- verifies manifest metadata can be fetched and contains the expected icon sizes;
- verifies service-worker registration code no-ops safely when secure context or
  service-worker support is absent in the test harness.

Keep the BDD setup isolated. Use placeholder hosts and in-process fixtures only.

## Implementation Plan

1. **RED/GREEN: PWA metadata and static serving**
   - Add tests proving root layout includes manifest/theme/apple metadata.
   - Add endpoint/static tests for `/manifest.webmanifest`, `/sw.js`, and icon
     assets. Include `Cache-Control` expectations for `/sw.js`.
   - Expand `Plug.Static` allowlist explicitly to the new static extensions this
     slice needs, expected as `~w(css js png svg webmanifest)`. Note that
     `Plug.Static` filters by extension, not by subdirectory.

2. **RED/GREEN: service-worker registration**
   - Add a small browser JS module/function so `npm run test:js` can prove with
     plain Node mocks, without jsdom:
     - secure context + support registers `/sw.js`;
     - insecure context or missing support no-ops without throwing.
   - Keep registration failure non-fatal.

3. **RED/GREEN: mobile layout**
   - Add browser-harness mobile viewport assertions for Tickets, Citizens, remote
     sections, and full terminal geometry.
   - Adjust CSS/HEEx narrowly to remove horizontal overflow and keep touch
     controls reachable.
   - Convert touched Tickets/Citizens index styling to light-first tokens while
     leaving the terminal canvas dark.

4. **Docs and roadmap**
   - Update `BAB-2300` to mark Phase 17.2 merged and add this 17.3 CHG as the
     current implementation contract.
   - Update `BAB-0000` document index.
   - Amend `BAB-1004` to record that Phase 17 supersedes the older desktop-only
     mobile-scope note.

5. **Review and validation**
   - Review this CHG with Trinity `fast-review` and fold blockers before code.
   - After implementation, run Trinity implementation review.
   - Follow `BAB-1503` / `COR-1616`, then `COR-1615` / `COR-1612` for the PR.

## Acceptance Criteria

- Root HTML exposes manifest, theme color, and mobile app metadata.
- `/manifest.webmanifest` returns a valid manifest with 192px and 512px icon
  entries, `standalone` display, and `/` scope/start URL.
- Icon assets and `/sw.js` are served by BabsWeb without exposing unrelated
  static directories.
- Browser boot code registers the service worker only in secure contexts and
  otherwise no-ops without breaking LiveView.
- Service worker caches only safe static shell assets and does not cache API,
  LiveView socket, terminal socket, or mutation routes as offline data.
- `/sw.js` is served with update-friendly cache headers.
- Tickets, Citizens, remote read sections, and full terminal views are usable at
  phone viewport width without horizontal overflow.
- Touched Tickets/Citizens mobile surfaces use light-first tokens rather than
  hardcoded dark page palettes.
- Every action button touched by the mobile shell keeps a semantic icon and an
  accessible label or visible text.
- Unit/LiveView/static tests and browser-harness BDD cover the PWA metadata,
  registration gating, and mobile viewport behavior.
- No raw secrets, private hostnames, private IPs, local checkout paths, runtime
  Ticket data, generated remote-node data, browser profiles, or cache artifacts
  are published in docs, PR body, comments, commits, tests, or fixtures.

## Validation Commands

```bash
mise exec -- mix test apps/babs/test/babs_web/endpoint_test.exs apps/babs/test/babs_web/live/citizens_live_test.exs apps/babs/test/babs_web/live/tickets_live_test.exs apps/babs/test/babs_web/live/terminal_live_test.exs --seed 1
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
mise exec -- mix test --cover
npm run test:js
BABS_BDD_SCENARIO='mobile pwa shell' npm run test:bdd
af validate --root .
git diff --check
git diff -U0 | rg -n '^\+.*(100\.[0-9]{1,3}|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|/Users/[^[:space:]]+|api_token|secret|token)' || true
```

`npm run test:e2e` may be run as a supplemental smoke gate if this slice touches
existing Playwright-covered behavior, but browser-harness is the required mobile
BDD path for Phase 17.3.

## Results

- Plan review:
  - Trinity fast-review R1 on 2026-05-09: GLM PASS; DeepSeek raw review found a
    blocker around `BAB-1004`'s older desktop-only mobile note. Folded that by
    amending `BAB-1004` and explicitly reconciling Phase 17 mobile scope.
    Also folded high/medium findings for `theme-color` meta semantics, service
    worker JS test strategy, `Plug.Static` extension scope, cache headers, and
    Tickets/Citizens light-first styling.
  - Trinity fast-review R2 on 2026-05-09: GLM PASS and DeepSeek PASS with no
    blockers. Folded advisories for `Last updated` headers, 44px touch target
    consistency, 180px `apple-touch-icon`, and service-worker cache version bump
    strategy. Marked CHG Approved.
- Implementation: Pending.
- Validation: Pending.
- Implementation review: Pending.
- PR review loop: Pending.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-09 | Initial Phase 17.3 mobile PWA shell CHG | Codex |
| 2026-05-09 | Fold Trinity plan review blockers/advisories and mark Approved | Codex |
