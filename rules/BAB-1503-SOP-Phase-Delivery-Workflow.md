# SOP-1503: Phase Delivery Workflow

**Applies to:** BAB project
**Last updated:** 2026-05-05
**Last reviewed:** 2026-05-05
**Status:** Active

---

## What Is It?

The standard Babs phase-delivery loop: route the work, clarify the phase
document, review the plan, implement with tests, validate locally, run external
review, then publish a PR using the correct GitHub identity.

## Why

Babs phases are large enough that skipping the early design/review loop creates
rework later. Phase 0a-1a showed a useful operating pattern: make the phase
contract explicit first, get Trinity review on that contract, implement only
after blockers are resolved, prove behavior with unit/BDD/E2E/coverage gates,
then publish a clean PR without runtime artifacts or private machine details.

This SOP keeps later phases from becoming ad hoc. It is especially important
once Babs Citizens start implementing phases from inside Babs, because the
operator still needs a predictable review and validation path.

---

## When to Use

- Starting or continuing any roadmap phase from `BAB-2300`.
- Implementing a Phase 0x/1x hardening phase such as `BAB-2206` or `BAB-2207`.
- Turning a phase discussion into a PRP/CHG and implementation PR.
- Preparing a PR that closes or materially advances a phase.

## When NOT to Use

- Tiny documentation edits that do not affect phase scope; use COR-1300.
- Runtime incidents or regressions; route through the project incident path
  from `BAB-2100`.
- The official Phase 0 long PTY validation run; use `BAB-1502`.
- Pure evolve/compression work; use `BAB-1801`.
- Work in another repository.

---

## Prerequisites

- Read `CLAUDE.md`, `BAB-2100`, and the relevant `BAB-22xx` phase document.
- For architecture-touching changes, read the affected `BAB-11xx` ADRs before
  proposing alternatives.
- Run `af guide --root <repo>` and use `af plan` when the task spans multiple
  SOPs.
- Confirm GitHub-visible writes use `gh` authenticated as `ryosaeba1985`.
  Do not create PRs or PR comments through an account that would publish as
  `frankyxhl`.
- Do not include private Tailscale IPs or host-specific secrets in public docs,
  commits, PR bodies, or review packets.

---

## Outputs

A completed phase delivery produces:

- an updated PRP or CHG with clear scope, acceptance, validation, and result
- implementation commits with focused tests
- local validation evidence
- Trinity plan-review and code-review records when required by the phase
- a GitHub PR opened by `ryosaeba1985`
- follow-up handling of PR review comments until merge or explicit defer

## Steps

1. **Route the work.**
   Read `BAB-2100` and identify whether the phase needs PRP, CHG, PLN, ADR, or
   an existing SOP. Declare the active SOP before starting and at major
   transitions.

2. **Load phase context.**
   Read the roadmap entry in `BAB-2300`, the phase document, relevant ADRs, and
   recent discussion tracker entries. State the current phase objective,
   deferred items, and explicit out-of-scope items.

3. **Write or update the phase contract before code.**
   For a new capability, draft/update a PRP. For a scoped change to accepted
   work, draft/update a CHG. The document must include:
   - what changes
   - why it matters now
   - impact and risk
   - implementation plan
   - test/BDD/coverage expectations
   - acceptance criteria
   - validation commands
   - out-of-scope/deferred items

4. **Review the plan before implementation.**
   Run Trinity review on the phase document or review packet before coding.
   Default reviewers are GLM and DeepSeek through `trinity review --preset
   fast-review`; add Gemini when the operator asks or when the phase risk
   warrants the slower review. Inspect raw outputs, not only the synthesis.
   Fix blockers in the document and rerun until blockers are resolved.

5. **Make an implementation checklist.**
   Convert the accepted plan into a short task list. Identify the first RED
   tests or BDD scenarios before touching production code. For frontend/browser
   workflows, prefer `browser-harness` for BDD; keep existing Playwright tests
   as legacy smoke until deliberately retired by a later CHG.

6. **Implement with test pressure.**
   Add or update tests first where practical, then implement narrowly. Keep to
   existing repo patterns and ADR boundaries. Avoid unrelated refactors. Keep
   generated/runtime artifacts out of git.

