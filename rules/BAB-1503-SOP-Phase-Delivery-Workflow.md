# SOP-1503: Phase Delivery Workflow

**Applies to:** BAB project
**Last updated:** 2026-05-07
**Last reviewed:** 2026-05-07
**Status:** Active
**Inherits from:** COR-1616 Contract-First Delivery Workflow
**Related:** COR-1500, COR-1612, COR-1615, COR-1616, BAB-2100, BAB-2300

---

## What Is It?

Babs's project adapter for `COR-1616` Contract-First Delivery Workflow.

Use `COR-1616` as the authoritative reviewed-delivery loop: contract before
code, plan review, TDD/BDD/E2E pressure, validation, implementation review,
privacy/artifact cleanup, correct-identity PR, PR review loop, and post-merge
closeout.

This SOP only adds Babs-specific routing, validation commands, review defaults,
GitHub identity rules, and browser-harness settings.

## Why

`BAB-1503` started as the Babs phase-delivery pattern and was promoted into
`COR-1616`. Keeping this file as a thin adapter prevents drift: Babs inherits
the general workflow while still documenting its own roadmap, gates, and safety
rules.

---

## When to Use

- Starting or continuing any Babs roadmap phase from `BAB-2300`.
- Implementing a Babs Phase 0x/1x/13x hardening or feature slice.
- Turning a Babs phase discussion into a PRP/CHG/PLN and implementation PR.
- Preparing a PR that closes or materially advances a Babs phase contract.

## When NOT to Use

- Tiny documentation edits that do not affect Babs phase scope; use COR-1300.
- Runtime incidents or regressions; route through `BAB-2100` incident guidance.
- The official Phase 0 long PTY validation run; use `BAB-1502`.
- Pure evolve/compression work; use `BAB-1801`.
- Work in another repository.
- Multi-PR continuous execution under one operator contract; use COR-1614 for
  the meta-contract, then use COR-1616/BAB-1503 for each PR slice.

---

## Prerequisites

- Read `CLAUDE.md`, `BAB-2100`, `BAB-2300`, and the relevant `BAB-22xx`
  PRP/CHG/phase document.
- For architecture-touching changes, read the affected `BAB-11xx` ADRs before
  proposing alternatives.
- Run `af guide --root /Users/frank/Projects/babs` and
  `af plan COR-1616 BAB-1503`.
- Confirm GitHub-visible writes use `gh` authenticated as `ryosaeba1985`.
- Do not include private Tailscale IPs, local filesystem paths, machine-local
  URLs, tokens, or host-specific secrets in public docs, commits, PR bodies, or
  review packets.

---

## Babs Contract Rules

Follow `COR-1616` Step 3 with these Babs document choices:

- New capability/design: draft or update a `BAB-22xx` PRP.
- Scoped implementation change to accepted work: draft or update a `BAB-22xx`
  CHG.
- Multi-step coordination inside one PR slice: use a `BAB-23xx` PLN if a CHG
  alone is too small to carry sequencing.
- Architecture decision already made: record a `BAB-11xx` ADR before the CHG if
  the decision changes architecture.

Every Babs contract must state:

- scope and out-of-scope items
- acceptance criteria
- BDD/E2E/unit/coverage expectations
- exact validation commands
- deferred gates, if any, with the operator's explicit approval
- Trinity plan-review result before implementation
- Trinity implementation-review result before PR

## Babs Review Defaults

| Stage | Default | Notes |
|-------|---------|-------|
| Plan review | `trinity review --preset fast-review` | GLM + DeepSeek. Add Gemini or Council Review only when risk or the operator requires it. Inspect raw outputs, not only synthesis. |
| Implementation review | `trinity review --preset fast-review --scope <scope>` | Fix blockers, rerun focused validation, and rerun review after material behavior changes. |
| GitHub PR review | COR-1615 then COR-1612 | Trigger once per current head, avoid duplicate review spam, poll until the current head has no required changes or the operator pauses. |

## Babs Validation Stack

Run the subset that applies to the slice, and record exact results in the
contract:

- `mise exec -- mix format --check-formatted`
- `mise exec -- mix compile --warnings-as-errors`
- `mise exec -- mix test`
- `mise exec -- mix test --cover` when coverage gates exist or are being
  changed
- `npm run test:js` when browser JavaScript exists
- `npm run test:bdd` for browser-harness BDD scenarios
- `npm run test:e2e` while Playwright smoke coverage remains in the repo
- phase-specific gates such as `mise exec -- mix babs.gate_a`
- `af validate --root /Users/frank/Projects/babs`
- `git diff --check`
- privacy/artifact scan before commit

