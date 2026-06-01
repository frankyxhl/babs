# CHG-2276: Knowledge FileSystem Watcher

**Applies to:** BAB project
**Last updated:** 2026-06-01
**Last reviewed:** 2026-06-01
**Status:** Approved
**Date:** 2026-06-01
**Requested by:** @frankyxhl via GitHub issue #87
**Priority:** P2
**Change Type:** Normal

---

## What

Implement `BAB-2271` Phase 2 slice 2.4 / GitHub issue #87 by adding a
Knowledge filesystem watcher that broadcasts debounced change notifications when
Citizen Knowledge markdown files change under `knowledge_root`.

The slice introduces `Babs.Knowledge.Watcher` in the `:babs_citizens` app with:

- `topic/0` returning the PubSub topic for Knowledge file changes.
- `start_link(opts \\ [])` for supervision and focused tests.
- PubSub broadcasts shaped as `{:knowledge_changed, slug, name}`, where `slug`
  is the Citizen slug and `name` is the markdown path relative to that Citizen's
  Knowledge home, such as `Readme.md` or `notes/plan.md`.

## Why

Phase 2's Citizen Knowledge Home treats files as the source of truth. Browser
edits, Citizen workspace edits, external editor changes, and git checkouts must
all reach the future LiveView read/edit tabs without polling. The existing
`Babs.Citizens.Tickets.Watcher` already proves the local FileSystem + debounce +
PubSub pattern; this slice mirrors that approach for Knowledge files.

## Impact Analysis

- **Systems affected:** `:babs_citizens` supervision tree, new
  `Babs.Knowledge.Watcher` module, focused unit tests, and this CHG/index entry.
- **Runtime behavior:** the application starts a Knowledge watcher alongside the
  Ticket watcher. The watcher observes the resolved `knowledge_root` from
  `Babs.Citizens.Knowledge.Config.knowledge_root/1`, retries if the directory is
  missing at boot, and broadcasts after a short debounce window.
- **PubSub behavior:** LiveViews can subscribe to `Babs.Knowledge.Watcher.topic/0`
  on `Babs.Citizens.PubSub` and receive `{:knowledge_changed, slug, name}`.
  Payloads contain logical Citizen/file identifiers, not host filesystem paths.
- **File scope:** only markdown files inside `<knowledge_root>/<slug>/...` are
  treated as Knowledge files. Internal temp files written by `Babs.Knowledge`
  (for example `.Readme.md.<n>.babs.md.tmp`), hidden/editor artifact names, and
  non-markdown files are ignored.
- **Privacy behavior:** broadcasts must not expose absolute local paths.
- **Rollback plan:** remove the module/tests, remove the child from
  `Babs.Citizens.Application`, and remove this CHG/index entry.

## Acceptance Criteria

- [x] `Babs.Knowledge.Watcher` is started in the `:babs_citizens` supervision
      tree.
- [x] The watcher observes the resolved `knowledge_root`, with retry behavior
      when the root does not exist at startup.
- [x] A markdown file change broadcasts `{:knowledge_changed, slug, name}` on
      `Babs.Knowledge.Watcher.topic/0`.
- [x] Debounce coalesces rapid successive events for the same Citizen/file into
      one broadcast.
- [x] Non-markdown files and `Babs.Knowledge` temp files are ignored.
- [x] Focused tests cover tmp-root write/broadcast behavior, manual debounce
      coalescing, root retry, and ignored files.
- [x] Validation passes: focused tests, `mix format --check-formatted`,
      `mix compile --warnings-as-errors`, `mix test`, `npm run test:js`,
      `af validate --root .`, and `git diff --check`.

## Implementation Plan

1. Add `apps/babs_citizens/lib/babs/knowledge/watcher.ex` defining
   `Babs.Knowledge.Watcher`. This follows the existing `Babs.Knowledge` and
   `Babs.Knowledge.Markdown` namespace used by the generic Knowledge context in
   the `:babs_citizens` app. The implementation should alias
   `Babs.Citizens.Knowledge.Config` as `KnowledgeConfig` and
   `Babs.Citizens.Citizen.Config` as `CitizenConfig` for resolver and slug
   validation calls.
