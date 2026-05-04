# Hardline Phase 0 Validation Summary

- Profile: `smoke`
- Generated: 2026-05-04T06:35:55.231350Z
- Overall status: **INCOMPLETE**
- Web byte-path confirmed: false

## Scenario Plan

- chaos_interval_seconds: 2
- chaos_seconds: 5
- detach_count: 1
- detach_seconds: 5
- fleet_count: 1
- resize_seconds: 3
- slow_reader_seconds: 3
- soak_seconds: 5
- web_seconds: 30

## Results

- provision_fleet: PASS - started 1 tmux session(s)
- soak: PASS - seconds=5 port_downs=0 dead_sessions=0 allowed_port_downs=0 memory_delta=-212072
- chaos: PASS - intentional_port_kills=3
- resize_storm: PASS - resize_calls=30 resize_errors=0 port_downs=0
- slow_reader: PASS - seconds=3 skipped_os_pid=27616 port_downs=0 memory_delta=14064
- detach_reattach: PASS - detach_reattach_runs=1
- web_byte_path: WARN - manual check required: run `mix hardline.web` and confirm xterm.js renders for 30 minutes

## Phase 1 Handoff Notes

- erlexec attach command: `tmux attach-session -t <session>`
- default workload shell: `/bin/zsh -f`
- erlexec resize command: `:exec.winsz(os_pid, rows, cols)`
- tmux session shape: detached sessions, `tmux new-session -d -s <session> <command>`
- PubSub byte contract: `{:pane_bytes, stream_id, seq, binary}` on topic `pane:<name>`, chunks <= 4096 bytes
- xterm.js page: run `mix hardline.web --port 4010`, then open `http://localhost:4010/`
- Browser resize path: xterm FitAddon -> Channel `resize` event -> `:exec.winsz(os_pid, rows, cols)`
- Browser assets: `@xterm/xterm@5.5.0`, `@xterm/addon-fit@0.10.0`, `phoenix@1.8.5`
- Toolchain: see `spikes/hardline/README.md`
