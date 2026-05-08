# CHG-2263: Implement Phase 17.1 Node Identity and Read API

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

Implement **Phase 17.1: Node identity and read API** from `BAB-2245`.

This slice introduces the local-node configuration and read-only HTTP API that
later Phase 17 slices will use for mobile and cross-node federation. It does
not add remote write/control and does not mount peer nodes in the UI yet.

This slice will:

- Add configurable local node identity: `id`, `name`, and optional
  `public_url`.
- Add peer/capability config parsing for the Phase 17 TOML shape, including
  per-peer and per-Citizen capability allowlists.
- Add a JSON API pipeline and read-only endpoints:
  - `GET /api/v1/node`
  - `GET /api/v1/citizens`
  - `GET /api/v1/citizens/:slug`
  - `GET /api/v1/citizens/:slug/transcript`
  - `GET /api/v1/tickets`
  - `GET /api/v1/tickets/:id`
- Keep every endpoint read-only. No API endpoint in this slice mutates Tickets,
  Citizens, tmux sessions, direct CLI sessions, provider sessions, transcripts,
  or runtime configuration.
- Return bounded transcript output only, using the existing transcript replay
  boundary and line/tail limits.
- Use placeholder hostnames in docs/tests and avoid private operator machine
  names, private IPs, local paths, tokens, and runtime data in public artifacts.

Out of scope:

- Real-time/cursored events. That is Phase 17.2.
- Remote node mounting in local UI. That is Phase 17.2.
- PWA/mobile shell and phone viewport polish. That is Phase 17.3.
- Remote write/control endpoints and audit events. That is Phase 17.4 and must
  first reconcile `BAB-1109`.
- Multi-node BDD/E2E. This slice may add read API request tests; live remote
  multi-node browser tests start in Phase 17.2.
- Authentication/secret distribution. The current operator model remains
  Tailscale/local-network scoped; public-internet exposure remains out of
  scope.
- Pagination for Citizens/Tickets list endpoints. Phase 17.1 returns bounded
  local-node snapshots; pagination can be added when remote UI scale requires
  it.

Depends on:

- `BAB-2245` Phase 17 Mobile and Federated Control PRP.
- Phase 16.4 merged: Mayor proposals can now materialize child Tickets and
  complete the single-node flywheel needed before federation.

## Why

Phase 17 needs a stable local-node read contract before Babs can display remote
nodes, build mobile views, or add guarded remote control. Starting with a
read-only API keeps the first federation slice small, auditable, and safe: it
exposes the same local state the browser already reads, without adding cross-node
writes or a distributed data model.

## Impact Analysis

- **Systems affected:** BabsWeb router/controllers, read-only Citizen status
  snapshots, Ticket store presentation, runtime config parsing, tests, roadmap
  docs.
- **Runtime behavior:** Local browser behavior should not change. New API
  endpoints return JSON snapshots for the local node.
- **Persistence:** No schema migration and no runtime data writes. Federation
  config is read from process/app env or an external TOML file.
- **Security/privacy:** API is intentionally read-only in this slice. Tests and
  docs must use placeholder hostnames such as `http://babs-peer.example:4000`.

## Design

### Config Location

Use an external TOML config file selected by `BABS_FEDERATION_CONFIG`.

If the env var is unset, Phase 17.1 falls back to in-memory defaults:

```toml
[node]
id = "local"
name = "Local Babs"
public_url = ""

[peers]
```

The default is intentionally not a repo file. Operators can later place a
private file under their runtime root, for example
`$BABS_ROOT/config/federation.toml`, without committing it.

Supported TOML shape follows `BAB-2245`:

```toml
[node]
id = "node-local"
name = "Local Babs"
public_url = "http://babs-local.example:4000"

[peers.workbench]
name = "Workbench Babs"
url = "http://babs-workbench.example:4000"
capabilities = ["read", "control"]

[peers.workbench.citizens.dylan]
capabilities = ["read"]
```

Validation rules:

- Node ids and peer keys must be URL-safe slugs:
  `^[a-z][a-z0-9-]{0,47}$`.
- Node/peer names are non-empty strings capped at 80 characters.
- URLs are optional for `node.public_url`, required for peers, and must be
  `http://` or `https://`. Empty `node.public_url` values normalize to `nil`
  and render as JSON `null`.
- Capabilities are normalized to unique canonical values from `read`, `write`,
  `control`.
- Capability expansion happens in the parser:
  - `read` stays `["read"]`.
  - `write` expands to `["read", "write"]`.
  - `control` expands to `["read", "write", "control"]`.
  - Mixed lists are deduplicated and returned in canonical order.
- Per-Citizen capabilities override peer defaults but do not grant access to an
  unknown peer.
