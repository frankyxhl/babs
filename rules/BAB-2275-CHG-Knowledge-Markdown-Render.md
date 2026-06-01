# CHG-2275: Knowledge Markdown Render

**Applies to:** BAB project
**Last updated:** 2026-06-01
**Last reviewed:** 2026-06-01
**Status:** Approved
**Date:** 2026-06-01
**Requested by:** @frankyxhl via GitHub issue #86
**Priority:** P2
**Change Type:** Normal

---

## What

Implement `BAB-2271` Phase 2 slice 2.3 / GitHub issue #86 by adding a
Knowledge markdown helper that parses optional YAML frontmatter and renders the
markdown body to sanitized HTML.

The slice introduces `Babs.Knowledge.Markdown` in the `:babs_citizens` app with:

- `parse(content)` returning `{:ok, {frontmatter_map, body}}`.
- `render_body(body)` returning `{:ok, sanitized_html}` for a markdown body.
- `render(content)` returning parsed frontmatter, separated body, and sanitized
  HTML in one call.

## Why

Phase 2's Citizen Knowledge Home needs a server-side rendering boundary before
the LiveView read tab can safely display `Readme.md` and later note files. The
parser must keep generic Knowledge frontmatter looser than strict Ticket
frontmatter while still producing safe HTML for future `Phoenix.HTML.raw/1`
injection by UI code.

## Impact Analysis

- **Systems affected:** `:babs_citizens` dependencies, new
  `Babs.Knowledge.Markdown` module, focused unit tests, and this CHG/index entry.
- **Dependency behavior:** add `:mdex` for CommonMark/GFM-compatible markdown
  rendering with sanitizer support. This slice uses MDEx's built-in extension
  flags, not the separate `:mdex_gfm` package. `:yaml_elixir` is already present
  and remains the YAML parser.
- **Runtime behavior:** callers can parse optional YAML frontmatter from any
  Knowledge markdown file. Files without frontmatter return an empty map and the
  full body unchanged.
- **Security behavior:** rendered HTML is sanitized at the rendering boundary.
  Raw script injection and common event-handler / `javascript:` URL vectors must
  not survive into returned HTML. YAML frontmatter parsing must keep keys as
  strings so user-authored frontmatter cannot create unbounded atoms. Leading
  frontmatter is capped at 65,536 bytes before a closing fence is found.
- **Privacy behavior:** parser/render errors return stable reason tuples and do
  not include host filesystem paths.
- **Rollback plan:** remove the module/tests, remove the `:mdex` dependency and
  lockfile entries, and remove this CHG/index entry.

## Acceptance Criteria

- [x] Optional YAML frontmatter is parsed into a map and separated from the body.
- [x] Missing frontmatter returns `%{}` plus the full markdown body.
- [x] Empty YAML frontmatter returns `%{}`.
- [x] Invalid YAML or non-map YAML returns a stable parse error.
- [x] Markdown body renders to sanitized HTML suitable for later LiveView use.
- [x] Unit tests cover frontmatter, no-frontmatter, missing closing fence,
      non-binary input, code blocks, and sanitizer XSS vectors.
- [x] Validation passes: focused tests, `mix format --check-formatted`,
      `mix compile --warnings-as-errors`, `mix test`, `npm run test:js`,
      `af validate --root .`, and `git diff --check`.

## Implementation Plan

1. Add `{:mdex, "~> 0.12.2"}` to `apps/babs_citizens/mix.exs` and update
   `mix.lock` with `mise exec -- mix deps.get`.
2. Add `apps/babs_citizens/lib/babs/knowledge/markdown.ex` defining
   `Babs.Knowledge.Markdown` with these public specs:
   - `parse(term()) :: {:ok, {map(), String.t()}} | {:error, term()}`
   - `render_body(term()) :: {:ok, String.t()} | {:error, term()}`
   - `render(term()) :: {:ok, %{frontmatter: map(), body: String.t(), html: String.t()}} | {:error, term()}`
