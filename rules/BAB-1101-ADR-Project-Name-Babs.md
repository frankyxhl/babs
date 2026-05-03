# ADR-1101: Project Name "Babs"

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Accepted

---

## What Is It?

The project is named **Babs**, with CLI `bb`, PRJ document prefix `BAB`. This ADR records why and what was rejected.

---

## Context

The project is being created alongside **Alfred** (`af`) — a personal SOP/runbook CLI named after Bruce Wayne's butler from DC Comics. Alfred's naming follows a clear convention:

1. Real (fictional/historical) character whose canonical role mirrors the tool's function
2. Two-letter CLI shortcut
3. Optional backronym subtitle ("Agent Runbook")
4. Dignified, English-flavored, "senior assistant" archetype

This project's job is **multi-agent communications and coordination**: hosting many citizens (`*.bob/`), relaying messages across Discord/Telegram/Web/tmux, coordinating agent-to-agent (A2A) protocols. This is functionally distinct from Alfred (which is per-agent SOPs).

A name was needed that:
- Pairs with Alfred (same family, complementary scope)
- Reflects the *coordination of many* (not the *guidance of one*)
- Has a clean two-letter CLI
- Has no trademark or strong-brand collision
- Resonates with the `*.bob/` citizen directory convention

---

## Decision

**Babs.** Barbara Gordon's canonical Bat-Family nickname.

- **CLI:** `bb`
- **PRJ document prefix:** `BAB`
- **Module namespace:** `Babs.*` (and `BabsWeb.*` for the Phoenix endpoint)
- **No mandatory backronym.** The name stands on the character reference; like Alfred, the "Agent Runbook" subtitle is descriptive, not prescriptive.

**Why Babs specifically:**

1. **Role match.** Barbara Gordon, in her Oracle persona, operates from the Clocktower as the Bat-Family's communications and intelligence hub. She coordinates Batgirl, Black Canary, Huntress, et al. — many agents, one coordinator. That is precisely Babs-the-project's role.
2. **Family relationship with Alfred.** Both are Bat-Family support figures: Alfred is the personal runbook for Bruce; Babs is the comm hub for the team. Alfred and Babs reading together = the full operational stack.
3. **Phonetic resonance with `*.bob/`.** Citizens live in `<name>.bob/` directories. "Babs takes care of the Bobs" — the architecture is encoded in the name.
4. **Trademark-clean.** "Babs" is a common nickname (not a registered trademark for software), unlike "Oracle" (Oracle Corp.).
5. **CLI clean.** `bb` has no common shell collision (unlike `or`, which collides with shell `||` patterns; `gd`, which collides with `gdb`; `jv`, with Java).

---

## Consequences

**Positive:**
- The Alfred + Babs pairing tells a coherent story without explanation
- The `*.bob/` pun gives the architecture a memorable shape
- No trademark exposure
- Two-letter CLI is fast to type

**Negative:**
- "Babs" sounds informal next to "Alfred" — some users may read it as a less-serious tool. We accept this; the substance is the same.
- DC Comics canon is not universally known — non-comic-readers may not recognize the reference. We accept this; the name still functions as just a name.

**Neutral:**
- Future tools in this family should continue the Bat-Family / English-butler-and-staff naming convention if they're operationally adjacent (e.g., a hypothetical "Lucius" for tooling/infrastructure provisioning, named after Lucius Fox).

---

## Rejected Alternatives

### Oracle (`or`)

Barbara Gordon's actual codename. Most direct functional fit.

**Rejected because:**
- Oracle Corp. trademark — for an open-source project this is mostly cosmetic, but it creates ambiguity in package names, logos, and search engines
- `or` collides with shell control-flow `||` patterns, making CLI scripting awkward

### Pennyworth (`pw`)

Alfred's surname; explicitly "Alfred-extended."

**Rejected because:**
- Long; doesn't read as memorable as a single first-name
- Doesn't introduce a *new character* with a *different role*; the architecture has two distinct functions (per-agent runbook vs. multi-agent coordination), and the name should reflect that

### Lucius (`lc` / `lx`)

Lucius Fox, Wayne Enterprises CTO; provides Batman's gear and infrastructure.

**Rejected because:**
- The "infrastructure provider" framing fits a *future* tooling project better than Babs (which is the runtime, not the infrastructure layer)
- Reserved as a possible future name in this family

### Jeeves (`jv`)

P. G. Wodehouse's archetypal English valet; Ask Jeeves search engine connotation.

**Rejected because:**
- Outside the Bat-Family universe; breaks the family naming pattern with Alfred
- `jv` collides with Java in tool ecosystems

### Moneypenny (`mp`)

Bond's secretary; gateway to M; literal relay role.

**Rejected because:**
- Long, multi-syllable, harder to type
- Bond universe is a different family from Alfred; would split the naming line

### Clocktower (`ct`)

Babs's base of operations rather than her name.

**Rejected because:**
- Strong functional metaphor (broadcast tower, time, coordination), but it's the *place*, not the *agent*. Naming after the agent (Babs) keeps the Alfred-style "named character" pattern intact. Considered as a possible component name within Babs (e.g., a future scheduler module), not the project name.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial version — name decided after evaluating Oracle, Pennyworth, Lucius, Jeeves, Moneypenny, Clocktower | Claude Code |
| 2026-05-03 | Reframe Context: project is created (not renamed); drop "existing" qualifier on `.bob/` | Claude Code |
