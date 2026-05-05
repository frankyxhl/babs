# ADR-1112: Multi-AI-CLI Citizen Configuration

**Applies to:** BAB project
**Last updated:** 2026-05-05
**Last reviewed:** 2026-05-04
**Status:** Accepted

---

## Context

Babs hosts AI Citizens. Originally the design implicitly assumed a single AI CLI (Anthropic's `claude`). The AI tooling landscape has diversified rapidly:

- `claude` (Anthropic Claude Code) — prevalent
- `codex` (OpenAI Codex CLI) — gaining
- `droid` (Factory.ai Droid) — emerging
- `pi` ([pi.dev](https://pi.dev/) / [pi-mono coding-agent](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent)) — open-source agent framework
- `gh copilot` (GitHub Copilot CLI) — gaining
- Future: `aider`, `ollama`-wrapped local models, others

A v0.1 Babs that hardcodes `claude` is artificially narrow. The user explicitly requested multi-CLI from day 1 (Phase 1 SEED).

## Decision

**Babs is AI-CLI-agnostic from day 1.** Citizen configuration declares which CLI to spawn; Babs treats the CLI as an opaque interactive process behind the Hardline.

### Citizen Configuration

Per-citizen config lives in `citizens/citizen-<slug>.toml`:

```toml
# citizens/citizen-clare.toml
id = "BAB-CIT-0001"
slug = "clare"
display_name = "Clare"
cli = "claude"                  # required: the binary to invoke
cli_args = ["--continue"]       # optional: argv passed to the CLI
cwd = "clare"                   # required: workspace directory name under workspace_root
description = "Claude Code seed citizen"

[env]
# Environment variables injected into the erlexec child process
# These supersede the BEAM node's environment for this citizen only
ANTHROPIC_API_KEY = "${ANTHROPIC_API_KEY}"  # interpolation from Babs node env

[role]
# Optional: for V0-L role-based routing
name = "developer"           # nullable
skills = ["elixir", "phoenix"]
```

Gate A also uses a deterministic sentinel config:

```toml
# citizens/citizen-sentinel.toml
id = "BAB-CIT-0000"
slug = "sentinel"
display_name = "Sentinel"
cli = "/bin/zsh"
cli_args = ["-f"]
cwd = "sentinel"
description = "Deterministic shell citizen for reload validation"
```

### Spawn Flow (Phase 1+)

1. Read `citizens/citizen-<slug>.toml`
2. Resolve `[env]` interpolations from Babs node environment
3. Resolve `cwd` under configurable `workspace_root` unless it is absolute
4. `tmux new-session -d -s babs-<slug> -c <resolved-cwd>` (detached)
5. `erlexec` opens a port that runs the citizen's CLI inside the tmux pane:
   - Process: `<cli>` with `<cli_args>`
   - Working dir: `<resolved-cwd>`
   - Env: merged (Babs node env + `[env]` overrides)
6. `Hardline.Pane` GenServer spawned to manage the port; PubSub topic `pane:<slug>` published

### CLI Compatibility Matrix (v0.1 day-1 expectations)

| CLI | Authenticate via | Tested in Phase 0 spike? | Notes |
|-----|------------------|--------------------------|-------|
| `claude` | `ANTHROPIC_API_KEY` env | yes | reference implementation |
| `codex` | `OPENAI_API_KEY` env | yes (1 of 2 mandatory) | |
| `droid` | Factory.ai env vars | encouraged | |
| `pi` | per pi-mono docs | encouraged | |
| `gh copilot` | `gh auth login` (file-based) | optional | needs PATH to `gh` + login state |

Phase 0 spike must validate `claude` and `codex` minimum; the rest are "expected to work" by virtue of being interactive TTY apps.

### What Babs Does NOT Do

- **Parse CLI output for structured commands** — the CLI's stdout is opaque bytes streamed to xterm.js / persisted to transcript
- **Translate prompts between CLIs** — each CLI gets the same Ticket body as initial input; CLIs that need different prompt formats are responsibility of the operator (or, in V0-L, Mayor)
- **Interpose on auth** — credentials are env vars; Babs is a passthrough
- **Quota / cost tracking** — out of scope for v0.1 (flagged for v0.2 by Trinity review `BAB-1006`)

### Failure Modes

- CLI missing from PATH → spawn fails; Phase 1 in-memory status marks `:failed`; Phase 3 SQLite citizen row marks `:failed` per `BAB-1107`
- CLI authenticates but quota exhausted → CLI itself errors in pane; Babs sees the bytes, doesn't intercept
- CLI version mismatch / breaking change → operator's responsibility to upgrade or pin

## Why Config-File-Driven (vs UI-only)

1. **Phase 1 has no UI to configure citizens** (spawn UI is Phase 4); the config file is the only handle
2. **Operators can edit configs offline** — `vim citizens/citizen-clare.toml` works even when Babs is down
3. **Configs are git-trackable** — diffs are reviewable history of how a citizen was set up
4. **Phase 4 spawn UI just writes the config file** — UI and CLI agree on the format

## Why TOML (vs YAML / JSON)

- Human-editable: TOML is friendlier than JSON, less error-prone than YAML (no whitespace gotchas)
- Standard Elixir parsing: `toml` Hex package is mature
- Frontmatter precedent: Alfred PRJ docs use YAML frontmatter, but those are inside markdown files where YAML is the established convention. Standalone config files lean TOML in the broader Elixir/Rust/etc. ecosystems.

## Consequences

- Phase 1 SEED includes a TOML parser dep + `citizens/citizen-<slug>.toml` reader
- Phase 4 NewCitizenLive form writes citizen.toml + database row (form fields → TOML)
- New CLI support = no Babs code changes, just a new `cli = "..."` value (assuming the binary works as an interactive TTY process)
- Operator who wants to test a Citizen with a different CLI doesn't need to redeploy Babs — just edits `citizen.toml` and restarts

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial decision; multi-CLI agnostic from Phase 1 | Claude Code |
| 2026-05-04 | Phase 1 cleanup: move config to `citizens/citizen-<slug>.toml`, add required `id`/`slug`/`cwd`, switch examples to Clare and deterministic Sentinel, and defer SQLite failure state to Phase 3 | Codex |
| 2026-05-05 | Phase 2a: migrate examples to `cwd = "<slug>"` and clarify that spawn uses resolved cwd under configurable `workspace_root` | Codex |
