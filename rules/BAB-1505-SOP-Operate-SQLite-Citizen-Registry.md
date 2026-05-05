# SOP-1505: Operate SQLite Citizen Registry

**Applies to:** BAB project
**Last updated:** 2026-05-05
**Last reviewed:** 2026-05-05
**Status:** Active

---

## What Is It?

The operational runbook for Babs's Phase 3 SQLite Citizen registry. It explains
where the registry database lives, how migrations are run, how seed TOML import
relates to SQLite rows, how to inspect and repair Citizen status, and how to
handle backups safely.

## Why

The SQLite registry becomes the durable runtime authority for Citizens starting
in Phase 3. Without a dedicated SOP, later phases would have to rediscover
database path rules, migration order, status semantics, and secret-handling
constraints from code. This SOP gives operators and future Citizens a stable
reference.

---

## When to Use

- Before running Phase 3 migrations or starting a Babs node that uses the
  SQLite registry.
- When investigating why a Citizen did or did not auto-respawn.
- Before manually inspecting, backing up, restoring, or editing the registry
  database.
- When Phase 4-6 work needs to understand Citizen `running` / `stopped` /
  `failed` semantics.

## When NOT to Use

- For Babs-owned Hardline byte transcripts; those remain JSONL files under each
  resolved Citizen `cwd`.
- For upstream Claude/Codex/GitHub Copilot transcript formats; Babs does not own
  those formats.
- For Ticket filesystem operations; Phase 7+ ticket SOPs own those.

## Steps

1. **Find the database path.**

   Phase 3 config uses `BABS_CITIZENS_DB_PATH` when set. Otherwise it defaults
   to `<BABS_ROOT>/var/babs_citizens.sqlite3`.

2. **Confirm file permissions.**

   The database and parent directory should be readable/writable only by the
   operator account where the filesystem supports it. Treat DB backups as
   sensitive because `env` may contain spawn-ready credential values.

3. **Run migrations before production boot.**

   Dev/test may auto-migrate for flywheel ergonomics. Production/release use
   must run the explicit migration command chosen during Phase 3 implementation
   before starting Babs.

   The rollback command chosen during implementation must also be documented and
   tested for the initial `citizens` table migration.

4. **Understand import authority.**

   Seed TOML files are import sources. SQLite rows are the runtime authority
   after import. Import upserts by `slug`; existing rows preserve `id`, `status`,
   and `cwd`.

5. **Read status correctly.**

   - `running`: desired to be running; boot reattaches live tmux or respawns if
     tmux is missing.
   - `stopped`: intentionally stopped; boot must not start it.
   - `failed`: start/reattach failed; boot must not auto-retry.

6. **Repair carefully.**

   Prefer Babs lifecycle APIs or future UI controls over manual DB edits. If a
   manual edit is unavoidable, back up the database first and preserve resolved
   `cwd` unless the operator is deliberately migrating workspaces.

7. **Redact secrets.**

   Do not paste raw `env` values into logs, PR comments, screenshots, or support
   notes. Use key names and redacted values only.

8. **Treat env values as snapshots.**

   Imported `env` values are point-in-time spawn settings. Changing an OS
   environment variable later does not automatically rewrite existing SQLite
   rows.

## Phase 3 Notes

This SOP is created during Phase 3 planning. Exact command names may be updated
when the implementation lands. The semantic contract above should remain stable
unless a later ADR/PRP changes the SQLite registry design.

## Examples

### Example 1 - Citizen Does Not Auto-Respawn

1. Find the registry database path from `BABS_CITIZENS_DB_PATH` or the default
   path rule.
2. Inspect the Citizen row by `slug`.
3. If `status = "stopped"`, Babs is behaving correctly and should not start it.
4. If `status = "failed"`, read `last_error`; fix the underlying workspace,
   CLI, or config issue before retrying through a lifecycle API or future UI.

### Example 2 - Backing Up Before Manual Repair

1. Stop the Babs node or confirm no migration/import is running.
2. Copy the SQLite file to a private backup location.
3. Inspect or edit only the intended row.
4. Keep `cwd` unchanged unless the operator is deliberately migrating the
   Citizen workspace.
5. Restart Babs and confirm the Citizen reaches the expected status.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-05 | Initial version | — |
| 2026-05-05 | Draft Phase 3 SQLite registry operations runbook covering path, permissions, migrations, import authority, status semantics, repair, and redaction | Codex |
