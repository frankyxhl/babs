# REF-1005: Naming History — `hardline` (PTY Bridge / Phase 0 Spike)

**Applies to:** BAB project
**Last updated:** 2026-05-03
**Last reviewed:** 2026-05-03
**Status:** Active
**Related:** `BAB-1002` (Naming & Vocabulary, authoritative current names), `BAB-2200` (Phase 0 PRP), `BAB-1103` (PTY ADR), `BAB-1106` (LiveView/Channels/PTY ADR)

---

## What Is It?

A one-shot retrospective of how the Phase 0 PTY-bridge spike got the name **`hardline`**. The decision itself lives in `BAB-2200` and `BAB-1002`; this document preserves the exploration that surrounded it — six namespaces of candidate names, the reasons each was considered, and the decision path that ended at `hardline`.

This is a **回味文** (lore document), not a spec. It does not bind future code. Its purpose is to make the naming taste of the project legible: future contributors reading this should walk away with a feel for what kinds of names belong in Babs and which don't, more than with a literal rule.

If a future module needs the same kind of exploration (Manager, Router, BusView, BabsWeb LiveViews, future connectors), open a new `BAB-XXXX` Naming History sibling — one per major naming event — rather than appending here.

---

## Final Decision

**Name:** `hardline`

**Path:** `/Users/frank/Projects/babs/spikes/hardline/`

**Mix app:** `:hardline`

**Future production module namespace** (if the spike succeeds): `Babs.Hardline.*` — e.g. `Babs.Hardline.Pane`, `Babs.Hardline.dial/1`, `Babs.Hardline.hangup/1`.

**Origin:** *The Matrix* (1999). The "hardline phones" are the wired landlines used to enter and exit the Matrix — a Nebuchadnezzar operator (Tank, later Link) watches monitors and pulls a person out when they reach a hardline; the same line is how they enter. It is the canonical bidirectional cross-world conduit, and the rules around it (must be wired, must have an operator listening, severance = death) are unusually disciplined for a film device.

---

## What Was Being Named

The boundary between two worlds:

- **One side**: Babs, a BEAM process supervising N citizens
- **Other side**: a `tmux` pane running an interactive AI CLI (`claude`, `codex`, etc.) under a PTY

The module's responsibilities (from `BAB-1001`/`BAB-1103`/`BAB-1106`):

| Direction | What it does |
|-----------|--------------|
| Babs → tmux | Create/destroy tmux sessions; spawn the AI CLI; inject bytes into the pane (A2A-routed messages, user input from BabsWeb) |
| tmux → Babs | Tail every byte the CLI writes; fan out to (a) Phoenix Channel → xterm.js, (b) TranscriptTailer → SQLite/JSONL, (c) parser → A2A Router |
| Lifecycle | PTY crash recovery; clean fd reclamation; multi-citizen isolation; cross-OS (macOS/Linux) parity |

It is **not**: the citizen itself, the supervision tree, the A2A router, or the persistence layer. It is the I/O gateway between BEAM and a single tmux pane — one instance per citizen.

---

## Exploration Log

The exploration spanned six namespaces and roughly one conversation. Each section lists the candidates that were on the table and why they were not picked.

### 1. Functional / descriptive (first attempt)

The earliest candidates were straightforward English describing what the code does. They were rejected as "too dry" once the conversation moved toward poetic naming.

| Candidate | Note |
|-----------|------|
| `tmux_bridge` | Strong functional fit — bridge = the right metaphor; later resurfaced as the conceptual anchor when other namespaces were evaluated |
| `pane_io` | Accurate but flavorless |
| `pane_session` | Conflicts with the existing `PaneSession` GenServer concept in `BAB-1106` (different layer) |
| `tmux_runtime` | Too broad — sounds like the whole project |
| `citizen_io` | Too broad — citizens are more than their PTY |
| `pty_gateway` | Functional, but PTY is the OS mechanism while tmux is the proximate object — name should sit closer to the object |
| `pane_driver` | Solid functional fit ("driver" = controls an external resource); kept as runner-up in this category |

### 2. Spike-flavored (rejected by user — "assume PTY will work")

When the spike framing was strongest, candidates carried verification semantics. The user explicitly rejected this direction with the instruction *"we assume PTY will work"* — meaning: name the module for what it permanently is, not for the temporary verification step.

| Candidate | Note |
|-----------|------|
| `pty_stability` | "Stability" is a property we care about, not what the code does — adjective masquerading as noun |
| `tmux_pty_probe` | "probe" = good spike semantics; rejected once the spike framing was dropped |
| `erlexec_pty_trial` | Hard-codes the technology choice; awkward if the fallback path replaces erlexec |
| `pty_driver` | Functional but flat |
| `tmux_pane_io` | Functional but flat |
| `tty_bridge_spike` | "spike" suffix redundant with the parent `spikes/` directory |

