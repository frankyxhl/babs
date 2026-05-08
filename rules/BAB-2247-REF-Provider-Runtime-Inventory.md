# REF-2247: Provider Runtime Inventory

**Applies to:** BAB project
**Last updated:** 2026-05-08
**Last reviewed:** 2026-05-08
**Status:** Active

---

## What Is It?

The current public-safe inventory for Babs provider runtime contracts.

This reference documents the read-only capability rows implemented by
`Babs.Citizens.ProviderRuntime.Inventory` in Phase 13f.1. It describes what
Babs knows about each supported provider/backend/ownership combination without
running live provider commands.

## Why

Phase 14-17 automation needs routing and UI decisions to use capabilities
instead of provider-name special cases. A durable inventory keeps the contract
understandable outside the code and gives later phases a stable reference for
role routing, inspection, Mayor proposals, mobile views, and federated nodes.

## Contract Keys

Inventory rows are keyed by:

```text
{provider, backend, ownership}
```

Current backend values:

| Backend | Meaning |
|---------|---------|
| `direct_cli` | Non-interactive provider turn launched by Babs for a Ticket turn. |
| `hardline` | Interactive tmux-backed Citizen with transcript/reply capture. |
| `lazy_tmux` | Reserved future mode for starting tmux only when needed. |

Current ownership values:

| Ownership | Meaning |
|-----------|---------|
| `babs` | Babs owns the runtime row and may use the capabilities declared by it. |
| `external` | The runtime is imported/operator-owned; Babs may attach/detach but must not kill it. |
| `reserved` | Vocabulary exists, but execution is deferred. |

## Current Inventory

| Provider | Backend | Ownership | Status | Launch profiles | Input modes | Resume | Parsers | Interactive attach | Lifecycle authority | Raw artifact refs |
|----------|---------|-----------|--------|-----------------|-------------|--------|---------|--------------------|---------------------|-------------------|
| `claude` | `direct_cli` | `babs` | `supported` | `trusted_autonomous` | `argv_prompt` | provider session id | session id + reply | no | no kill, no detach | none |
| `codex` | `direct_cli` | `babs` | `supported` | `trusted_autonomous` | `argv_prompt` | provider session id | session id + reply | no | no kill, no detach | none |
| `copilot` | `direct_cli` | `babs` | `supported` | `trusted_autonomous` | `argv_prompt` | provider session id | session id + reply | no | no kill, no detach | none |
| `fake` | `direct_cli` | `babs` | `supported` | `trusted_autonomous` | `argv_prompt` | provider session id | session id + reply | no | no kill, no detach | none |
| `ai_cli` | `hardline` | `babs` | `supported` | `safe_interactive`, `trusted_autonomous` | `terminal_injection` | tmux session | transcript/jsonl reply capture | yes | kill + detach | `transcript_cursor` |
| `ai_cli` | `hardline` | `external` | `supported` | `safe_interactive`, `trusted_autonomous` | `terminal_injection` | tmux session | transcript/jsonl reply capture | yes | detach only | `transcript_cursor` |
| `droid` | `hardline` | `reserved` | `deferred` | none | none | no | no | no | none | none |
| `pi` | `hardline` | `reserved` | `deferred` | none | none | no | no | no | none | none |
| `ai_cli` | `lazy_tmux` | `reserved` | `deferred` | none | none | no | no | no | none | none |

## Public Capability Surface

The implementation exposes:

- `Babs.Citizens.ProviderRuntime.Inventory.all/0`
- `Babs.Citizens.ProviderRuntime.Inventory.get/2`
- `Babs.Citizens.ProviderRuntime.Inventory.get/3`
- `Babs.Citizens.ProviderRuntime.Inventory.for_config/1`
- `Babs.Citizens.ProviderRuntime.Inventory.capability_map/1`

`for_config/1` resolves direct CLI rows through
`Babs.Citizens.DirectCli.Adapters.resolve/1`. Provider detection should stay in
that adapter layer rather than being duplicated in the inventory.

`capability_map/1` returns string-keyed, public-safe data suitable for UI,
routing, docs, and remote capability exchange.

## Privacy Rules

`raw_artifact_refs` may contain opaque descriptors such as
`%{"kind" => "transcript_cursor"}`. It must not contain:

- absolute local paths;
- private hostnames or private IPs;
- raw provider stdout/stderr;
- raw Ticket prompts or replies;
- tokens, credentials, or environment maps.

Direct CLI rows currently expose an empty raw artifact ref list. Hardline rows
may expose `transcript_cursor` because it describes a local runtime cursor kind,
not a filesystem path or host-specific locator.

## Deferred Rows

`droid`, `pi`, and `lazy_tmux` are visible so UI/config code can distinguish
"known but not executable yet" from "unknown provider." They must not be treated
as supported execution backends until a later CHG implements and tests provider
behavior.

## References

- `BAB-1112` Multi-AI-CLI Citizen Configuration
- `BAB-1113` Imported Tmux Sessions Are External-Owned Hardlines
- `BAB-2235` Implement Phase 13a3 Direct CLI Provider Sessions
- `BAB-2241` Phase 13f Provider Runtime Contract
- `BAB-2246` Implement Phase 13f.1 Provider Runtime Contract and Inventory

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-08 | Initial provider runtime inventory reference for Phase 13f.1 | Codex |
