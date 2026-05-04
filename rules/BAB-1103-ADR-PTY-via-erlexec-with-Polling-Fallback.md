# ADR-1103: PTY via erlexec; tmux send-keys Polling as Fallback

**Applies to:** BAB project
**Last updated:** 2026-05-04
**Last reviewed:** 2026-05-03
**Status:** Accepted

---

## ⚠️ v0.1 Terminology Amendment (2026-05-04)

The functional decision in this ADR remains accepted: `erlexec` PTY attach is primary, and `tmux send-keys`/`capture-pane` polling is the fallback if Phase 0 stability validation fails.

Current v0.1 naming supersedes older terms in the body:

- `PaneSession` / `Babs.Citizen.PaneSession` → `Hardline.Pane`
- `Tmux.Core` / `Babs.Tmux.Core` → `Hardline` boundary in `:babs_citizens`
- terminal bytes publish through PubSub topic `pane:<slug>` per `BAB-1106`; direct Channel↔pane PID coupling is not the v0.1 design

---

## What Is It?

How Babs talks to the AI CLIs running inside tmux panes. Two methods are documented; **Method A (erlexec PTY attach)** is the primary plan; **Method B (`tmux send-keys` + `capture-pane` polling)** is the reserved fallback contingent on Phase 0 stability validation.

---

## Context

Babs hosts AI CLIs (Claude, Codex, future Gemini/etc.) running inside tmux panes. It needs to:

1. **Inject text** into a pane (paste a message, send Enter)
2. **Read pane output** (capture AI replies, watch for prompt-state changes)
3. **Resize the pane** (when a browser terminal client connects with different dimensions)
4. **Detect liveness** (pane died, AI CLI exited)

Erlang/OTP has **no built-in PTY module**. (For reference — the equivalent Python primitives are `pty.fork()` + `os.write` + `os.read` + `fcntl.ioctl(TIOCSWINSZ)`. We're not using them, but they describe the shape of what we need on the BEAM.)

Three options were evaluated:

- **Method A**: `erlexec` (Hex package — C++ port + Erlang NIF). Provides full PTY semantics: `:exec.run(cmd, [:pty, :stdin, :stdout])`, `:exec.send/2`, `:exec.pty_resize/2`, monitor for child death.
- **Method B**: No PTY. Use `System.cmd("tmux", ["send-keys", ...])` to inject and `tmux capture-pane` polling at ~200ms intervals to read.
- **Method C**: Write a custom NIF wrapping `posix_openpt + execve` (~200 lines C). Lightest dependency footprint.

---

## Decision

**Method A (erlexec) is the primary implementation.**

**Method B (tmux send-keys polling) is the documented fallback,** to be activated if Phase 0 stability validation (`BAB-1502` SOP, `BAB-2200` PRP) shows erlexec PTY attach is operationally unsound on our actual workload.

**Method C (custom NIF) is rejected** for the initial implementation but kept as a future option if both A and B prove inadequate.

### What Method A Looks Like

```elixir
{:ok, pid, os_pid} = :exec.run(
  ~c"tmux attach-session -t #{session}",
  [:pty, :stdin, :stdout, {:stderr, :stdout}, :monitor]
)
:exec.pty_resize(os_pid, {cols, rows})
:exec.send(os_pid, payload)

receive do
  {:stdout, ^os_pid, data} -> handle(data)
  {:DOWN, _, :process, ^pid, reason} -> handle_death(reason)
end
```

Owned by `Hardline.Pane` (one per active Citizen). Serialized writes; received bytes publish to PubSub topic `pane:<slug>` per `BAB-1106`.

### Why A Beats B for the Primary Path

- **Real-time output.** PTY streams bytes as they appear; polling has ~200ms latency floor.
- **No polling waste.** Idle citizens cost ~zero; polling tmux every 200ms wastes CPU even when nothing's happening.
- **Real terminal semantics.** `xterm.js` in the browser expects a real PTY (terminal modes, escape sequences, proper resize). Polling fakes some of this.
- **Death detection is event-driven.** `:exec` `:monitor` sends a `:DOWN` message when the child exits; polling has to compare snapshots.

### The Documented Risk

`erlexec` is a **C++ port + NIF**. Specific failure modes:
- Port process can crash (segfault, OOM kill, NIF bug)
- Crashes inside a `tmux attach` can propagate: the attached client's death may be interpreted by tmux as the session being closed in some configurations, killing the AI CLI inside
- Build chain requires C++ toolchain (Xcode CLI tools or equivalent on Linux)

**Phase 0 SOP `BAB-1502` validates this empirically.** Pass criterion: ≤1 erlexec port crash per 48h **AND** any crash that does occur leaves the underlying tmux session alive (so the AI CLI inside survives).

### Method B Fallback Trigger

If Phase 0 fails the criterion:
1. Switch `Hardline.Pane` to wrap `System.cmd("tmux", ["send-keys", session, "-l", payload])` for inject
2. Switch terminal-byte read path to `tmux capture-pane -p` polling at 150-250ms (browser terminal latency budget)
3. Switch death detection to `tmux has-session` polling at 1s
4. Browser terminal Channel still receives bytes, just delayed by polling cadence

This costs latency and CPU but eliminates the BEAM-side PTY dependency entirely. Method B is a known-working pattern at the tmux-CLI layer (send-keys + capture-pane is well-validated as a substrate), so falling back here is not introducing untested ground.

---

## Consequences

**Positive (Method A):**
- Real-time terminal experience, matching today's xterm.js dashboard
- Event-driven CPU profile (idle citizens cost nothing)
- Single ownership semantics (`Hardline.Pane` owns the port; restart-coupled to the citizen)

**Negative (Method A):**
- C++ build dependency
- Recovery from port crash needs careful supervision (don't kill the citizen subtree on every flake; back off and retry)

**Positive (Method B fallback):**
- No NIF / C++ dependency at all
- Stateless inject path (no port lifecycle to manage)

**Negative (Method B fallback):**
- 150-250ms read latency floor on terminal output
- Constant tmux CLI invocations regardless of activity
- Less faithful terminal semantics for browser-side xterm.js

---

## Rejected Alternatives

### Method C — Custom NIF wrapping `posix_openpt + execve`

~200 lines of C wrapping the POSIX PTY API directly.

**Rejected because:**
- erlexec already does this and is battle-tested in production Elixir systems
- Custom NIF means we own the segfault surface; erlexec's surface is shared with the Elixir community
- Build complexity is similar (still needs C toolchain)
- Reserved as a future option only if both A and B fail and Babs grows enough to justify owning a PTY library

### Method D — No tmux at all; spawn AI CLI directly under erlexec

Skip tmux entirely; `Hardline.Pane` runs the AI CLI as a direct child of erlexec.

**Rejected because:**
- Loses tmux's session persistence (Babs restart wouldn't lose the AI CLI's state)
- Loses the human-attachable session (operator can't `tmux attach` to debug)
- tmux-as-substrate is the intended design; persistent sessions across operator/agent connection cycles is a feature we want, not a workaround

---

## Change History

| Date | Change | By |
|------|--------|----|
| 2026-05-03 | Initial version — Method A primary, Method B fallback, Method C reserved | Claude Code |
| 2026-05-03 | Drop "Python implementation" / "migration research" framing | Claude Code |
| 2026-05-04 | Add v0.1 terminology amendment: `PaneSession` → `Hardline.Pane`, `Tmux.Core` → `Hardline`, terminal bytes via PubSub `pane:<slug>` | Codex |