### 3. Greek mythology

User asked for "古希腊里诗意点的名字" (something poetically Greek). The category fit the "messenger between worlds" frame.

| Candidate | Note |
|-----------|------|
| **Hermes** | The textbook-perfect messenger — but already used by Hermes JS engine, AWS Hermes, and many other projects; would collide on every search |
| **Iris** | Female counterpart to Hermes; rainbow goddess; appears more in *The Iliad*; rare collisions; **strong runner-up** in this category |
| Charon | Ferries souls across the Styx — bidirectional, but death-coded; wrong tone for an always-running runtime |
| Stentor | Herald with the voice of fifty men — accurate (high-volume byte streams) but obscure |
| Echo | Forced to repeat others — semantically one-way; wrong |
| Argus | The hundred-eyed watcher — read-biased; would imply observation more than I/O |
| Thoth | Egyptian god of writing/messengers — already heavily claimed |
| Caduceus | Hermes's twin-snake staff — bidirectional symbolism (two snakes), object name (good — fewer collisions than person names), but spelling is brutal in English-medium code |

**Why no Greek name won:** the Greek pantheon and the Bat-Family are two different worlds. Mixing them would dilute the project's voice. Babs is already a Bat-Family name; the runtime should stay in that universe (or one adjacent to it).

### 4. Bat-Family / DC

User pivoted to "蝙蝠侠电影里找人物或者物品的名字" (Batman characters or artifacts).

| Candidate | Note |
|-----------|------|
| **Oracle** | Babs's *own* DC alter ego — the comms hub Barbara Gordon becomes after *The Killing Joke* — would have been narratively perfect, but Oracle is a heavy DB/Java/ML namespace and would drown searches |
| **Commlink** | Bat-Family wearable two-way radio; one per hero, all routing back to Oracle in the Clocktower — **strong fit**, became the recommendation in this round; lost later only because Matrix produced something more precise |
| Bat-Signal | Iconic but one-way (Gordon → Batman) |
| Clocktower | Oracle's HQ — but that's the whole project, not a sub-module |
| Wayne Enterprises | Too broad |
| Batcomputer | The Babs-level equivalent, not the bridge |
| Grappling Hook | Reaches across distance, but the metaphor is "pull yourself in," not "talk back and forth" |
| Tightrope | The cable from the grapple — too thin a metaphor |
| **Earpiece** | The seed that opened the next namespace |

### 5. Earpiece / two-way intercom (user-suggested seed)

Earpiece itself was small but the user found the metaphor — "贴在耳边的小设备，双向、随身、每人一个，所有 channel 汇回一个中枢" — productive. We expanded it.

| Candidate | Note |
|-----------|------|
| earpiece | Charming, but technical-feel low |
| headset | Office/VR collision |
| commlink | Re-surfaced from the Bat-Family round |
| handset | Old-fashioned; phone-coded |
| **intercom** | **Strong fit** — "inter-" matches Babs's between-citizen role; many-to-many; building-internal communication; became the recommended name in this round |
| walkie / walkie_talkie | Casual, fun, but unprofessional in module-name register |
| receiver | Unidirectional implication |
| tannoy | British PA system — unidirectional |
| squawk / squawkbox | Slang fun but unprofessional |
| bullhorn | Unidirectional |
| mic | Unidirectional, too short |
| ptt | Push-to-talk — military/radio — abbreviation-heavy |
| channel | Conflicts with Phoenix `Channel` — would collide inside the project |
| linkup | Verb, not object |
| hailing | Star Trek "hailing frequencies" — kept as a sleeper option |

`intercom` was the strongest candidate after this expansion until the user redirected toward "relay" (next section).

### 6. Relay (originally typoed "replay")

User asked about "从 replay 这个词出发" — almost certainly meaning *relay* (the two words differ by one letter but in opposite directions: replay = past playback, relay = real-time forwarding). I confirmed the intent and listed both branches.

**Relay branch:**

| Candidate | Note |
|-----------|------|
| relay | Direct, but heavily used in messaging/networking lib names |
| **switchboard** | 1880s telephone exchange — operator at the center patches arbitrary endpoint pairs together; bidirectional; many-to-many; resonates with Barbara Gordon / Oracle's "remote female information node" archetype (switchboard operators were a contemporaneous female-led profession). **Strong fit** and the recommended name in this round. |
| patchbay | Recording-studio routing wall; precise engineering object; works, but English-only register |
| exchange | Telephone exchange; abstract |
| conduit | Passive pipe |
| junction | Generic |
| baton, torch, semaphore | All unidirectional or wrong technical referent |

