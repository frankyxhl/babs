# CHG-2274: Knowledge Markdown CRUD

**Applies to:** BAB project
**Last updated:** 2026-06-01
**Last reviewed:** 2026-06-01
**Status:** Approved
**Date:** 2026-06-01
**Requested by:** @frankyxhl via GitHub issue #85
**Priority:** P2
**Change Type:** Normal

---

## What

Implement `BAB-2271` Phase 2 slice 2.2 / GitHub issue #85 by adding a
top-level `Babs.Knowledge` context for safe Citizen-scoped markdown file CRUD.

The slice introduces:

- `Babs.Knowledge.list(slug, opts \\ [])`, returning sorted root-level markdown
  file names from a Citizen knowledge home.
- `Babs.Knowledge.read(slug, child_path, opts \\ [])`, returning markdown file
  contents.
- `Babs.Knowledge.write(slug, child_path, content, opts \\ [])`, writing
  markdown content with an atomic same-directory temp-file plus rename.
  `write/4` is create-or-replace; concurrent writes to the same path are
  last-writer-wins.
- `Babs.Knowledge.delete(slug, child_path, opts \\ [])`, deleting a markdown
  file.

All concrete file paths must be produced by
`Babs.Citizens.Knowledge.Config.resolve/3` from slice 2.1. Public return values
must not expose host absolute paths, including resolver failure paths.
`child_path` is a relative path inside the Citizen knowledge home, not only a
flat basename; for example, `"Readme.md"` and `"notes/draft.md"` are both valid
child paths when they pass the resolver and markdown checks.

## Why

Phase 2 needs a file-backed Citizen Knowledge Home before render, watcher, UI,
and prompt-injection slices can be built. The core CRUD boundary is where path
safety, markdown scoping, atomic write semantics, and symlink rejection must be
centralized so later slices do not each reimplement filesystem policy.

## Impact Analysis

- **Systems affected:** new `Babs.Knowledge` module in the `:babs_citizens`
  app, tests under `apps/babs_citizens/test/`, and this CHG/index entry.
- **Runtime behavior:** callers can list/read/write/delete markdown files in a
  Citizen knowledge home. Missing homes list as empty. `write/4` creates parent
  directories for safe relative markdown paths, permits empty markdown content,
  and intentionally does not roll back newly created safe directories if a later
  write step fails.
- **Storage behavior:** files remain the source of truth. No SQLite schema or
  state table is introduced.
- **Security behavior:** every user-supplied child path goes through the slice
  2.1 resolver before filesystem access. Traversal and non-relative paths return
  normalized resolver-derived errors. Existing symlink components from the
  configured Babs root or knowledge root through the target path, including the
  Citizen home itself, are rejected before read/write/delete/list file
  inspection.
- **Atomicity behavior:** writes occur by writing a temp file in the final
  directory and then installing it with `File.rename/2`, so readers never observe
  a partially written final file. Because this module is stateless, `write/4`
  also cleans stale temp files for the target child path at the start of each
  write. Cleanup uses an age threshold to avoid deleting another writer's recent
  in-flight temp file.
- **Listing behavior:** `list/2` returns only visible root-level lowercase `.md`
  regular files. It excludes dot-prefixed entries, `~`-prefixed entries,
  `*.tmp`, and editor backup names starting or ending in `#` or ending in `~`.
  Symlinked root-level entries are omitted from the listing, while direct
  read/write/delete attempts on the same path return an unsafe-symlink error.
- **Privacy behavior:** successful public API responses return relative names or
  markdown content only. Knowledge CRUD maps resolver child-path errors to
  redacted child-path reason atoms so errors avoid absolute host paths.
- **Rollback plan:** delete the `Babs.Knowledge` module/tests and remove this
  CHG/index entry. Existing markdown files remain on disk and need no migration.

## Acceptance Criteria

- [x] `Babs.Knowledge` implements list/read/write/delete scoped to a Citizen
      home.
- [x] All file access uses `Babs.Citizens.Knowledge.Config.resolve/3` or
      `citizen_home/2` for the Citizen home boundary; traversal attempts error
      out before filesystem access.
- [x] Resolver child-path errors are normalized so `Babs.Knowledge` never
      returns absolute host paths.
- [x] Non-markdown child paths return `{:error, {:not_markdown, child_path}}`.
- [x] Existing symlink components, including configured knowledge-root ancestry
      and the Citizen home itself, are rejected before read/write/delete/list
      file inspection, with the relative unsafe component in the error.
- [x] `write/4` is atomic via same-directory temp file plus `File.rename/2`;
      tests prove the final file still contains the old content before rename.
- [x] `write/4` cleans stale temp files for the target child path before writing
      a new temp file without deleting recent in-flight temp files.