2. Mirror `Babs.Citizens.Tickets.Watcher` structure:
   - `use GenServer`
   - load app-env defaults with
     `Application.get_env(:babs_citizens, __MODULE__, [])`
   - configurable `enabled?`, `knowledge_root`, `debounce_ms`, `retry_ms`, and
     optional registered `name` for tests
   - `FileSystem.start_link(dirs: [root])`
   - `FileSystem.subscribe/1`
   - retry on missing root or FileSystem start failure
   - handle `{:file_event, watcher, {path, events}}` and
     `{:file_event, watcher, :stop}`
   - retry is intentionally indefinite at the configured interval, matching the
     Ticket watcher behavior for roots that may be created after application
     boot
   - info/warning logs should report watcher state without interpolating
     absolute `knowledge_root` paths; for example, log
     `"Babs Knowledge watcher active"` and
     `"Babs Knowledge watcher retrying after start failure"` without root paths.
     PubSub payloads must never contain host paths.
3. Define constants:
   - topic: `"knowledge"`
   - default debounce: `250` ms
   - default retry: `1_000` ms
   - no dedicated temp-suffix constant is required; the hidden/editor artifact
     segment rule below catches `Babs.Knowledge` temp files ending in
     `.babs.md.tmp`
4. Parse event paths without leaking host paths:
   - normalize `/private/var/` to `/var/` like the Ticket watcher for macOS
     test stability
   - only process events containing one of `:created`, `:modified`, `:renamed`,
     `:deleted`, `:removed`, `:moved_to`, or `:moved_from`
   - require the event path to be inside or equal to the expanded
     `knowledge_root` with an explicit containment guard before calling
     `Path.relative_to/2`: `path == root or String.starts_with?(path, root <> "/")`
     after both values are normalized and expanded. For root `/`, the child
     prefix is `/`.
   - compute `relative = Path.relative_to(normalized_path, normalized_root)`
   - reject root-level events where `relative == "."`
   - split `relative` with `Path.split/1`; require `[slug | name_segments]`
     where `name_segments` is non-empty
   - join `name_segments` back into `name`, preserving nested paths such as
     `notes/plan.md`
   - require `name` to end in `.md`
   - reject hidden/editor artifact path segments using the same shape as
     `Babs.Knowledge.list/2`, extended across nested paths: any `name` segment
     starts with `.`, `~`, or `#`, or ends with `.tmp`, `~`, or `#`
   - the hidden/editor artifact rule also rejects `Babs.Knowledge` temp files
     such as `.Readme.md.<n>.babs.md.tmp`
   - validate `slug` with `Babs.Citizens.Citizen.Config.valid_slug?/1`
5. On qualifying events, store `{slug, name}` tuples in a `MapSet` and reset the
   debounce timer. When the timer fires, sort the tuples and broadcast one
   `{:knowledge_changed, slug, name}` per tuple through
   `Phoenix.PubSub.broadcast(Babs.Citizens.PubSub, topic(), message)`, then clear
   the `MapSet` in the same callback. Multiple rapid events for the same tuple
   therefore produce one broadcast. This intentionally differs from the Ticket
   watcher single-payload shape because Knowledge LiveViews will usually
   subscribe for one Citizen/file and can react directly to per-file logical
   identifiers.
6. Add `Babs.Knowledge.Watcher` to `Babs.Citizens.Application` after
   `Babs.Citizens.Tickets.Watcher`.
7. Add focused tests in
   `apps/babs_citizens/test/babs_citizens/knowledge/watcher_test.exs`:
   this path follows the existing `Babs.Knowledge.MarkdownTest` location in the
   `:babs_citizens` app. Use `async: false`, matching the Ticket watcher tests,
   because these tests start PubSub/FileSystem processes and use wall-clock
   debounce windows.
   - a real tmp-root write emits `{:knowledge_changed, "clare", "Readme.md"}`
   - rapid manual file events for the same path produce exactly one broadcast
     after debounce
   - rapid manual events for two different Citizens/files in one debounce window
     produce one broadcast per tuple
   - missing root at startup retries and begins watching once the directory
     appears
   - root-level and slug-directory events are ignored
   - outside-root paths are ignored before relative path parsing
   - non-markdown files, hidden markdown files, editor artifacts, and
     `.babs.md.tmp` files do not broadcast, including hidden nested directories
   - nested markdown names such as `notes/plan.md` are preserved
8. Run focused tests to RED before implementation, implement to GREEN, then run
   the full Babs validation stack and Trinity implementation review.

## References

