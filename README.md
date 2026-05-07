<p align="center">
  <h1 align="center">Babs</h1>
  <p align="center"><strong>Multi-Agent Communications & Coordination Hub</strong></p>
</p>

---

## What is Babs?

Babs is an Elixir/Phoenix multi-agent runtime. It hosts long-lived
`tmux`-backed Citizens, exposes their terminals in the browser, stores Tickets
for coordination, and captures AI CLI replies from local transcripts when
available.

Current runtime shape:

- Phoenix web UI on port `4000` by default
- `tmux` sessions named `babs-<slug>`
- seed Citizens in `citizens/citizen-<slug>.toml`
- default workspaces under `workspaces/<slug>/`
- default runtime data under `var/`
- browser terminals powered by xterm.js
- Ticket markdown/history files under `var/tickets/` unless configured

Built from scratch on Elixir 1.19 / OTP 28 / Phoenix 1.8, with `erlexec` for
PTY attachment and Phoenix LiveView/Channels for browser coordination.

## Status

Active v0.1 development. This is not packaged as a release yet; run it from the
repo as a development app. The current main branch supports:

- Citizen index and terminal pages
- full-window terminal mode via `?full=1`
- start/stop/restart controls for Babs-owned Citizens
- attach/detach for imported external `tmux` panes
- Ticket list/detail/new pages
- Ticket assignment, comments, approval/rejection flow
- JSONL transcript reply capture for supported AI CLIs

## Babs and Alfred

