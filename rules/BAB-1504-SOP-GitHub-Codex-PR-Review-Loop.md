# SOP-1504: GitHub Codex PR Review Loop

**Applies to:** BAB project
**Last updated:** 2026-05-05
**Last reviewed:** 2026-05-05
**Status:** Deprecated
**Replaced by:** COR-1615 (GitHub App PR Review Bot Loop), then COR-1612
(Respond To PR Review Comments)

---

## v0.1 Status - Deprecated (2026-05-05)

This Babs-specific SOP was promoted into the package-level `COR-1615` workflow.
Do not use `BAB-1504` as the active PR review loop. Use `COR-1615` to trigger,
poll, and match GitHub App review bot results to the current PR head; then use
`COR-1612` to classify and address fetched review findings.

Keep this document only as historical source material for why the Babs workflow
needed the promoted COR procedure.

---

## What Is It?

The Babs project procedure for using GitHub's Codex pull-request review loop:
triggering a review, interpreting GitHub reactions and review objects, polling
without spamming, reading actionable comments, fixing blockers, and repeating
until the latest head commit has no new required changes.

## Why

Phase 1a showed that GitHub Codex review is useful but easy to misread. An
`eyes` reaction on an `@codex review` comment means Codex has seen or queued the
request, not that review has completed. Flat PR comment APIs can also show old
inline comments against new diff lines, so an agent can mistake already-fixed
feedback for a fresh blocker.

This SOP makes the loop explicit so later Babs phases do not merge while a review
is still pending, ignore a real blocker, or spam duplicate review requests.

---

## When to Use

- A Babs PR is open and the operator asks for Codex/GitHub review.
- A branch has been pushed after addressing PR feedback and needs another review
  on the new head commit.
- A phase delivery is in `BAB-1503` step 13, "Handle PR review loops."
- The agent needs to distinguish pending Codex work from completed Codex review
  results.

## When NOT to Use

- Trinity plan review or Trinity code review. Use the Trinity workflow instead.
- Local code review before a PR exists.
- CI failure diagnosis without PR review comments. Use the CI/debug route.
- GitHub-visible writes from an account other than `ryosaeba1985`.

---

## Prerequisites

- Know the repository and PR number, for example `frankyxhl/babs` PR `7`.
- Confirm `gh auth status` shows the active account is `ryosaeba1985` before any
  PR comment or PR creation.
- Do not use a GitHub connector for visible writes if it would publish as
  `frankyxhl`.
- Know the local branch head and the remote PR head:
  `git status --short --branch` and `gh pr view <PR> --json headRefOid`.
- Do not include private Tailscale IPs, tokens, or local host details in PR
  comments, PR bodies, or committed docs.

---

## Status Vocabulary

| Signal | Meaning | What to do |
|--------|---------|------------|
| `@codex review` PR comment by `ryosaeba1985` | Manual review request was posted | Wait; do not post another request immediately |
| `eyes` reaction on that comment | Codex has noticed or queued the request | Keep polling; review is not complete yet |
| `thumbs up` reaction with no new comments | Codex may have no suggestions for that request | Confirm the reaction applies to the current head before treating it as clear |
| Review by `chatgpt-codex-connector` with `Reviewed commit: <sha>` | Codex review completed for that commit | Compare `<sha>` with current `headRefOid` |
| Inline comments from `chatgpt-codex-connector` | Actionable or advisory findings | Read priority and body; fix blockers first |
| Review is for an older commit | Current head is not covered | Trigger a new review after the latest push |
| Thread `isOutdated: true` | Comment was anchored to old diff content | Do not treat it as a fresh blocker unless the issue still exists |

---

## Commands

Confirm identity:

```bash
gh auth status
```

Trigger manual Codex review:

```bash
gh pr comment <PR> --repo <owner>/<repo> --body '@codex review'
```

Poll PR status and latest reviews:

```bash
gh pr view <PR> --repo <owner>/<repo> \
  --json number,state,mergeable,reviewDecision,headRefOid,latestReviews,comments,statusCheckRollup
```

Read flat inline comments:

```bash
gh api repos/<owner>/<repo>/pulls/<PR>/comments \
  --jq '.[] | {id, user: .user.login, path, line, commit_id, body, created_at, html_url}'
```