- `BAB-2271` - Operator Dashboard Panels, Phase 2 Citizen Knowledge Home.
- `BAB-2273` - Knowledge Root Resolution.
- `BAB-2274` - Knowledge Markdown CRUD.
- `BAB-2275` - Knowledge Markdown Render.
- GitHub issue #87 - FileSystem watcher for `knowledge_root` -> PubSub.
- `Babs.Citizens.Tickets.Watcher` - FileSystem + debounce + PubSub precedent.
- `Babs.Citizens.Knowledge.Config` - `knowledge_root` resolver.

## Review Plan

- **Plan review:** Trinity with providers `glm,deepseek,minimax` before code.
- **Implementation review:** Trinity with providers `glm,deepseek,minimax`
  before PR.
- **PR review:** GitHub Codex review loop per `COR-1615`.

## Validation Results

- 2026-06-01 initial plan review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2276-CHG-Knowledge-Watcher.md`
  produced a PASS synthesis, but raw GLM/MiniMax output identified plan blockers
  around hidden/editor artifact filtering, path parsing clarity, namespace/test
  path clarity, and event-type specificity. This revision clarifies those points
  before implementation.
- 2026-06-01 second plan review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2276-CHG-Knowledge-Watcher.md`
  produced a PASS synthesis, but raw DeepSeek output identified one remaining
  blocker: the plan required root containment but did not specify the explicit
  guard needed before `Path.relative_to/2`. This revision adds the containment
  guard, nested hidden-segment filtering, and `async: false` test guidance.
- 2026-06-01 final plan review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2276-CHG-Knowledge-Watcher.md`
  passed with no blocking findings in raw provider output; synthesis at
  `.trinity/reviews/20260601-090435-rules-BAB-2276-CHG-Knowledge-Watcher.md/synthesis.md`.
  Follow-up advisory hardening clarified the PubSub process, `start_link/1`
  default argument, no-path log templates, and cross-Citizen debounce coverage.
- 2026-06-01 TDD RED:
  `mise exec -- mix test apps/babs_citizens/test/babs_citizens/knowledge/watcher_test.exs`
  failed with 5 failures because `Babs.Knowledge.Watcher` was undefined.
- 2026-06-01 TDD GREEN:
  `mise exec -- mix test apps/babs_citizens/test/babs_citizens/knowledge/watcher_test.exs`
  passed with 9 tests and 0 failures after implementation and advisory
  hardening.
- 2026-06-01 validation stack:
  `mise exec -- mix format --check-formatted` passed;
  `mise exec -- mix compile --warnings-as-errors` passed;
  `mise exec -- mix test` passed with 565 `babs_citizens` tests and 154 `babs`
  tests; `npm run test:js` passed with 19 tests; `af validate --root .` passed
  with 203 documents checked; `git diff --check` passed.
- 2026-06-01 implementation review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope apps/babs_citizens`
  passed with no blocking findings; synthesis at
  `.trinity/reviews/20260601-091622-apps-babs_citizens/synthesis.md`.
  Raw advisory output requested Elixir-version-safe `MapSet` conversion and
  more focused test coverage; the implementation uses `Enum.to_list/1`, and the
  focused test suite now covers disabled mode, FileSystem `:stop`, every
  configured event type, invalid slugs, deterministic watcher startup, and
  outside-root cleanup.
- 2026-06-01 PR CI R1:
  GitHub Actions failed the real-write watcher test on Linux because the test
  created `clare/` after the FileSystem watcher had started. The test now creates
  the Citizen home before watcher startup, matching the existing-dir behavior
  this slice guarantees. Local rechecks passed:
  `mise exec -- mix test apps/babs_citizens/test/babs_citizens/knowledge/watcher_test.exs`
  and
  `mise exec -- mix test --max-cases 1 apps/babs_citizens/test/babs_citizens/knowledge/watcher_test.exs`.
- 2026-06-01 PR CI R2:
  GitHub Actions still missed the first Linux inotify write event on the
  real-write watcher test. The retry helper previously used `File.touch!/1`,
  which can surface as an `:attribute` event on inotify and is intentionally
  ignored by the Knowledge watcher. The helper now rewrites the markdown file
  with unique content so retries produce write/close events that the watcher
  handles.
- 2026-06-01 PR review R3:
  Codex identified that Linux inotify reports atomic save/rename target paths
  as `:moved_to`/`:moved_from`, while the watcher only accepted `:renamed`.
  The watcher now accepts both inotify move events so `Babs.Knowledge.write/4`
  and editor atomic saves broadcast for the final markdown path.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-06-01 | Initial version | Codex |
