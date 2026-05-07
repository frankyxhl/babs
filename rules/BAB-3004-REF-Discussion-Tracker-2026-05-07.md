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
| D1 | Dylan/Codex reply capture bug and Copilot CLI research | Active | User observed Dylan still following `bb ticket comment` instead of smooth JSONL reply capture. Diagnose real Codex JSONL shape, fix Babs parsing/prompt behavior, research GitHub Copilot CLI transcript options, and assess whether direct CLI hosting without tmux would simplify the system. Added `BAB-2230` coverage for direct `copilot` transcript parsing, Elena reply capture, and browser-harness BDD that creates a Ticket then captures an Elena Copilot JSONL reply into chat. Drafted `BAB-2232` as Phase 13a for multi-turn Ticket sessions plus direct CLI / lazy tmux execution, with `better-sqlite3` evaluated but excluded from the Elixir runtime stack. Review results: Trinity R3 GLM PASS and DeepSeek PASS; direct Gemini/Claude/Codex FIX findings were folded into the PRP. User prefers light theme over the previous dark UI; Phase 13a.1 now includes a light-theme `/dev/kitchen-sink` page and messaging-app-style Ticket chat. OpenHanako takeaways are recorded as product-shape inspiration only: async desk/files, self-contained agents, background hub, plugins/widgets/theme contracts, and registered session resources; Babs stays on Elixir/Phoenix/Ecto. Operator rejected the first inline-CSS kitchen-sink palette; Phase 13a.1 now starts with Phoenix Tailwind pipeline, Babs theme tokens, and Tailwind UI / shadcn / Petal / Tremor visual references before Ticket-detail polish. `BAB-2233` completed after Trinity implementation R2 GLM/DeepSeek PASS. `BAB-2234` completed after Trinity implementation R3 GLM/DeepSeek PASS: turn ids, conversation reducer, prompt assembler, turn/attempt events, reply correlation, and Ticket detail chat UI are implemented locally. Isolated-Chrome browser-harness BDD now passes, including Ticket new form, Elena Copilot capture, assignment, and follow-up comment injection scenarios. Next slice is 13a.3 direct CLI provider sessions. |

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
| 2026-05-07 | Record Phase 13a PRP draft for multi-turn Tickets, direct CLI execution, lazy tmux, and database-driver decision under D1 | Codex |
| 2026-05-07 | Record Phase 13a multi-model review outcome and folded direct Gemini/Claude/Codex findings under D1 | Codex |
| 2026-05-07 | Record light-theme preference, kitchen-sink route, and messaging-app-style Ticket chat decision under D1 | Codex |
| 2026-05-07 | Record OpenHanako takeaways for Phase 13a as product-shape inspiration, not stack adoption | Codex |
| 2026-05-07 | Record accepted Tailwind-backed UI correction route after kitchen-sink palette review | Codex |
| 2026-05-07 | Record BAB-2233 CHG approval after Trinity R2 GLM/DeepSeek PASS | Codex |
| 2026-05-07 | Record BAB-2233 implementation completion and Trinity implementation R2 PASS | Codex |
| 2026-05-07 | Record BAB-2234 implementation completion, Trinity implementation R3 PASS, validation results, and browser-harness authorization fallback | Codex |
| 2026-05-07 | Update BAB-1503 with browser-harness isolated Chrome profile policy for repeatable BDD validation | Codex |
| 2026-05-07 | Verify Alfred 1.12.0 exposes COR-1616 and rebase BAB-1503 into a Babs adapter over COR-1616 | Codex |
| 2026-05-07 | Replace BAB-2234 browser-harness fallback with isolated-Chrome BDD PASS and record Phase 13a.2 validation refresh | Codex |
| 2026-05-07 | Record BAB-2234 Trinity implementation R4 PASS and folded raw-review hardening for bubble class, kitchen-sink script, prompt observability, de-duplication, and sanitizer coverage | Codex |
