# CLAUDE.md — Babs

Guidance for Claude Code (and other agents) working in the Babs repository.

## Project Identity

**Babs** is a from-scratch Elixir/Phoenix multi-agent runtime: citizens, message relay across Discord/Telegram/Web/tmux, and A2A coordination.

- **CLI**: `bb` (planned)
- **PRJ document prefix**: `BAB`
- **Pairs with**: Alfred (`af`) — same ecosystem, complementary scope. Alfred = per-agent runbook; Babs = multi-agent runtime.
- **Naming**: Babs is Barbara Gordon's Bat-Family nickname. `*.bob/` citizen directories are the "Bobs" Babs takes care of.

## Alfred Workflow (mandatory)

This project uses Alfred's `af` CLI for SOPs, routing, and document management. Run it at the **start of every session and before every task**.

### Session Start

1. Load today's Discussion Tracker per **COR-1201**:
   ```bash
   af list --type ref --prefix BAB --root /Users/frank/Projects/babs | grep "Discussion Tracker.*$(date '+%Y %m %d')"
   ```
   - Found → `af read BAB-<ACID>`, parse Active + Archived, set `next_d = max + 1`
   - Not found → check most recent prior tracker for Deferred items, then `af create ref --prefix BAB --area 30 --title "Discussion Tracker $(date +%Y-%m-%d)" --root /Users/frank/Projects/babs`

2. Run workflow routing:
   ```bash
   af guide --root /Users/frank/Projects/babs
   ```

### Before Every Task

3. Identify which SOPs apply (from the decision tree in `BAB-2100` and COR routing)
4. Generate the checklist:
   ```bash
   af plan <SOP_IDs> --root /Users/frank/Projects/babs
   ```
5. Declare the active SOP per **COR-1402** before starting work; re-declare at every transition
6. Do not commit code without completing review steps
7. At session end, use the plan output as a completion checklist

## Project-Specific Routing

Babs is a greenfield Elixir/Phoenix runtime. Common tasks and their routes:

| Task type | Route |
|-----------|-------|
| Architecture decision (already discussed in conversation) | ADR (COR-1100) → `BAB-11xx` |
| New phase implementation (Phase 0/1/2/3/4) | PRP (COR-1102) → review → CHG → `BAB-22xx` |
| Add a new citizen `.bob` | follow `BAB-1500` |
| PTY stability validation (Phase 0) | follow `BAB-1502` |
| Update existing BAB doc | COR-1300 |
| Bug in running Babs node | INC + CHG (COR-1101) |
| Evolve Babs config/structure | follow `BAB-1801` — uses `BAB-1800` weights |

See **`BAB-2100`** (Workflow Routing PRJ) for the full project decision tree.

## Architecture Reference

The canonical architecture, naming, and decision history live in `rules/`:

- **`BAB-1001`** — Architecture Overview (OTP supervision tree, persistence layering, external boundaries)
- **`BAB-1002`** — Naming & Vocabulary (Babs / `*.bob/` / Citizen / PaneSession / etc.)
- **`BAB-1100`–`BAB-1106`** — ADRs (Elixir choice, name, citizen subtree, PTY, A2A, persistence, LiveView/Channels)

When making changes that touch architecture, **always cross-reference the relevant ADR** before proposing alternatives. Rejected alternatives in those ADRs are not invitations to reopen — they are documented reasons.

## Code (when development starts)

Not yet — repository is pre-development. Phase 0 (PTY stability spike, `BAB-1502`) precedes any production code; subsequent build phases are sequenced in `BAB-2300` per `BAB-1001` §"Build Phases".

When development starts, this section will document:
- Module layout (`Babs.*` namespace)
- Mix project structure
- Test conventions
- Style/formatting rules

## Memory & Persistence

This file is the project-level guide. Per-user memories and broader Claude Code conventions are inherited from `~/.claude/CLAUDE.md`. Babs-specific memories (the project name decision, the `*.bob/` resonance) are in `~/.claude/projects/-Users-frank-Projects-prefrontal-cortex/memory/` for now and may move to a Babs-specific memory namespace once active development begins.