3. Implement `parse/1`:
   - non-binary input returns `{:error, {:invalid_markdown, :not_string}}`.
  - content beginning with a first line whose trailing-whitespace-trimmed value
    is exactly `---`, with no leading whitespace before the fence,
     parses the first complete leading frontmatter block using a line-based
     scanner, not a single regex. The scanner finds the next line whose
     trailing-whitespace-trimmed value is exactly `---`, again with no leading
     whitespace before the fence; bytes between the opening and closing fence
     are YAML, and bytes after the closing fence line are body. This avoids
     ambiguity for empty frontmatter such as `---\n---\n`, supports LF or CRLF
     line endings, and prevents indented `---` inside YAML block scalars from
     being mistaken for a closing fence.
   - a leading `---` without a closing fence returns
     `{:error, {:invalid_frontmatter, :missing_closing_fence}}`.
     A leading `---` is intentionally treated as attempted frontmatter, not a
     CommonMark thematic break, because this slice follows Jekyll/Hugo-style
     file-frontmatter convention.
   - more than 65,536 bytes of YAML before the closing fence returns
     `{:error, {:invalid_frontmatter, :frontmatter_too_large}}`.
   - no leading frontmatter returns `{:ok, {%{}, content}}`; the body is the full
     input unchanged.
   - empty or `nil` YAML returns `%{}`.
   - YAML is decoded with `YamlElixir.read_from_string(yaml, atoms: false)`, and
     returned frontmatter maps use string keys. User-authored keys must never be
     converted with `String.to_atom/1`; YAML keys written as `:symbol` remain
     string keys such as `":symbol"`.
   - decoded non-map YAML returns
     `{:error, {:invalid_frontmatter, :frontmatter_not_map}}`.
   - YAML failures return
     `{:error, {:invalid_frontmatter, {:yaml_decode_failed, reason}}}` with no
     host path data.
   - for content with frontmatter, the returned body is the markdown after the
     closing fence with the one fence separator line ending removed; no
     additional whitespace trimming is performed.
4. Implement `render_body/1`:
   - non-binary input returns `{:error, {:invalid_markdown, :not_string}}`.
   - empty string input returns `{:ok, ""}`.
   - use `MDEx.to_html/2` with the explicit built-in extensions
     `strikethrough: true`, `table: true`, `tasklist: true`, and `autolink:
     true`.
  - use `render: [unsafe: true]` plus `sanitize:
     MDEx.Document.default_sanitize_options()`. `unsafe: true` is intentional
     only so user-authored inline HTML can be passed through the sanitizer and
     safe tags can survive; sanitizer output, not raw MDEx unsafe output, is the
     trust boundary. The default sanitizer strips the checkbox `<input>` emitted
     by the task-list extension; this slice does not add an `input` allowlist
     because that would also allow user-authored input elements.
   - MDEx failures return `{:error, {:render_failed, reason}}`; raised
     exceptions are caught defensively and return
     `{:error, {:render_failed, {exception_module, message}}}`.
5. Implement `render/1` as parse then render, returning
   `{:ok, %{frontmatter: frontmatter, body: body, html: html}}` or propagating
   parse/render errors unchanged. For content without frontmatter, `body` is the
   full input unchanged.
   `render/1` does not call `render_body/1` when `parse/1` fails.
6. Add RED tests in
   `apps/babs_citizens/test/babs_citizens/knowledge/markdown_test.exs` covering:
   - frontmatter + body split
   - no frontmatter
   - empty frontmatter
   - frontmatter-only content returning `%{}` and an empty body
   - missing closing frontmatter fence
   - oversized frontmatter before a closing fence
   - leading blank line before `---` does not trigger frontmatter parsing
   - invalid YAML / non-map YAML
   - empty string input for `parse/1` and direct empty string input for
     `render_body/1`
   - non-binary parse/render input
   - combined `render/1` happy path with `:frontmatter`, `:body`, and `:html`
     keys
   - `render/1` propagates parse errors unchanged and does not attempt body
     rendering after parse failure
   - render failures from invalid body bytes are propagated unchanged from
     `render_body/1` when MDEx returns an error
  - fenced code block and indented code block rendering
  - CRLF line endings and trailing whitespace on the closing frontmatter fence
  - indented `---` inside YAML frontmatter content is not treated as a fence
  - frontmatter at exactly the 65,536-byte cap is accepted
  - strikethrough, table, task-list, and autolink extension behavior through the
    sanitizer boundary
   - raw `<script>`, `<img onerror>`, `<svg onload>`, and
     `<style>` sanitization
   - lowercase and mixed-case `<a href="javascript:...">` sanitization
7. Do not use MDEx's native `front_matter_delimiter` extension in this slice.
   Manual split plus `YamlElixir` is chosen to preserve TicketMarkdown-style
   error tuples and keep parse/render concerns separate.
8. Run focused tests to RED before implementation, implement to GREEN, then run
   the full Babs validation stack and Trinity implementation review.

## References