- Local node capabilities are not configurable in Phase 17.1. `/api/v1/node`
  always advertises `["read"]` for the local node because this slice exposes
  read-only endpoints only.
- The federation facade reads the TOML file on each API request in Phase 17.1.
  There is no watcher or cache yet; changing `BABS_FEDERATION_CONFIG` itself
  still requires the normal runtime environment to be restarted.
  Implementation should isolate the read site in one function so Phase 17.2 can
  replace it with a cache/watcher without restructuring controllers.
- If `BABS_FEDERATION_CONFIG` is set and the file is missing, unreadable, or
  malformed, the facade returns an explicit config error. It does not silently
  fall back to the default identity, because that could hide a bad federation
  setup.
- Per-Citizen override tables are only valid inside a valid peer table. A peer
  with Citizen overrides but missing required peer fields such as `name` or
  `url` is a parse error.

### API Shape

`GET /api/v1/node`:

```json
{
  "node": {
    "id": "node-local",
    "name": "Local Babs",
    "public_url": "http://babs-local.example:4000",
    "capabilities": ["read"],
    "api_version": "v1"
  },
  "peers": [
    {
      "id": "workbench",
      "name": "Workbench Babs",
      "url": "http://babs-workbench.example:4000",
      "capabilities": ["read", "write", "control"],
      "citizens": {
        "dylan": {"capabilities": ["read"]}
      }
    }
  ]
}
```

Peers are rendered as a stable array sorted by peer id. The TOML source is a
map keyed by peer id, but the API makes the id explicit in each peer object so
clients do not depend on JSON object ordering.

`GET /api/v1/citizens` returns:

```json
{"node": {"id": "node-local", "name": "Local Babs"}, "citizens": []}
```

Each Citizen item is a read-only projection of `StatusSnapshot`, excluding host
paths where possible. The API should prefer labels such as `cwd_label` over raw
absolute `cwd` for public JSON. If an existing UI field currently requires a raw
path, that raw path must not be exposed through the federation API in Phase 17.1.

Citizen projections must use this allowlist:

- `id`
- `slug`
- `display_name`
- `cli_label`
- `roles`
- `ticket_backend`
- `ticket_backend_label`
- `cwd_label`
- `durable_status`
- `live_status`
- `visual_state`
- `actions`
- `provider_runtime`
- `provider_runtime_capabilities`
- `interactive_attach`
- `kill_authority`
- `detach_authority`
- `ownership`
- `imported`
- `ownership_badge`
- `lifecycle_reminder`

Citizen projections must exclude raw `cwd` and raw `last_error`. `last_error`
can contain filesystem paths in existing runtime rows; path-safe error
projection can be added later with a redaction helper.
Projection keys are JSON key names, not internal Elixir atom names. Internal
boolean keys such as `interactive_attach?` must be rendered without the `?`
suffix. `lifecycle_reminder` is a fixed display string from
`ImportedHardline.reminder/1`; `target_label` is excluded in Phase 17.1 because
imported tmux target names are operator-controlled strings and may contain
private labels.
`roles` renders as a list of role-name strings, not full internal role maps.
`provider_runtime` renders only the safe summary subkeys `provider`, `backend`,
`ownership`, and `status`.

Citizen list and detail endpoints return the same allowlisted projection shape
for each Citizen. Fields with no value render as JSON `null`; they are not
silently omitted.

`GET /api/v1/citizens/:slug` returns:

```json
{
  "node": {"id": "node-local", "name": "Local Babs"},
  "citizen": {
    "id": "BAB-CIT-00000000-0000-0000-0000-000000000000",
    "slug": "clare",
    "display_name": "Clare",
    "cli_label": "claude",
    "roles": ["developer"],
    "ticket_backend": "hardline",
    "ticket_backend_label": "Hardline",
    "cwd_label": "clare",
    "durable_status": "running",
    "live_status": "up",
    "visual_state": "idle",
    "actions": ["open", "full", "stop", "restart"],
    "provider_runtime": {
      "provider": "ai_cli",
      "backend": "hardline",
      "ownership": "babs",
      "status": "supported"
    },
    "provider_runtime_capabilities": {"interactive_attach": true},
    "interactive_attach": true,
    "kill_authority": true,
    "detach_authority": true,
    "ownership": "babs",
    "imported": false,
    "ownership_badge": null,
    "lifecycle_reminder": null
  }
}
```

`GET /api/v1/citizens/:slug/transcript` returns bounded output:

```json
{
  "node": {"id": "node-local", "name": "Local Babs"},
  "citizen_slug": "clare",
  "transcript": {"output": "...", "truncated": false, "lines": 200, "returned_lines": 12}
}
```

This endpoint uses the Citizen record's cwd only internally and must not return
the cwd path.

Transcript query parameters:

