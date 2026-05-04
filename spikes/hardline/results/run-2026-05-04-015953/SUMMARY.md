# Hardline Phase 0 Validation Summary

- Profile: `quick10`
- Generated: 2026-05-04T02:08:54.500660Z
- Overall status: **INCOMPLETE**
- Web byte-path confirmed: false

## Scenario Plan

- chaos_interval_seconds: 30
- chaos_seconds: 180
- detach_count: 1
- detach_seconds: 60
- fleet_count: 2
- resize_seconds: 60
- slow_reader_seconds: 60
- soak_seconds: 180
- web_seconds: 600

## Results

- provision_fleet: PASS - started 2 tmux session(s)
- soak: PASS - seconds=180 port_downs=0 dead_sessions=0 memory_delta=-2599984
- chaos: PASS - intentional_port_kills=6
- resize_storm: PASS - resize_calls=1188
- slow_reader: PASS - seconds=60 skipped_os_pid=85532 port_downs=0 memory_delta=128968
- detach_reattach: PASS - detach_reattach_runs=1
- web_byte_path: WARN - manual check required: run `mix hardline.web` and confirm xterm.js renders for 30 minutes

## Phase 1 Handoff Notes

- erlexec attach command: `tmux attach-session -t <session>`
- erlexec resize command: `:exec.winsz(os_pid, rows, cols)`
- tmux session shape: detached sessions, `tmux new-session -d -s <session> <command>`
- PubSub byte contract: `{:pane_bytes, binary}` on topic `pane:<name>`, chunks <= 4096 bytes
- xterm.js page: run `mix hardline.web --port 4010`, then open `http://localhost:4010/`
- Browser assets: `@xterm/xterm@5.5.0`, `phoenix@1.8.5`
- Toolchain: see `spikes/hardline/README.md`
