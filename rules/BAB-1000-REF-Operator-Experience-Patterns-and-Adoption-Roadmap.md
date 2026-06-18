# REF-1000: Operator Experience Patterns and Adoption Roadmap

**Applies to:** BAB project
**Last updated:** 2026-06-19
**Last reviewed:** 2026-06-19
**Status:** Active
**Related:** BAB-1001 (Architecture), BAB-1002 (Naming), BAB-2271 (Operator Dashboard Panels), BAB-2278 (Dogfood Program)

---

## What Is It?

A catalogue of **operator-experience patterns** for a multi-agent runtime, plus a
phased roadmap for adopting them in Babs. The patterns are synthesised from prior
art in a mature multi-agent operator workspace studied in 2026-06; the source's
specifics (its name, internals, and file layout) are intentionally abstracted —
this document captures only the *transferable design principles*, restated in
Babs's own vocabulary (Citizen / Ticket / Hardline / Mayor / Inspector).

It exists because early dogfood use (BAB-2278) surfaced that Babs's operator
surface feels awkward. This document names *why*, catalogues proven remedies, and
sequences them so each can later graduate into its own PRP/CHG under the
BAB-1503 phase-delivery loop.

**Scope note:** This is a reference + roadmap, not an implementation mandate.
Per BAB-2278, no new feature work happens during the dogfood window
(→ 2026-06-27). This roadmap is the candidate batch for the **post-dogfood PRP
cycle**, to be re-prioritised by the friction log at the 2026-06-27 review.

**Design stance: adapt, don't clone.** This document captures the *problems
solved* and the *information-architecture principles*, never a UI to copy. Every
pattern below is a problem statement plus a Babs mapping — the concrete widgets,
layout, and interaction are Babs's own design work. In particular, Babs's
**terminal-first identity is a genuine differentiator, not just a deficiency to
paper over**: the live Hardline (you see exactly what a Citizen does and can drop
in) is a feature. The likely Babs synthesis is therefore *not* "hide the terminal
behind a chat clone" but "keep the terminal first-class and build a scannable
fleet view, readable handoff state, and a composer-style input around it." Where
Babs's substrate or thesis is stronger (OTP/Channels; terminal-centric Hardline),
it should diverge deliberately rather than converge on the reference.

---

## Content

### 1. The core insight: chat-first vs terminal-first

The single highest-leverage observation: a mature multi-agent workspace presents
a **chat-first** operator surface, whereas Babs today is **terminal-first**.

| Dimension | Chat-first reference | Babs today |
|---|---|---|
| Primary surface | Fleet sidebar + message thread + composer | One raw terminal (xterm) per Citizen |
| How the operator drives a Citizen | Types into a composer (slash-commands, mentions, attachments) | Types keystrokes into the raw PTY pane |
| Citizen output | Transcript rendered as message bubbles (markdown, images) | Raw PTY byte stream |
| Terminal's role | An *optional secondary pane*, collapsed by default | The *only* surface |
| Fleet awareness | Sidebar lists every Citizen with status at a glance | Hunt across per-Citizen terminal pages |

The awkwardness is not a rendering bug — xterm-in-browser is a fine *mechanism*.
It is an **information-architecture** gap: the terminal is the whole product
instead of one pane within a coordination surface.

Crucially, **Babs already owns the pieces** to become chat-first: it captures
JSONL transcripts (reply capture) and models work as Tickets. The work is to
render a conversation view from the transcript and demote the terminal — not to
rebuild the runtime.

### 2. Pattern catalogue

Each pattern: what it is, the operator problem it solves, and how it maps onto
Babs. Patterns are grouped by concern.

#### A. Operator surface

| Pattern | Problem it solves | Babs mapping |
|---|---|---|
| **Conversation view from transcript** | Raw byte streams are unreadable; operators want a chat history | Render the captured JSONL transcript as a message thread on the Citizen page; keep Hardline/terminal as a secondary pane |
| **Composer, not raw keystrokes** | Typing into a live PTY is fragile and modal | A message composer that injects into the Citizen via the existing inject path; supports quick presets |
| **Fleet sidebar with status badges** | No at-a-glance fleet view; must visit each terminal | A persistent Citizen list with a state badge per row (idle / working / question / review / done / error / stuck) |
| **Attention-only glyphs** | Important "needs you" signals get lost in scrollback | Show a glyph on a sidebar row *only* when it needs action (e.g. uncommitted work, unverified result); render nothing for the safe case so the list stays scannable |
| **Cross-Ticket review inbox** | Operators (esp. on mobile) need to bookmark items to revisit | A saved/forward surface that collects messages across Citizens for asynchronous review |

#### B. Handoff and shipping verification

| Pattern | Problem it solves | Babs mapping |
|---|---|---|
| **State-marker handoff trailer** | "Done" is asserted, not checkable; operator can't tell commit/verify/ship state | Citizens end a turn with a structured trailer — `[Commit: yes/no/no-need]`, `[Verified: yes/no/no-need]`, `[Shipped: yes/no/no-need]` — parsed into Ticket state + sidebar glyphs |
| **Prove-it's-live check** | A Ticket marked done may be stuck unmerged / not deployed | A small verifier that *checks* whether the change actually reached its canonical destination (e.g. merged to the target branch), rather than trusting the claim |
| **Honest "is it live?" framing** | Operators conflate "agent finished" with "it's in production" | Separate the three checkpoints in the UI: committed → approved → shipped; never collapse them |

