# REF-1200: Multi-Agent Loop Config

**Applies to:** BAB project
**Last updated:** 2026-06-06
**Last reviewed:** 2026-05-10
**Status:** Active
**Instantiates:** COR-1622 (Multi-Agent Loop Project Configuration parameter schema)
**Related:** COR-1617 (umbrella SOP), COR-1618 (consent auto-pick), COR-1619 (worker dispatch), COR-1620 (loop primitives), COR-1621 (triage), COR-1615 (GitHub App PR Review Bot Loop), BAB-1503 (Phase Delivery Workflow), BAB-1504 (deprecated GitHub Codex PR Review Loop), BAB-1800 (Evolution Philosophy / review weights)

---

## What Is It?

The Babs PRJ-layer instantiation of COR-1622's parameter schema. Fills in concrete values for every required key so that a COR-1617 Multi-Agent Workflow Loop session can run against `frankyxhl/babs`.

## Why

COR-1622 separates the *shape* of the loop (specified once in the COR cluster) from the *values* a given repo plugs in. Without this PRJ doc, an orchestrator session against Babs has no canonical source for identities, providers, weight pointers, or label names — it would either hard-code Trinity's values (wrong project) or hallucinate. This file is that canonical source.

---

## Parameter Values

### Identity & repository

| Key | Value | Notes |
|-----|-------|-------|
| `<repo>` | `frankyxhl/babs` | |
| `<repo-owner>` | `frankyxhl` | |
| `<repo-trusted-reactor-list>` | `[frankyxhl]` | Single-operator repo; no shared trust set. |
| `<gh-write-identity>` | `ryosaeba1985` | Per global CLAUDE.md identity rule. Verified via `gh auth status` per COR-1505. |
| `<pr-push-remote>` | `origin` | Single-remote project — no fork. PR head branches push to `origin`; the invariant "never push to `origin/main`" is preserved by the workflow, not by topology. |

### Consent gate (COR-1618)

| Key | Value | Notes |
|-----|-------|-------|
| `<consent-signal>` | `rocket` | Default. |
| `<intake-quality-mode>` | `1FA` | Babs issues are hand-curated by the operator; ceremony cost of 2FA isn't justified at current volume. Reconsider if external contributors join. |
| `<intake-quality-label>` | unset | Not applicable in `1FA` mode. |
| `<intake-quality-applier-set>` | unset | Not applicable in `1FA` mode. |

### Review panel (COR-1602 binding)

| Key | Value | Notes |
|-----|-------|-------|
| `<panel-providers>` | `[glm, deepseek, minimax]` | Three viable verdicts — meets the COR-1622 minimum. See §Accepted Trade-offs below for the worker/reviewer overlap and shared-CLI risk. |
| `<weights-doc>` | `BAB-1800` (scalar) | Babs's own Evolution Philosophy doc covers both code and doc weights. Plan-review uses BAB-1800; code-review uses COR-1610 implicitly per COR-1617 §Phase 4. |
| `<spec-format>` | `CHG` | Most plan-review work in Babs is on CHG/PRP artifacts in `BAB-22xx`. ADR work is rare enough not to warrant the map form. |
| `<panel-pass-threshold>` | `9.0` | Default. |

### Worker dispatch (COR-1619)

| Key | Value | Notes |
|-----|-------|-------|
| `<worker-agent>` | `trinity-glm via droid exec` | Memory: "delegate heavy implementation/debug to Sonnet sub-agents; Opus orchestrates and reviews." trinity-glm is the externalized worker pattern (model-diverse from the orchestrator) for Babs phase work. |
| `<worker-min-loc>` | `30` | Default. At or below: orchestrator edits directly; above: dispatch to `<worker-agent>`. |

### R-count cap (COR-1617 Phase 8)

| Key | Value | Notes |
|-----|-------|-------|
| `<max-r-count>` | `10` | Default soft cap. At R10 and later, the orchestrator evaluates convergence before continuing review-loop rounds. |
| `<max-r-count-extension>` | `15` | Babs-specific extension above the COR-1622 default of `3`. When P0/P1/P2 findings remain open, up to fifteen additional rounds are auto-authorized before hard stop. |
| `<convergence-severity>` | `advisory` | Default convergence threshold. The PR is considered converged when no P0/P1/P2 findings remain open. |

### Bot polling (COR-1615 binding)

| Key | Value | Notes |
|-----|-------|-------|
| `<bot-actors>` | `[chatgpt-codex-connector[bot], iterwheel-clearance[bot]]` | codex bot already in use per BAB-1504; iterwheel-clearance bot polled for clearance-side review activity. |

### Delivery continuation (BAB-1503 binding)

These keys are Babs-local loop policy, not required COR-1622 schema keys.

| Key | Value | Notes |
|-----|-------|-------|
| `<approval-ready-auto-advance>` | `true` | When a PR reaches Stage 3 / `ready-for-approval`, the agent treats it as waiting for operator merge and immediately starts the next non-conflicting issue or roadmap slice. |
| `<approval-ready-hold-worktree>` | `true` | Keep the approval-ready PR worktree available so new CI, review, conflict, or clearance feedback can be fixed before further new work. |
| `<approval-ready-preempts-new-work>` | `true` | If an approval-ready PR falls back because of semantic review feedback, failed CI, merge conflicts, or clearance blockers, restore it to approval-ready before starting additional new work. |