- `BAB-2271` - Operator Dashboard Panels, Phase 2 Citizen Knowledge Home.
- `BAB-2273` - Knowledge Root Resolution.
- `BAB-2274` - Knowledge Markdown CRUD.
- GitHub issue #86 - Markdown render + frontmatter parse for knowledge files.
- `Babs.Citizens.Tickets.TicketMarkdown` - strict Ticket frontmatter precedent.
- MDEx docs - markdown rendering and sanitizer behavior.

## Review Plan

- **Plan review:** Trinity with providers `glm,deepseek,minimax` before code.
- **Implementation review:** Trinity with providers `glm,deepseek,minimax`
  before PR.
- **PR review:** GitHub Codex review loop per `COR-1615`.

## Validation Results

- 2026-06-01 initial plan review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2275-CHG-Knowledge-Markdown-Render.md`
  produced a PASS synthesis, but raw GLM/DeepSeek output identified plan
  blockers around `render_body/1` return type, `render/1` error propagation,
  MDEx extension specificity, frontmatter fence/body rules, and missing
  non-binary tests. This revision clarifies those points before implementation.
- 2026-06-01 second plan review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2275-CHG-Knowledge-Markdown-Render.md`
  produced a PASS synthesis, but raw GLM output identified one remaining blocker:
  the frontmatter fence regex used `[ \t]*`, which was narrower than the
  TicketMarkdown precedent and less CRLF-tolerant. This revision switches fence
  whitespace to `\s*`, documents the manual-frontmatter trade-off, and adds
  combined render/frontmatter-only/code-block test requirements.
- 2026-06-01 third plan review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2275-CHG-Knowledge-Markdown-Render.md`
  produced a PASS synthesis, but raw GLM/DeepSeek output identified remaining
  blockers around empty frontmatter matching and YAML atom safety. This revision
  supports `---\n---\n`, requires `atoms: false` with string-keyed maps, documents
  leading-fence semantics, and expands sanitizer tests beyond `<script>`.
- 2026-06-01 fourth plan review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2275-CHG-Knowledge-Markdown-Render.md`
  produced a PASS synthesis, but raw DeepSeek output identified that the revised
  regex could still treat an empty closing fence as YAML content. This revision
  replaces the regex contract with a line-based fence scanner and adds explicit
  empty-input and `render/1` error-propagation test requirements.
- 2026-06-01 final plan review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2275-CHG-Knowledge-Markdown-Render.md`
  passed with no blocking findings in raw provider output; synthesis at
  `.trinity/reviews/20260601-081646-rules-BAB-2275-CHG-Knowledge-Markdown-Render.md/synthesis.md`.
  Follow-up advisory hardening expanded sanitizer tests and documented leading
  blank-line frontmatter behavior.
- 2026-06-01 TDD RED:
  `mise exec -- mix test apps/babs_citizens/test/babs_citizens/knowledge/markdown_test.exs`
  failed before implementation because `Babs.Knowledge.Markdown` was undefined.
- 2026-06-01 TDD GREEN:
  `mise exec -- mix test apps/babs_citizens/test/babs_citizens/knowledge/markdown_test.exs`
  passed with 14 tests and 0 failures after implementation and advisory
  hardening.
- 2026-06-01 validation stack:
  `mise exec -- mix format --check-formatted` passed;
  `mise exec -- mix compile --warnings-as-errors` passed;
  `mise exec -- mix test` passed with 556 `babs_citizens` tests and 154 `babs`
  tests; `npm run test:js` passed with 19 tests; `af validate --root .` passed
  with 202 documents checked; `git diff --check` passed.
- 2026-06-01 contract re-review after fence/sanitizer clarification:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope rules/BAB-2275-CHG-Knowledge-Markdown-Render.md`
  passed with no blocking findings; synthesis at
  `.trinity/reviews/20260601-083711-rules-BAB-2275-CHG-Knowledge-Markdown-Render.md/synthesis.md`.
  A wording advisory changed "newline" to "line ending".
- 2026-06-01 implementation review:
  `trinity review --providers glm,deepseek,minimax --preset fast-review --scope apps/babs_citizens`
  passed with no blocking findings; synthesis at
  `.trinity/reviews/20260601-084208-apps-babs_citizens/synthesis.md`.
  Raw advisory output requested a task-list sanitizer comment, generic
  frontmatter schema guidance, a less spacing-sensitive task-list assertion, and
  safe-HTML passthrough coverage; those were applied and the validation stack was
  rerun.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-06-01 | Initial version | Codex |
