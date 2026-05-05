# PRP-2208: Phase 2 Transcript JSONL Persistence

**Applies to:** BAB project
**Last updated:** 2026-05-05
**Last reviewed:** 2026-05-05
**Status:** Draft

---

## What Is It?

Phase 2 completes durable transcript persistence for Babs-hosted Citizens.

The Phase 1 flywheel dogfood already landed the first slice: `Hardline.Pane`
opens `<cwd>/transcript.jsonl` and appends JSONL records for browser input and
PTY output bytes. This PRP reconciles that partial implementation with the full
roadmap acceptance: browser tab restart must replay recent transcript context
from disk, not merely show whatever tmux can still capture.

---

## Problem

`BAB-2300` defines Phase 2 as:

- every byte that flows through `Hardline.Pane` is appended to
  `<cwd>/transcript.jsonl`
- browser reload/reopen replays recent transcript context to xterm.js
- tab restart is byte-loss-free

PR #7 delivered the first bullet as part of Phase 1 Gate B:

- `Babs.Citizens.Hardline.Transcript` writes append-only JSONL
- `Babs.Citizens.Hardline.Pane` records `input` and `output` byte records
- transcript writes tolerate hot-reload state from before the transcript field
  existed
- unit tests cover encoding, arbitrary binary payloads, append mode, and Pane
  hot-reload tolerance

The remaining gap is that browser reconnect currently gets context from
`tmux capture-pane` in `BabsWeb.PaneChannel`, not from
`<cwd>/transcript.jsonl`. That is useful but does not satisfy the Phase 2
contract because tmux scrollback is bounded and does not prove byte-loss-free
tab restart.

There is also a vocabulary/ADR alignment issue: `BAB-1105` originally described
AI CLI JSONL transcripts as external truth written by Claude/Codex and read-only
to Babs. Phase 2 introduces a separate Babs-owned Hardline byte transcript. That
is not the same file or same contract; the distinction must be explicit.

## Proposed Solution

Complete Phase 2 as a small hardening phase on top of the landed dogfood slice.

1. Keep the existing Babs-owned transcript path:
   `<citizen cwd>/transcript.jsonl`.
2. Treat the existing byte record shape as accepted for byte records:
   - `ts`
   - `slug`
   - `direction`: `input` or `output`
   - `stream_id`
   - `seq`
   - `b64`
3. Add read-side transcript helpers in `Babs.Citizens.Hardline.Transcript`:
   - parse JSONL records defensively
   - ignore malformed lines rather than crashing terminal reconnect
   - decode only `direction == "output"` for browser replay
   - return the most recent replay payload by decoding output records, splitting
     on `\n`, and keeping the newest 200 lines or fewer if fewer exist
   - tolerate a final partial line if the file is read while the Pane is
     appending; replay is a best-effort UX read, not a transactional boundary
4. Change `BabsWeb.PaneChannel` snapshot behavior:
   - on join, ask the live `Hardline.Pane` for its configured `cwd`; prefer a
     small `Pane.cwd(slug)` call over re-reading TOML on every browser reconnect
   - replay transcript output bytes first when available
   - keep `tmux capture-pane` as a best-effort fallback when transcript is
     missing or empty
5. Add lifecycle event records for reattach boundaries if this can be done
   without widening the JSONL contract too much:
   - at minimum, record a regular `direction == "output"` JSONL record whose
     payload is a textual marker such as `[babs hardline reattached]`
   - do not introduce a full event schema unless the implementation needs it
6. Update docs so Phase 2 clearly distinguishes:
   - **Babs Hardline transcript**: Babs-owned append-only byte log at
     `<cwd>/transcript.jsonl`
   - **AI CLI transcript**: upstream Claude/Codex JSONL files, read-only to
     Babs, still a later `TranscriptTailer` concern

## Acceptance

Phase 2 is complete when:

- `Hardline.Pane` continues to append every accepted browser input byte and PTY
  output byte to `<cwd>/transcript.jsonl`.
- Closing a browser tab, producing output while the tab is closed, and reopening
  `/citizens/<slug>` replays the recent output from `transcript.jsonl`.
- Replayed browser context is sourced from transcript JSONL, with tmux
  `capture-pane` only as fallback.
- The replay cap is deterministic and documented: replay decodes output records,
  splits on `\n`, and returns the most recent 200 output lines, or fewer if the
  transcript contains fewer.
- Malformed transcript lines do not crash reconnect.
- "Byte-loss-free tab restart" means bytes produced while the tab is closed are
  appended to the transcript and the newest 200 output lines are replayed on
  reconnect. It does not mean old output beyond the replay cap is re-rendered.
- Existing Phase 1 Gate A still passes.
- Existing Phase 1a test tiers still pass.

## Tests

Expected test additions:

- Unit tests for transcript read/replay helpers:
  - output-only replay ignores input records
  - arbitrary binary output round-trips from `b64`
  - malformed JSONL lines are skipped or reported without crashing
  - replay caps to the newest 200 lines
  - empty/missing transcript returns no replay payload
- Channel tests for snapshot source order:
  - transcript replay is pushed when available
  - tmux capture fallback remains best-effort when transcript is absent
- Browser-harness BDD:
  - sentinel connects
  - browser tab closes
  - the test appends a deterministic output record directly to sentinel's
    transcript while the tab is closed, avoiding sleep/timing flake
  - browser reopens `/citizens/sentinel`
  - marker appears from transcript replay
- Existing validation stack:
  - `mise exec -- mix format --check-formatted`
  - `mise exec -- mix compile --warnings-as-errors`
  - `mise exec -- mix test`
  - `mise exec -- mix test --cover`
  - `npm run test:js`
  - `npm run test:bdd`
  - `npm run test:e2e`
  - `mise exec -- mix babs.gate_a`
  - `af validate --root <repo>`

## Out Of Scope

- SQLite-backed citizens table; Phase 3 owns that.
- `/citizens/new`; Phase 4 owns that.
- Multi-citizen index, tabs, stop/start/restart UI; Phases 5-6 own those.
- Ticket/billboard automation.
- Parsing upstream Claude/Codex JSONL into semantic messages. Phase 2 only
  persists and replays Babs terminal byte transcripts.

## Open Questions

- Should replay include only PTY output bytes? Proposed answer: yes. Browser
  input is persisted for audit, but terminal replay should render only output
  because output is the terminal's actual display stream.
- Should lifecycle reattach be a structured JSONL event? Proposed answer: not
  yet. Use a textual output marker in Phase 2 if needed; reserve structured
  event schemas for Phase 7+ ticket/history work unless implementation pressure
  proves otherwise.
- Should replay trim by records or lines? Proposed answer: lines. The roadmap
  says "last 200 lines"; implement a line cap over decoded output bytes, while
  preserving raw terminal bytes inside those lines as much as possible.
- Does `{:delayed_write, 4096, 50}` weaken "byte-loss-free"? Proposed answer:
  not for the Phase 2 tab-restart contract. A hard BEAM crash could lose or
  delay the last few milliseconds of buffered writes; Phase 2 only claims
  browser tab restart while the Pane continues running.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-05 | Initial reconciliation PRP: record Phase 1 dogfood slice, identify remaining transcript replay gap, and define Phase 2 completion criteria | Codex |
| 2026-05-05 | Trinity fast-review PASS follow-up: make 200-line replay deterministic, prefer `Pane.cwd/1`, require reattach markers as normal output records, make BDD replay deterministic, and clarify byte-loss-free scope | Codex |
