# PRP-2241: Phase 13f Provider Runtime Contract

**Applies to:** BAB project
**Last updated:** 2026-05-07
**Last reviewed:** 2026-05-07
**Status:** Approved
**Date:** 2026-05-07
**Requested by:** Operator
**Priority:** High

---

## What Is It?

Add Phase 13f: Provider Runtime Contract.

Phase 13a through 13e made Babs capable of multi-turn Ticket chat, direct CLI
execution, resumable compact prompts, stale-Citizen guards, and CI. The next
pre-Phase-14 preparation step is to formalize the runtime contract Babs uses to
wrap AI CLIs and terminal-backed Citizens.

The operator-provided OpenClaw wrapping research is useful inspiration, but this
phase is not a stack adoption. Babs keeps its own Elixir/Phoenix/Ecto runtime
and extracts the lessons into explicit provider contracts:

- command and argv building
- environment and cwd preparation
- prompt/input delivery mode
- session id discovery and resume semantics
- transcript/output parsing
- capability flags
- timeout and cancellation behavior
- error redaction and operator-visible diagnostics
- optional interactive Hardline attachment

## Problem

Babs now has two execution families:

- `hardline`: tmux-backed live interactive panes with transcript capture and
  operator inspection.
- `direct_cli`: supervised non-interactive AI CLI executions with provider
  session rows and reply capture.

Both families work, but provider-specific knowledge is still spread across
several layers: `Runner`, `DirectCli.Adapters`, transcript readers, prompt
assembly, Ticket delivery, and UI labels. That is manageable for four Citizens,
but it becomes fragile before:

- Phase 14 multi-role Citizens route more work automatically.
- Phase 15 lets inspector Citizens judge other Citizens' work.
- Phase 16 introduces a Mayor that uses Alfred-like rules.
- Phase 17 introduces mobile/federated nodes and remote Citizens.

Without a shared contract, every new provider or execution backend risks
re-learning how to launch, resume, parse, redact, and expose capabilities.

## Proposed Solution

Phase 13f should create a Babs-native provider runtime contract before broader
automation phases depend on it.

### 1. Provider Runtime Contract

Define a small explicit contract for provider adapters. The contract should
describe the data Babs needs, not impose one class hierarchy for every runtime.

Minimum fields:

| Field | Purpose |
|-------|---------|
| `provider` | stable provider id, e.g. `claude`, `codex`, `copilot`, `fake` |
| `backend` | `hardline` or `direct_cli` in the first implementation |
| `command` | executable and argv builder |
| `cwd_policy` | how cwd is resolved and validated |
| `env_policy` | allowlisted environment plus provider-specific home/config |
| `launch_profile` | how `safe_interactive` / `trusted_autonomous` changes command, cwd, and env behavior |
| `input_modes` | `stdin`, argv prompt, paste/submit, or terminal injection |
| `resume` | whether session resume is supported and how to pass session id |
| `session_id_parser` | how Babs extracts or confirms provider session ids |
| `reply_parser` | how Babs finds assistant replies without duplicating turns |
| `capabilities` | machine-readable flags used by routing and UI |
| `version_fingerprint` | provider CLI version or canary metadata used to detect parser/resume drift |
| `timeouts` | start, execution, capture, and cancellation bounds |
| `output_limits` | maximum stdout/stderr/transcript bytes retained before parsing/redaction |
| `redaction` | output/error cleanup before storing or rendering |
| `interactive_attach` | whether/how the operator can open a Hardline view |
| `ownership` | `babs_owned` or `external_owned` lifecycle authority for terminal backends |

The contract can be implemented as structs and behaviours in Elixir, but the
important outcome is an inspectable capability map and uniform adapter result
shape.

`launch_profile` is intentionally a first-class field because it changes more
than argv. The `trusted_autonomous` profile can add provider-specific
non-interactive trust flags and workspace trust setup, while `safe_interactive`
must avoid implicit autonomy. Phase 13f must not hide that behavior inside
provider-name conditionals.

`backend` remains an execution mode (`direct_cli`, `hardline`, or existing
reserved `lazy_tmux`). Imported external Hardline sessions are represented as
`backend: "hardline"` plus `ownership: "external_owned"` rather than a third
Hardline backend.

### 2. Contract Inventory

Before code migration, document the current behavior of each supported provider:

- Claude direct CLI
- Codex direct CLI
- Copilot direct CLI
- Fake deterministic direct adapter
- Hardline AI CLI Citizens
- Imported external Hardline Citizens
- Reserved/future provider labels such as `droid` and `pi`

The inventory must identify which providers support resume, transcript capture,
session id extraction, interactive attach, trusted autonomous launch, and
operator-visible diagnostics.

`droid` and `pi` are recognized as Citizen/provider vocabulary, but they do not
currently have direct CLI provider adapters. The Phase 13f inventory should mark
them as deferred/reserved rather than silently omitting them.

### 3. Runtime Result Shape

Normalize provider execution results so later phases can reason about them:

```elixir
%{
  status: :ok | :failed | :timeout | :cancelled | :unsupported,
  provider: "codex",
  backend: "direct_cli",
  provider_session_id: "...",
  reply: "...",
  diagnostics: %{redacted: true, summary: "..."},
  capabilities: %{},
  raw_artifact_refs: []
}
```

Raw artifacts remain local runtime artifacts. Public PRs and docs must only
include redacted summaries or fixtures.

The normalized result shape should map from today's adapter result keys without
breaking existing call sites. Existing direct adapters return reply text as
`text` and session identity as `provider_session_id`; Phase 13f may expose
`reply` as a clearer public field, but it must document and test that migration
mapping. `raw_artifact_refs` are opaque local references to runtime artifacts,
such as a transcript cursor or internal capture id. They must not be absolute
paths, private hostnames, raw provider output, or credentials.