7. **Run the phase validation stack.**
   At minimum, run the commands that exist and apply to the phase:
   - `mise exec -- mix format --check-formatted`
   - `mise exec -- mix compile --warnings-as-errors`
   - `mise exec -- mix test`
   - `mise exec -- mix test --cover` when coverage gates exist or are being
     changed
   - `npm run test:js` when browser JavaScript exists
   - `npm run test:bdd` for browser-harness BDD scenarios
   - `npm run test:e2e` while Playwright smoke coverage remains in the repo
   - phase-specific gates such as `mise exec -- mix babs.gate_a`
   - `af validate --root <repo>`

8. **Update the phase document with facts.**
   Record real validation results, coverage percentages, skipped/deferred gates,
   and any deliberate deviations from the original plan. Do not mark a phase
   complete while required gates remain unrun, except where the operator has
   explicitly deferred a gate and the document records that deferral.

9. **Run code review before PR.**
   Run Trinity code review on the working tree or changed scope. Default to
   `trinity review --preset fast-review --scope .` unless a narrower scope is
   clearly safer. Fix blocking findings, rerun focused validation, and rerun
   review if the fix materially changes behavior. Advisory findings may be
   documented or deferred.

10. **Clean the worktree.**
    Before commit, check:
    - `git diff --check`
    - no private Tailscale IPs or secrets via `rg`
    - no coverage directories, `__pycache__`, `.pyc`, `test-results`, or
      Playwright reports
    - no runtime transcripts such as `workspaces/*/transcript.jsonl`
    - `git status --short` contains only intended phase files

11. **Commit and push intentionally.**
    Use a terse commit message that names the phase or deliverable. Push the
    branch. If rebasing or force-pushing is needed, get explicit operator
    approval first.

12. **Open the PR with the correct identity.**
    Use `gh` authenticated as `ryosaeba1985`. Confirm with `gh auth status`.
    Create a non-draft PR when the operator asks for a real PR; otherwise follow
    their requested draft/non-draft state. The PR body must include summary,
    validation, deferred gates, and no private machine details.

13. **Handle PR review loops.**
    Wait for GitHub/Codex review when requested. For each review round, inspect
    comments, fix actionable blockers, rerun relevant validation, push, and keep
    monitoring until no new required changes remain or the operator pauses the
    loop. When actively monitoring an open PR, poll every few minutes rather
    than assuming silence means completion. After every push, resume monitoring
    the new head commit until reviews/checks settle.

14. **Close out after merge.**
    After the operator merges, pull `main`, verify the local branch state, update
    trackers or phase docs if needed, and identify the next roadmap item.

---

## Review Defaults

| Stage | Default | Notes |
|-------|---------|-------|
| Plan review | Trinity GLM + DeepSeek fast-review | Gemini is optional unless requested or risk warrants it. |
| Code review | Trinity GLM + DeepSeek fast-review | Inspect raw outputs and fix blockers before PR. |
| GitHub PR review | Codex/GitHub review loop | Continue fixing/pushing until no new required changes remain. |

---

## PR Safety Rules

- GitHub-visible writes must publish as `ryosaeba1985`.
- Do not use the GitHub connector for PR creation when it would publish as the
  wrong account.
- Public docs and PR bodies must not include the operator's real Tailscale IP.
  Use `100.x.y.z` for examples or describe `BABS_HTTP_IP=0.0.0.0`.
- Runtime transcripts, generated coverage, caches, and browser test artifacts
  are not review artifacts unless a phase explicitly says otherwise.
- Existing user changes must not be reverted unless the operator explicitly asks.

---

## Examples

### Example 1 — Start Phase 2 transcript persistence

1. Read `BAB-2300` and the Phase 2 scope.
2. Draft or update the Phase 2 PRP/CHG with transcript persistence acceptance
   criteria.
3. Run Trinity plan review with GLM and DeepSeek.
4. Add transcript tests, implement JSONL persistence, and run Elixir/browser
   validation.
5. Run Trinity code review, fix blockers, then create the PR as `ryosaeba1985`.

### Example 2 — Add a hardening phase after implementation

1. Create a CHG such as `BAB-22xx-CHG-...`.
2. Record the current gap as RED evidence.
3. Review the CHG with Trinity before code.
4. Add the missing test tier or coverage gate, implement the refactor, and
   record exact validation results.
5. Open the PR only after local validation and code review pass.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-05 | Initial version capturing the Phase 0a-1a plan-review, TDD/BDD, validation, Trinity code-review, and PR workflow | Codex |
| 2026-05-05 | Clarify active PR monitoring cadence: poll every few minutes and resume after each push until reviews/checks settle | Codex |
