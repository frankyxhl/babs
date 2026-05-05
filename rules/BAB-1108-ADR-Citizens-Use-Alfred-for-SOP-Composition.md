# ADR-1108: Citizens Use Alfred for SOP Composition (Convention Only)

**Applies to:** BAB project
**Last updated:** 2026-05-05
**Last reviewed:** 2026-05-03
**Status:** Accepted

---

## ⚠️ v0.1 Layout Amendment (2026-05-04)

The convention-only Alfred decision remains accepted. Current Citizen configuration lives in `citizens/citizen-<slug>.toml`, and working files live under the resolved `workspace_root` per `BAB-1002`, `BAB-1112`, and `BAB-2209`. Any legacy `<name>.bob/` references in this ADR should be read as historical examples of "Citizen-owned prompt/config text," not as the current runtime file layout.

---

## Context

Babs and Alfred are sister projects in the same ecosystem. Alfred (`af` CLI) is the SOP/runbook system — it manages PRJ documents, generates workflow checklists, validates document structure. Babs is the multi-agent runtime that hosts Citizens (AI agents).

The natural question: how do Citizens compose SOPs into their work? Specifically, when a Citizen takes on a Ticket, should Babs:

A. Parse the Ticket's SOP references, load the relevant `af`-managed documents, and inject them into the Citizen's prompt?
B. Provide `af` in the Citizen's PATH and let the Citizen AI itself decide when and how to call `af`?
C. Build a Babs-native SOP system (don't use Alfred at all)?

## Decision

**Option B: Convention only. Babs ensures `af` is in PATH; Citizens decide for themselves when to invoke it.**

Babs explicitly does NOT:
- Parse Alfred SOPs
- Inject Alfred document contents into prompts
- Track which SOPs apply to which Tickets
- Validate that a Citizen "followed the SOP"

What Babs DOES guarantee:
- `af` CLI is callable from inside the tmux pane (PATH inheritance from spawn env)
- The Citizen's working directory has Alfred PRJ docs accessible (typically `<repo>/rules/`)
- The Citizen's AI prompt configuration (Phase 1: `citizens/citizen-<slug>.toml`; legacy/deferred: `<name>.bob/` files) MAY reference SOP IDs as a hint, but Babs treats those references as opaque text

## Why Convention (Not Integration)

1. **Layering principle**: Babs is the runtime; Alfred is the workflow framework. Coupling them tightly would make either one harder to evolve. The convention boundary is the right one.
2. **AI-native SOP composition**: Modern AI CLIs (`claude`, `codex`, etc.) are perfectly capable of running `af list`, `af read`, `af plan` themselves and composing the output into their own context. Babs adding a parsing layer in front would duplicate work and add a failure mode.
3. **Project-agnosticism**: Not every Babs Citizen will be an Alfred user. A Citizen running a non-Alfred project should not pay the cost of an Alfred parsing layer. Convention-only stays out of their way.
4. **Alfred can evolve independently**: SOP file format, `af` CLI semantics, document layering — all these can change in Alfred without Babs needing a release. The contract is "`af` is in PATH and works."

## What This Means in Practice

A Citizen `dylan` is given a Ticket with body "Refactor the auth module per `COR-1500` and `BAB-1102`." When dylan's AI processes this:

1. dylan's AI sees the SOP IDs as **plain text** in the prompt
2. dylan's AI decides "I should look these up" and types `af read COR-1500` in the tmux pane
3. The shell runs `af` (which is in PATH); dylan's AI sees the SOP body in its context
4. dylan's AI follows the SOP

Babs is not involved beyond PATH inheritance and pane I/O.

## Consequences

- **Citizen prompts can reference SOP IDs naturally** without any Babs-side parsing. Operators write Tickets in human English with SOP IDs scattered as needed.
- **Citizens that don't use Alfred just don't run `af`** — no overhead.
- **Babs has no Alfred-aware code paths**, no SOP parsers, no document graph traversal. Smaller surface, faster development.
- **CLAUDE.md project conventions still apply** — operators document "this Babs project uses Alfred PRJ prefix `BAB`" as project-level convention, but Babs runtime doesn't read CLAUDE.md.
- **Alfred and Babs can be developed/released independently** with no coupling concerns beyond CLI compatibility (`af` flags).

## What Would Justify Reversing This Decision

If, after meaningful production use, we discover that Citizens consistently fail to invoke `af` correctly (forgetting, getting the syntax wrong, parsing output incorrectly) AND a Babs-side parsing layer would reliably fix this — we revisit. As of 2026-05-03 there is no evidence for this; modern AI CLIs handle shell commands competently.

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial decision; convention-only Alfred integration | Claude Code |
| 2026-05-04 | Add v0.1 layout amendment for `citizens/citizen-<slug>.toml` + `workspaces/<slug>/`; update example seed name to Dylan | Codex |
| 2026-05-05 | Phase 2a: update layout amendment to describe resolved `workspace_root` instead of hard-coded repo-local workspaces | Codex |
