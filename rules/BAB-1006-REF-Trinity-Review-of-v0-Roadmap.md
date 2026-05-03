# REF-1006: Trinity Review of v0 Roadmap

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Active
**Role:** Historical review archive
**Reviewers:** Codex (GPT-5.5) / Gemini 3 / DeepSeek V4

---

## What Is It?

Archive of the multi-model review conducted on 2026-05-03 against the proposed v0.1 16-phase roadmap (Bootstrap → Flywheel design). Three independent LLM reviewers (Codex / Gemini / DeepSeek) reviewed the design brief and answered six load-bearing questions about decomposition, scope, the `:babs_citizens` separation choice, estimate realism, hidden risks, and bootstrap viability. This document preserves the convergent findings, divergence points, and resulting design changes.

The original review brief lived at `REVIEW-PENDING-v0-roadmap.md` (deleted after this archive was written). The decisions and roadmap changes derived from the review are codified in `BAB-1110` (β + γ live-reload-safety), `BAB-2201` (Phase 1 SEED PRP), and `BAB-2300` (revised master roadmap).

---

## The Three Reviewers

| Reviewer | Model | Style |
|----------|-------|-------|
| Codex | GPT-5.5 | Pragmatic, conditional acceptance, surfaces operational edge cases |
| Gemini | Gemini 3 | Strong opinions, willing to flatly reject design choices, sees catastrophic failure modes |
| DeepSeek | DeepSeek V4 | Engineering-detail focused, names specific protocol bugs (e.g. Channel PID staleness) |

---

## Convergent Findings (3/3 agreement)

### 1. Missing Phase 6.5: Manual Ticket Dogfood

All three reviewers independently flagged the jump from Phase 6 (V0-S complete: multi-citizen runtime working) to Phase 7 (build ticket file infrastructure) as missing a validation step. **Build ticket infrastructure only after manually validating the billboard concept end-to-end** — write a ticket file by hand, manually assign it to a citizen, watch the workflow, then build infrastructure for what you observed.

**Adopted**: Phase 6.5 inserted into `BAB-2300`. ~1-2 days. Manual end-to-end test before automated tooling.

### 2. Phase 1 Estimate Optimistic (3/3)

7-10 days estimate for Phase 1 SEED ignores: full xterm.js ANSI coverage, complete keyboard fidelity (Ctrl+C edge cases alone burn days), two-OTP-app structure setup, multi-CLI credential plumbing, live-reload-safe Channel re-registration. Realistic: 14-21 days (2× multiplier).

**Adopted**: Phase 1 estimate revised to 14-21 days in `BAB-2201` and `BAB-2300`.

### 3. Flywheel Timeline (Phases 2-16) is Best-Case Fantasy (3/3)

