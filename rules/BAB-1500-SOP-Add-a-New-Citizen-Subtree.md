# SOP-1500: Add a New Citizen Subtree

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Active
**Depends on:** BAB-1001 (Architecture), BAB-1002 (Naming), BAB-1102 (Citizen-as-subtree ADR)

---

## What Is It?

The end-to-end procedure for adding a new citizen `<name>.bob/` to a running Babs node. Covers: directory layout, supervision-tree wiring, Connectors registration, A2A registration, and verification.

---

## Why

A citizen is not a single config entry — it is a coherent subtree of processes plus a directory plus a tmux session plus optionally Connectors registrations. Without a checklist, ad-hoc citizen creation drops one of these and produces a half-citizen that "almost works" until something restarts. This SOP also encodes the order of operations: tmux first, then directory, then Babs registration — because the supervisor wires up against an existing tmux session, not the other way around.

---

## When to Use

- Adding any new `<name>.bob/` citizen to a Babs node
- Cloning an existing citizen archetype (`relay`, `dashboard`, `transcript`) under a new name

## When NOT to Use

- Re-attaching an existing citizen after a Babs restart (Babs's DynamicSupervisor handles this on boot from the SQLite registry)
- Architecturally novel citizen patterns (e.g., a citizen that needs more than one tmux session) — file a PRP first

---

## Prerequisites

- Babs node running (or planned to run) on the target machine
- tmux available and the user has permission to create sessions
- The citizen's AI CLI binary is installed (e.g., `claude`, `codex`)
- A name that is unique across the Babs registry and follows the naming convention (lowercase, no dots in the bare name; the `.bob` suffix is appended by directory layout)

---

## Steps

1. **Pick the name and the archetype.**
   - Name: short, lowercase, role-descriptive (`relay`, `dashboard`, `transcript`, `summary`, `scheduler`).
   - Archetype: which existing citizen most resembles the role? Copy its `<name>.bob/` directory structure as a starting point; do NOT copy from scratch.

2. **Create the tmux session for the citizen.**
   ```
   tmux new-session -d -s <name> "<ai-cli-binary> [args...]"
   ```
   Confirm the AI CLI is responsive: `tmux send-keys -t <name> "hello" Enter` then `tmux capture-pane -t <name> -p | tail`.

3. **Create the citizen directory.**
   ```
   mkdir citizens/<name>.bob/
   cp -r citizens/<archetype>.bob/{config,skills} citizens/<name>.bob/
   ```
   Edit `citizens/<name>.bob/config/identity.toml` (or the project's identity file) to set `name = "<name>"`, `tmux_session = "<name>"`, and an `a2a_url` (or the marker for "host-derived").

4. **Register the citizen in the SQLite registry.**
   - Insert into the `citizens` table (Babs Ecto schema) with columns: `name`, `tmux_session`, `host`, `a2a_url`, `skills`, `created_at`.

5. **Register the supervisor.**
   - Start the citizen subtree explicitly:
     ```elixir
     Babs.Citizens.Supervisor.start_citizen("<name>")
     ```
   - `Babs.Citizens.Supervisor` is the top-level DynamicSupervisor. The call spawns one `Babs.CitizenSupervisor` (per-citizen `:rest_for_one` supervisor) holding the subtree: `Citizen.Server`, `PaneSession` (attaches to the tmux session from step 2), and `TranscriptTailer` (no transcript file yet — tails a path that will appear).

6. **Register Connectors (if the citizen receives external messages).**
   - For Discord: add an entry to `relay_config` (Babs SQLite) with `channel_id`, `target_citizen = "<name>"`, `ai_type`. Babs's `Babs.Connectors.Supervisor` picks it up on its next refresh.
   - For Telegram: same, with the Telegram channel/chat id.
   - If the citizen is internal-only (only receives A2A from other citizens), skip this step.

7. **Verify the subtree is alive.**
   ```elixir
   Babs.Citizens.Registry.lookup("<name>")
   #=> {:ok, %{server: pid, pane: pid, tailer: pid, supervisor: pid}}
   ```
   - `Citizen.Server` mailbox responds to `GenServer.call(pid, :status)` with `:idle`
   - `PaneSession` accepts `inject("hello world")` and the bytes appear in the tmux pane
   - `TranscriptTailer` is watching for the transcript file (it may not exist yet — that's fine)

8. **Verify A2A reachability.**
   ```elixir
   Babs.A2A.Router.dispatch("<name>", %{"method" => "ping", "params" => %{}})
   #=> {:ok, %{"pong" => true}}
   ```

9. **Verify Dashboard visibility.**
   - Open the BabsWeb dashboard. The new citizen should appear in the citizen list with status `idle`.
   - Click into the citizen detail view; PaneSession's terminal channel should attach within a second.

10. **Document the new citizen.**
    - Add an entry to the Babs project's citizen catalog (when one exists; for now, note in the Discussion Tracker)
    - If the citizen uses a non-standard archetype or pattern, file an ADR (`BAB-11xx`) describing the new pattern

---

## Examples

### Example 1 — Adding a `summary.bob` citizen that receives Discord messages

1. Name: `summary`. Archetype: `relay` (it does similar Discord-driven work).
2. `tmux new-session -d -s summary "claude --workdir ~/.babs/citizens/summary.bob"`.
3. `mkdir citizens/summary.bob && cp -r citizens/relay.bob/{config,skills} citizens/summary.bob/`. Edit identity.
4. SQLite insert: `name=summary, tmux_session=summary, host=local, skills=["summarize", "respond"]`.
5. `Babs.Citizens.Supervisor.start_citizen("summary")`.
6. Add `relay_config` entry: `channel_id=<discord-channel>, target_citizen=summary, ai_type=claude`.
7-9. Verify Server, PaneSession, A2A reachability, Dashboard visibility.
10. Note in tracker.

### Example 2 — Adding an internal-only `scheduler.bob`

Same as Example 1, but **skip step 6** (no Connectors). The scheduler is invoked only via A2A from other citizens. Step 8 (A2A reachability) is the critical verification here.

### Example 3 — Cloning `relay.bob` for a second Discord guild

Tempting shortcut: just copy `relay.bob` to `relay2.bob`. **Don't.** A citizen has identity; running two citizens with near-identical names creates routing ambiguity. Instead, name based on role (`backup-relay.bob`, `mod-relay.bob`) and add an ADR if the divergence from the original archetype is structural.

---

## Common Failure Modes

- **Step 2 forgotten** → step 5 fails because PaneSession can't attach to a non-existent tmux session
- **Step 4 forgotten** → citizen runs but isn't routable (A2A and Connectors look up via the registry)
- **Step 6 forgotten** → citizen runs and is A2A-reachable but never sees Discord/TG messages
- **Reusing a name** → registry insert fails; or worse, succeeds with conflicting state. Always check `Babs.Citizens.Registry.lookup/1` returns `:not_found` before step 4.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial version — covers the create-tmux → directory → register → wire → verify path | Claude Code |
| 2026-05-03 | Drop hybrid/migration sub-bullet (Babs is from-scratch; no Python-era citizen.db) | Claude Code |
| 2026-05-03 | Step 5 reworded to drop unsupported "30s registry refresh tick" claim; clarified DynamicSupervisor relationship | Claude Code |