When thread state matters, use a thread-aware GraphQL read. In Codex sessions
with the GitHub plugin available, the helper script can be used:

```bash
python3 /path/to/gh-address-comments/scripts/fetch_comments.py <owner>/<repo> <PR>
```

The important fields are `reviewThreads[].isOutdated`,
`reviewThreads[].isResolved`, `path`, `line`, and the comment body.

## Steps

1. **Resolve the current PR head.**
   Run `gh pr view` and record `headRefOid`. A Codex review only clears the head
   it explicitly reviewed.

2. **Confirm GitHub identity before writing.**
   Run `gh auth status`. If the active account is not `ryosaeba1985`, stop and
   fix authentication before creating comments, PRs, or reviews.

3. **Trigger review only when needed.**
   Post one `@codex review` comment when the PR is ready for review or after a
   push changes the head. Do not repeatedly post review requests while a prior
   request already has an `eyes` reaction or is still waiting.

4. **Poll every few minutes.**
   Check `latestReviews`, `comments`, and `headRefOid`. An `eyes` reaction is an
   in-progress signal. It is not an approval and not a failure.

5. **Match review result to the head commit.**
   Read the Codex review body and find `Reviewed commit: <sha>`. If `<sha>` does
   not match the current `headRefOid` prefix, the review is stale and another
   review is needed after the current push settles.

6. **Read actionable findings.**
   Use flat comments for a quick scan, then use thread-aware data when a comment
   might be stale or remapped to a new line. Treat P1/P2 findings as blockers
   unless there is a clear reason to reject them.

7. **Fix blockers locally.**
   Make focused changes, update the phase CHG or SOP when the fix changes
   process or acceptance facts, and run relevant validation. Do not run unrelated
   long checks unless the phase requires them or the operator approves.

8. **Commit and push.**
   Keep commits focused and do not include generated artifacts, transcripts,
   private IPs, or secrets.

9. **Restart the loop after every push.**
   A push creates a new head commit. Trigger a new `@codex review`, then repeat
   polling and comment inspection for that head.

10. **Stop only when the latest head is clear.**
    The loop is done when the latest Codex review or reaction applies to the
    current `headRefOid`, there are no new actionable comments, required checks
    are settled, and the operator has not asked to keep waiting.

---

## Pitfalls

- **Wrong GitHub identity:** PR comments must be posted by `ryosaeba1985`, not
  `frankyxhl`.
- **Mistaking `eyes` for done:** `eyes` means Codex noticed the request; wait for
  a completed review or a clear no-suggestion reaction.
- **Stale inline comments:** GitHub can display old comments against current
  diff lines. Check `isOutdated` before re-fixing an already-fixed item.
- **Reviewing the wrong commit:** a review on `abc123` does not cover a later
  push `def456`.
- **Duplicate triggers:** repeated `@codex review` comments while one is already
  active add noise and can make the review timeline harder to interpret.
- **Private environment leakage:** never put real Tailscale IPs or machine-local
  secrets in public PR text.

---

## Completion Criteria

- Current `headRefOid` is known.
- Latest Codex result is matched to that head.
- New actionable comments have been fixed or explicitly deferred by the
  operator.
- Relevant local validation has passed after the last fix.
- The PR is mergeable or the remaining blockers are external to Codex review.

---

## Examples

### Example 1 - `eyes` reaction but no completed review yet

1. The agent posts `@codex review`.
2. GitHub shows an `eyes` reaction from Codex on that comment.
3. `gh pr view` still shows the latest review was for an older commit.
4. The correct action is to wait and poll again in a few minutes. Do not treat
   `eyes` as approval, and do not post another `@codex review`.

### Example 2 - Fix pushed after Codex finds a P1

1. Codex review for `abc123` reports a P1 inline comment.
2. The agent fixes it locally, runs relevant validation, commits, and pushes
   `def456`.
3. The old review is now stale because it covered `abc123`, not `def456`.
4. The agent posts one new `@codex review` and monitors until Codex reviews
   `def456` or reacts with a clear no-suggestion signal for that head.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-05 | Initial version documenting GitHub Codex review triggers, reactions, polling, thread checks, and fix/push/review loop | Codex |
| 2026-05-05 | Deprecated after promotion to package-level `COR-1615`; active PR review findings handling now continues through `COR-1612` | Codex |