The 16-week flywheel estimate ignores AI failure cycles, hallucination rework, context window exhaustion, recursive debugging spirals (citizen debugging the runtime it's running inside). Apply 2-3× multiplier.

**Adopted**: `BAB-2300` shows both "optimistic" and "realistic" timeline columns. Realistic ~36 weeks total.

### 4. Phase 2 Has a Real Chicken-and-Egg (3/3)

When a citizen modifies `Hardline.Pane` (in `:babs_citizens`) to add transcript persistence, recompiling and restarting `:babs_citizens` will kill the citizen executing the upgrade. This is a single-point failure of the flywheel concept. The fix is **tmux session detached + reattach on BEAM restart** (option γ semantics), not just OTP-app separation (option β alone).

**Adopted**: `BAB-1110` records the decision to use β + γ together (independent OTP apps + tmux detach). `BAB-2200` Phase 0 spike must validate the detach + reattach scenario.

### 5. Phase 1 Missing Credential Injection (2/3)

`citizen.toml` config schema needs an `env` map to inject API keys (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.) into the erlexec child process. Without it, AI CLIs can't authenticate and the flywheel test cannot run.

**Adopted**: Required in `BAB-2201` and `BAB-1112`.

### 6. Ticket File Concurrency Risk (2/3)

Two citizens writing to the same ticket file simultaneously will produce torn writes. Filesystem-as-database needs explicit serialization (single-writer GenServer per ticket) or strict append-only history.

**Adopted**: `BAB-1111` mandates serialized writes via per-ticket GenServer.

### 7. Phase 1 Must Include Restart/Reconnect Path (3/3)

Browser reconnect, Channel re-registration, tmux re-attach must all work in Phase 1. Otherwise the flywheel test (PASS = task completed in browser only) is impossible.

**Adopted**: Required in `BAB-2201`. Phase 0 spike must validate detach/reattach.

---

## Divergence: β vs γ Live-Reload-Safety

The user pre-selected **β** (independent OTP applications). Reviewers split:

| Reviewer | Verdict on β |
|----------|--------------|
| Codex | β correct default for Phoenix reload, but Phase 1 must also include γ-style tmux detach. "If `Hardline.Pane` dies and takes the execution context with it, the flywheel test is fake." |
| Gemini | **β fatally flawed** for self-modifying agents. Strong recommendation: switch to γ alone (tmux as the durable boundary). |
| DeepSeek | β correct for v0.1; γ is a layered enhancement that fits naturally into Phase 3's auto-respawn work. |

**Synthesis (and decision)**: β and γ are not mutually exclusive — β operates at the OTP supervision level, γ at the OS process level. The chicken-and-egg in Phase 2 is genuinely a problem that β alone cannot solve, because reloading `:babs_citizens` does kill its supervised processes including the modifying citizen. Adopting γ-style tmux detach + reattach as a sub-strategy of β resolves the problem.

**Adopted**: **β + γ together**. Recorded in `BAB-1110`. Phase 0 must validate detach + reattach (`BAB-2200`).

---

## Other Notable Findings

- **Codex**: keyboard fidelity in Phase 1 should be narrowed to essential keys (printable / Enter / Tab / Ctrl+C/D/Z / arrows / paste); full fn/cmd combo deferred. Adopted in `BAB-2201`.
- **Gemini**: drop multi-CLI from Phase 1, hardcode `claude`. **Not adopted** — multi-CLI is a v0.1 differentiator and `citizen.toml` parsing is cheap.
- **DeepSeek**: explicit Phase 0 test for "erlexec detach + re-attach to same tmux session without session loss". Adopted in `BAB-2200`.
- **DeepSeek**: Channel PID staleness on `:babs` reload — `PaneSession` must detect dead Channel PID and re-register on browser reconnect. Adopted in `BAB-1106` revision and `BAB-2201`.
- **Gemini**: BEAM scheduler blocking on byte storms (PTY back-pressure) — flagged for `BAB-1106` revision.

---

## Lessons for Future Reviews

1. **Multi-model review surfaces protocol-level bugs that single-reviewer review misses** — DeepSeek's Channel PID staleness call-out was specific enough to add directly to acceptance criteria.
2. **Disagreement is signal, not noise** — Gemini's β rejection forced a clearer rationale and surfaced that β + γ together is the actual correct answer (which no single reviewer named directly).
3. **Estimates always come back ×2-3** — three independent reviewers all flagged this. Future PRPs should bake the multiplier in upfront rather than discover it at review time.

---

## Second-Round Review (Post-Integration, 2026-05-03)

A second trinity review was run AFTER all first-round changes were integrated, this time against the **actual landed documents** (not the design brief). All three reviewers verified faithful integration AND surfaced new issues introduced during integration.

### Convergent findings (3/3 reviewers)

1. **`BAB-1106` body still describes superseded design** — banner says "use PubSub, no PIDs" but body still describes Channel storing PaneSession PID + bypassing PubSub. Risk: implementer follows body. **Fixed**: added 🛑 STALE BODY WARNING section + corrected layer-3 description in "What Is It?"
2. **`bb` CLI completely undefined** — referenced everywhere, specified nowhere. **Fixed**: added explicit Transport Specification to `BAB-1111` (Elixir escript, UDS at `/tmp/babs-<uid>.sock`, JSON, mode-0700 auth, gated to Phase 7 implementation).
3. **`BAB-1107` lifecycle table missing `babs-` prefix** — `tmux new-session -d -s <name>` should be `babs-<name>`. **Fixed**.

### Significant findings (2/3 reviewers)

4. **`:babs_citizens` reload mechanism contradiction** — BAB-1110 says "live_reload watches only `apps/babs/lib/**`"; BAB-2201 Flywheel Test requires editing `apps/babs_citizens/...`. **Fixed**: added "Reload Mechanism" section to BAB-1110 specifying `Babs.Citizens.SourceWatcher` (custom FileSystem watcher → `Application.stop`/`start`).
5. **`BAB-2201` implementation plan non-sequential** — Day 3-4 Lifecycle reads citizen.toml but TOML parser is Day 11-14; SQLite referenced before Phase 3. **Fixed**: reordered plan; TOML parser now Day 2-3, Lifecycle Day 4-5, Phase 1 reads citizen.toml only (no SQLite).
6. **PubSub chunk size unspecified** — TUI redraws can produce KB-scale messages, blocking BEAM schedulers. **Fixed**: explicit ≤4 KB chunk limit added to `BAB-1106` warning section.
7. **Seed count inconsistency** — BAB-2300 said "ONE Citizen seed"; BAB-2201 needs alex+morgan to validate multi-CLI. **Fixed**: BAB-2300 updated to "two seed Citizens".
8. **Singular `assignee` vs multi-assignee Phase 12** — schema mismatch. **Fixed**: `assignee: alex` → `assignees: [alex]` (list, forward-compatible).

### Protocol-level findings (1/3, DeepSeek)

9. **ReattachScanner ↔ DynamicSupervisor race** — concurrent spawn during boot scan could double-spawn Hardline.Pane. **Fixed**: BAB-2201 Day 5-6 explicitly requires "ReattachScanner must complete before DynamicSupervisor accepts spawns".
10. **`Babs.Ticket.Writer` OTP app unspecified** — should be `:babs_citizens` (filesystem-only, no web dep). **Fixed**: explicitly stated in BAB-1111.

### Approved without change

- **β + γ resolution** — Gemini (who initially flagged β as fatally flawed) confirmed β + γ together correctly resolves the chicken-and-egg. The synthesis works.
- **Phase 6.5 insertion** — all three reviewers re-confirmed.
- **Phase 1 estimate (14-21 days)** — all three reviewers re-confirmed realism.
- **Filesystem-first ticket design** — all three reviewers approved.

### Deferred to post-Phase-1

- Full body rewrite of `BAB-1102` and `BAB-1106` — banners + warnings suffice for now; Citizens themselves will rewrite.
- Phase 0 → Phase 1 handoff artifacts list (erlexec flags, tmux command shape, byte contract) — recommended by Codex; will be captured in `BAB-2200` `SUMMARY.md` produced by the spike itself.
- `babs-<name>` → citizen-name derivation rule explicitly documented — implicitly "strip `babs-` prefix"; safe to leave for code-level documentation.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial archive of trinity review and resulting design changes | Claude Code |
| 2026-05-03 | Second-round (post-integration) review added; 8 fixes applied across BAB-1106/1107/1110/1111/2201/2300; remaining 4 nice-to-have findings deferred to post-Phase-1 | Claude Code |
| 2026-05-03 | Normalize Status metadata to `Active`; preserve historical-record role in a dedicated metadata field | Codex |