- `lines`: optional integer, default `200`, allowed range `1..1000`.
- `tail_bytes`: optional integer, default `1048576`, allowed range
  `1..1048576`.

Invalid query values return JSON 400 with code `invalid_params`. The transcript
uses output records only. `truncated` is true when the transcript file is larger
than the requested tail window or when output line pruning occurred.
`lines` echoes the requested line limit; `returned_lines` is the actual number
of lines returned after pruning.

`GET /api/v1/tickets` returns Ticket summaries plus invalid-file counts, not raw
host paths for invalid entries.

```json
{
  "node": {"id": "node-local", "name": "Local Babs"},
  "tickets": [
    {
      "id": "T-2026-05-09-001",
      "type": "assignment",
      "state": "open",
      "assigner": "user",
      "title": "Example Ticket",
      "assignees": [],
      "assignee_role": "developer",
      "inspector": "user",
      "priority": "normal",
      "parent_ticket": null,
      "created_at": "2026-05-09T00:00:00Z",
      "updated_at": "2026-05-09T00:00:00Z",
      "metadata": {}
    }
  ],
  "invalid": {"count": 0}
}
```

`GET /api/v1/tickets/:id` returns the Ticket projection and history. It must not
include `ticket.path`.

All API projections must use explicit field whitelists. Do not serialize
`Ticket`, `CitizenRecord`, or `StatusSnapshot` structs/maps directly and then
drop fields afterward.

Ticket summary projections must construct maps from exactly these fields:
`id`, `type`, `state`, `assigner`, `assignees`, `assignee_role`, `inspector`,
`priority`, `parent_ticket`, `created_at`, `updated_at`, `metadata`, and
`title`.

Ticket detail projections use the summary fields plus `body` and `history`.
`warnings` and `path` are intentionally excluded.

JSON error shape:

```json
{"error": {"code": "not_found", "message": "Ticket T-0000-00-00-000 was not found"}}
```

Use stable `code` values such as `not_found`, `invalid_id`, and `read_failed`.
Error messages must use existing redacted error text and must not include host
paths.
Malformed or unreadable federation config returns HTTP 503 with
`code: "config_error"`.
Unreadable Ticket roots return HTTP 500 with `code: "read_failed"`; parseable
but invalid Ticket files remain represented by the list endpoint's
`invalid.count` value. Error responses intentionally omit the `node` envelope so
clients can handle failures before node identity is available.

## Implementation Plan

1. **RED/GREEN: federation config parser**
   - Add `Babs.Citizens.Federation.Config` and structs for node, peer, and
     capability overrides.
   - Unit test defaults, valid TOML, invalid ids, invalid URLs, duplicate/unknown
     capabilities, per-Citizen overrides, and privacy-safe fixture values.

2. **RED/GREEN: node info boundary**
   - Add a small `Babs.Citizens.Federation` read facade that returns node and
     peer config from opts/application env.
   - Add tests proving default config does not require a file and external TOML
     values are normalized.

3. **RED/GREEN: JSON API routing**
   - Add `:api` pipeline with JSON accepts.
   - Add versioned controller(s) under `BabsWeb.Api.V1`.
   - Add request tests for `/api/v1/node`, citizens list/detail, tickets
     list/detail, and transcript.

4. **Privacy-safe projections**
   - Add presenter helpers for API JSON or keep projection functions inside the
     API boundary.
   - Use explicit allowlist projections for all JSON resources.
   - Remove raw `cwd`, `path`, and invalid file paths from API responses.
   - Keep API responses deterministic for tests.

5. **Docs and roadmap**
   - Keep `BAB-2300` and `BAB-0000` in sync. The initial CHG already marks
     Phase 16 as merged through 16.4 and records `BAB-2263`; implementation
     results should update the same docs if scope changes.

6. **Review and validation**
   - Review this CHG with Trinity `fast-review` and fold blockers before code.
   - After implementation, run Trinity implementation review.
   - Follow `BAB-1503` / `COR-1616`, then `COR-1615` / `COR-1612` for the PR.

## Acceptance Criteria

- `GET /api/v1/node` returns configured node identity and normalized peer
  capability config.
- `GET /api/v1/citizens` and `GET /api/v1/citizens/:slug` return read-only
  Citizen projections with no raw local paths.
- `GET /api/v1/citizens/:slug/transcript` returns bounded transcript output and
  no raw cwd/path.
- `GET /api/v1/tickets` and `GET /api/v1/tickets/:id` return read-only Ticket
  projections/history with no raw ticket file paths.
- Unknown Citizen/Ticket resources return JSON 404s.
- Capability config parser has unit coverage for valid and invalid TOML.
- No endpoint in this slice can mutate runtime state.
- No raw secrets, private hostnames, private IPs, local checkout paths, runtime
  Ticket data, or generated node data are published in docs, PR body, comments,
  or fixtures.

