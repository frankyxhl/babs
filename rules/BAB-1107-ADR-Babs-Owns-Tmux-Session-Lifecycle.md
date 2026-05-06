# ADR-1107: Babs Owns Tmux Session Lifecycle

**Applies to:** BAB project
**Last updated:** 2026-05-06
**Last reviewed:** 2026-05-04
**Status:** Accepted
**Supersedes:** Earlier "operator-managed tmux" framing implicit in `BAB-1001` (pre-2026-05-03)

---

## Context

The original Babs scope assumed citizen tmux sessions were created and managed externally — operator runs `tmux new-session` manually, Babs attaches via `erlexec`. This was inverted in the v0.1 scope redefinition (2026-05-03): BabsWeb gains click-to-spawn, which requires Babs to programmatically create the tmux session.

Once Babs creates the session, it follows that Babs also destroys it, monitors its health, and decides recovery semantics. The choice is no longer "attach" vs "lifecycle owner" — Babs is the lifecycle owner end-to-end.

## Decision

**Babs owns tmux session lifecycle for every Babs-owned Citizen it hosts**,
end-to-end. Phase 13 adds an explicit imported-session exception in
`BAB-1113`: external-owned imported tmux sessions can be attached/detached by
Babs, but Babs does not own kill semantics for them.

| Lifecycle event | Babs action |
|-----------------|-------------|
| **Citizen `start`** | Read `citizens/citizen-<slug>.toml`; `tmux new-session -d -s babs-<slug> -c <cwd>` (detached, `babs-` prefix per naming convention below); spawn AI CLI via `erlexec`; open Hardline.Pane GenServer; ready |
| **Citizen `stop`** | Polite TERM to AI CLI process → 2s grace → `tmux kill-session -t babs-<slug>`; mark stopped in Phase 1 memory / Phase 3 SQLite; resolved workspace `cwd` such as `<workspace_root>/<slug>/` is **preserved** |
| **Citizen `restart`** | `stop` + `start` atomic, with same cwd and same AI CLI config |
| **Babs node restart** | On `:babs_citizens` startup, scan tmux for sessions matching `^babs-` prefix; reattach via fresh `erlexec` port to existing detached sessions; resume from where the AI was left off (see `BAB-1110`) |
| **`:babs_citizens` reload / BEAM restart** | Detach BEAM-side erlexec/GenServer only; tmux session and AI CLI process keep running; ReattachScanner reacquires them. This path MUST NOT kill tmux. |
| **Citizen `archive`** | Currently equivalent to `stop`; v0.3+ may add workspace move to `_archive/` |
| **Spawn failure** | Phase 1 memory marks `:failed`; Phase 3 SQLite row marks `:failed`; tmux session (if partially created) `tmux kill-session`; config and workspace are preserved for forensics; **no auto-cleanup** |

## Pre-dev Decisions (formalized here)

These were surfaced and confirmed during the v0.1 scope redefinition session:

1. **Citizen kill semantics (v0.1 = explicit `stop`)**: only `stop_citizen/1` calls `tmux kill-session`; reload and BEAM restart never do. Preserve config and workspace; Phase 1 records status in memory, Phase 3 adds SQLite `:stopped`. Operator can later add explicit `archive` action that moves the workspace to `_archive/`. v0.1 does NOT delete workspaces automatically — preserves transcripts and any AI-created files for forensics/audit.
2. **Spawn failure rollback**: Mark Phase 1 memory / Phase 3 SQLite row `:failed`. Do NOT auto-cleanup. Operator inspects forensically, decides whether to delete workspace/config or retry.
3. **Same-slug reuse after stop**: After stop, `start` of the same slug reuses `citizens/citizen-<slug>.toml` and the configured `cwd`. This is "the worker came back to work", not "a new worker."

## tmux Session Naming Convention

All Babs-managed tmux sessions are prefixed `babs-<slug>` (e.g. `babs-clare`, `babs-dylan`, `babs-sentinel`). This:
- Distinguishes Babs sessions from operator's personal tmux usage
- Lets `:babs_citizens` reattach scan be unambiguous (`tmux ls | grep '^babs-'`)
- Avoids name collision when operator already has a session named `clare`

## Why Babs Owns Lifecycle (vs operator-managed)

1. **Click-to-spawn UI in Phase 4 requires programmatic session creation** — UI doesn't have access to operator's shell.
2. **Restart-resume semantics require Babs to know which sessions belong to it** — `babs-` prefix is the discriminator.
3. **Multi-machine future (v0.2+ federation) requires session-as-resource** — Babs as lifecycle owner is the only consistent model.
4. **`stop` semantics demand consistent destruction** — operator `tmux kill-session` may or may not happen; Babs's `stop` always does.

## What Stays the Operator's Responsibility

- Initial Babs node setup (mix release, `mix phx.server`)
- Tailscale connectivity for cross-machine federation
- Manually running `tmux attach -t babs-<slug>` if the operator wants to inspect a session from terminal (read-only inspection is fine — Babs's `erlexec` port is a separate attach instance)

## Consequences

- `BAB-1102` Citizen subtree must include `Citizen.Lifecycle` module that wraps tmux + erlexec calls (was previously implied to be a thinner module).
- `BAB-2201` Phase 1 SEED must include start + stop + restart capability from day 1 (previously could have been deferred). Updated.
- Operator who runs their own tmux must accept the `babs-` prefix discipline for
  Babs-owned sessions. Babs will not touch un-prefixed sessions unless the
  operator explicitly imports one through the Phase 13 flow described in
  `BAB-1113`.
- Phase 1 uses `citizens/citizen-<slug>.toml` + configured `cwd` as the lifecycle source of truth. SQLite becomes authoritative in Phase 3, not Phase 1.
- Phase 2a resolves relative `cwd` values under configurable `workspace_root`;
  absolute `cwd` values remain exact overrides.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial decision; supersedes earlier "operator-managed" framing | Claude Code |
| 2026-05-03 | Trinity 2nd-round fix: tmux session naming in lifecycle table corrected to use `babs-<name>` prefix (was missing prefix in `start`/`stop` rows; inconsistent with naming-convention section and `BAB-1110`/`BAB-1112`) | Claude Code |
| 2026-05-04 | Phase 1 cleanup: replace `.bob`/SQLite Phase 1 assumptions with `citizens/citizen-<slug>.toml` + configured workspaces, clarify `babs-<slug>` examples, and make reload/BEAM restart detach-only while explicit stop kills tmux | Codex |
| 2026-05-05 | Phase 2a: clarify that lifecycle preserves resolved workspace cwd under configurable `workspace_root`, while absolute cwd remains an override | Codex |
| 2026-05-06 | Clarify that Phase 13 imported external tmux sessions are an explicit `BAB-1113` exception to Babs-owned kill semantics | Codex |
