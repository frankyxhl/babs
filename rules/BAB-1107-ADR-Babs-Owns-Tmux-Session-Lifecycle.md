# ADR-1107: Babs Owns Tmux Session Lifecycle

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Accepted
**Supersedes:** Earlier "operator-managed tmux" framing implicit in `BAB-1001` (pre-2026-05-03)

---

## Context

The original Babs scope assumed citizen tmux sessions were created and managed externally — operator runs `tmux new-session` manually, Babs attaches via `erlexec`. This was inverted in the v0.1 scope redefinition (2026-05-03): BabsWeb gains click-to-spawn, which requires Babs to programmatically create the tmux session.

Once Babs creates the session, it follows that Babs also destroys it, monitors its health, and decides recovery semantics. The choice is no longer "attach" vs "lifecycle owner" — Babs is the lifecycle owner end-to-end.

## Decision

**Babs owns tmux session lifecycle for every Citizen it hosts**, end-to-end:

| Lifecycle event | Babs action |
|-----------------|-------------|
| **Citizen `start`** | `tmux new-session -d -s babs-<name>` (detached, `babs-` prefix per naming convention below); `cd <name>.bob/`; spawn AI CLI via `erlexec`; open Hardline.Pane GenServer; ready |
| **Citizen `stop`** | Polite TERM to AI CLI process → 2s grace → `tmux kill-session -t babs-<name>`; SQLite mark `:stopped`; `<name>.bob/` directory **preserved** |
| **Citizen `restart`** | `stop` + `start` atomic, with same cwd and same AI CLI config |
| **Babs node restart** | On `:babs_citizens` startup, scan tmux for sessions matching `^babs-` prefix; reattach via fresh `erlexec` port to existing detached sessions; resume from where the AI was left off (see `BAB-1110`) |
| **Citizen `archive`** | Currently equivalent to `stop`; v0.3+ may add `.bob/` move to `_archive/` |
| **Spawn failure** | SQLite row marked `:failed`; tmux session (if partially created) `tmux kill-session`; `.bob/` (if created) preserved for forensics; **no auto-cleanup** |

## Pre-dev Decisions (formalized here)

These were surfaced and confirmed during the v0.1 scope redefinition session:

1. **Citizen kill semantics (v0.1 = `stop`)**: `tmux kill-session` + preserve `.bob/` + SQLite `:stopped`. Operator can later add explicit `archive` action that moves `.bob/` to `_archive/`. v0.1 does NOT delete `.bob/` automatically — preserves transcripts and any AI-created files for forensics/audit.
2. **Spawn failure rollback**: Mark SQLite row `:failed`. Do NOT auto-cleanup. Operator inspects forensically, decides whether to delete `.bob/` or retry.
3. **Same-name reuse after stop**: After stop, the citizen's SQLite row is `:stopped` (not deleted). `start` of same name reuses the row, reuses `.bob/`, reuses cwd. This is "the worker came back to work", not "a new worker."

## tmux Session Naming Convention

All Babs-managed tmux sessions are prefixed `babs-<citizen_name>` (e.g. `babs-alex`, `babs-mayor`). This:
- Distinguishes Babs sessions from operator's personal tmux usage
- Lets `:babs_citizens` reattach scan be unambiguous (`tmux ls | grep '^babs-'`)
- Avoids name collision when operator already has a session named `alex`

## Why Babs Owns Lifecycle (vs operator-managed)

1. **Click-to-spawn UI in Phase 4 requires programmatic session creation** — UI doesn't have access to operator's shell.
2. **Restart-resume semantics require Babs to know which sessions belong to it** — `babs-` prefix is the discriminator.
3. **Multi-machine future (v0.2+ federation) requires session-as-resource** — Babs as lifecycle owner is the only consistent model.
4. **`stop` semantics demand consistent destruction** — operator `tmux kill-session` may or may not happen; Babs's `stop` always does.

## What Stays the Operator's Responsibility

- Initial Babs node setup (mix release, `mix phx.server`)
- Tailscale connectivity for cross-machine federation
- Manually running `tmux attach -t babs-<name>` if the operator wants to inspect a session from terminal (read-only inspection is fine — Babs's `erlexec` port is a separate attach instance)

## Consequences

- `BAB-1102` Citizen subtree must include `Citizen.Lifecycle` module that wraps tmux + erlexec calls (was previously implied to be a thinner module).
- `BAB-2201` Phase 1 SEED must include start + stop + restart capability from day 1 (previously could have been deferred). Updated.
- Operator who runs their own tmux must accept the `babs-` prefix discipline — Babs will not touch un-prefixed sessions.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial decision; supersedes earlier "operator-managed" framing | Claude Code |
| 2026-05-03 | Trinity 2nd-round fix: tmux session naming in lifecycle table corrected to use `babs-<name>` prefix (was missing prefix in `start`/`stop` rows; inconsistent with naming-convention section and `BAB-1110`/`BAB-1112`) | Claude Code |