## Validation Commands

```bash
# Run after the RED/GREEN implementation creates these focused test files.
mise exec -- mix test apps/babs_citizens/test/babs_citizens/federation_config_test.exs apps/babs/test/babs_web/controllers/api_v1_read_controller_test.exs
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
npm run test:js
af validate --root .
git diff --check
git diff -U0 | rg -n '^\+.*(100\.[0-9]{1,3}|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|/Users/[^[:space:]]+|api_token|secret|token)' || true
```

## Results

- Plan review:
  - Trinity fast-review R1 on 2026-05-09: GLM PASS. DeepSeek returned three
    blockers around local node capabilities, capability implication semantics,
    and explicit path-safe projection contracts. Folded all blockers plus
    advisories for error shape, peer array rendering, empty `public_url`,
    final-state focused test command wording, and config reload semantics.
  - Trinity fast-review R2 on 2026-05-09: GLM PASS. DeepSeek raw output still
    found blockers around expanded capability examples and Citizen projection
    allowlists. Folded those blockers plus advisories for ticket list shape,
    Citizen detail shape, config file error semantics, peer override validity,
    and transcript query parameters.
  - Trinity fast-review R3 on 2026-05-09: GLM PASS. DeepSeek raw output still
    found blockers around Elixir `?` suffixes in JSON keys and incomplete
    Ticket projection allowlists. Folded both blockers plus advisories for
    transcript key naming, config-error HTTP status, imported target label
    exposure, pagination deferral, and list/detail projection shape.
  - Trinity fast-review R4 on 2026-05-09: GLM PASS and DeepSeek PASS with no
    blockers. Folded non-blocking advisories for provider runtime subkeys, roles
    projection as names, transcript `returned_lines`, explicit error envelope
    behavior, config-read extension point, and Ticket-root read errors.
- Implementation:
  - Added `Babs.Citizens.Federation.Config` and `Babs.Citizens.Federation` for
    local node identity, sorted peers, normalized capability expansion, and
    per-Citizen peer overrides.
  - Added `/api/v1` JSON routing and read-only endpoints for node, Citizens,
    bounded Citizen transcripts, Tickets list, and Ticket detail/history.
  - Added explicit allowlist projections for Citizen and Ticket JSON responses;
    raw `cwd`, raw Ticket paths, `last_error`, `target_label`, and invalid-file
    paths are not serialized.
  - Added transcript replay metadata via `replay_output_info/2` while preserving
    the existing `replay_output/2` output-only API.
  - Added `BABS_FEDERATION_CONFIG` runtime config support.
- Validation before implementation review:
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/federation_config_test.exs apps/babs/test/babs_web/controllers/api_v1_read_controller_test.exs --seed 1`
    passed: 15 tests, 0 failures.
  - `mise exec -- mix format --check-formatted` passed.
  - `mise exec -- mix compile --warnings-as-errors` passed.
  - `mise exec -- mix test` passed: 601 tests, 0 failures.
  - `npm run test:js` passed: 15 tests, 0 failures.
  - `af validate --root .` passed: 173 documents, 0 issues.
  - `git diff --check` passed.
  - Privacy grep over the diff found no private IPs, local user paths, or
    credential-like strings.
- Implementation review:
  - Trinity fast-review R1 on 2026-05-09: GLM PASS and DeepSeek PASS with no
    blockers. Folded DeepSeek's advisory about preserving falsey
    `provider_runtime` subkey values in the safe projection helper. Deferred
    broader API auth/CORS/cache topics to later Phase 17 slices; retained the
    existing manual controller dispatch style used elsewhere in BabsWeb.
- GitHub Codex review:
  - R1 on PR #56 found one P2 issue: transcript output may contain arbitrary
    non-UTF-8 PTY bytes and could fail JSON encoding. Fixed by replacing invalid
    UTF-8 bytes in the API response boundary while leaving raw transcript replay
    behavior unchanged. Added a controller regression test for invalid transcript
    bytes.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-09 | Initial Phase 17.1 node identity and read API CHG | Codex |
| 2026-05-09 | Fold Trinity R1 plan review blockers and advisories | Codex |
| 2026-05-09 | Fold Trinity R2 plan review blockers and advisories | Codex |
| 2026-05-09 | Fold Trinity R3 plan review blockers and advisories | Codex |
| 2026-05-09 | Mark Approved after Trinity R4 PASS/PASS and fold non-blocking advisories | Codex |
| 2026-05-09 | Implement Phase 17.1 read API and record validation results | Codex |
| 2026-05-09 | Record Trinity implementation review PASS/PASS and folded advisory | Codex |
| 2026-05-09 | Fold GitHub Codex R1 P2 transcript JSON encoding finding | Codex |