**Replay branch (recorded for completeness, not actually relevant to the PTY bridge):**

If "replay" was the literal intent, the right object would be the future `TranscriptTailer` (which replays SQLite-stored bytes to a fresh browser). Candidates noted: `gramophone`, `phonograph`, `tape`, `reel`, `pensieve` (Harry Potter, off-universe).

### 7. The Matrix (final)

User asked: *"在 matrix 电影里，他们在现实时间和真实时间互相穿越是通过听筒的是吗？"* This was the breakthrough. The film does not use earpieces — it uses **hardline phones** — but the underlying intuition (a wired, bidirectional, cross-world conduit, with strict rules and an operator on the other end) was exactly right.

| Candidate | Note |
|-----------|------|
| **hardline** | **Selected.** Wired phone in *The Matrix* used to enter/exit the simulation; bidirectional; operator-required; ceremonial weight; "hard" implicitly references the Phase 0 stability requirement |
| exit | Trinity / Morpheus catchphrase — but `exit` collides with BEAM `exit/1` |
| operator | Tank/Link's role title — but "operator" overloads with Erlang's notion of operators |
| nebuchadnezzar | The ship — a place, not a conduit; spelling penalty |
| construct | The white loading-program room — a space, not a channel |
| zion | Real-world city — a place |
| jack | "Jack in / jack out" — the headjack interface; concise, bidirectional, but `jack` collides with JACK Audio |
| redpill | An event, not a conduit; also culturally tainted |
| headjack | Fan-coined name for the back-of-skull port; vivid but not film-canonical |

---

## Why `hardline` Won

Five reasons, ranked:

1. **Precision of metaphor.** PTY bridge = "wired bidirectional channel between two worlds." Hardline = exactly that, in canonical form. `switchboard` and `intercom` describe many-to-many routing (a layer above this — that's what `Babs.A2A.Router` will do); `hardline` describes the per-pair line itself, which is the right level for this module.
2. **"Operator must be listening" rule.** The Matrix's hardline only works if a Nebuchadnezzar operator is watching. PTY only works if a `Hardline.Pane` GenServer is running. The contracts are isomorphic.
3. **Stability echo.** Phase 0 exists to verify *that this line stays hard.* The name doubles as a permanent reminder of the Phase 0 acceptance bar.
4. **Universe compatibility.** Babs / Oracle / Bat-Family is one operator-and-remote-agents universe; Matrix's Nebuchadnezzar / Tank / hardline / Neo is another instance of the same archetype — operator at a console pulling agents in and out across a barrier. The two universes don't clash; they reinforce each other.
5. **Search cleanliness.** No major BEAM/Elixir collision; rare in package indexes; specific enough that grep results are signal.

---

## Runner-Up Provenance

Names worth remembering for future modules in Babs:

- **`switchboard`** — strong candidate for the eventual A2A router or message bus, which *is* a many-to-many switchboard. Better there than at the PTY layer.
- **`commlink`** — good candidate for a future "operator-to-citizen direct channel" (e.g. an admin/maintenance pipe distinct from normal A2A traffic).
- **`iris`** — rainbow/messenger; a candidate for the multiplexed event stream (parser output → multiple subscribers).
- **`gramophone`** / **`reel`** — natural names for `TranscriptTailer` if it ever needs a friendly handle.
- **`patchbay`** — possible name for a future hot-pluggable connector framework if v0.2 brings Discord/Telegram/etc.

---

## Decision Path Summary

```
functional names (tmux_bridge, pane_io, ...)
   ↓ rejected: dry
spike-flavored names (pty_probe, erlexec_trial, ...)
   ↓ rejected: "assume PTY will work"
Greek pantheon (Iris, Hermes, Caduceus, ...)
   ↓ rejected: wrong universe (Babs is Bat-Family, not Greek)
Bat-Family (Oracle, Commlink, ...)
   ↓ recommended: commlink — but...
Earpiece-seeded two-way devices (intercom, headset, ...)
   ↓ recommended: intercom — but user redirected to relay
Relay objects (switchboard, patchbay, ...)
   ↓ recommended: switchboard — but user surfaced Matrix
Matrix artifacts (hardline, jack, ...)
   ↓ SELECTED: hardline
```

---

## When to Open a New Naming-History Document

Open a new `BAB-XXXX` REF (sibling to this one) when:

- A subsystem name was chosen after exploring **two or more namespaces** (not a single obvious name)
- The exploration produced **memorable runner-ups** worth preserving for future modules
- The naming reasoning is **non-obvious** and would otherwise be lost to git history

Do not open a Naming History for routine names (e.g. `Babs.Repo`, `Babs.Application`) — those go straight into `BAB-1002`.

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial document — captures the PTY-bridge naming exploration that ended at `hardline` | Claude Code |