This group maps almost 1:1 onto Babs's `pending_approval` → operator-merges-PR
flow, and directly answers a dogfood question: *did the Citizen's work actually
land?*

#### C. Isolation and Citizen operating protocol

| Pattern | Problem it solves | Babs mapping |
|---|---|---|
| **Worktree-per-task, fail-loud** | Multiple agents (and the operator) colliding on one working checkout | Each Ticket's work runs in a dedicated git worktree; if it can't be provisioned, fail loudly — never silently fall back to the shared checkout |
| **"Ask via message, never an interactive prompt"** | An interactive prompt renders only in the agent's terminal pane, which the dashboard operator never sees — so it hangs until timeout | Citizen protocol forbids interactive prompts as a question channel; questions must come back as a Ticket message the operator can see |
| **A Citizen operating-protocol document** | Implicit norms drift per Citizen | A short, injected protocol: own your domain, default to fixing over investigating, commit + surface work, branch + PR only (never to protected main) |

Two of these independently confirm decisions already on Babs's table: worktree
isolation was already flagged as dogfood friction (BAB-2278), and the
interactive-prompt-invisibility problem is a direct consequence of Babs's
terminal-first surface.

#### D. Data and runtime patterns worth borrowing

| Pattern | Problem it solves | Babs mapping |
|---|---|---|
| **Indexed transcript message store** | JSONL on disk isn't queryable for a chat view, pagination, or retention | Ingest captured transcripts into a queryable store (classification, pagination, retention) — the foundation the conversation view reads from |
| **Crash-safe ingestion offsets** | A restarted ingester re-reads or loses lines | Persist per-transcript read offsets; resume from checkpoint; idempotent inserts |
| **Lifecycle GC sweeper** | Stale sessions / worktrees accumulate | A periodic sweeper that reaps ended runtimes and merged worktrees on a config-driven cadence |
| **Config-driven cadence** | Changing a schedule requires a restart | Read interval/TTL settings at the start of each loop iteration, not at boot |

#### E. Looping / automation patterns (future)

Lower priority; recorded so they are not lost. A per-task loop state machine
(observe → analyse → human-confirm → act), periodic monitors that surface
structured findings, a "rate the agent's question" signal, and a progress view
showing goal evolution. These fit Babs's Mayor/Inspector model but are a later
milestone, not part of the first adoption batch.

### 3. Where Babs is already ahead (do NOT copy)

Honesty matters for prioritisation. The reference achieves resilience with
several OS-supervised daemons and a polling event-push channel. Babs's **OTP
supervision tree** and **Phoenix Channels / PubSub** are a *stronger* substrate
for the same goals (automatic restart, real-time push, stateful-connection
management are built in). Babs should borrow the reference's **information
architecture, data patterns, and Citizen protocol** — not its process model.
Replicating a multi-daemon split on top of the BEAM would be a regression.

### 4. Adoption roadmap

Sequenced by leverage and dependency. Each phase graduates into its own PRP/CHG
when work starts (BAB-1503). Phases are independently shippable except where a
dependency is noted. **None of this starts before the 2026-06-27 dogfood review**
— the friction log re-prioritises this list first.

| Phase | Theme | Why this order | Graduates to |
|---|---|---|---|
| **P1 — Transcript store** | Indexed message store + crash-safe ingestion (Pattern D) | Foundation the conversation view needs; invisible-but-enabling | PRP + CHG |
| **P2 — Chat-first surface** | Conversation view + composer + fleet sidebar + attention glyphs (Pattern A); terminal demoted to secondary pane | The direct fix for "feels awkward"; depends on P1 | PRP + CHG batch (mirror BAB-2271 slice style) |
| **P3 — Handoff + shipping proof** | State-marker trailer → Ticket state + glyphs; prove-it's-live verifier (Pattern B) | Independently shippable; high dogfood value ("did it land?"); low UI risk | PRP + CHG |
| **P4 — Isolation + protocol** | Worktree-per-Ticket fail-loud; Citizen operating-protocol doc; ask-via-message rule (Pattern C) | Safety hardening for autonomous work on real repos | PRP + CHG |
| **P5 — Automation loops** | Per-task loop state, monitors, question-rating, progress view (Pattern E) | Advanced; only after the surface and protocol are solid | Separate roadmap |

Recommended entry points after the review:
- If the goal is **"make it pleasant"** → P1 → P2.
- If the goal is **"trust the dogfood loop"** → P3 and P4 first (both independent of P1/P2).

### 5. Open questions for the 2026-06-27 review

- Does the conversation view **replace** the terminal as default, or sit beside
  it as a toggle? (Reference demotes the terminal; Babs may keep parity longer
  given its terminal-centric Hardline model.)
- Is P3's state-marker trailer authored by the Citizen (protocol) or derived by
  Babs from git/PR state (observation)? A hybrid is likely.
- Which patterns does the friction log actually rank highest — this roadmap is a
  hypothesis, not a commitment.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-06-19 | Initial version — anonymised operator-experience pattern catalogue + phased adoption roadmap, synthesised from external prior art (source abstracted) | Claude Code |