Babs pairs with [Alfred](https://github.com/frankyxhl/alfred) (`af`) — the same ecosystem for AI agent operations:

- **Alfred (`af`)** — per-agent runbook: SOPs, workflow checklists, document lifecycle
- **Babs (`bb`)** — multi-agent runtime: citizen lifecycle, message relay, A2A coordination

Both are named after Bat-Family support roles. Alfred Pennyworth keeps the runbook for one Batman; Babs (Barbara Gordon) coordinates the whole Bat-Family from her clocktower. The phonetic resonance with the legacy `*.bob/` idea remains part of the naming history, but it is not the Phase 1 runtime layout.

## Quickstart

These commands assume macOS with Homebrew. Linux should work, but the current
dogfood path is macOS.

```bash
# System tools
brew install git tmux mise node python pipx

# Optional but strongly recommended for LLM/agent workflows
pipx install fx-alfred
pipx ensurepath

# Clone and enter the repo
git clone git@github.com:frankyxhl/babs.git
# or: git clone https://github.com/frankyxhl/babs.git
cd babs

# Install pinned Erlang/Elixir from .mise.toml
mise trust
mise install

# Fetch Elixir and browser dependencies
mise exec -- mix deps.get
npm ci

# Refresh vendored browser assets when dependencies change
npm run vendor:browser

# Compile and run tests
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test

# Start the web app on localhost
mise exec -- mix phx.server
```

Open:

- `http://127.0.0.1:4000/` — redirects to the Citizen UI
- `http://127.0.0.1:4000/citizens` — Citizen index
- `http://127.0.0.1:4000/citizens/sentinel` — deterministic shell Citizen
- `http://127.0.0.1:4000/citizens/sentinel?full=1` — full-window terminal
- `http://127.0.0.1:4000/tickets` — Ticket index

## Remote Access

For a remote browser over Tailscale or a LAN, bind Phoenix to all interfaces:

```bash
BABS_HTTP_IP=0.0.0.0 mise exec -- mix phx.server
```

Then open `http://<machine-ip>:4000/` from the other machine. Do not commit real
private IPs into docs, PR bodies, or examples.

For a long-running detached server:

```bash
tmux new-session -d -s babs-web-main -c "$PWD" \
  'BABS_HTTP_IP=0.0.0.0 mise exec -- mix phx.server'

tmux capture-pane -p -t babs-web-main -S -80
tmux kill-session -t babs-web-main
```

## Runtime Configuration

Development defaults are intentionally local and gitignored:

| Variable | Default | Purpose |
|---|---|---|
| `BABS_ROOT` | current working directory | Base path for relative runtime paths |
| `BABS_HTTP_IP` | `127.0.0.1` | Dev bind address |
| `BABS_HTTP_PORT` / `PORT` | `4000` | Dev HTTP port |
| `BABS_WORKSPACE_ROOT` | `<BABS_ROOT>/workspaces` | Citizen workspaces |
| `BABS_TICKETS_ROOT` | `<BABS_ROOT>/var/tickets` | Ticket markdown/history files |
| `BABS_CITIZENS_DB_PATH` | `<BABS_ROOT>/var/babs_citizens.sqlite3` | SQLite registry |
| `BABS_SOCKET_TOKEN` | unset in dev | Required in prod browser-terminal URLs |

Example with repo-external runtime data:

```bash
export BABS_WORKSPACE_ROOT="$HOME/babs-data/workspaces"
export BABS_TICKETS_ROOT="$HOME/babs-data/tickets"
export BABS_CITIZENS_DB_PATH="$HOME/babs-data/babs.sqlite3"
mise exec -- mix phx.server
```

Production mode is not the main dogfood path yet. If you use `MIX_ENV=prod`,
set at least `PHX_HOST`, `SECRET_KEY_BASE`, and `BABS_SOCKET_TOKEN`.

## AI CLI Citizens

The seed Citizens are:

| Slug | CLI | Purpose |
|---|---|---|
| `sentinel` | `/bin/zsh -f` | deterministic shell smoke target |
| `clare` | `claude` | Claude Code seed Citizen |
| `dylan` | `codex` | Codex CLI seed Citizen |
| `elena` | `copilot` | GitHub Copilot CLI test Citizen |

If `claude`, `codex`, or `copilot` is missing or not authenticated, Babs can
still run; those Citizens may fail or wait for first-run prompts. Start with
`sentinel` to verify the base install before testing AI CLIs.

Expected local setup for AI Citizens:

- `tmux` works: `tmux -V`
- `claude` is installed and authenticated for Clare
- `codex` is installed and authenticated for Dylan
- `copilot` is installed and authenticated for Elena
- `af` is on `PATH` if Citizens need to read Alfred SOPs

`trusted_autonomous` Citizens are Babs-owned workspaces. Imported external
`tmux` sessions are attach/detach only; Babs should not own or kill them.

## Ticket Commands

The browser is the preferred operator UI, but temporary Mix bridge commands are
available:

```bash
mise exec -- mix babs.ticket.new \
  --title "Say hello" \
  --body "Please reply with BABS_REPLY <ticket-id>: hello"

mise exec -- mix babs.ticket.list
mise exec -- mix babs.ticket.show T-YYYY-MM-DD-NNN
mise exec -- mix babs.ticket.assign T-YYYY-MM-DD-NNN elena
mise exec -- mix babs.ticket.comment T-YYYY-MM-DD-NNN "Follow-up message" --by user
mise exec -- mix babs.ticket.transition T-YYYY-MM-DD-NNN pending_approval
mise exec -- mix babs.ticket.approve T-YYYY-MM-DD-NNN
mise exec -- mix babs.ticket.reject T-YYYY-MM-DD-NNN "Please revise this"
```

Inside a Citizen pane, `bin/bb` currently provides:

```bash
bin/bb ticket comment T-YYYY-MM-DD-NNN "comment body" --by dylan
```

## Validation

Fast local checks:

```bash
mise exec -- mix format --check-formatted
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test
npm run test:js
af validate --root .
git diff --check
```

Browser checks:

```bash
npm run test:e2e
npm run test:bdd
```

`npm run test:bdd` requires `browser-harness` and a browser/CDP setup. If Chrome
remote-debugging authorization gets in the way, run BDD from an isolated Chrome
profile and set `BU_CDP_URL` to that profile's debugging port.

Phase-specific gate:

```bash
mise exec -- mix babs.gate_a
```

## Troubleshooting

- **Port already in use:** run with `BABS_HTTP_PORT=4010`.
- **Remote browser cannot connect:** use `BABS_HTTP_IP=0.0.0.0` and verify the
  host firewall allows the port.
- **Terminal page connects but shows old state:** Babs reattaches existing
  `tmux` sessions. Inspect with `tmux ls` and `tmux capture-pane -p -t
  babs-sentinel -S -80`.
- **Need to stop one Babs-owned Citizen manually:** `tmux kill-session -t
  babs-<slug>`.
- **Need to reset local runtime data:** stop the server first, then remove
  runtime directories such as `var/` and local workspace contents. This deletes
  local Tickets, SQLite rows, and transcripts.
- **Missing browser assets:** run `npm ci && npm run vendor:browser`.
- **SQLite errors after schema changes:** run `mise exec -- mix ecto.migrate -r
  Babs.Citizens.Repo` or reset the gitignored SQLite file if local data can be
  discarded.

## LLM / Agent Notes

- Read `CLAUDE.md` first. `AGENTS.md` is only a redirect.
- Use `af guide --root .` and `af plan ... --root .` before non-trivial work.
- Primary project routing is `rules/BAB-2100-SOP-Workflow-Routing-PRJ.md`.
- Standard phase delivery is `rules/BAB-1503-SOP-Phase-Delivery-Workflow.md`.
- Do not commit runtime data from `var/`, `workspaces/*/transcript.jsonl`,
  `logs/`, `tmp/`, `test-results/`, or `node_modules/`.
- Do not publish real private IPs, tokens, host-specific paths, or credentials
  in commits, PR bodies, comments, or review packets.
- GitHub-visible writes for this project should use the `ryosaeba1985` account.

## Project Map

```text
apps/babs/              Phoenix web app
apps/babs_citizens/     Citizen lifecycle, tmux, tickets, SQLite, transcripts
citizens/               Seed Citizen TOML configs
config/                 Mix/Phoenix runtime config
rules/                  Alfred BAB documents
test/browser/           browser JS, E2E, and BDD tests
bin/bb                  temporary Citizen-side ticket bridge
var/                    gitignored runtime data
workspaces/             Citizen workspaces and local transcripts
```

## License

TBD