### 4. Capability-Driven Routing

Move future routing decisions toward capability checks rather than provider name
special cases. Examples:

- Phase 14 role routing can prefer Citizens whose provider contract supports
  resumable direct turns for background work.
- Phase 15 inspector automation can require `reply_parser` and
  `resume.supported?`.
- Phase 16 Mayor planning can require Alfred/SOP access as a capability, not a
  hardcoded Citizen name.
- Phase 17 remote Citizens can advertise read/write/control capability from the
  node contract and provider contract.

### 5. OpenClaw-Inspired Boundaries

Borrow these product/architecture ideas only as patterns:

- Make provider wrappers explicit and inspectable.
- Keep provider-specific command and parsing logic behind adapters.
- Treat capabilities as runtime data.
- Prefer durable session records over pane scraping when available.
- Keep escape hatches for interactive inspection.

Do not adopt OpenClaw runtime dependencies, process supervisors, storage, or UI
stack in this phase.

## Out of Scope

- Replacing the existing direct CLI implementation in one large refactor.
- Removing Hardline/tmux.
- Adopting OpenClaw dependencies or file layout.
- Changing provider credentials or logging raw provider output.
- Implementing ACP/acpx or MCP loopback.
- Remote-node control from Phase 17.
- Phase 14 role routing, Phase 15 inspector decisions, or Phase 16 Mayor rules.

## Implementation Slices

Phase 13f should stay small and reviewable:

1. **13f.1 Contract + inventory**
   - Add provider runtime structs/behaviour or equivalent contract modules.
   - Add fixtures/tests for supported provider capability maps.
   - Add docs inventory for current providers.

2. **13f.2 Direct CLI adapter migration**
   - Make direct CLI adapters return the normalized result shape.
   - Preserve a compatibility mapping for existing `text` and
     `provider_session_id` fields until callers are migrated.
   - Preserve existing provider session rows and Ticket history behavior.
   - Add regression tests for Claude, Codex, Copilot, and Fake.

3. **13f.3 Hardline capability mapping**
   - Expose Hardline/Imported Hardline capabilities without changing lifecycle.
   - Ensure UI labels can read capability data instead of provider name checks.

4. **13f.4 Diagnostics and redaction**
   - Standardize redacted operator-visible diagnostics for provider failures.
   - Add privacy tests and fixtures for local paths, tokens, and raw output.

## Acceptance Criteria

- Each supported provider/backend has an explicit capability map.
- Direct CLI provider execution can be represented with one normalized result
  shape without losing existing session/reply behavior.
- Hardline and imported Hardline expose capability data without changing their
  lifecycle ownership semantics.
- Provider-specific launch/resume/reply parsing rules are discoverable from one
  contract surface.
- `lazy_tmux` remains represented in the contract because the current
  `provider_sessions` schema already reserves it.
- Tests cover command building, env policy, session id parsing, reply parsing,
  result normalization, version/canary metadata, output limits, and redaction
  fixtures.
- BDD or E2E coverage proves at least one Ticket turn still works through
  direct CLI and one through Hardline after migration.
- No raw secrets, private hostnames, private IPs, or local checkout paths are
  published in docs, PR body, comments, or fixtures.

## Validation Plan

Each implementation CHG under Phase 13f should include:

```bash
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
mise exec -- mix test --cover
npm run test:js
npm run test:e2e
npm run test:bdd
af validate --root .
git diff --check
```

Focused tests should run before broad gates. Browser-harness BDD should use an
isolated Chrome profile and `BU_CDP_URL` per `BAB-1503`.

## Review Plan

- Review this PRP with Trinity `fast-review` and fold blockers before
  implementation CHGs.
- Each implementation CHG must follow `BAB-1503` / `COR-1616`.
- GitHub PRs must use the correct project GitHub identity and follow
  `COR-1612` + `COR-1615` review loops.
- Maximum five GitHub Codex review rounds per PR unless the operator explicitly
  extends the loop.

## Review Results

- 2026-05-07 Trinity fast-review of this PRP: GLM PASS, DeepSeek PASS.
- Review packet:
  `.trinity/reviews/20260508-045436-rules-BAB-2241-PRP-Phase-13f-Provider-Runtime-Contract.md`
- Non-blocking advisories folded into this document:
  launch profile integration, output limits, provider version/canary metadata,
  `lazy_tmux`, imported ownership as a separate dimension, deferred `droid`/`pi`
  inventory rows, raw artifact reference definition, `text` /
  `provider_session_id` compatibility mapping, `BAB-2229`/`BAB-2300`
  references, and removal of the obsolete `mix cmd mix test.coverage`
  validation command.

## Validation Results

- 2026-05-07 `af validate --root .`: 149 documents checked, 0 issues found.
- 2026-05-07 `git diff --check`: pass.

## References

- `BAB-2232` Phase 13a Multi-Turn Ticket Sessions and Direct CLI Backend
- `BAB-2235` Phase 13a.3 Direct CLI Provider Sessions
- `BAB-2237` Phase 13b Direct CLI Resumable Prompt Compaction
- `BAB-2229` Citizen Launch Profiles for Trusted AI CLIs
- `BAB-2226` Phase 12a Relay Reliability
- `BAB-1112` Multi-AI-CLI Citizen Configuration
- `BAB-1113` Imported Tmux Session Attach
- `BAB-1503` Phase Delivery Workflow
- `BAB-2300` Build Roadmap
- Operator-provided OpenClaw wrapping research notes

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-07 | Initial Phase 13f provider runtime contract PRP | Codex |
| 2026-05-07 | Mark approved after Trinity review and fold in provider contract advisories | Codex |
