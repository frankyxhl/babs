# SOP-2100: Workflow Routing PRJ

**Applies to:** BAB project
**Last updated:** 2026-05-04
**Last reviewed:** 2026-05-03
**Status:** Active

---

## What Is It?

Babs's project-specific workflow routing. Tells AI agents (and humans) which COR / BAB SOP applies to which kind of task **inside this project**. Sits underneath COR-1103 (universal routing) and PKG defaults; refines them for Babs's specific lifecycle and document set.

---

## Why

Babs has its own document set (`BAB-10xx` foundational REFs, `BAB-11xx` ADRs, `BAB-22xx` Phase PRPs, etc.) and its own lifecycle (phased build on a clean slate). Generic COR routing doesn't know any of this. This SOP closes that gap so an agent dropped into the Babs repo can route correctly without reading every doc first.

It also enforces a discipline specific to Babs: the current foundational ADR set (`BAB-1100`–`BAB-1112`) records decisions that should not be casually reopened. Routing through this SOP makes "did you read the relevant ADR?" a step, not an afterthought.

---

## When to Use

- Start of every session in `/Users/frank/Projects/babs/`
- Before every new task in this repo
- When the task spans multiple domains and isn't obviously covered by a single COR SOP

## When NOT to Use

- Mid-task when routing is already done and a checklist is being executed
- For tasks unrelated to Babs (other projects have their own routing PRJ docs)

---

## Always (every session, every task)

Inherits all of COR-1103 §"ALWAYS":

- **COR-1201** — Load today's Discussion Tracker (BAB area `30`; today's tracker is `BAB-3000-REF-Discussion-Tracker-2026-05-03` or successor by date)
- **COR-1402** — Declare 📋 active SOP before work and at every transition
- **COR-1103** — Route the task before reading detailed SOPs
- **af plan** — Before every response, decide if a checklist is needed
- **COR-1202** — When the task spans multiple SOPs, use Compose Session Plan

---

## Babs-specific Always

- **Cross-reference ADRs before architecture work.** Babs's foundational ADRs currently span `BAB-1100`–`BAB-1112`. When a task touches architecture (citizens, coordination, persistence, PTY, web framework choice, v0.1 scope, OTP app boundaries, or AI CLI configuration), read the relevant ADR(s) first. Rejected alternatives in those ADRs are not invitations to reopen; they are documented reasons.
- **Read `BAB-1001` (Architecture Overview) and `BAB-1002` (Naming) on first session in this repo.** They define the vocabulary and shape of the system.

---

## Primary Route (stop at first match)

### 1. Pure document management

| Sub-task | Route |
|---|---|
| New SOP for a Babs-specific process | COR-1000 → `BAB-15xx` |
| New REF (architecture, glossary, vocabulary update) | COR-1001 → `BAB-10xx` |
| Update existing BAB doc | COR-1300 |

### 2. Something broken / failing / unexpected

| Sub-task | Route |
|---|---|
| Bug in a running Babs node, citizen subtree, or PTY attachment | INC (project-level) → CHG if fix changes architecture |
| `af validate` failing on a BAB doc | COR-1300 (update doc) |

### 3. New capability / design that doesn't exist yet

| Sub-task | Route |
|---|---|
| Net-new architecture decision (not covered by existing ADRs) | PRP (COR-1102) → review (COR-1602) → ADR (COR-1100) → file as `BAB-11xx` |
| Phase implementation spec | PRP (COR-1102) → file as `BAB-22xx`; Phase 2+ sequencing follows `BAB-2300` |
| Phase 1 citizen seed | Follow `BAB-2201` and `BAB-1002` (`citizens/citizen-<slug>.toml` + `workspaces/<slug>/`) |
| New citizen archetype beyond Phase 1 seed layout | PRP (COR-1102) first if structurally novel; legacy `BAB-1500` is deferred |

### 4. Execution coordination for approved work

| Sub-task | Route |
|---|---|
| Phase rollout coordination (timeline, dependencies, kill criteria) | PLN → `BAB-23xx` |
| Multi-session build coordination | PLN |

### 5. Change to existing system / config / architecture

| Sub-task | Route |
|---|---|
| Standard config tweak (within accepted ADR constraints) | CHG (COR-1101), no review |
| Normal change (deviates from existing ADR) | PRP first → ADR → CHG; file CHG during implementation |
| Emergency (production node down) | CHG (COR-1101) → execute → post-approval within 24h |
| PTY method swap (A → B per `BAB-1103`) | CHG referencing `BAB-1103`'s fallback trigger |

### 6. Record a durable decision already made

| Sub-task | Route |
|---|---|
| Architectural choice made in conversation | ADR (COR-1100) → `BAB-11xx` |
| Decision about a process or workflow | typically REF or SOP, not ADR |

### 7. Track / discuss a topic within this session

D items per COR-1201 in today's Discussion Tracker (BAB area 30).

### 8. None of the above