If a phase requires a long manual gate, such as the Phase 0 24-hour PTY run,
record the explicit operator deferral in the contract and do not present that
gate as passed.

## Browser-Harness BDD Policy

Babs inherits `COR-1616`'s browser-harness policy and specializes the command
shape:

- Repeatable phase validation should use isolated Chrome plus `BU_CDP_URL`.

  ```bash
  /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
    --remote-debugging-port=9222 \
    --user-data-dir=/tmp/babs-browser-harness-profile \
    --no-first-run \
    --no-default-browser-check

  BU_CDP_URL=http://127.0.0.1:9222 npm run test:bdd
  ```

- The operator's normal Chrome profile may be used for real-browser assistance
  when saved logins or extensions are needed. Chrome 144+ can repeatedly show
  the `Allow remote debugging?` popup on later attaches. Do not treat repeated
  popups as operator error. If that popup blocks automation, record the exact
  failure in the CHG validation section and rerun required BDD with the
  isolated-profile mode.

## Babs PR Safety Rules

- Verify `gh auth status` before PRs, issue comments, review comments, or other
  GitHub-visible writes.
- Public GitHub writes must publish as `ryosaeba1985`.
- Do not use GitHub connector write tools if they would publish as `frankyxhl`.
- PR bodies must include summary, validation, deferred gates, and no private
  machine details.
- Runtime transcripts, generated coverage, caches, `test-results`, Playwright
  reports, `__pycache__`, `.pyc`, and browser profiles are not review artifacts
  unless the contract explicitly says otherwise.
- Existing user changes must not be reverted unless the operator explicitly
  asks.

## Steps

1. **Run COR-1616.**
   Treat `COR-1616` as the authoritative workflow for the delivery slice.

2. **Apply Babs routing.**
   Use `BAB-2100` to choose PRP, CHG, PLN, ADR, INC, or another project SOP.

3. **Use Babs contract rules.**
   Put the reviewed scope and validation expectations in the correct `BAB`
   document before implementation.

4. **Use Babs review defaults.**
   Run Trinity plan review before code and Trinity implementation review before
   PR unless the operator explicitly chooses a stronger or different review
   path.

5. **Use the Babs validation stack.**
   Run applicable Elixir, browser, document, whitespace, and privacy gates.
   Record real results and explicit deferrals in the contract.

6. **Use Babs PR safety rules.**
   Publish with `gh` as `ryosaeba1985`, then follow COR-1615/COR-1612 until the
   current PR head has no required changes or the operator pauses the loop.

7. **Close out after merge.**
   Pull `main`, reconcile local state, update phase docs or trackers if needed,
   and identify the next Babs roadmap slice.

---

## Examples

### Example 1 - Start a Babs roadmap phase

1. Read `BAB-2300` and the relevant `BAB-22xx` phase document.
2. Update or create the PRP/CHG with acceptance and validation commands.
3. Run Trinity plan review and fold blockers into the contract.
4. Implement with RED tests / BDD first where practical.
5. Run the Babs validation stack, update the contract with facts, run Trinity
   implementation review, then open the PR as `ryosaeba1985`.

### Example 2 - Browser BDD phase

1. Add the browser scenario to the contract.
2. Use isolated Chrome plus `BU_CDP_URL` for repeatable BDD validation.
3. If normal Chrome profile assistance is needed, record it as manual
   assistance, not as the repeatable BDD gate.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-05 | Initial version capturing the Phase 0a-1a plan-review, TDD/BDD, validation, Trinity code-review, and PR workflow | Codex |
| 2026-05-05 | Clarify active PR monitoring cadence: poll every few minutes and resume after each push until reviews/checks settle | Codex |
| 2026-05-05 | Link PR review handling to `BAB-1504` for GitHub Codex reaction/status mechanics | Codex |
| 2026-05-05 | Switch active PR review handling from Babs-specific `BAB-1504` to promoted `COR-1615` plus `COR-1612` | Codex |
| 2026-05-07 | Add Mermaid workflow graph for the phase delivery control flow | Codex |
| 2026-05-07 | Add browser-harness BDD policy: isolated Chrome + `BU_CDP_URL` for repeatable validation, real Chrome only for operator-assistance flows | Codex |
| 2026-05-07 | Rebase BAB-1503 onto promoted COR-1616 and keep only Babs-specific adapter rules | Codex |
