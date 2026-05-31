# CHG-2272: Custom Telemetry Gauges

**Applies to:** BAB project
**Last updated:** 2026-05-31
**Last reviewed:** 2026-05-31
**Status:** Approved
**Date:** 2026-05-31
**Requested by:** @frankyxhl via GitHub issue #82
**Priority:** P2
**Change Type:** Normal

---

## What

Implement `BAB-2271` slice 1.3 / GitHub issue #82 by adding Babs-domain
telemetry gauges for:

- Citizen counts tagged by durable status: `running`, `stopped`, `failed`.
- Live Hardline count.
- Ticket counts tagged by state: `open`, `in_progress`, `pending_approval`,
  `closed`, `cancelled`.

The gauges will be emitted by the existing Babs `:telemetry_poller` supervisor
and registered in `Babs.Telemetry.metrics/0` so Phoenix LiveDashboard can show
them on the Metrics tab.

## Why

The generic BEAM, Phoenix, and Ecto metrics added in slice 1.2 show runtime
health, but not operator workflow health. The operator needs an at-a-glance
view of whether Citizens are running, Hardlines are live, and Tickets are
backing up in any state.

## Impact Analysis

- **Systems affected:** `Babs.Telemetry`, the Babs telemetry poller,
  `StatusSnapshot`, `Hardline.Pane` registry reads, and `Tickets.Api` read-only
  listing.
- **Runtime behavior:** one periodic read-only measurement pass every 10s,
  sharing the existing telemetry poller period. No writes, no lifecycle changes,
  and no direct tmux or PTY operations.
- **Dashboard behavior:** LiveDashboard Metrics receives custom Babs gauges
  alongside existing Phoenix/Ecto/VM metrics.
- **Rollback plan:** remove the Babs custom measurement MFA from the poller,
  remove the three custom metric definitions, and delete the measurement module
  and tests.

## Acceptance Criteria

- [ ] A periodic measurement emits `babs.citizens.count`, tagged by `status`.
- [ ] A periodic measurement emits `babs.hardlines.live`.
- [ ] A periodic measurement emits `babs.tickets.count`, tagged by `state`.
- [ ] `Babs.Telemetry.metrics/0` registers the custom gauges for LiveDashboard.
- [ ] Measurement functions are unit-tested against known Citizen, Hardline, and
      Ticket fixture state.
- [ ] Validation passes: `mix format --check-formatted`,
      `mix compile --warnings-as-errors`, `mix test`, `npm run test:js`,
      `af validate --root .`, and `git diff --check`.
- [ ] Short local dashboard smoke confirms the Metrics tab still renders.

## Implementation Plan

1. Add a small measurement module under `apps/babs/lib/babs/telemetry/`.
2. Build measurement data from existing read APIs:
   `StatusSnapshot.list/1`, `Babs.Citizens.PaneRegistry` registry reads, and
   `Tickets.Api.list_tickets/1`.
3. Dispatch telemetry events as `[:babs, :citizens]`, `[:babs, :hardlines]`,
   and `[:babs, :tickets]` with the expected measurements and tags.
4. Add the measurement MFA to the existing `Babs.Telemetry` poller.
5. Register custom `last_value` metrics in `Babs.Telemetry.metrics/0`.
6. Add RED tests for metric registration and fixture-backed measurement output.
7. Run the validation stack and update this CHG with actual results.

## Review Plan

- **Plan review:** Trinity with providers `glm,deepseek,minimax` before code.
- **Implementation review:** Trinity with providers `glm,deepseek,minimax`
  before PR.
- **PR review:** GitHub Codex review loop per `COR-1615`.

## Validation Results

- 2026-05-31 plan review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2272-CHG-Custom-Telemetry-Gauges.md`
  passed with `LEGACY — 3/3 PASS · 0 FIX · 0 FAIL`;
  synthesis at
  `.trinity/reviews/20260531-222511-rules-BAB-2272-CHG-Custom-Telemetry-Gauges.md/synthesis.md`.
- `mise exec -- mix test apps/babs/test/babs/telemetry_test.exs apps/babs/test/babs/telemetry/measurements_test.exs`:
  passed, 8 tests.
- `mise exec -- mix format --check-formatted`: passed.
- `mise exec -- mix compile --warnings-as-errors`: passed.
- `mise exec -- mix test`: passed, 521 `babs_citizens` tests and 154
  `babs` tests.
- `npm run test:js`: passed, 19 tests.
- `af validate --root .`: passed, 198 documents checked.
- `git diff --check`: passed.
- Short measurement smoke:
  `Babs.Telemetry.Measurements.measurements/1` returned 9 gauge events in 35
  microseconds using fixture providers.
- 2026-05-31 implementation review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope apps/babs`
  passed with `LEGACY — 3/3 PASS · 0 FIX · 0 FAIL`;
  synthesis at `.trinity/reviews/20260531-224408-apps-babs/synthesis.md`.
- Local dashboard smoke: `BABS_HTTP_IP=0.0.0.0 mise exec -- mix phx.server`
  served `/dev/dashboard/home` with HTTP 200 and the Metrics tab present.
  In-app Browser was unavailable in this session, so the interactive tab click
  was not used as a validation gate.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-31 | Initial version | — |
