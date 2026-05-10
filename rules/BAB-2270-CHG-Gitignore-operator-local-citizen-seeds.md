# CHG-2270: Gitignore operator-local citizen seeds

**Applies to:** BAB project
**Last updated:** 2026-05-10
**Last reviewed:** 2026-05-10
**Status:** Approved
**Date:** 2026-05-10
**Requested by:** frankyxhl (issue #77)
**Priority:** P3
**Change Type:** Normal
**Closes:** #77

---

## What

Add an allowlist-style `.gitignore` block under `citizens/` that tracks the four committed seed Citizens (sentinel, clare, dylan, elena — listed in README §"AI CLI Citizens") by explicit `!`-exception and ignores everything else. The two currently-untracked files — `citizen-john.toml` (operator copilot-cli-dev citizen) and `citizen-test-copilot-cli.toml` (copilot smoke-test citizen) — will be silently ignored, making `git status` clean without committing operator-local seeds.

**Technical note on `!`-exceptions:** `.gitignore` rules apply only to untracked files; already-tracked files in the git index remain tracked regardless of any ignore rule. The four `!`-exception lines are therefore documentation-of-intent for the canonical set, not load-bearing guards for the currently-tracked files. They become functionally relevant on a fresh clone where the four seeds are initially untracked.

**Decision: Option B** (Ignore). Options considered:

- **A (Commit):** Add both TOMLs to the tracked set, update README table. Rejected — `citizen-test-copilot-cli.toml` is a development artifact (no description, no roles defined) and `citizen-john.toml` has no README §"AI CLI Citizens" table entry and is an operator-specific dev citizen (`role = "copilot-cli-dev"`). Committing operator-local seeds requires ongoing README maintenance for no runtime benefit.
- **B (Ignore) ← chosen:** Add an allowlist `.gitignore` block. Minimal diff, no behavior change, no code change. Resolves `git status` noise immediately.
- **C (citizens.local/):** Architecturally cleanest — new gitignored load path, runtime loader change. Rejected at P3/pre-development stage: the runtime code to support dual-directory loading doesn't exist yet; adding it now is disproportionate to the annoyance being resolved. Defer to a dedicated CHG when the loader is being written anyway.

## Why

Two untracked files in `citizens/` have appeared in `git status` since at least 2026-05-09 (surfaced during #69 audit, escalated to issue #77). They clutter `git status` and leave intent ambiguous: are they seeds to be committed, or operator-local artifacts?

The recurrence is active, not one-off: the Alfred workflow session-start routine (CLAUDE.md §Alfred Workflow step 2: `af guide --root <project-root>`) runs `git status` as its sanity check and **stops until the operator acknowledges anomalies**. These two untracked files trigger that stop at every new session — confirmed on 2026-05-09 and 2026-05-10. Any agent running the Babs COR-1617 loop encounters the disambiguation question at session start without a comment in `.gitignore` to explain that the files are intentionally operator-local.

Option B resolves the ambiguity with a 4-line `.gitignore` change, no runtime code touch, and a reversible rollback. Option C would be architecturally better but requires writing loader code that does not exist — a disproportionate scope increase for a P3 hygiene chore.

## Impact Analysis

- **Systems affected:** `.gitignore` only. No runtime code, no schema, no API surface.
- **Rollback plan:** Revert the `.gitignore` block. The two TOML files remain on disk; they simply become untracked again.

## Implementation Plan

1. Add the following block to `.gitignore` under `# Babs runtime` or at end:

```
# Citizens — allowlist committed seeds; ignore operator-local
citizens/citizen-*.toml
!citizens/citizen-clare.toml
!citizens/citizen-dylan.toml
!citizens/citizen-elena.toml
!citizens/citizen-sentinel.toml
```

2. Verify `git status` shows the two TOML files are no longer listed as untracked.
3. Verify `git ls-files citizens/` still lists the four committed seeds (tracked, unaffected by the ignore rule).
4. Run `mix format --check-formatted && mix compile --warnings-as-errors && mix test` (no-op if pre-dev; confirms no compile regression if partial code exists).

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-10 | Initial version — Option B selected (gitignore allowlist); Decision recorded per issue #77 acceptance criteria | Claude Code |
| 2026-05-10 | R2: fix "canonical" → "committed seed Citizens" (aligns with README table); reframe README-table claim; embed `!`-exception technical note; strengthen Necessity with Option C proportionality framing. Panel R1 fixes (GLM B1+B2, DeepSeek A1, MiniMax A1+A2). | Claude Code |
| 2026-05-10 | R3: expand Why with COR-1208 recurrence evidence — untracked files trigger mandatory session-start stop on every orchestrator session (confirmed 2026-05-09 and 2026-05-10). Addresses MiniMax R2 coerced-FIX (Necessity 8→9 target). | Claude Code |
| 2026-05-10 | R4: replace COR-1208 citation (PKG-layer SOP, not in BAB-0000) with direct description of the mechanism — Alfred workflow session-start `af guide` git-status sanity check (CLAUDE.md §Alfred Workflow). Addresses MiniMax R3 B-1. | Claude Code |
| 2026-05-10 | Status → Approved. Panel gate met: GLM R2 9.20, DeepSeek R2 9.55, MiniMax R4 9.00 — all PASS, no blockers. | Claude Code |