Fall back to COR-1103 §"None of the above" branch.

---

## Specialized Routes

### Phase 0 — PTY Stability Spike

- Execution SOP: `BAB-1502`
- Spec: `BAB-2200`
- Triggers method-A-vs-method-B selection per `BAB-1103`
- Pass criterion: ≤1 erlexec port crash per 48h AND any crash leaves the underlying tmux session alive

### Add a Phase 1 citizen seed

Follow `BAB-2201` and `BAB-1002`: create/update `citizens/citizen-<slug>.toml`, allocate `workspaces/<slug>/`, and route the active terminal byte channel through `Hardline.Pane` + PubSub topic `pane:<slug>`.

`BAB-1500` is deferred legacy guidance for the old `*.bob/` workflow. Do not route Phase 1 citizen creation there.

---

## Document Type Quick Reference

| Type | When | Naming | Area |
|------|------|--------|------|
| REF | Reference / glossary / index / non-prescriptive doc | `BAB-NNNN-REF-Title.md` | 10xx (foundational), 21xx (routing) |
| ADR | Recorded architectural decision | `BAB-NNNN-ADR-Title.md` | 11xx |
| SOP | Prescriptive step-by-step process | `BAB-NNNN-SOP-Title.md` | 15xx (project SOPs), 18xx (evolution SOP) |
| PRP | Proposal for net-new design | `BAB-NNNN-PRP-Title.md` | 22xx |
| CHG | Approved change to existing system | `BAB-NNNN-CHG-Title.md` | 11xx-22xx (file near the affected docs) |
| PLN | Coordination plan / roadmap | `BAB-NNNN-PLN-Title.md` | 23xx |
| INC | Incident report | `BAB-NNNN-INC-Title.md` | (no fixed area; incident-driven) |
| Discussion Tracker | Per-day session tracker | `BAB-NNNN-REF-Discussion-Tracker-YYYY-MM-DD.md` | 30xx |

ACID assignment: use `--acid` for predictable numbering on planned docs (ADRs, REFs); use `--area` for auto-assignment on as-needed docs (Discussion Trackers, INCs).

---

## Steps

This SOP is consulted, not executed. The "steps" are the routing decision pattern an agent runs at the start of a task in this project:

1. **Read `BAB-1001` and `BAB-1002` on first session in this repo** (architecture + vocabulary)
2. **Run COR-1103** (universal Always block) — Discussion Tracker, COR-1402 active SOP, etc.
3. **Match the task against §"Primary Route" above** — stop at first match (1–8)
4. **For architecture-touching tasks, read the relevant ADR(s)** in `BAB-11xx` before proposing alternatives
5. **Run `af plan <SOP_IDs>`** with the matched SOPs to generate a checklist
6. **Declare the active SOP per COR-1402** before starting work
7. **At every transition**, re-declare the new active SOP and update the Discussion Tracker
8. **At task completion**, use the plan output as a verification checklist

---

## Examples

### Example 1 — User says "I want to add a Slack connector to Babs"

1. Read `BAB-1001` (Architecture) → confirms Connectors live under `Babs.Connectors.Supervisor`
2. §"Primary Route" branch 3 (new capability) → PRP path
3. Check `BAB-1100`–`BAB-1112` ADRs — Slack connector is additive, no ADR conflict
4. `af plan COR-1102 COR-1602 COR-1101` → PRP → review → CHG checklist
5. Declare 📋 COR-1102 active; draft `BAB-22xx-PRP-Slack-Connector.md`

### Example 2 — User says "the dashboard is showing stale citizen status"

1. §"Primary Route" branch 2 (something broken) → INC
2. Read `BAB-1001` to recall the LiveView ↔ ETS ↔ Citizen.Server data flow
3. `af plan COR-INC-001` (or project INC SOP when defined)
4. Declare 📋 INC SOP active; investigate; if fix changes architecture, escalate to CHG referencing the relevant ADR

### Example 3 — User says "let's reconsider whether we should use :erpc instead of HTTP for inter-node A2A"

1. Read `BAB-1104` ADR — this is exactly the decision recorded there
2. The ADR's "Rejected Alternatives" section addresses this; reopening requires PRP, not casual change
3. §"Primary Route" branch 3 (new capability/design) — PRP (COR-1102) → review → if accepted, supersede `BAB-1104` with a new ADR

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial version — Babs project-specific routing | Claude Code |
| 2026-05-03 | Drop "Migration cutover" routes (Babs is from-scratch); collapse SOP "(when written)" notes for docs that now exist | Claude Code |
| 2026-05-03 | Self-review fixes: Phase 0/1/2/3 → 0/1/2/3/4; remove "(when written)" on BAB-2200 | Claude Code |
| 2026-05-04 | Expand architecture ADR range to `BAB-1100`–`BAB-1112`; route Phase 1 citizen seeds to `BAB-2201`/`BAB-1002` and mark `BAB-1500` deferred | Codex |