- [x] `write/4` creates parent directories for safe nested child paths, permits
      empty binary content, and rejects non-binary content.
- [x] `list/2` returns `{:ok, []}` for a missing Citizen home and excludes
      hidden/temp/editor-backup entries.
- [x] Unit tests cover CRUD, traversal rejection, markdown-only behavior,
      symlink rejection, missing files, and atomic write behavior.
- [x] Validation passes: focused tests, `mix format --check-formatted`,
      `mix compile --warnings-as-errors`, `mix test`, `npm run test:js`,
      `af validate --root .`, and `git diff --check`.

## Implementation Plan

1. Add `apps/babs_citizens/lib/babs/knowledge.ex` defining `Babs.Knowledge`.
   This top-level module name matches the issue/PRP surface while staying in
   the `:babs_citizens` app because the resolver and Citizen storage policy live
   there.
2. Implement public functions:
   - `list(slug, opts \\ []) :: {:ok, [String.t()]} | {:error, term()}`
   - `read(slug, child_path, opts \\ []) ::
     {:ok, String.t()} | {:error, term()}`
   - `write(slug, child_path, content, opts \\ []) ::
     :ok | {:error, term()}`
   - `delete(slug, child_path, opts \\ []) :: :ok | {:error, term()}`
3. Resolve paths with this sequence for read/write/delete:
   1. Call `Babs.Citizens.Knowledge.Config.resolve(slug, child_path, opts)`.
      Resolver errors take precedence over markdown extension errors so unsafe
      traversal attempts never get masked by extension checks. Normalize resolver
      child-path errors before returning them from `Babs.Knowledge`:
      - `{:invalid_relative_path, _}` -> `{:invalid_child_path, :not_string}`
      - `{:null_byte, _}` -> `{:invalid_child_path, :null_byte}`
      - `{:empty_relative_path, _}` -> `{:invalid_child_path, :empty}`
      - `{:non_relative_path, _}` -> `{:invalid_child_path, :non_relative}`
      - `{:path_traversal, _}` -> `{:invalid_child_path, :path_traversal}`
      - `{:path_escape, _}` -> `{:invalid_child_path, :path_escape}`
      `{:invalid_slug, slug}` passes through because it contains caller-supplied
      slug data, not a host path.
   2. Reject non-`.md` child paths with
      `{:error, {:not_markdown, child_path}}`.
   3. Get the Citizen home with `citizen_home/2` and derive the symlink guard
      root. When `knowledge_root` is lexically inside `root`, the guard starts
      at `root` so configured `root/knowledge` ancestry is inspected before
      `File.mkdir_p/1`. When `knowledge_root` is outside `root`, the guard
      starts at `knowledge_root`.
   4. Walk existing path components from the guard root through the target with
      `File.lstat/1` and reject any symlink with:
      `{:error, {:unsafe_symlink, %{path: child_path, component: component}}}`.
      `component` is relative to the guard root; for the default
      `root/knowledge/<slug>` layout, `"knowledge"` means the configured
      knowledge root, `"knowledge/<slug>"` means the Citizen home,
      `"knowledge/<slug>/notes"` means an intermediate directory, and
      `"knowledge/<slug>/<file>.md"` means the target file. During write
      preflight, `:enoent` for a non-existent component stops the first walk
      successfully because all existing ancestors have been checked; after
      `File.mkdir_p(Path.dirname(final_path))`, run the walk again so
      newly-created parent directories are also checked. During read/delete,
      `:enoent` stops the guard successfully and the subsequent `File.read/1` or
      `File.rm/1` maps the missing target to `{:not_found, child_path}`.
   5. Perform the filesystem operation.
4. Implement `list/2` by resolving `"."` for the home path, rejecting symlinked
   configured knowledge-root ancestry or homes with
   `{:error, {:unsafe_symlink, %{path: ".", component: component}}}`, returning
   `{:ok, []}` only when `File.lstat(home_path)` returns `{:error, :enoent}`,
   and mapping other home inspection/listing errors to
   `{:error, {:redacted_io_error, {:list_knowledge, reason}}}`. Return names in
   ascending lexical order. List only root-level visible lowercase `.md` regular
   files. Exclude entries whose basename starts with `.`, `~`, or `#`, entries
   ending in `.tmp`, and entries ending in `~` or `#`. For each listed markdown
   entry, resolve the entry name before inspecting it and ignore non-regular
   files, including symlinks. Resolver errors on individual listed entries are
   skipped because they represent list/inspect races or impossible
   directory-entry states; only home-level resolution and home symlink checks are
   hard list errors. If all entries are skipped this still returns `{:ok, []}`
   in this slice; later UI slices may add observability if that becomes
   confusing.
