# ADR-1113: Imported Tmux Sessions Are External-Owned Hardlines

**Applies to:** BAB project
**Last updated:** 2026-05-06
**Last reviewed:** 2026-05-06
**Status:** Accepted

---

## Context

`BAB-1107` established the default v0.1 lifecycle rule: Babs creates,
reattaches, stops, and kills the tmux sessions it hosts, and those sessions use
the `babs-<slug>` prefix.

The operator now wants a Phase 13 feature where an existing Citizen can attach
to a tmux session that already exists outside Babs and has not previously been
attached by Babs. This is useful when a useful AI CLI or shell is already
running in tmux and should be brought into the Babs browser/ticket workflow
without restarting it.

That feature conflicts with a literal reading of `BAB-1107` if Babs treats the
external tmux session as lifecycle-owned. It is safe if Babs treats the session
as explicitly imported and externally owned.

## Decision

Babs may explicitly import an existing tmux pane as a Citizen Hardline, but the
default ownership mode for imported sessions is **external**.

An external-owned imported Hardline has these rules:

| Event | Babs action |
|-------|-------------|
| **Import / attach** | Operator selects an existing tmux pane from the browser UI. Babs records the exact tmux target and starts a Hardline.Pane attached to that pane. |
| **Browser reload** | Same as Babs-owned Hardlines: browser reconnects to the existing Hardline and transcript stream. |
| **Babs node restart** | Babs reattaches only to persisted imported tmux targets. It does not scan all unprefixed sessions as candidates for automatic ownership. |
| **Imported session missing** | Mark the Citizen unavailable/failed with a visible error. Do not create a replacement tmux session automatically. |
| **External pane dies at runtime** | Mark the Citizen unavailable/failed with a visible error. Do not create a replacement tmux session automatically. Do not kill or rename any external session while recovering. |
| **Stop / detach** | Stop the Babs-side Hardline and mark the Citizen stopped or detached. Do **not** run `tmux kill-session` for external-owned imports. |
| **Restart** | For external-owned imports, restart means detach then reattach if the same tmux target still exists. It does not kill and recreate the session. |

`BAB-1107` remains authoritative for Babs-owned sessions. This ADR defines the
explicit exception for operator-imported sessions.

## Invariants

- One Citizen still has at most one active Hardline.
- Attaching an imported tmux session to an existing Citizen requires that
  Citizen to have no active Babs-owned Hardline, or that the operator first
  stops/detaches the current Hardline.
- Phase 13 attaches imported tmux sessions to existing Citizen identities only.
  Creating a new Citizen identity directly from an imported pane is deferred
  until a separate lifecycle proposal approves that flow.
- Babs must never silently replace a Babs-owned session with an imported
  session.
- Babs must never silently take kill ownership of an imported external session.
- Imported sessions are not discovered by the normal `^babs-` reattach scan.
  They are reattached only from explicit persisted import records.
- Ticket/Billboard history remains authoritative. The imported terminal is a
  transport and UI surface, not a second coordination store.

## Persistence

Phase 13 should persist enough information to reattach deterministically:

- Citizen slug and display name.
- Ownership mode: `babs` or `external`.
- tmux session name.
- tmux window index or id.
- tmux pane id.
- Optional observed command and pane current path for UI display only.
- Import timestamp and last attach error.

The exact schema may use dedicated SQLite columns or structured `metadata`, but
the behavior above is mandatory.

## UI Semantics

The browser should make ownership visible:

- Babs-owned Citizens show normal Start / Stop / Restart behavior.
- External-owned imported Citizens show a persistent badge such as
  `Imported · External-owned`.
- Lifecycle controls for external-owned imports also show a persistent
  `Detach only · tmux stays running` reminder or equivalent tooltip text.
- External-owned imported Citizens show Attach / Detach / Reattach language
  where possible.
- If a Stop button is reused for layout consistency, the confirmation/copy must
  make clear that Babs will detach and will not kill the external tmux session.
- Candidate tmux sessions should be listed explicitly. Babs should not
  auto-import all unmanaged sessions.

## Rejected Alternatives

### Automatically scan and attach all tmux sessions

Rejected. It risks exposing or mutating operator-private tmux sessions and
breaks the clear `babs-` ownership boundary from `BAB-1107`.

### Treat imported sessions as Babs-owned immediately

Rejected. It would let a browser Stop action kill a session that the operator
created outside Babs, which violates the expectation behind importing.

### Allow one Citizen to attach multiple tmux sessions

Rejected for v0.1. The current runtime invariant is one Citizen, one active
Hardline. Parallel execution belongs to a later design.

### Rename imported sessions to `babs-<slug>` automatically

Rejected for the first implementation. Renaming can disrupt operator workflows
and other tooling that refers to the original tmux session name. A future
explicit "adopt and rename" action can be proposed separately.

## Consequences

- Phase 13 needs a tmux inventory/listing module that can show external
  sessions without attaching to them.
- Phase 13 needs lifecycle code that distinguishes Babs-owned stop/kill from
  external-owned detach.
- Existing lifecycle tests from Phase 6 must remain valid for Babs-owned
  sessions.
- New tests must prove external-owned Stop/Detach never kills the underlying
  tmux session.
- The operator can bring an already-running shell or AI CLI into Babs without
  losing its state.

## References

- `BAB-1002` Naming and Vocabulary
- `BAB-1107` Babs Owns Tmux Session Lifecycle
- `BAB-1110` Two OTP Apps Plus Tmux Detach
- `BAB-1112` Multi AI CLI Citizen Configuration
- `BAB-2225` Phase 13 Imported Tmux Session Attach

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-06 | Initial ADR for Phase 13 explicit imported tmux session attach semantics | Codex |
| 2026-05-06 | Fold Trinity R2 advisory by deferring new-Citizen-from-import flow and recording GLM/DeepSeek review pass | Codex |
| 2026-05-06 | Fold Trinity R3 advisory by defining runtime external-pane death semantics | Codex |
