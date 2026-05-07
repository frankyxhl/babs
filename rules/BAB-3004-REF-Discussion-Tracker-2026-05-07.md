# REF-3004: Discussion Tracker 2026-05-07

**Applies to:** BAB project
**Last updated:** 2026-05-07
**Last reviewed:** 2026-05-07
**Status:** Active

---

## What Is It?

Tracks active Babs implementation and operations discussions for 2026-05-07.

---

## Content

## Active

| ID | Topic | Status | Notes |
|----|-------|--------|-------|
| D1 | Dylan/Codex reply capture bug and Copilot CLI research | Active | User observed Dylan still following `bb ticket comment` instead of smooth JSONL reply capture. Diagnose real Codex JSONL shape, fix Babs parsing/prompt behavior, research GitHub Copilot CLI transcript options, and assess whether direct CLI hosting without tmux would simplify the system. Added `BAB-2230` coverage for direct `copilot` transcript parsing, Elena reply capture, and browser-harness BDD that creates a Ticket then captures an Elena Copilot JSONL reply into chat. |

## Archived

| ID | Topic | Outcome |
|----|-------|---------|
| D2 | Citizen AI CLI launch profiles | Completed via `BAB-2229`: added `safe_interactive` / `trusted_autonomous`, switched Elena to direct `copilot`, and verified Copilot launches without repeated folder-trust prompt by using `COPILOT_HOME/config.json` `trustedFolders`. |

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-07 | Initial version | — |
| 2026-05-07 | Added D2 for Citizen launch profiles | Codex |
| 2026-05-07 | Archived completed D2 launch profile work | Codex |
| 2026-05-07 | Record Elena Copilot JSONL BDD coverage under D1 | Codex |