### Loop primitives (COR-1620)

| Key | Value | Notes |
|-----|-------|-------|
| `<wakeup-tool>` | `ScheduleWakeup` | Default. Claude Code is the orchestrator. |
| `<idle-cap>` | `12` | Default. |
| `<merge-watch-cap>` | `24` | Default. |

### Resilience (CLI retry / failure escalation)

| Key | Value | Notes |
|-----|-------|-------|
| `<cli-retry-attempts>` | `3` | Default. |
| `<cli-retry-backoff-seconds>` | `600` | Default — 10-minute wait between attempts matches the operator-stated policy that motivated FXA-146 (the schema extension). |
| `<cli-retry-on-failure>` | `pause-and-ask` | Default. After 3 failed attempts at 10-minute intervals, surface to the operator rather than silently degrading the panel. |

---

## Accepted Trade-offs

The current configuration has two known trade-offs accepted explicitly by the operator on 2026-05-10. Both are revisitable.

### Worker / reviewer overlap

`<worker-agent>` = `trinity-glm` AND `glm` is in `<panel-providers>`. The implementer is also one of three reviewers, so glm holds 33% of the gate weight. Trinity itself has the same overlap but mitigates it with a 4-reviewer panel where glm holds 25%. Babs accepts the higher overlap weight because the only realistic alternatives — switching the worker to a non-panel model, or swapping glm out of the panel — both reduce the model diversity available right now.

**Revisit when:** another non-droid reviewer becomes available (e.g., gemini wired in), at which point promoting it into the panel and dropping glm to 25% is a strict improvement.

### Shared-CLI failure surface

`glm` and `minimax` both run through `droid exec`; `deepseek` runs through its own `claude` CLI wrapper. A single `droid` outage drops 2 of 3 panel verdicts simultaneously, leaving the panel below the 3-viable minimum.

The §Resilience parameters above (3 retries × 10-minute backoff, then `pause-and-ask`) are the explicit mitigation: a transient droid outage is absorbed by retries; a persistent one escalates to the operator instead of silently shipping a 1-reviewer review.

**Revisit when:** the panel grows to 4+ reviewers with at least 2 reviewers on a non-droid CLI, at which point a single droid outage still leaves a viable panel.

---

## Provider Bring-Up Status

| Provider | CLI surface | Worker agent file | Smoke test |
|----------|-------------|-------------------|------------|
| `glm` | `droid exec --model "custom:GLM-5.1-(Z.AI)-0"` | `~/.claude/agents/trinity-glm.md` | Pre-existing. |
| `deepseek` | `providers/bin/deepseek` (Anthropic-compatible endpoint) | `~/.claude/agents/trinity-deepseek.md` | Pre-existing. |
| `minimax` | `droid exec --model "custom:MiniMax-M2.7"` | `~/.claude/agents/trinity-minimax.md` | 2026-05-10 — `MINIMAX_SMOKE_OK` returned. |

`~/.factory/settings.json` `customModels[]` includes `custom:MiniMax-M2.7` with `id`, `index: 3`, `baseUrl: https://api.minimaxi.com/anthropic`, `provider: anthropic`. Required by all three droid-routed providers.

---

## Guard Rails

Inherited from COR-1622:

- All required keys are filled. Adding new schema keys upstream that this file does not yet specify is a hard error — this doc must be updated before the next loop run.
- Substituting `<weights-doc>` with a foreign project's weights doc (e.g., `TRN-1800`, `COR-1610` standalone) is a guard-rail violation. Babs panel-review uses `BAB-1800` only.
- `<intake-quality-mode>` may not silently change between sessions. Moving from `1FA` to `2FA` requires re-checking every previously-rocket-eligible issue against the new mode and updating this doc in the same change.

Babs-specific:

- Adding a new provider to `<panel-providers>` requires (1) a corresponding `~/.claude/agents/trinity-<provider>.md` file, (2) a smoke-test entry under §Provider Bring-Up Status, and (3) a §Accepted Trade-offs revisit if the addition changes the worker/reviewer overlap or shared-CLI surface.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-10 | Initial instantiation of COR-1622 schema for Babs. Panel = `[glm, deepseek, minimax]` (3 viable, MiniMax newly bootstrapped 2026-05-10). Worker = `trinity-glm`. 1FA intake. Two trade-offs accepted: worker/reviewer overlap (glm both sides) and shared-droid CLI surface (glm + minimax) — mitigated by §Resilience defaults from COR-1622 v1.16.0 (FXA-146). | Claude Opus 4.7 |
| 2026-05-31 | Add R-count cap parameters introduced by COR-1622: `<max-r-count>`, `<max-r-count-extension>`, and `<convergence-severity>`; set Babs extension to `15` for a stricter review-loop budget. | Codex |
| 2026-06-06 | Add Babs-local delivery continuation parameters: approval-ready PRs auto-advance to the next non-conflicting slice while keeping their worktrees available for fixes. | Codex |