5. Implement `write/4` so content must be a binary, otherwise return
   `{:error, {:invalid_content, :not_binary}}`. Empty binaries are valid
   markdown content. For a final path such as `notes/draft.md`, call
   `File.mkdir_p(Path.dirname(final_path))` after resolver validation. This
   creates the Citizen home itself and all nested parent directories as needed.
   A `File.mkdir_p/1` failure maps to
   `{:error, {:redacted_io_error, {:mkdir_knowledge, reason}}}`. Re-run the
   symlink guard after directory creation, and write the temp file in that same
   final directory. Newly created safe directories are not rolled back on later
   failure because deleting them risks removing externally-created files and they
   are already inside a resolved, checked Citizen home.
6. Name temp files as `".#{Path.basename(final_path)}.#{unique}.babs.md.tmp"`.
   Generate `unique` with `System.unique_integer([:positive, :monotonic])`.
   At the start of `write/4`, after resolving and creating the target directory,
   delete files matching the final-directory-scoped exact temp-name pattern
   `~r/^\.#{Regex.escape(Path.basename(final_path))}\.\d+\.babs\.md\.tmp$/`
   only when their mtime is at least `:stale_temp_age_ms` old. Use `File.ls/1`
   plus a compiled regex, not a glob, so markdown names containing glob
   metacharacters cannot broaden cleanup. The default threshold is 900_000 ms
   (15 minutes); tests may pass `stale_temp_age_ms: 0` to make cleanup
   deterministic. Then write the new hidden temp file. The optional internal
   test hook is read from `opts[:before_rename]`, defaults to
   `fn _temp_path, _final_path -> :ok end`, is called as
   `before_rename.(temp_path, final_path)` after the temp file is fully written
   and immediately before `File.rename/2`, and must return `:ok` or
   `{:error, reason}`. It follows existing writer test-hook patterns but is not
   part of the stable production API. On hook failure or `File.rename/2` error,
   remove the temp file before returning the mapped error. Use `File.rename/2`,
   not `File.rename!/2`.
7. Map expected file errors to stable API errors:
   - `{:error, {:not_found, child_path}}` for missing read/delete targets
   - `{:error, {:invalid_child_path, reason}}` for normalized resolver
     child-path errors
   - `{:error, {:redacted_io_error, {operation, reason}}}` for other IO errors
   - operation atoms are `:list_knowledge`, `:inspect_knowledge_path`,
     `:mkdir_knowledge`, `:cleanup_knowledge_temp`, `:read_knowledge`,
     `:write_knowledge_temp`, `:before_rename_knowledge`, `:install_knowledge`,
     and `:delete_knowledge`
   - only `{:invalid_slug, slug}` resolver errors pass through as-is
   This slice does not add a user-facing error-message module; later UI slices
   can map these stable tuples to display text.
8. Add RED tests first in
   `apps/babs_citizens/test/babs_citizens/knowledge_test.exs` with test module
   `Babs.KnowledgeTest`. The file path follows the `:babs_citizens` app's test
   root; the module name follows the top-level module under test. Cover:
   - list returns sorted root markdown names only
   - list returns empty for a missing home
   - list excludes hidden/temp/editor-backup entries
   - read/write/delete round trip under configured knowledge root
   - nested child path write creates parent directories
   - traversal and absolute paths are rejected
   - resolver child-path errors are redacted to `{:invalid_child_path, reason}`
     without absolute host paths
   - non-markdown names are rejected
   - invalid slugs propagate resolver errors
   - missing read/delete returns `{:error, {:not_found, child_path}}`
   - non-binary write content returns `{:invalid_content, :not_binary}`
   - empty binary content writes successfully
   - symlinked configured knowledge-root ancestry, Citizen homes, directories,
     and files are rejected for direct operations, while symlinked root-level
     files are omitted by `list/2`
   - stale temp cleanup removes orphaned temp files for the target child path
   - atomic write hook observes the old final content before rename and no temp
     file remains after success/failure
9. Run focused tests to prove RED, implement the module, then run focused tests
   to GREEN.
10. Run the full Babs validation stack, update this CHG with actual results, run
   Trinity implementation review, then publish the PR per `COR-1615`.

## References

- `BAB-2271` - Operator Dashboard Panels, Phase 2 Citizen Knowledge Home.
- `BAB-2273` - Knowledge Root Resolution.
- GitHub issue #85 - `Babs.Knowledge` core safe markdown CRUD.
- `Babs.Citizens.Knowledge.Config` - canonical Citizen knowledge path resolver.
- `Babs.Citizens.Tickets.Writer` - existing same-directory temp plus rename
  pattern for markdown writes.

## Review Plan

- **Plan review:** Trinity with providers `glm,deepseek,minimax` before code.
- **Implementation review:** Trinity with providers `glm,deepseek,minimax`
  before PR.
- **PR review:** GitHub Codex review loop per `COR-1615`.

## Validation Results

- 2026-06-01 initial plan review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2274-CHG-Knowledge-Markdown-CRUD.md`
  produced a PASS synthesis, but raw provider output identified plan blockers
  around `child_path` semantics, home-level symlink checks, hidden/temp listing
  filters, stateless temp cleanup, symlink error shape, write directory
  creation, and concurrent overwrite semantics. This revision clarifies those
  points before implementation.
- 2026-06-01 second plan review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2274-CHG-Knowledge-Markdown-CRUD.md`
  produced a PASS synthesis, but raw provider output identified remaining plan
  blockers around resolver path redaction, `:before_rename` hook contract,
  `File.lstat/1` `:enoent` handling during symlink walks, and test file
  placement. This revision clarifies those points before implementation.
- 2026-06-01 third plan review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2274-CHG-Knowledge-Markdown-CRUD.md`
  produced a PASS synthesis, but raw provider output identified remaining plan
  blockers around `File.mkdir_p/1` failure mapping and whether `write/4` creates
  the Citizen home. This revision clarifies that `write/4` creates the home and
  all parent directories, maps mkdir failures through `:mkdir_knowledge`, fixes
  the missing-error wrapper in the test checklist, and specifies temp unique and
  glob behavior.
- 2026-06-01 final plan review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2274-CHG-Knowledge-Markdown-CRUD.md`
  passed with no blocking findings in raw provider output; synthesis at
  `.trinity/reviews/20260601-061537-rules-BAB-2274-CHG-Knowledge-Markdown-CRUD.md/synthesis.md`.
- RED:
  `mise exec -- mix test apps/babs_citizens/test/babs_citizens/knowledge_test.exs`
  failed with 10 tests, 10 failures because `Babs.Knowledge` did not exist.
- GREEN:
  `mise exec -- mix test apps/babs_citizens/test/babs_citizens/knowledge_test.exs`
  passed, 10 tests.
- `mise exec -- mix format --check-formatted`: passed.
- `mise exec -- mix compile --warnings-as-errors`: passed.
- `mise exec -- mix test`: passed, 539 `babs_citizens` tests and 154 `babs`
  tests.
- `npm run test:js`: passed, 19 tests.
- `af validate --root .`: passed, 201 documents checked.
- `git diff --check`: passed.
- 2026-06-01 implementation review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope apps/babs_citizens`
  passed with no blocking findings in raw provider output; synthesis at
  `.trinity/reviews/20260601-062536-apps-babs_citizens/synthesis.md`. Follow-up
  hardening changed temp cleanup to `File.lstat/2`, added direct target-symlink
  write/delete assertions, covered null/empty/non-string child paths, and covered
  unexpected `:before_rename` returns.
- 2026-06-01 second implementation review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope apps/babs_citizens`
  passed with no blocking findings in raw provider output; synthesis at
  `.trinity/reviews/20260601-063037-apps-babs_citizens/synthesis.md`. Follow-up
  advisory hardening changed invalid child-path type mapping from `:not_binary`
  to `:not_string` and tightened stale-temp cleanup to exact numeric temp-name
  matching.
- Final validation after implementation-review hardening:
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/knowledge_test.exs`:
    passed, 10 tests.
  - `mise exec -- mix format --check-formatted`: passed.
  - `mise exec -- mix compile --warnings-as-errors`: passed.
  - `mise exec -- mix test`: passed, 539 `babs_citizens` tests and 154 `babs`
    tests.
  - `npm run test:js`: passed, 19 tests.
  - `af validate --root .`: passed, 201 documents checked.
  - `git diff --check`: passed.
- PR review hardening for GitHub Codex finding
  `discussion_r3330978394`: expanded the symlink walk to include configured
  knowledge-root ancestry before write directory creation. Follow-up Trinity
  advisory hardening added the root `/` containment edge case, absolute external
  `knowledge_root` coverage, and direct read/delete assertions for the new
  symlink scenarios.
  - `mise exec -- mix test apps/babs_citizens/test/babs_citizens/knowledge_test.exs`:
    passed, 13 tests.
  - `mise exec -- mix format --check-formatted`: passed.
  - `mise exec -- mix compile --warnings-as-errors`: passed.
  - `mise exec -- mix test`: passed, 542 `babs_citizens` tests and 154 `babs`
    tests.
  - `npm run test:js`: passed, 19 tests.
  - `af validate --root .`: passed, 201 documents checked.
  - `git diff --check`: passed.
  - `trinity review --providers glm,deepseek,minimax --preset fast-review --scope apps/babs_citizens`:
    passed 3/3 providers; synthesis at
    `.trinity/reviews/20260601-074733-apps-babs_citizens/synthesis.md`.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-06-01 | Initial version | — |
