from __future__ import annotations

import base64
import json
import os
import signal
import shutil
import sqlite3
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from dataclasses import dataclass
from pathlib import Path

from browser_harness.helpers import (
    cdp,
    click_at_xy,
    ensure_real_tab,
    js,
    new_tab,
    page_info,
    press_key,
    type_text,
    wait,
    wait_for_element,
    wait_for_load,
)


ROOT = Path(__file__).resolve().parents[3]
RUNTIME_ROOT = (
    Path(os.environ.get("BABS_ROOT") or os.environ.get("RELEASE_ROOT") or ROOT)
    .expanduser()
    .resolve()
)
WORKSPACE_ROOT = None
PANE_SOURCE = ROOT / "apps/babs_citizens/lib/babs_citizens/hardline/pane.ex"
WEB_SOURCE = ROOT / "apps/babs/lib/babs_web/channels/pane_channel.ex"
SERVER_LOG = ROOT / "logs/bdd-server.log"


class SkipScenario(Exception):
    pass


@dataclass(frozen=True)
class Scenario:
    name: str
    given: str
    when: str
    then: str
    run: object


class BabsBddContext:
    def __init__(self) -> None:
        self.base_url = os.environ.get("BABS_BROWSER_BASE_URL", "http://127.0.0.1:4000").rstrip("/")
        self.server_process: subprocess.Popen | None = None
        self.test_target_id: str | None = None
        self.tickets_root = tickets_root()
        self.direct_prompts_path = Path(
            os.environ.get("BABS_BDD_DIRECT_PROMPTS_PATH")
            or (tmp_bdd_dir("direct-prompts") / "prompts.jsonl")
        )
        self.federation_config_path = tmp_bdd_dir("federation") / "federation.toml"

    def write_federation_config(
        self,
        *,
        node_id: str = "bdd-local",
        peer_id: str = "bdd-peer",
        peer_name: str = "BDD Peer",
        capabilities: list[str] | None = None,
        citizen_overrides: dict[str, list[str]] | None = None,
    ) -> None:
        capabilities = capabilities or ["read"]
        citizen_overrides = citizen_overrides or {}
        citizen_tables = ""

        for slug, caps in sorted(citizen_overrides.items()):
            citizen_tables += (
                f"\n            [peers.{peer_id}.citizens.{slug}]\n"
                f"            capabilities = {json.dumps(caps)}\n"
            )

        self.federation_config_path.write_text(
            f"""
            [node]
            id = "{node_id}"
            name = "BDD Local"

            [peers.{peer_id}]
            name = "{peer_name}"
            url = "{self.base_url}"
            capabilities = {json.dumps(capabilities)}
            {citizen_tables}
            """,
            encoding="utf-8",
        )

    def ensure_server(self) -> None:
        if self._server_ready():
            return

        SERVER_LOG.parent.mkdir(parents=True, exist_ok=True)
        log = SERVER_LOG.open("ab")
        env = os.environ.copy()
        env["BABS_TICKETS_ROOT"] = str(self.tickets_root)
        env.setdefault("BABS_BDD_FAKE_DIRECT", "1")
        env.setdefault("BABS_BDD_DIRECT_REPLY", "BDD direct CLI UI reply.")
        env["BABS_BDD_DIRECT_PROMPTS_PATH"] = str(self.direct_prompts_path)
        self.write_federation_config()
        env["BABS_FEDERATION_CONFIG"] = str(self.federation_config_path)
        self.server_process = subprocess.Popen(
            ["mise", "exec", "--", "mix", "phx.server"],
            cwd=ROOT,
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )

        deadline = time.time() + 35
        while time.time() < deadline:
            if self._server_ready():
                return
            if self.server_process.poll() is not None:
                raise RuntimeError(f"Babs server exited early; see {SERVER_LOG}")
            time.sleep(0.5)

        raise RuntimeError(f"Babs server did not become ready at {self.base_url}; see {SERVER_LOG}")

    def cleanup(self) -> None:
        self.close_test_tab()

        if self.server_process is not None and self.server_process.poll() is None:
            os.killpg(self.server_process.pid, signal.SIGTERM)
            try:
                self.server_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(self.server_process.pid, signal.SIGKILL)
                self.server_process.wait(timeout=5)

        if self.server_process is not None and RUNTIME_ROOT != ROOT:
            cleanup_bdd_seed_sessions()

    def restart_server(self) -> None:
        if self.server_process is None:
            raise SkipScenario("BDD did not start the Babs server, so it cannot restart it")

        if self.server_process.poll() is None:
            os.killpg(self.server_process.pid, signal.SIGTERM)
            try:
                self.server_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(self.server_process.pid, signal.SIGKILL)
                self.server_process.wait(timeout=5)

        deadline = time.time() + 10
        while time.time() < deadline and self._server_ready():
            time.sleep(0.25)
        if self._server_ready():
            raise RuntimeError("Babs server did not shut down within 10s; refusing to restart")
        self.server_process = None
        self.ensure_server()

    def close_test_tab(self) -> None:
        if not self.test_target_id:
            return

        try:
            cdp("Target.closeTarget", targetId=self.test_target_id)
        finally:
            self.test_target_id = None
            try:
                ensure_real_tab()
            except Exception:
                pass

    def open_path(self, path: str) -> None:
        self.close_test_tab()
        self.test_target_id = new_tab(f"{self.base_url}{path}")
        wait_for_load(timeout=20)

    def connect_citizen(self, slug: str = "sentinel", *, full: bool = False) -> None:
        suffix = "?full=1" if full else ""
        self.open_path(f"/citizens/{slug}{suffix}")
        wait_for_terminal_connection(slug)

    def type_command_and_expect(self, marker: str, *, exactly_once: bool = False) -> None:
        click_terminal()
        type_text(f"printf '\\033[2J\\033[H{marker}\\n'")
        press_key("Enter")

        if exactly_once:
            wait_until(
                f"terminal output to contain {marker} exactly once",
                lambda: terminal_text().count(marker) == 1,
                timeout=15,
            )
        else:
            wait_until(
                f"terminal output to contain {marker}",
                lambda: marker in terminal_text(),
                timeout=15,
            )

    def _server_ready(self) -> bool:
        try:
            status, _body = http_get_status(f"{self.base_url}/tickets", timeout=2)
            return status == 200
        except Exception:
            return False


def wait_for_terminal_connection(slug: str) -> None:
    assert_element_visible('[data-testid="terminal"]', "terminal root")
    assert_element_visible(".xterm", "xterm surface")
    wait_until(
        f"{slug} connection status to be connected",
        lambda: js("document.querySelector('[data-testid=\"connection-status\"]')?.dataset.state || ''")
        == "connected",
        timeout=15,
    )


def scenarios() -> list[Scenario]:
    return [
        Scenario(
            name="sentinel terminal connects",
            given="sentinel is configured",
            when="the operator opens /citizens/sentinel",
            then="the terminal connects and reports connected status",
            run=scenario_sentinel_connects,
        ),
        Scenario(
            name="input reaches tmux once",
            given="sentinel is connected",
            when="the operator types a printf marker",
            then="the marker reaches the terminal exactly once",
            run=scenario_input_reaches_tmux_once,
        ),
        Scenario(
            name="citizens reload preserves terminal",
            given="sentinel is connected",
            when=":babs_citizens reloads",
            then="the terminal can still send and receive bytes",
            run=scenario_citizens_reload_preserves_terminal,
        ),
        Scenario(
            name="web reload reconnects terminal",
            given="sentinel is connected",
            when=":babs reloads",
            then="the browser reconnects and input still works",
            run=scenario_web_reload_reconnects_terminal,
        ),
        Scenario(
            name="transcript replay survives tab restart",
            given="sentinel is connected",
            when="the browser tab closes and transcript output arrives before reopen",
            then="the reopened terminal replays the transcript marker",
            run=scenario_transcript_replay_survives_tab_restart,
        ),
        Scenario(
            name="sentinel is registered in SQLite",
            given="sentinel is connected after Babs boot",
            when="the Phase 3 citizen registry is inspected",
            then="the SQLite row is running and preserves the resolved workspace cwd",
            run=scenario_sentinel_is_registered_in_sqlite,
        ),
        Scenario(
            name="new citizen spawn UI creates shell citizen",
            given="/citizens/new is available",
            when="the operator submits a unique shell citizen",
            then="the citizen terminal opens, persists TOML and SQLite, and records transcript bytes",
            run=scenario_new_citizen_spawn_ui_creates_shell_citizen,
        ),
        Scenario(
            name="browser-created citizen survives restart",
            given="a shell citizen was created from the browser",
            when="the managed BDD server restarts",
            then="boot import and SQLite reconciliation preserve the citizen terminal",
            run=scenario_browser_created_citizen_survives_restart,
        ),
        Scenario(
            name="configured workspace root stores transcript outside app root",
            given="BABS_WORKSPACE_ROOT is configured",
            when="sentinel produces output while the browser tab is closed",
            then="the transcript replay marker is read from the configured workspace root",
            run=scenario_configured_workspace_root_stores_transcript,
        ),
        Scenario(
            name="multi citizen index and tab navigation stays fd bounded",
            given="three shell citizens are running",
            when="the operator opens the index and switches between terminal tabs",
            then="the rows, tabs, full mode, and fast fd thresholds stay correct",
            run=scenario_multi_citizen_index_and_tab_navigation_stays_fd_bounded,
        ),
        Scenario(
            name="citizen lifecycle controls stop start restart",
            given="a shell citizen was created from the browser",
            when="the operator stops, starts, and restarts it from Babs UI",
            then="status, terminal access, workspace, and transcript continuity stay correct",
            run=scenario_citizen_lifecycle_controls_stop_start_restart,
        ),
        Scenario(
            name="imported external tmux attach detaches without killing external session",
            given="a stopped Citizen and an unmanaged tmux pane exist",
            when="the operator imports the pane from /citizens/attach and later detaches it",
            then="Babs uses Attach/Detach semantics and the external tmux session stays alive",
            run=scenario_imported_external_tmux_attach_detaches_without_killing_external_session,
        ),
        Scenario(
            name="stopped citizens stay stopped across managed server restart",
            given="one browser-created citizen is stopped and one is running",
            when="the managed BDD server restarts",
            then="the stopped citizen stays stopped while the running citizen reattaches",
            run=scenario_stopped_citizens_stay_stopped_across_managed_server_restart,
        ),
        Scenario(
            name="terminal fills viewport",
            given="a terminal page is open",
            when="the viewport is resized",
            then="the xterm surface keeps stable full-window dimensions",
            run=scenario_terminal_fills_viewport,
        ),
        Scenario(
            name="mobile pwa shell",
            given="Babs is opened from a phone-sized browser viewport",
            when="the operator opens Tickets, Citizens, and a full terminal",
            then="PWA metadata and mobile shell layout remain usable without horizontal overflow",
            run=scenario_mobile_pwa_shell,
        ),
        Scenario(
            name="citizen home browser edit and external refresh",
            given="a Citizen has an isolated Knowledge Home Readme",
            when="the operator edits it in the browser and the file is later edited on disk",
            then="the saved browser edit renders and the external edit refreshes in the Home tab",
            run=scenario_citizen_home_browser_edit_and_external_refresh,
        ),
        Scenario(
            name="mobile ticket diff approval",
            given="a pending approval Ticket has assignee workspace git changes",
            when="the operator reviews the diff from a phone-sized browser viewport",
            then="the diff is readable, controls are reachable, and approval closes the Ticket",
            run=scenario_mobile_ticket_diff_approval,
        ),
        Scenario(
            name="seed citizen terminals connect when CLIs are available",
            given="Clare, Dylan, and Elena are configured",
            when="their CLI commands are available",
            then="their terminal pages connect or are skipped with an explicit reason",
            run=scenario_seed_citizens_connect_when_available,
        ),
        Scenario(
            name="missing citizen returns clear 404",
            given="a citizen slug is missing",
            when="the operator opens that citizen URL",
            then="the page returns a clear citizen-not-found response",
            run=scenario_missing_citizen_returns_404,
        ),
        Scenario(
            name="ticket billboard list shows manual ticket",
            given="a runtime Ticket file is created manually",
            when="the operator opens /tickets",
            then="the Ticket appears in the Billboard list with icon-labeled navigation",
            run=scenario_ticket_billboard_list_shows_manual_ticket,
        ),
        Scenario(
            name="ticket external edit refreshes index",
            given="the /tickets page is open",
            when="the Ticket markdown title is edited on disk",
            then="the page updates without a browser reload",
            run=scenario_ticket_external_edit_refreshes_index,
        ),
        Scenario(
            name="ticket detail renders body and history",
            given="a runtime Ticket has markdown body and history",
            when="the operator opens /tickets/<id>",
            then="the detail page renders the body and history timeline",
            run=scenario_ticket_detail_renders_body_and_history,
        ),
        Scenario(
            name="ticket new form creates chat ready detail",
            given="/tickets is available",
            when="the operator creates a Ticket from the browser",
            then="the detail page opens with a chat panel and composer",
            run=scenario_ticket_new_form_creates_chat_ready_detail,
        ),
        Scenario(
            name="ticket chat shows captured citizen reply",
            given="a Ticket detail page is open",
            when="a Citizen reply is appended to the Ticket history JSONL",
            then="the chat view refreshes with the Citizen message",
            run=scenario_ticket_chat_shows_captured_citizen_reply,
        ),
        Scenario(
            name="ticket inspection panel shows auto approval",
            given="a Ticket was auto-approved by an inspector",
            when="the operator opens the Ticket detail page",
            then="the inspection panel shows the inspector approval and approved result",
            run=scenario_ticket_inspection_panel_shows_auto_approval,
        ),
        Scenario(
            name="ticket inspection panel shows rejected decision",
            given="a Ticket was rejected by an inspector",
            when="the operator opens the Ticket detail page",
            then="the inspection panel shows the needs-changes decision and rejected result",
            run=scenario_ticket_inspection_panel_shows_rejected_decision,
        ),
        Scenario(
            name="ticket inspection panel shows council status",
            given="a two-inspector council is pending",
            when="the operator opens the Ticket detail page",
            then="the inspection panel shows both inspector rows and human override controls",
            run=scenario_ticket_inspection_panel_shows_council_status,
        ),
        Scenario(
            name="mayor proposal approval creates child tickets",
            given="a Mayor proposal is waiting for operator approval",
            when="the operator approves the proposal from Ticket detail",
            then="child Tickets are created, routed, and linked from the root Ticket",
            run=scenario_mayor_proposal_approval_creates_child_tickets,
        ),
        Scenario(
            name="ticket new form captures Elena Copilot JSONL reply",
            given="a Ticket is created from /tickets/new",
            when="a Copilot events.jsonl assistant reply is captured for Elena",
            then="the Ticket chat shows Elena's captured message",
            run=scenario_ticket_new_form_captures_elena_copilot_jsonl_reply,
        ),
        Scenario(
            name="ticket chat shows direct CLI fake reply",
            given="a Ticket detail page is open",
            when="a deterministic direct CLI provider turn completes",
            then="the Ticket chat shows the direct provider reply and direct turn history",
            run=scenario_ticket_chat_shows_direct_cli_fake_reply,
        ),
        Scenario(
            name="direct cli backend UI creation and assignment",
            given="the New Citizen form and Ticket detail page are available",
            when="the operator creates a Direct CLI Citizen and assigns a Ticket",
            then="the direct reply appears in chat without starting a tmux session",
            run=scenario_direct_cli_backend_ui_creation_and_assignment,
        ),
        Scenario(
            name="role routed ticket flow",
            given="a multi-role Direct CLI Citizen exists",
            when="the operator creates a role Ticket and routes it by role",
            then="the Ticket is assigned by role and the direct reply appears in chat",
            run=scenario_role_routed_ticket_flow,
        ),
        Scenario(
            name="direct cli compact prompt",
            given="a Direct CLI Citizen has an active provider session",
            when="the operator sends multiple Ticket comments",
            then="resumed direct turns send only the latest comment and reuse the provider session",
            run=scenario_direct_cli_compact_prompt,
        ),
        Scenario(
            name="ticket assignment hides stale sqlite citizen",
            given="a Citizen still has a SQLite row after its TOML is deleted",
            when="the operator opens an assignable Ticket detail page",
            then="the stale Citizen is not offered as an assignment target",
            run=scenario_ticket_assignment_hides_stale_sqlite_citizen,
        ),
        Scenario(
            name="citizens index hides stale sqlite citizen",
            given="a Citizen still has a SQLite row after its TOML is deleted",
            when="the operator opens /citizens",
            then="the stale Citizen is not shown in the normal fleet index",
            run=scenario_citizens_index_hides_stale_sqlite_citizen,
        ),
        Scenario(
            name="malformed ticket is visible",
            given="a malformed runtime Ticket file exists",
            when="the operator opens /tickets",
            then="the Invalid section shows the malformed file without crashing",
            run=scenario_malformed_ticket_is_visible,
        ),
        Scenario(
            name="ticket assignment auto starts stopped citizen",
            given="a stopped shell citizen and an open Billboard Ticket exist",
            when="the operator assigns the Ticket from /tickets/<id>",
            then="the citizen starts, the Ticket moves to in_progress, and the prompt is injected",
            run=scenario_ticket_assignment_auto_starts_stopped_citizen,
        ),
        Scenario(
            name="ticket comment notifies assigned citizen",
            given="an in-progress Ticket is assigned to a running citizen",
            when="the operator submits a Ticket comment from /tickets/<id>",
            then="the comment appears in history and is injected into the assignee terminal",
            run=scenario_ticket_comment_notifies_assigned_citizen,
        ),
        Scenario(
            name="federation events feed returns cursor snapshots",
            given="the Phase 17 read API is available",
            when="a remote peer reads /api/v1/events and repeats the returned cursor",
            then="the first read returns snapshots and the unchanged cursor returns no events",
            run=scenario_federation_events_feed_returns_cursor_snapshots,
        ),
        Scenario(
            name="remote operation bdd e2e ticket and citizen controls",
            given="a loopback peer has write/control capabilities",
            when="the operator comments, transitions, and restarts through remote UI controls",
            then="the operations go through the remote HTTP control path and update local state",
            run=scenario_remote_operation_bdd_e2e_ticket_and_citizen_controls,
        ),
    ]


def scenario_sentinel_connects(context: BabsBddContext) -> None:
    context.connect_citizen("sentinel")


def scenario_input_reaches_tmux_once(context: BabsBddContext) -> None:
    context.connect_citizen("sentinel")
    context.type_command_and_expect(unique_marker("BABS_BDD_INPUT_OK"), exactly_once=True)


def scenario_citizens_reload_preserves_terminal(context: BabsBddContext) -> None:
    context.connect_citizen("sentinel")
    context.type_command_and_expect(unique_marker("BABS_BDD_BEFORE_CITIZENS_RELOAD"))
    touch_source(PANE_SOURCE)
    wait(2)
    context.type_command_and_expect(unique_marker("BABS_BDD_AFTER_CITIZENS_RELOAD"))


def scenario_web_reload_reconnects_terminal(context: BabsBddContext) -> None:
    context.connect_citizen("sentinel")
    context.type_command_and_expect(unique_marker("BABS_BDD_BEFORE_WEB_RELOAD"))
    touch_source(WEB_SOURCE)
    wait_until(
        "web terminal status to reconnect",
        lambda: js("document.querySelector('[data-testid=\"connection-status\"]')?.dataset.state || ''")
        == "connected",
        timeout=20,
    )
    context.type_command_and_expect(unique_marker("BABS_BDD_AFTER_WEB_RELOAD"))


def scenario_transcript_replay_survives_tab_restart(context: BabsBddContext) -> None:
    slug = "sentinel"
    marker = unique_marker("BABS_BDD_TRANSCRIPT_REPLAY")

    context.connect_citizen(slug)
    context.close_test_tab()
    send_tmux_output(slug, marker)
    wait_until(
        f"transcript to contain {marker}",
        lambda: transcript_contains(slug, marker),
        timeout=10,
    )

    context.connect_citizen(slug)
    wait_until(
        f"terminal output to replay {marker}",
        lambda: marker in terminal_text(),
        timeout=15,
    )


def scenario_sentinel_is_registered_in_sqlite(context: BabsBddContext) -> None:
    context.connect_citizen("sentinel")
    row = sqlite_citizen_row("sentinel")

    assert row is not None
    assert row["status"] == "running"
    assert row["cwd"] == str(workspace_root() / "sentinel")
    assert json.loads(row["cli_args"]) == ["-f"]
    assert json.loads(row["env"]) == {}


def scenario_new_citizen_spawn_ui_creates_shell_citizen(context: BabsBddContext) -> None:
    slug = unique_slug("bdd-spawn")

    try:
        create_shell_citizen_from_ui(context, slug)
        marker = unique_marker("BABS_BDD_NEW_CITIZEN")
        context.type_command_and_expect(marker, exactly_once=True)

        toml = citizen_toml_path(slug)
        assert toml.exists()
        assert f'slug = "{slug}"' in toml.read_text()

        row = sqlite_citizen_row(slug)
        assert row is not None
        assert row["status"] == "running"
        assert row["cwd"] == str(workspace_root() / slug)
        assert row["cli"] == "/bin/zsh"
        assert json.loads(row["cli_args"]) == ["-f"]

        wait_until(
            f"new citizen transcript to contain {marker}",
            lambda: transcript_contains(slug, marker),
            timeout=10,
        )

        context.open_path("/citizens/new")
        submit_new_citizen_form(slug, "Duplicate Citizen", "shell", slug)
        wait_until(
            "duplicate citizen error to render",
            lambda: "Citizen TOML already exists" in js("document.body.innerText"),
            timeout=10,
        )
        assert tmux_session_count(slug) == 1
    finally:
        cleanup_spawned_citizen(slug)


def scenario_browser_created_citizen_survives_restart(context: BabsBddContext) -> None:
    slug = unique_slug("bdd-restart")

    try:
        create_shell_citizen_from_ui(context, slug)
        context.close_test_tab()
        context.restart_server()
        toml = citizen_toml_path(slug)
        assert toml.exists()
        assert f'slug = "{slug}"' in toml.read_text()

        row = sqlite_citizen_row(slug)
        assert row is not None
        assert row["status"] == "running"
        assert row["cwd"] == str(workspace_root() / slug)
        assert row["cli"].endswith("zsh")
        assert json.loads(row["cli_args"]) == ["-f"]

        context.connect_citizen(slug)
        context.type_command_and_expect(unique_marker("BABS_BDD_RESTART_CREATED"), exactly_once=True)
    finally:
        cleanup_spawned_citizen(slug)


def scenario_configured_workspace_root_stores_transcript(context: BabsBddContext) -> None:
    if not os.environ.get("BABS_WORKSPACE_ROOT"):
        raise SkipScenario("BABS_WORKSPACE_ROOT is not set")

    slug = "sentinel"
    marker = unique_marker("BABS_BDD_WORKSPACE_ROOT")

    context.connect_citizen(slug)
    context.close_test_tab()
    send_tmux_output(slug, marker)
    wait_until(
        f"custom workspace transcript to contain {marker}",
        lambda: transcript_contains(slug, marker),
        timeout=10,
    )

    transcript = transcript_path(slug)
    assert str(transcript).startswith(str(workspace_root()))

    context.connect_citizen(slug)
    wait_until(
        f"terminal output to replay {marker}",
        lambda: marker in terminal_text(),
        timeout=15,
    )


def scenario_multi_citizen_index_and_tab_navigation_stays_fd_bounded(context: BabsBddContext) -> None:
    slugs = [unique_slug("bdd-nav-a"), unique_slug("bdd-nav-b"), unique_slug("bdd-nav-c")]
    beam_pid = None
    baseline_fd = None

    try:
        for slug in slugs:
            create_shell_citizen_from_ui(context, slug)
            context.close_test_tab()

        beam_pid = managed_beam_pid(context)
        baseline_fd = fd_count(beam_pid)

        context.open_path("/citizens")
        assert_element_visible('[data-testid="citizens-index"]', "citizens index")

        for slug in slugs:
            assert_element_visible(f'[data-testid="citizen-row-{slug}"]', f"{slug} index row")
            assert_element_visible(f'[data-testid="citizen-open-{slug}"]', f"{slug} open link")
            assert_element_visible(f'[data-testid="citizen-full-{slug}"]', f"{slug} full link")
            wait_until(
                f"{slug} index status to be up",
                lambda slug=slug: "up"
                in js(f"document.querySelector('[data-testid=\"citizen-status-{slug}\"]')?.innerText || ''"),
                timeout=10,
            )

        click_selector(f'[data-testid="citizen-open-{slugs[0]}"]')
        wait_until(
            f"browser to open /citizens/{slugs[0]}",
            lambda: js("window.location.pathname") == f"/citizens/{slugs[0]}",
            timeout=10,
        )
        wait_for_terminal_connection(slugs[0])

        for index, slug in enumerate(slugs):
            if index > 0:
                click_selector(f'[data-testid="citizen-tab-{slug}"]')
                wait_until(
                    f"browser to switch to /citizens/{slug}",
                    lambda slug=slug: js("window.location.pathname") == f"/citizens/{slug}",
                    timeout=10,
                )
                wait_for_terminal_connection(slug)

            marker = unique_marker(f"BABS_BDD_PHASE5_{slug.upper().replace('-', '_')}")
            context.type_command_and_expect(marker, exactly_once=True)
            wait_until(
                f"{slug} transcript to contain {marker}",
                lambda slug=slug, marker=marker: transcript_contains(slug, marker),
                timeout=10,
            )

            current_fd = fd_count(beam_pid)
            if current_fd > baseline_fd + 12:
                raise AssertionError(f"fd count exceeded fast threshold: baseline={baseline_fd} current={current_fd}")

        click_selector('[data-testid="terminal-full-link"]')
        wait_until(
            "browser to enter full terminal mode",
            lambda: js("new URLSearchParams(window.location.search).get('full')") == "1",
            timeout=10,
        )
        wait_for_terminal_connection(slugs[-1])
        assert_no_element('[data-testid="terminal-chrome"]', "terminal chrome in full mode")

        context.close_test_tab()
        wait_until(
            "fd count to return near baseline after browser cleanup",
            lambda: fd_count(beam_pid) <= baseline_fd + 4,
            timeout=15,
        )
    finally:
        context.close_test_tab()
        for slug in slugs:
            cleanup_spawned_citizen(slug)


def scenario_citizen_lifecycle_controls_stop_start_restart(context: BabsBddContext) -> None:
    slug = unique_slug("bdd-life")

    try:
        create_shell_citizen_from_ui(context, slug)
        transcript = transcript_path(slug)
        before_marker = unique_marker("BABS_BDD_LIFECYCLE_BEFORE")
        context.type_command_and_expect(before_marker, exactly_once=True)
        wait_until(
            f"{slug} transcript to contain {before_marker}",
            lambda: transcript_contains(slug, before_marker),
            timeout=10,
        )

        context.open_path("/citizens")
        click_selector(f'[data-testid="citizen-stop-{slug}"]')
        wait_for_index_status(slug, "stopped")
        assert_control_disabled(f'[data-testid="citizen-open-{slug}"]', f"{slug} open link after stop")
        assert_control_disabled(f'[data-testid="citizen-full-{slug}"]', f"{slug} full link after stop")
        status, body = http_get_status(f"{context.base_url}/citizens/{slug}", timeout=5)
        assert status == 404
        assert f"citizen not found: {slug}" in body

        click_selector(f'[data-testid="citizen-start-{slug}"]')
        wait_for_index_status(slug, "up")
        click_selector(f'[data-testid="citizen-open-{slug}"]')
        wait_until(
            f"browser to reopen /citizens/{slug}",
            lambda: js("window.location.pathname") == f"/citizens/{slug}",
            timeout=10,
        )
        wait_for_terminal_connection(slug)

        after_start_marker = unique_marker("BABS_BDD_LIFECYCLE_AFTER_START")
        context.type_command_and_expect(after_start_marker, exactly_once=True)
        wait_until(
            f"{slug} transcript to contain {after_start_marker}",
            lambda: transcript_contains(slug, after_start_marker),
            timeout=10,
        )

        before_restart_stream_id = latest_transcript_output_stream_id(slug)
        click_selector('[data-testid="terminal-restart"]')
        wait_until(
            f"browser to reconnect /citizens/{slug} after restart",
            lambda: js("window.location.pathname") == f"/citizens/{slug}"
            and js("document.querySelector('[data-testid=\"connection-status\"]')?.dataset.state || ''")
            == "connected",
            timeout=20,
        )
        wait_until(
            f"{slug} hardline stream to change after restart",
            lambda: latest_transcript_output_stream_id(slug) not in (None, before_restart_stream_id),
            timeout=20,
        )
        after_restart_marker = unique_marker("BABS_BDD_LIFECYCLE_AFTER_RESTART")
        context.type_command_and_expect(after_restart_marker, exactly_once=True)
        wait_until(
            f"{slug} transcript to contain {after_restart_marker}",
            lambda: transcript_contains(slug, after_restart_marker),
            timeout=10,
        )

        assert transcript == transcript_path(slug)
        assert transcript_contains(slug, before_marker)
        assert transcript_contains(slug, after_start_marker)
        assert transcript_contains(slug, after_restart_marker)
    finally:
        cleanup_spawned_citizen(slug)


def scenario_imported_external_tmux_attach_detaches_without_killing_external_session(
    context: BabsBddContext,
) -> None:
    slug = unique_slug("bdd-import")
    external_session = unique_slug("bdd-external")
    target = f"{external_session}:0.0"
    pane_id = ""

    try:
        create_shell_citizen_from_ui(context, slug)
        context.open_path("/citizens")
        click_selector(f'[data-testid="citizen-stop-{slug}"]')
        wait_for_index_status(slug, "stopped")

        start_external_tmux_session(external_session)
        assert external_tmux_session_alive(external_session)
        pane_id = external_tmux_pane_id(external_session)

        context.open_path("/citizens/attach")
        assert_element_visible('[data-testid="attach-citizen-page"]', "attach Citizen page")
        assert_element_visible('[data-testid="attach-form"]', "attach form")
        assert "Attach tmux" in js("document.body.innerText")
        assert "Attachable" in js("document.body.innerText")
        submit_attach_form(slug, pane_id)

        wait_until(
            f"browser to open imported terminal /citizens/{slug}",
            lambda: js("window.location.pathname") == f"/citizens/{slug}",
            timeout=20,
        )
        wait_for_terminal_connection(slug)
        wait_until(
            "imported terminal badge and detach controls to render",
            lambda: "Imported" in js("document.body.innerText")
            and "External-owned" in js("document.body.innerText")
            and "Detach only" in js("document.body.innerText")
            and "Detach" in js("document.body.innerText")
            and "Reattach" in js("document.body.innerText"),
            timeout=10,
        )

        marker = unique_marker("BABS_BDD_IMPORTED_ATTACH")
        context.type_command_and_expect(marker, exactly_once=True)
        assert external_tmux_capture_contains(external_session, marker)

        click_selector('[data-testid="terminal-stop"]')
        wait_until(
            "browser to return to citizens index after external detach",
            lambda: js("window.location.pathname") == "/citizens",
            timeout=15,
        )
        wait_for_index_status(slug, "stopped")
        assert external_tmux_session_alive(external_session)

        row = sqlite_citizen_row(slug)
        assert row is not None
        metadata = json.loads(row["metadata"])
        assert metadata["hardline"]["ownership"] == "external"
        assert metadata["hardline"]["tmux"]["target"] == target
    finally:
        context.close_test_tab()
        cleanup_spawned_citizen(slug)
        cleanup_external_tmux_session(external_session)


def scenario_stopped_citizens_stay_stopped_across_managed_server_restart(context: BabsBddContext) -> None:
    if context.server_process is None:
        raise SkipScenario("BDD is using an externally managed server, so managed restart is skipped")

    stopped_slug = unique_slug("bdd-stopped")
    running_slug = unique_slug("bdd-running")

    try:
        create_shell_citizen_from_ui(context, stopped_slug)
        context.close_test_tab()
        create_shell_citizen_from_ui(context, running_slug)
        context.close_test_tab()

        context.open_path("/citizens")
        click_selector(f'[data-testid="citizen-stop-{stopped_slug}"]')
        wait_for_index_status(stopped_slug, "stopped")
        context.close_test_tab()

        context.restart_server()

        stopped_row = sqlite_citizen_row(stopped_slug)
        running_row = sqlite_citizen_row(running_slug)
        assert stopped_row is not None
        assert running_row is not None
        assert stopped_row["status"] == "stopped"
        assert running_row["status"] == "running"
        assert tmux_session_count(stopped_slug) == 0
        assert tmux_session_count(running_slug) == 1

        status, _body = http_get_status(f"{context.base_url}/citizens/{stopped_slug}", timeout=5)
        assert status == 404

        context.connect_citizen(running_slug)
        context.type_command_and_expect(unique_marker("BABS_BDD_RUNNING_AFTER_RESTART"), exactly_once=True)
    finally:
        cleanup_spawned_citizen(stopped_slug)
        cleanup_spawned_citizen(running_slug)


def scenario_terminal_fills_viewport(context: BabsBddContext) -> None:
    context.connect_citizen("sentinel")

    try:
        before = terminal_geometry()
        assert before["width"] > 400
        assert before["height"] > 250
        assert_terminal_mode_geometry(before)

        cdp(
            "Emulation.setDeviceMetricsOverride",
            width=1200,
            height=700,
            deviceScaleFactor=1,
            mobile=False,
        )
        wait(1)

        after = terminal_geometry()
        if abs(after["viewport_width"] - 1200) > 4:
            raise SkipScenario(
                f"CDP viewport override did not apply in this browser-harness session: {after}"
            )

        assert abs(after["width"] - 1200) <= 4, after
        assert_terminal_mode_geometry(after)
        assert rendered_xterm_row_count() > 0

        context.connect_citizen("sentinel", full=True)
        full = terminal_geometry()
        assert abs(full["top"]) <= 2, full
        assert abs(full["width"] - full["viewport_width"]) <= 4, full
        assert abs(full["height"] - full["viewport_height"]) <= 4, full
        assert_no_element('[data-testid="terminal-chrome"]', "terminal chrome in full mode")
    finally:
        cdp("Emulation.clearDeviceMetricsOverride")


def scenario_mobile_pwa_shell(context: BabsBddContext) -> None:
    ticket_id = allocate_ticket_id(context.tickets_root)
    slug = unique_slug("bdd-mobile")

    try:
        write_ticket(context.tickets_root, ticket_id, "BDD Mobile Ticket", "Visible in phone layout.")
        create_shell_citizen_from_ui(context, slug)
        set_mobile_viewport()

        status, body = http_get_status(f"{context.base_url}/manifest.webmanifest", timeout=5)
        assert status == 200
        manifest = json.loads(body)
        assert manifest["display"] == "standalone"
        assert any(icon["sizes"] == "192x192" for icon in manifest["icons"])
        assert any(icon["sizes"] == "512x512" for icon in manifest["icons"])

        context.open_path("/tickets")
        assert_service_worker_registration_noops_without_secure_context()
        assert_element_visible('[data-testid="tickets-index"]', "tickets index")
        assert_element_visible('[data-testid="tickets-new"]', "new ticket button")
        assert_element_visible('[data-testid="tickets-nav-citizens"]', "tickets citizens nav")
        wait_until("ticket row to render in mobile layout", lambda: ticket_id in js("document.body.innerText"))
        assert_no_horizontal_overflow("tickets mobile page")
        assert_touch_targets(".tickets-nav .button", "ticket nav buttons")
        if js("Boolean(document.querySelector('[data-testid=\"remote-peer-tickets\"]'))"):
            assert_element_visible('[data-testid="remote-peer-tickets"]', "remote ticket section")
            assert_no_horizontal_overflow("remote tickets mobile section")

        context.open_path("/citizens")
        assert_element_visible('[data-testid="citizens-index"]', "citizens index")
        assert_element_visible('[data-testid="citizens-nav-tickets"]', "citizens tickets nav")
        assert_no_horizontal_overflow("citizens mobile page")
        assert_touch_targets(".citizens-nav .button", "citizens nav buttons")
        assert_touch_targets(".citizen-actions .button", "citizen action buttons", required=False)
        if js("Boolean(document.querySelector('[data-testid=\"remote-peer-citizens\"]'))"):
            assert_element_visible('[data-testid="remote-peer-citizens"]', "remote citizen section")
            assert_no_horizontal_overflow("remote citizens mobile section")

        context.connect_citizen(slug, full=True)
        full = terminal_geometry()
        assert abs(full["width"] - full["viewport_width"]) <= 4, full
        assert abs(full["height"] - full["viewport_height"]) <= 4, full
        assert_no_element('[data-testid="terminal-chrome"]', "terminal chrome in mobile full mode")
    finally:
        cdp("Emulation.clearDeviceMetricsOverride")
        cleanup_ticket(context.tickets_root, ticket_id)
        cleanup_spawned_citizen(slug)


def scenario_citizen_home_browser_edit_and_external_refresh(context: BabsBddContext) -> None:
    slug = unique_slug("bdd-home")
    initial_marker = unique_marker("BABS_BDD_HOME_INITIAL")
    browser_marker = unique_marker("BABS_BDD_HOME_BROWSER_SAVE")
    external_marker = unique_marker("BABS_BDD_HOME_EXTERNAL_REFRESH")

    try:
        create_shell_citizen_from_ui_without_terminal(context, slug)
        write_knowledge_file(slug, "Readme.md", f"# Browser Home\n\n{initial_marker}\n")

        context.open_path(f"/citizens/{slug}")
        wait_until(
            "LiveView socket to connect on Citizen Home",
            lambda: bool(js("window.liveSocket?.isConnected?.() || false")),
            timeout=10,
        )
        assert_element_visible('[data-testid="citizen-home"]', "Citizen Home tab")
        assert_element_visible('[data-testid="knowledge-rendered"]', "rendered Knowledge Home")
        wait_until(
            "initial Readme content to render",
            lambda: initial_marker in js("document.body.innerText"),
            timeout=10,
        )
        assert_no_horizontal_overflow("Citizen Home BDD initial page")

        click_selector('[data-testid="knowledge-edit-button"]')
        assert_element_visible('[data-testid="knowledge-edit-form"]', "Knowledge edit form")
        submit_home_edit(f"# Browser Saved\n\n{browser_marker}\n")

        wait_until(
            "browser-saved Readme to render",
            lambda: browser_marker in js("document.body.innerText")
            and "Saved Readme.md" in js("document.body.innerText"),
            timeout=15,
        )
        assert knowledge_file_path(slug, "Readme.md").read_text(encoding="utf-8") == (
            f"# Browser Saved\n\n{browser_marker}\n"
        )
        assert_no_element('[data-testid="knowledge-edit-form"]', "Knowledge edit form after save")

        external_content = f"# External Edit\n\n{external_marker}\n"
        last_external_write_at = 0.0

        def external_edit_refreshed() -> bool:
            nonlocal last_external_write_at

            body = js("document.body.innerText")
            if external_marker in body and browser_marker not in body:
                return True

            now = time.monotonic()
            if now - last_external_write_at >= 0.5:
                write_knowledge_file(slug, "Readme.md", external_content)
                last_external_write_at = now

            return False

        write_knowledge_file(slug, "Readme.md", external_content)
        last_external_write_at = time.monotonic()
        wait_until(
            "external Readme edit to refresh through Knowledge watcher",
            external_edit_refreshed,
            timeout=30,
        )
        assert_no_horizontal_overflow("Citizen Home BDD refreshed page")
    finally:
        cleanup_spawned_citizen(slug)
        shutil.rmtree(knowledge_root() / slug, ignore_errors=True)


def scenario_mobile_ticket_diff_approval(context: BabsBddContext) -> None:
    ticket_id = allocate_ticket_id(context.tickets_root)
    slug = unique_slug("bdd-diff")
    marker = unique_marker("BABS_BDD_MOBILE_DIFF")
    long_line = f"{marker}-" + ("mobile-contained-scroll-" * 18)

    try:
        workspace = create_git_diff_workspace(slug, long_line)
        upsert_sqlite_citizen(slug, f"BDD {slug}", workspace)
        write_ticket(
            context.tickets_root,
            ticket_id,
            "BDD Mobile Diff Approval",
            "Approve this ticket after reading the mobile diff.",
            state="pending_approval",
            assignees=[slug],
        )

        set_mobile_viewport()
        context.open_path(f"/tickets/{ticket_id}")
        set_mobile_viewport()
        wait_until(
            "mobile viewport to apply on ticket detail",
            lambda: abs(page_info()["w"] - 390) <= 4,
            timeout=5,
        )
        wait_until(
            "LiveView socket to connect on mobile diff detail",
            lambda: bool(js("window.liveSocket?.isConnected?.() || false")),
            timeout=10,
        )

        assert_element_visible('[data-testid="ticket-review-diff"]', "mobile ticket diff panel")
        assert_element_visible('[data-testid="git-diff-component"]', "mobile git diff component")
        assert_element_visible('[data-testid="ticket-approve"]', "mobile approve button")
        assert_element_visible('[data-testid="ticket-reject"]', "mobile reject button")
        wait_until(
            "mobile diff to render workspace file and long addition",
            lambda: "README.md" in js("document.body.innerText") and marker in js("document.body.innerText"),
            timeout=15,
        )

        assert js("Boolean(document.querySelector('[data-line-kind=\"addition\"]'))")
        assert_mobile_diff_containment("mobile ticket diff detail")
        assert_touch_targets(
            '[data-testid="ticket-approve"], [data-testid="ticket-reject"]',
            "mobile approval controls",
        )

        click_selector('[data-testid="ticket-approve"]')
        wait_until(
            "mobile approval to close the Ticket",
            lambda: "Approved ticket" in js("document.body.innerText")
            and "closed" in js("document.body.innerText"),
            timeout=20,
        )
        assert_no_element('[data-testid="ticket-review-diff"]', "diff panel after approval")
        wait_until(
            "approved event to be written to Ticket history",
            lambda: history_has_event(
                context.tickets_root,
                ticket_id,
                lambda event: event.get("event") == "approved",
            ),
            timeout=10,
        )
    finally:
        cdp("Emulation.clearDeviceMetricsOverride")
        cleanup_ticket(context.tickets_root, ticket_id)
        cleanup_spawned_citizen(slug)


def scenario_seed_citizens_connect_when_available(context: BabsBddContext) -> None:
    command_by_slug = {"clare": "claude", "dylan": "codex", "elena": "copilot"}
    checked = 0

    for slug, command in command_by_slug.items():
        if not command_exists(command):
            print(f"  SKIP {slug}: {command} CLI is not installed")
            continue

        status, _body = http_get_status(f"{context.base_url}/citizens/{slug}", timeout=5)
        if status == 404:
            print(f"  SKIP {slug}: citizen is not running")
            continue

        context.connect_citizen(slug)
        wait_until(
            f"{slug} terminal to render content",
            lambda: len(terminal_text().strip()) > 0,
            timeout=15,
        )
        checked += 1

    if checked == 0:
        raise SkipScenario("no optional seed CLI commands are installed")


def scenario_missing_citizen_returns_404(context: BabsBddContext) -> None:
    missing_path = "/citizens/babs-bdd-missing"
    status, body = http_get_status(f"{context.base_url}{missing_path}", timeout=5)
    assert status == 404
    assert "citizen not found: babs-bdd-missing" in body

    context.open_path(missing_path)
    assert "citizen not found: babs-bdd-missing" in js("document.body.innerText")


def scenario_ticket_billboard_list_shows_manual_ticket(context: BabsBddContext) -> None:
    ticket_id = allocate_ticket_id(context.tickets_root)

    try:
        write_ticket(context.tickets_root, ticket_id, "BDD Billboard Ticket", "Manual Ticket body.")

        context.open_path("/tickets")
        assert_element_visible("[data-testid='tickets-index']", "tickets index")
        assert_element_visible(f"[data-testid='ticket-row-{ticket_id}']", f"{ticket_id} row")
        assert "BDD Billboard Ticket" in js("document.body.innerText")
        assert js("Boolean(document.querySelector('[data-testid=\"tickets-refresh\"] [data-icon=\"refresh\"]'))")
        assert js("document.querySelector('[data-testid=\"tickets-refresh\"]')?.getAttribute('aria-label')") == "Refresh tickets"
        assert js("Boolean(document.querySelector('[data-testid=\"tickets-nav-citizens\"] [data-icon=\"users\"]'))")
    finally:
        cleanup_ticket(context.tickets_root, ticket_id)


def scenario_ticket_external_edit_refreshes_index(context: BabsBddContext) -> None:
    ticket_id = allocate_ticket_id(context.tickets_root)

    try:
        write_ticket(context.tickets_root, ticket_id, "BDD Refresh Before", "Manual Ticket body.")
        context.open_path("/tickets")
        assert_element_visible(f"[data-testid='ticket-row-{ticket_id}']", f"{ticket_id} row before edit")

        path = ticket_markdown_path(context.tickets_root, ticket_id)
        content = path.read_text()
        path.write_text(content.replace("BDD Refresh Before", "BDD Refresh After"))

        wait_until(
            "ticket index to refresh after external edit",
            lambda: "BDD Refresh After" in js("document.body.innerText"),
            timeout=10,
        )
    finally:
        cleanup_ticket(context.tickets_root, ticket_id)


def scenario_ticket_detail_renders_body_and_history(context: BabsBddContext) -> None:
    ticket_id = allocate_ticket_id(context.tickets_root)

    try:
        write_ticket(context.tickets_root, ticket_id, "BDD Detail Ticket", "Detail body from BDD.")
        context.open_path(f"/tickets/{ticket_id}")
        assert_element_visible("[data-testid='ticket-detail']", "ticket detail")
        assert "BDD Detail Ticket" in js("document.body.innerText")
        assert "Detail body from BDD." in js("document.body.innerText")
        assert "created" in js("document.body.innerText")
        assert_element_visible("[data-testid='ticket-history-event']", "ticket history event")
    finally:
        cleanup_ticket(context.tickets_root, ticket_id)


def scenario_ticket_new_form_creates_chat_ready_detail(context: BabsBddContext) -> None:
    title = f"BDD New Ticket {int(time.time() * 1000)}"
    body = "Created from the browser-harness new Ticket form."
    ticket_id = None

    try:
        context.open_path("/tickets")
        assert_element_visible("[data-testid='tickets-index']", "tickets index")
        assert_element_visible('[data-testid="tickets-new"]', "new Ticket button")
        assert js("Boolean(document.querySelector('[data-testid=\"tickets-new\"] [data-icon=\"plus\"]'))")

        click_selector('[data-testid="tickets-new"]')
        wait_until(
            "browser to open new Ticket form",
            lambda: js("window.location.pathname") == "/tickets/new",
            timeout=10,
        )
        assert_element_visible('[data-testid="new-ticket-form"]', "new Ticket form")
        wait_until(
            "LiveView socket to connect on new Ticket form",
            lambda: bool(js("window.liveSocket?.isConnected?.() || false")),
            timeout=10,
        )

        submit_new_ticket_form(title, "high", body)
        wait_until(
            "browser to redirect to created Ticket detail",
            lambda: str(js("window.location.pathname") or "").startswith("/tickets/T-"),
            timeout=20,
        )
        ticket_id = str(js("window.location.pathname")).split("/")[-1]

        assert_element_visible("[data-testid='ticket-detail']", "created Ticket detail")
        assert title in js("document.body.innerText")
        assert body in js("document.body.innerText")
        assert_element_visible('[data-testid="ticket-detail-chat"]', "Ticket chat")
        assert_element_visible('[data-testid="ticket-comments-empty"]', "empty Ticket comments state")
        assert_element_visible('[data-testid="ticket-comment-form"]', "Ticket chat composer")
        assert js("Boolean(document.querySelector('[data-testid=\"ticket-comment\"] [data-icon=\"send\"]'))")

        events = [event["event"] for event in ticket_history_events(context.tickets_root, ticket_id)]
        assert "created" in events
    finally:
        if ticket_id is not None:
            cleanup_ticket(context.tickets_root, ticket_id)


def scenario_ticket_chat_shows_captured_citizen_reply(context: BabsBddContext) -> None:
    ticket_id = allocate_ticket_id(context.tickets_root)
    reply = f"BDD captured Citizen reply {int(time.time() * 1000)}."

    try:
        write_ticket(context.tickets_root, ticket_id, "BDD Captured Reply Ticket", "Capture reply body.")
        context.open_path(f"/tickets/{ticket_id}")
        assert_element_visible("[data-testid='ticket-detail']", "ticket detail")
        assert_element_visible('[data-testid="ticket-comments-empty"]', "empty Ticket comments state")

        append_ticket_history_event(
            context.tickets_root,
            ticket_id,
            {
                "ts": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
                "event": "comment",
                "by": "clare",
                "ticket_id": ticket_id,
                "body": reply,
            },
        )

        wait_until(
            "captured Citizen reply to appear in chat",
            lambda: ticket_comment_message_contains(reply)
            and "clare" in js("document.body.innerText"),
            timeout=15,
        )

        events = ticket_history_events(context.tickets_root, ticket_id)
        assert any(
            event.get("event") == "comment" and event.get("by") == "clare" and event.get("body") == reply
            for event in events
        )
    finally:
        cleanup_ticket(context.tickets_root, ticket_id)


def scenario_ticket_inspection_panel_shows_auto_approval(context: BabsBddContext) -> None:
    ticket_id = allocate_ticket_id(context.tickets_root)

    try:
        write_ticket(
            context.tickets_root,
            ticket_id,
            "BDD Auto Approved Ticket",
            "Inspection panel should show approval.",
            state="closed",
            assignees=["clare"],
            metadata=auto_inspection_metadata(["dylan"], "single"),
        )
        append_inspection_history(context.tickets_root, ticket_id, ["dylan"], [decision("dylan", "approve", "Dylan approves.")], "approved")

        context.open_path(f"/tickets/{ticket_id}")
        assert_element_visible("[data-testid='ticket-inspection-panel']", "inspection panel")
        assert "Auto single" in js("document.body.innerText")
        assert "Dylan approves." in js("document.body.innerText")
        assert "approved" in js("document.body.innerText")
        assert_element_visible("[data-testid='ticket-inspector-dylan']", "dylan inspection row")
    finally:
        cleanup_ticket(context.tickets_root, ticket_id)


def scenario_ticket_inspection_panel_shows_rejected_decision(context: BabsBddContext) -> None:
    ticket_id = allocate_ticket_id(context.tickets_root)

    try:
        write_ticket(
            context.tickets_root,
            ticket_id,
            "BDD Needs Changes Ticket",
            "Inspection panel should show rejection feedback.",
            state="in_progress",
            assignees=["clare"],
            metadata=auto_inspection_metadata(["dylan"], "single"),
        )
        append_inspection_history(
            context.tickets_root,
            ticket_id,
            ["dylan"],
            [decision("dylan", "needs_changes", "Add tests.", findings=[{"path": "README.md", "line": 12}])],
            "rejected",
        )

        context.open_path(f"/tickets/{ticket_id}")
        assert_element_visible("[data-testid='ticket-inspection-panel']", "inspection panel")
        assert "Auto single" in js("document.body.innerText")
        assert "Needs changes" in js("document.body.innerText")
        assert "Add tests." in js("document.body.innerText")
        assert "README.md:12" in js("document.body.innerText")
        assert "rejected" in js("document.body.innerText")
    finally:
        cleanup_ticket(context.tickets_root, ticket_id)


def scenario_ticket_inspection_panel_shows_council_status(context: BabsBddContext) -> None:
    ticket_id = allocate_ticket_id(context.tickets_root)

    try:
        write_ticket(
            context.tickets_root,
            ticket_id,
            "BDD Council Ticket",
            "Inspection panel should show council rows.",
            state="pending_approval",
            assignees=["clare"],
            metadata=auto_inspection_metadata(["dylan", "elena"], "council"),
        )
        append_inspection_history(
            context.tickets_root,
            ticket_id,
            ["dylan", "elena"],
            [decision("dylan", "approve", "Dylan approves.")],
            None,
        )

        context.open_path(f"/tickets/{ticket_id}")
        assert_element_visible("[data-testid='ticket-inspection-panel']", "inspection panel")
        assert "Auto council" in js("document.body.innerText")
        assert_element_visible("[data-testid='ticket-inspector-dylan']", "dylan inspection row")
        assert_element_visible("[data-testid='ticket-inspector-elena']", "elena inspection row")
        assert "Prompt delivered" in js("document.body.innerText")
        assert_element_visible("[data-testid='ticket-approve']", "human approve override")
        assert_element_visible("[data-testid='ticket-reject-form']", "human reject override")
    finally:
        cleanup_ticket(context.tickets_root, ticket_id)


def scenario_mayor_proposal_approval_creates_child_tickets(context: BabsBddContext) -> None:
    proposal_id = f"prop_bdd_{int(time.time() * 1000)}"
    child_title = f"BDD Mayor Child {int(time.time() * 1000)}"
    ticket_id = None
    created_child_ids: list[str] = []

    try:
        ticket_id = create_mayor_proposal_ticket_once(
            context.tickets_root,
            proposal_id,
            child_title,
        )

        context.open_path(f"/tickets/{ticket_id}")
        wait_until(
            "LiveView socket to connect on Mayor proposal detail",
            lambda: bool(js("window.liveSocket?.isConnected?.() || false")),
            timeout=10,
        )
        assert_element_visible('[data-testid="ticket-proposal-panel"]', "Mayor proposal panel")
        assert_element_visible('[data-testid="ticket-proposal-approve"]', "Mayor proposal approve button")
        assert child_title in js("document.body.innerText")
        click_selector('[data-testid="ticket-proposal-approve"]')

        wait_until(
            "Mayor approval to show created child Ticket links",
            lambda: "Approved proposal" in js("document.body.innerText")
            and "Created child Tickets" in js("document.body.innerText")
            and "routing failed" in js("document.body.innerText"),
            timeout=20,
        )

        events = ticket_history_events(context.tickets_root, ticket_id)
        created = next(event for event in events if event.get("event") == "mayor_children_created")
        approved = next(event for event in events if event.get("event") == "mayor_proposal_approved")
        assert approved["proposal_id"] == proposal_id
        assert created["proposal_id"] == proposal_id
        assert len(created["children"]) == 1
        child = created["children"][0]
        created_child_ids = [child["ticket_id"]]
        assert child["title"] == child_title
        assert child["routing"]["status"] == "failed"
        assert_element_visible(
            f'[data-testid="ticket-proposal-created-child-{child["ticket_id"]}"]',
            "created Mayor child Ticket row",
        )
        assert f'href="/tickets/{child["ticket_id"]}' in js("document.body.innerHTML")
        assert ticket_markdown_path(context.tickets_root, child["ticket_id"]).exists()
        child_markdown = ticket_markdown_path(context.tickets_root, child["ticket_id"]).read_text()
        assert f'parent_ticket: "{ticket_id}"' in child_markdown
        assert 'assigner: "mayor:flora"' in child_markdown
    finally:
        if ticket_id is not None:
            cleanup_ticket(context.tickets_root, ticket_id)
        for child_id in created_child_ids:
            cleanup_ticket(context.tickets_root, child_id)


def scenario_ticket_new_form_captures_elena_copilot_jsonl_reply(context: BabsBddContext) -> None:
    title = f"BDD Elena Copilot Ticket {int(time.time() * 1000)}"
    body = "Created from browser-harness to validate Elena Copilot JSONL capture."
    reply = f"hello from Elena Copilot JSONL {int(time.time() * 1000)}"
    ticket_id = None
    copilot_home = tmp_bdd_dir("copilot-home")

    try:
        context.open_path("/tickets")
        assert_element_visible('[data-testid="tickets-new"]', "new Ticket button")
        click_selector('[data-testid="tickets-new"]')
        wait_until(
            "browser to open new Ticket form for Elena capture",
            lambda: js("window.location.pathname") == "/tickets/new",
            timeout=10,
        )
        wait_until(
            "LiveView socket to connect on Elena capture Ticket form",
            lambda: bool(js("window.liveSocket?.isConnected?.() || false")),
            timeout=10,
        )

        submit_new_ticket_form(title, "normal", body)
        wait_until(
            "browser to redirect to created Elena capture Ticket detail",
            lambda: str(js("window.location.pathname") or "").startswith("/tickets/T-"),
            timeout=20,
        )
        ticket_id = str(js("window.location.pathname")).split("/")[-1]
        assert_element_visible("[data-testid='ticket-detail']", "Elena capture Ticket detail")
        assert_element_visible('[data-testid="ticket-comments-empty"]', "empty Ticket comments state")

        started_at = utc_now_iso()
        events_path = write_copilot_events(copilot_home, ticket_id, started_at, reply)
        run_elena_reply_capture_once(context.tickets_root, ticket_id, started_at, events_path, copilot_home)

        wait_until(
            "Elena Copilot JSONL reply to appear in Ticket chat",
            lambda: ticket_comment_message_contains(reply) and "elena" in js("document.body.innerText"),
            timeout=15,
        )

        events = ticket_history_events(context.tickets_root, ticket_id)
        assert any(
            event.get("event") == "comment" and event.get("by") == "elena" and event.get("body") == reply
            for event in events
        )
    finally:
        if ticket_id is not None:
            cleanup_ticket(context.tickets_root, ticket_id)
        shutil.rmtree(copilot_home, ignore_errors=True)


def scenario_ticket_chat_shows_direct_cli_fake_reply(context: BabsBddContext) -> None:
    ticket_id = allocate_ticket_id(context.tickets_root)
    reply = f"BDD direct CLI fake reply {int(time.time() * 1000)}."

    try:
        write_ticket(context.tickets_root, ticket_id, "BDD Direct CLI Ticket", "Direct CLI body.")
        context.open_path(f"/tickets/{ticket_id}")
        assert_element_visible("[data-testid='ticket-detail']", "direct CLI Ticket detail")
        assert_element_visible('[data-testid="ticket-comments-empty"]', "empty Ticket comments state")

        run_fake_direct_turn_once(context.tickets_root, ticket_id, reply)

        wait_until(
            "direct CLI fake reply to appear in Ticket chat",
            lambda: ticket_comment_message_contains(reply) and "dylan" in js("document.body.innerText"),
            timeout=15,
        )

        events = ticket_history_events(context.tickets_root, ticket_id)
        assert any(
            event.get("event") == "turn_execution_started" and event.get("backend") == "direct_cli"
            for event in events
        )
        assert any(
            event.get("event") == "turn_delivered"
            and event.get("backend") == "direct_cli"
            and event.get("provider_session_id")
            for event in events
        )
        assert any(
            event.get("event") == "comment" and event.get("by") == "dylan" and event.get("body") == reply
            for event in events
        )
    finally:
        cleanup_ticket(context.tickets_root, ticket_id)


def scenario_direct_cli_backend_ui_creation_and_assignment(context: BabsBddContext) -> None:
    slug = unique_slug("bdd-direct")
    ticket_id = allocate_ticket_id(context.tickets_root)
    reply = os.environ.get("BABS_BDD_DIRECT_REPLY", "BDD direct CLI UI reply.")

    try:
        context.open_path("/citizens/new")
        assert_element_visible('[data-testid="new-citizen-form"]', "new citizen form")
        wait_until(
            "LiveView socket to connect",
            lambda: bool(js("window.liveSocket?.isConnected?.() || false")),
            timeout=10,
        )
        submit_new_citizen_form(slug, f"BDD {slug}", "copilot-cli", slug, "direct_cli")
        wait_until(
            "browser to redirect to /citizens after direct creation",
            lambda: js("window.location.pathname") == "/citizens",
            timeout=15,
        )
        wait_for_index_status(slug, "stopped")
        assert "Direct CLI" in js(f"document.querySelector('[data-testid=\"citizen-row-{slug}\"]')?.innerText || ''")
        if tmux_session_alive(f"babs-{slug}"):
            raise AssertionError(f"direct_cli UI creation unexpectedly started tmux session babs-{slug}")

        write_ticket(context.tickets_root, ticket_id, "BDD Direct UI Ticket", f"Direct UI body for {slug}.")
        context.open_path(f"/tickets/{ticket_id}")
        wait_until(
            "LiveView socket to connect on direct Ticket detail",
            lambda: bool(js("window.liveSocket?.isConnected?.() || false")),
            timeout=10,
        )
        assert_element_visible(f'[data-testid="ticket-assign-{slug}"]', f"assign button for {slug}")
        assert "Direct CLI" in js(f"document.querySelector('[data-testid=\"ticket-assign-{slug}\"]')?.innerText || ''")
        click_selector(f'[data-testid="ticket-assign-{slug}"]')

        wait_until(
            "direct CLI UI reply to appear in Ticket chat",
            lambda: reply in js("document.body.innerText"),
            timeout=20,
        )
        wait_until(
            "direct CLI UI assignment to record direct turn",
            lambda: history_has_event(
                context.tickets_root,
                ticket_id,
                lambda event: event.get("event") == "turn_execution_started"
                and event.get("backend") == "direct_cli"
                and event.get("to") == slug,
            ),
            timeout=20,
        )
        if tmux_session_alive(f"babs-{slug}"):
            raise AssertionError(f"direct_cli Ticket assignment unexpectedly started tmux session babs-{slug}")
    finally:
        cleanup_ticket(context.tickets_root, ticket_id)
        cleanup_spawned_citizen(slug)


def scenario_role_routed_ticket_flow(context: BabsBddContext) -> None:
    slug = unique_slug("bdd-role")
    role = slug
    title = f"BDD Role Routed Ticket {int(time.time() * 1000)}"
    body = f"BDD role-routed body for {slug}."
    reply = os.environ.get("BABS_BDD_DIRECT_REPLY", "BDD direct CLI UI reply.")
    ticket_id = None

    try:
        context.direct_prompts_path.unlink(missing_ok=True)

        context.open_path("/citizens/new")
        assert_element_visible('[data-testid="new-citizen-form"]', "new citizen form")
        wait_until(
            "LiveView socket to connect",
            lambda: bool(js("window.liveSocket?.isConnected?.() || false")),
            timeout=10,
        )
        submit_new_citizen_form(
            slug,
            f"BDD {slug}",
            "copilot-cli",
            slug,
            "direct_cli",
            roles=f"{role}\nInspector",
        )
        wait_until(
            "browser to redirect to /citizens after role Citizen creation",
            lambda: js("window.location.pathname") == "/citizens",
            timeout=15,
        )
        wait_for_index_status(slug, "stopped")
        assert_element_visible(f'[data-testid="citizen-role-{slug}-0"]', f"first role for {slug}")
        assert role in js(f"document.querySelector('[data-testid=\"citizen-row-{slug}\"]')?.innerText || ''")
        assert "inspector" in js(f"document.querySelector('[data-testid=\"citizen-row-{slug}\"]')?.innerText || ''")

        context.open_path("/tickets")
        assert_element_visible('[data-testid="tickets-new"]', "new Ticket button")
        click_selector('[data-testid="tickets-new"]')
        wait_until(
            "browser to open new role Ticket form",
            lambda: js("window.location.pathname") == "/tickets/new",
            timeout=10,
        )
        wait_until(
            "LiveView socket to connect on role Ticket form",
            lambda: bool(js("window.liveSocket?.isConnected?.() || false")),
            timeout=10,
        )
        assert_element_visible('[data-testid="ticket-assignee-role"]', "Ticket assignee role select")
        submit_new_ticket_form(title, "normal", body, assignee_role=role)
        wait_until(
            "browser to redirect to created role Ticket detail",
            lambda: str(js("window.location.pathname") or "").startswith("/tickets/T-"),
            timeout=20,
        )
        ticket_id = str(js("window.location.pathname")).split("/")[-1]

        assert_element_visible("[data-testid='ticket-detail']", "role-routed Ticket detail")
        assert_element_visible(f'[data-testid="ticket-assign-role-{role}"]', "role route button")
        click_selector(f'[data-testid="ticket-assign-role-{role}"]')

        wait_until(
            "role-routed direct CLI reply to appear in Ticket chat",
            lambda: reply in js("document.body.innerText"),
            timeout=20,
        )
        wait_until(
            "role-routed assignment to record direct turn",
            lambda: history_has_event(
                context.tickets_root,
                ticket_id,
                lambda event: event.get("event") == "turn_execution_started"
                and event.get("backend") == "direct_cli"
                and event.get("to") == slug,
            ),
            timeout=20,
        )

        assert f"ticket-unassign-{slug}" in js("document.body.innerHTML")
        assert f"assigned to {slug} via role {role}" in js("document.body.innerText")
        assert not tmux_session_alive(f"babs-{slug}")
        assert any(body in event.get("prompt", "") for event in direct_prompt_events(context.direct_prompts_path))

        events = ticket_history_events(context.tickets_root, ticket_id)
        assert any(
            event.get("event") == "assigned"
            and event.get("to") == [slug]
            and event.get("via_role") == role
            for event in events
        )
    finally:
        if ticket_id is not None:
            cleanup_ticket(context.tickets_root, ticket_id)
        cleanup_spawned_citizen(slug)


def scenario_direct_cli_compact_prompt(context: BabsBddContext) -> None:
    slug = unique_slug("bdd-compact")
    ticket_id = allocate_ticket_id(context.tickets_root)
    body = f"BDD compact full body for {slug}."
    first_comment = f"BDD compact first comment for {slug}."
    second_comment = f"BDD compact second comment for {slug}."

    try:
        context.direct_prompts_path.unlink(missing_ok=True)

        context.open_path("/citizens/new")
        assert_element_visible('[data-testid="new-citizen-form"]', "new citizen form")
        wait_until(
            "LiveView socket to connect",
            lambda: bool(js("window.liveSocket?.isConnected?.() || false")),
            timeout=10,
        )
        submit_new_citizen_form(slug, f"BDD {slug}", "copilot-cli", slug, "direct_cli")
        wait_until(
            "browser to redirect to /citizens after compact direct creation",
            lambda: js("window.location.pathname") == "/citizens",
            timeout=15,
        )
        wait_for_index_status(slug, "stopped")

        write_ticket(context.tickets_root, ticket_id, "BDD Compact Direct Ticket", body)
        context.open_path(f"/tickets/{ticket_id}")
        wait_until(
            "LiveView socket to connect on compact direct Ticket detail",
            lambda: bool(js("window.liveSocket?.isConnected?.() || false")),
            timeout=10,
        )
        click_selector(f'[data-testid="ticket-assign-{slug}"]')
        wait_until(
            "direct assignment prompt to be captured",
            lambda: len(direct_prompt_events(context.direct_prompts_path)) >= 1,
            timeout=20,
        )

        submit_ticket_comment(first_comment)
        wait_until(
            "first compact direct comment prompt to be captured",
            lambda: len(direct_prompt_events(context.direct_prompts_path)) >= 2,
            timeout=20,
        )

        submit_ticket_comment(second_comment)
        wait_until(
            "second compact direct comment prompt to be captured",
            lambda: len(direct_prompt_events(context.direct_prompts_path)) >= 3,
            timeout=20,
        )

        prompts = direct_prompt_events(context.direct_prompts_path)
        assignment_prompt = prompts[0]["prompt"]
        first_prompt = prompts[1]["prompt"]
        second_prompt = prompts[2]["prompt"]

        assert body in assignment_prompt
        assert prompts[1]["resume"] is True
        assert prompts[2]["resume"] is True
        assert prompts[1]["provider_session_id"] == prompts[2]["provider_session_id"]

        assert first_comment in first_prompt
        assert f"BABS_REPLY {ticket_id}:" in first_prompt
        assert body not in first_prompt

        assert second_comment in second_prompt
        assert f"BABS_REPLY {ticket_id}:" in second_prompt
        assert body not in second_prompt
        assert first_comment not in second_prompt
        assert "Recent visible chat messages" not in second_prompt
    finally:
        cleanup_ticket(context.tickets_root, ticket_id)
        cleanup_spawned_citizen(slug)


def scenario_ticket_assignment_hides_stale_sqlite_citizen(context: BabsBddContext) -> None:
    slug = unique_slug("bdd-stale")
    ticket_id = allocate_ticket_id(context.tickets_root)

    try:
        create_shell_citizen_from_ui(context, slug)
        context.close_test_tab()
        wait_until("stale Citizen row to exist in SQLite", lambda: sqlite_citizen_row(slug) is not None, timeout=10)
        citizen_toml_path(slug).unlink()

        write_ticket(context.tickets_root, ticket_id, "BDD Stale Citizen Ticket", f"Stale assignment body for {slug}.")
        context.open_path(f"/tickets/{ticket_id}")
        assert_element_visible("[data-testid='ticket-detail']", "stale Citizen Ticket detail")
        assert_no_element(f'[data-testid="ticket-assign-{slug}"]', f"assign button for stale Citizen {slug}")
    finally:
        cleanup_ticket(context.tickets_root, ticket_id)
        cleanup_spawned_citizen(slug)


def scenario_citizens_index_hides_stale_sqlite_citizen(context: BabsBddContext) -> None:
    slug = unique_slug("bdd-stale-index")
    visible_slug = unique_slug("bdd-visible-index")

    try:
        create_shell_citizen_from_ui(context, visible_slug)
        context.close_test_tab()
        create_shell_citizen_from_ui(context, slug)
        context.close_test_tab()
        wait_until("stale index Citizen row to exist in SQLite", lambda: sqlite_citizen_row(slug) is not None, timeout=10)
        citizen_toml_path(slug).unlink()

        context.open_path("/citizens")
        assert_element_visible("[data-testid='citizens-index']", "citizens index")
        assert_element_visible(f'[data-testid="citizen-row-{visible_slug}"]', f"row for configured Citizen {visible_slug}")
        assert_no_element(f'[data-testid="citizen-row-{slug}"]', f"row for stale Citizen {slug}")
    finally:
        cleanup_spawned_citizen(slug)
        cleanup_spawned_citizen(visible_slug)


def scenario_malformed_ticket_is_visible(context: BabsBddContext) -> None:
    ticket_id = allocate_ticket_id(context.tickets_root)

    try:
        context.tickets_root.mkdir(parents=True, exist_ok=True)
        ticket_markdown_path(context.tickets_root, ticket_id).write_text("not frontmatter")

        context.open_path("/tickets")
        assert_element_visible("[data-testid='ticket-group-invalid']", "invalid ticket group")
        assert_element_visible("[data-testid='ticket-invalid-row']", "invalid ticket row")
        assert f"{ticket_id}.md" in js("document.body.innerText")
    finally:
        cleanup_ticket(context.tickets_root, ticket_id)


def scenario_ticket_assignment_auto_starts_stopped_citizen(context: BabsBddContext) -> None:
    slug = unique_slug("bdd-ticket")
    ticket_id = allocate_ticket_id(context.tickets_root)
    body = f"BDD assignment body for {slug}."

    try:
        create_shell_citizen_from_ui(context, slug)
        context.open_path("/citizens")
        click_selector(f'[data-testid="citizen-stop-{slug}"]')
        wait_for_index_status(slug, "stopped")

        write_ticket(context.tickets_root, ticket_id, "BDD Assign Ticket", body)
        context.open_path(f"/tickets/{ticket_id}")
        wait_until(
            "LiveView socket to connect on ticket detail",
            lambda: bool(js("window.liveSocket?.isConnected?.() || false")),
            timeout=10,
        )
        assert_element_visible(f'[data-testid="ticket-assign-{slug}"]', f"assign button for {slug}")
        assert js(
            f"Boolean(document.querySelector('[data-testid=\"ticket-assign-{slug}\"] [data-icon=\"user-plus\"]'))"
        )

        click_selector(f'[data-testid="ticket-assign-{slug}"]')

        wait_until(
            "ticket detail to show assignment success",
            lambda: f"Assigned to {slug}" in js("document.body.innerText"),
            timeout=20,
        )
        wait_until(
            "ticket detail to show in_progress state and unassign control",
            lambda: "in_progress" in js("document.body.innerText")
            and f"ticket-unassign-{slug}" in js("document.body.innerHTML"),
            timeout=20,
        )
        wait_until(
            "ticket prompt to be recorded as terminal input",
            lambda: transcript_input_contains(slug, body),
            timeout=20,
        )

        assert_element_visible(
            '[data-testid="ticket-transition-pending_approval"]',
            "pending approval transition button",
        )
        assert js(
            "Boolean(document.querySelector('[data-testid=\"ticket-transition-pending_approval\"] [data-icon=\"route\"]'))"
        )
        click_selector('[data-testid="ticket-transition-pending_approval"]')
        wait_until(
            "ticket detail to show pending approval",
            lambda: "Moved to pending_approval" in js("document.body.innerText")
            and "pending_approval" in js("document.body.innerText")
            and f"ticket-unassign-{slug}" not in js("document.body.innerHTML"),
            timeout=20,
        )

        feedback = f"BDD rejection feedback for {slug}."
        context.open_path("/citizens")
        click_selector(f'[data-testid="citizen-stop-{slug}"]')
        wait_for_index_status(slug, "stopped")

        context.open_path(f"/tickets/{ticket_id}")
        wait_until(
            "LiveView socket to reconnect on pending ticket detail",
            lambda: bool(js("window.liveSocket?.isConnected?.() || false")),
            timeout=10,
        )
        assert_element_visible('[data-testid="ticket-reject-form"]', "reject feedback form")
        assert js("Boolean(document.querySelector('[data-testid=\"ticket-reject\"] [data-icon=\"x\"]'))")
        submit_rejection_feedback(feedback)
        wait_until(
            "ticket detail to show rejection",
            lambda: "Rejected ticket" in js("document.body.innerText")
            and "in_progress" in js("document.body.innerText"),
            timeout=20,
        )
        wait_until(
            "rejection feedback to be recorded as terminal input",
            lambda: transcript_input_contains(slug, feedback),
            timeout=25,
        )

        click_selector('[data-testid="ticket-transition-pending_approval"]')
        wait_until(
            "ticket detail to return to pending approval",
            lambda: "Moved to pending_approval" in js("document.body.innerText")
            and "pending_approval" in js("document.body.innerText"),
            timeout=20,
        )
        assert_element_visible('[data-testid="ticket-approve"]', "approve button")
        assert js("Boolean(document.querySelector('[data-testid=\"ticket-approve\"] [data-icon=\"check\"]'))")
        click_selector('[data-testid="ticket-approve"]')
        wait_until(
            "ticket detail to show approved closed state",
            lambda: "Approved ticket" in js("document.body.innerText")
            and "closed" in js("document.body.innerText"),
            timeout=20,
        )
    finally:
        cleanup_ticket(context.tickets_root, ticket_id)
        cleanup_spawned_citizen(slug)


def scenario_ticket_comment_notifies_assigned_citizen(context: BabsBddContext) -> None:
    slug = unique_slug("bdd-comment")
    ticket_id = allocate_ticket_id(context.tickets_root)
    body = f"BDD comment assignment body for {slug}."
    comment = f"BDD comment update for {slug}."

    try:
        create_shell_citizen_from_ui(context, slug)
        write_ticket(context.tickets_root, ticket_id, "BDD Comment Ticket", body)

        context.open_path(f"/tickets/{ticket_id}")
        wait_until(
            "LiveView socket to connect on comment ticket detail",
            lambda: bool(js("window.liveSocket?.isConnected?.() || false")),
            timeout=10,
        )
        click_selector(f'[data-testid="ticket-assign-{slug}"]')
        wait_until(
            "ticket detail to show assigned comment target",
            lambda: f"Assigned to {slug}" in js("document.body.innerText")
            and f"ticket-unassign-{slug}" in js("document.body.innerHTML"),
            timeout=20,
        )
        assert_element_visible('[data-testid="ticket-comment-form"]', "ticket comment form")
        assert_element_visible('[data-testid="ticket-detail-chat"]', "ticket comments chat")
        assert_element_visible('[data-testid="ticket-comments-empty"]', "empty ticket comments state")
        assert js("Boolean(document.querySelector('[data-testid=\"ticket-comment\"] [data-icon=\"send\"]'))")

        submit_ticket_comment(comment)
        wait_until(
            "ticket detail to show stored comment",
            lambda: "Comment stored" in js("document.body.innerText")
            and ticket_comment_message_contains(comment),
            timeout=20,
        )
        second_comment = f"{comment} second turn"
        submit_ticket_comment(second_comment)
        wait_until(
            "ticket detail to show second stored comment in same chat",
            lambda: ticket_comment_message_contains(second_comment)
            and js("document.querySelectorAll('[data-testid=\"ticket-chat-message\"]').length") >= 2,
            timeout=20,
        )
        wait_until(
            "ticket comment to be recorded as terminal input",
            lambda: transcript_input_contains(slug, comment),
            timeout=25,
        )

        events = [event["event"] for event in ticket_history_events(context.tickets_root, ticket_id)]
        assert "comment" in events
        assert events.count("turn_created") >= 2
        assert events.count("turn_delivery_attempted") >= 2
        assert "comment_notification_attempted" in events
        assert "comment_notified" in events
    finally:
        cleanup_ticket(context.tickets_root, ticket_id)
        cleanup_spawned_citizen(slug)


def scenario_federation_events_feed_returns_cursor_snapshots(context: BabsBddContext) -> None:
    ticket_id = allocate_ticket_id(context.tickets_root)

    try:
        write_ticket(context.tickets_root, ticket_id, "BDD Remote Events Ticket", "Expose through events.")

        status, body = http_get_status(f"{context.base_url}/api/v1/events", timeout=5)
        assert status == 200
        first = json.loads(body)

        assert isinstance(first.get("cursor"), str)
        assert [event["type"] for event in first["events"]] == [
            "node.snapshot",
            "citizens.snapshot",
            "tickets.snapshot",
        ]

        tickets_event = next(event for event in first["events"] if event["type"] == "tickets.snapshot")
        assert any(ticket["id"] == ticket_id for ticket in tickets_event["payload"]["tickets"])

        encoded_cursor = urllib.parse.quote(first["cursor"], safe="")
        status, body = http_get_status(f"{context.base_url}/api/v1/events?cursor={encoded_cursor}", timeout=5)
        assert status == 200
        second = json.loads(body)

        assert second["cursor"] == first["cursor"]
        assert second["events"] == []
    finally:
        cleanup_ticket(context.tickets_root, ticket_id)


def scenario_remote_operation_bdd_e2e_ticket_and_citizen_controls(context: BabsBddContext) -> None:
    if context.server_process is None:
        raise SkipScenario("remote operation bdd e2e needs a managed server so it can set loopback federation config")

    slug = unique_slug("bdd-remote")
    ticket_id = allocate_ticket_id(context.tickets_root)
    comment = f"BDD remote operation comment for {ticket_id}."

    try:
        context.write_federation_config(
            node_id="bdd-client",
            peer_id="bdd-client",
            peer_name="BDD Loopback",
            capabilities=["control"],
        )
        create_shell_citizen_from_ui(context, slug)
        write_ticket(
            context.tickets_root,
            ticket_id,
            "BDD Remote Operation Ticket",
            "Remote operation bdd e2e body.",
            state="in_progress",
            assignees=[slug],
        )

        context.open_path("/tickets")
        wait_until(
            "remote operation bdd e2e Ticket row to render",
            lambda: f"remote-ticket-{ticket_id}" in js("document.body.innerHTML")
            and "Control-enabled" in js("document.body.innerText"),
            timeout=20,
        )
        assert_element_visible(
            f'[data-testid="remote-ticket-comment-form-{ticket_id}"]',
            "remote operation bdd e2e comment form",
        )
        assert_element_visible(
            f'[data-testid="remote-ticket-transition-{ticket_id}"]',
            "remote operation bdd e2e transition button",
        )
        set_mobile_viewport()
        assert_no_horizontal_overflow("remote operation bdd e2e remote tickets mobile controls")
        submit_remote_ticket_comment(ticket_id, comment)
        wait_until(
            "remote operation bdd e2e comment to be stored through HTTP control",
            lambda: "Remote comment sent" in js("document.body.innerText")
            and history_has_event(
                context.tickets_root,
                ticket_id,
                lambda event: event.get("event") == "comment"
                and event.get("by") == "remote:bdd-client"
                and event.get("body") == comment,
            ),
            timeout=20,
        )

        submit_remote_ticket_transition(ticket_id)
        wait_until(
            "remote operation bdd e2e transition to reach pending approval",
            lambda: "Remote transition sent" in js("document.body.innerText")
            and history_has_event(
                context.tickets_root,
                ticket_id,
                lambda event: event.get("event") == "remote_transition"
                and event.get("by") == "remote:bdd-client"
                and event.get("to") == "pending_approval",
            ),
            timeout=20,
        )

        context.open_path("/citizens")
        wait_until(
            "remote operation bdd e2e Citizen row to render",
            lambda: f"remote-citizen-{slug}" in js("document.body.innerHTML")
            and "Control-enabled" in js("document.body.innerText"),
            timeout=20,
        )
        restart_selector = f'[data-testid="remote-citizen-restart-{slug}"]'
        assert_element_visible(restart_selector, "remote operation bdd e2e citizen restart")
        assert_no_horizontal_overflow("remote operation bdd e2e remote citizens mobile controls")
        assert not js(f"document.querySelector({json.dumps(restart_selector)})?.disabled")
        click_selector(restart_selector)
        wait_until(
            "remote operation bdd e2e citizen restart to be acknowledged",
            lambda: "Remote restart sent" in js("document.body.innerText"),
            timeout=20,
        )
    finally:
        cleanup_ticket(context.tickets_root, ticket_id)
        cleanup_spawned_citizen(slug)
        context.write_federation_config()


def assert_element_visible(selector: str, label: str) -> None:
    if not wait_for_element(selector, timeout=15, visible=True):
        raise AssertionError(f"{label} was not visible: {selector}")


def assert_no_element(selector: str, label: str) -> None:
    if js(f"Boolean(document.querySelector({json.dumps(selector)}))"):
        raise AssertionError(f"{label} should not be present: {selector}")


def assert_no_horizontal_overflow(label: str) -> None:
    metrics = js(
        """
        const root = document.documentElement;
        const body = document.body;
        const viewportWidth = window.innerWidth;
        const offenders = Array.from(document.body.querySelectorAll("*"))
          .filter((element) => {
            const style = window.getComputedStyle(element);
            if (style.display === "none" || style.visibility === "hidden") return false;
            const rect = element.getBoundingClientRect();
            return rect.width > 0 && (rect.left < -2 || rect.right > viewportWidth + 2);
          })
          .slice(0, 5)
          .map((element) => ({
            tag: element.tagName.toLowerCase(),
            testid: element.getAttribute("data-testid"),
            className: typeof element.className === "string" ? element.className : element.getAttribute("class"),
            rect: (() => {
              const r = element.getBoundingClientRect();
              return {left: r.left, right: r.right, width: r.width};
            })()
          }));

        return {
          viewportWidth,
          scrollWidth: Math.max(root.scrollWidth, body.scrollWidth),
          clientWidth: root.clientWidth,
          offenders
        };
        """
    )

    if metrics["scrollWidth"] > metrics["clientWidth"] + 2 or metrics["offenders"]:
        raise AssertionError(f"{label} has horizontal overflow: {metrics}")


def assert_mobile_diff_containment(label: str) -> None:
    metrics = js(
        """
        const root = document.documentElement;
        const body = document.body;
        const viewportWidth = window.innerWidth;
        const panel = document.querySelector('[data-testid="ticket-review-diff"]');
        const file = document.querySelector(".git-diff-file");
        const code = document.querySelector(".git-diff-code");
        const rectFor = (element) => {
          if (!element) return null;
          const rect = element.getBoundingClientRect();
          return {left: rect.left, right: rect.right, width: rect.width};
        };

        return {
          viewportWidth,
          rootScrollWidth: root.scrollWidth,
          bodyScrollWidth: body.scrollWidth,
          panel: rectFor(panel),
          file: rectFor(file),
          codeClientWidth: code?.clientWidth || 0,
          codeScrollWidth: code?.scrollWidth || 0,
          codeHasHorizontalScroll: Boolean(code && code.scrollWidth > code.clientWidth)
        };
        """
    )

    page_scroll_width = max(metrics["rootScrollWidth"], metrics["bodyScrollWidth"])
    if page_scroll_width > metrics["viewportWidth"] + 2:
        raise AssertionError(f"{label} page has horizontal scroll: {metrics}")

    for key in ["panel", "file"]:
        rect = metrics[key]
        if not rect or rect["left"] < -2 or rect["right"] > metrics["viewportWidth"] + 2:
            raise AssertionError(f"{label} {key} escapes viewport: {metrics}")

    if not metrics["codeHasHorizontalScroll"]:
        raise AssertionError(f"{label} expected per-file diff horizontal scroll: {metrics}")


def assert_touch_targets(selector: str, label: str, required: bool = True) -> None:
    selector_json = json.dumps(selector)
    result = js(
        f"""
        const elements = Array.from(document.querySelectorAll({selector_json}))
          .filter((element) => {{
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0;
          }});
        return {{
          count: elements.length,
          tooSmall: elements
            .map((element) => {{
              const rect = element.getBoundingClientRect();
              return {{
                text: element.innerText.trim(),
                testid: element.getAttribute("data-testid"),
                width: rect.width,
                height: rect.height
              }};
            }})
            .filter((item) => item.height < 42)
        }};
        """
    )

    if required and result["count"] == 0:
        raise AssertionError(f"{label} not found for selector {selector}")

    if result["tooSmall"]:
        raise AssertionError(f"{label} had small touch targets: {result['tooSmall']}")


def assert_service_worker_registration_noops_without_secure_context() -> None:
    js(
        """
        window.__babsPwaRegistrationResult = null;
        window.__babsPwaRegistrationCalled = false;
        import("/js/pwa_boot.js")
          .then((module) => module.registerBabsServiceWorker({
            navigator: {serviceWorker: {register: () => { window.__babsPwaRegistrationCalled = true; }}},
            window: {isSecureContext: false}
          }))
          .then((result) => { window.__babsPwaRegistrationResult = result; })
          .catch((error) => { window.__babsPwaRegistrationResult = {status: "failed", reason: String(error)}; });
        """
    )

    wait_until(
        "service worker no-op result",
        lambda: js("window.__babsPwaRegistrationResult !== null"),
        timeout=5,
    )
    result = js("window.__babsPwaRegistrationResult")
    called = js("window.__babsPwaRegistrationCalled")
    assert result == {"status": "skipped", "reason": "insecure-context"}
    assert called is False


def click_selector(selector: str) -> None:
    selector_json = json.dumps(selector)
    rect = js(
        f"""
        const e = document.querySelector({selector_json});
        if (!e) return null;
        e.scrollIntoView({{block: "center", inline: "center"}});
        const r = e.getBoundingClientRect();
        return {{x: r.left + r.width / 2, y: r.top + r.height / 2}};
        """
    )
    if not rect:
        raise AssertionError(f"element not found for click: {selector}")
    click_at_xy(rect["x"], rect["y"])


def submit_rejection_feedback(feedback: str) -> None:
    js(f"window.__babsBddRejectFeedback = {json.dumps(feedback)}")
    script = """
        (() => {
        const feedback = window.__babsBddRejectFeedback;
        const textarea = document.querySelector('[data-testid="ticket-reject-feedback"]');
        if (!textarea) throw new Error("missing reject feedback textarea");
        textarea.value = feedback;
        textarea.dispatchEvent(new Event("input", {bubbles: true}));
        textarea.dispatchEvent(new Event("change", {bubbles: true}));
        const form = document.querySelector('[data-testid="ticket-reject-form"]');
        if (!form) throw new Error("missing reject feedback form");
        form.requestSubmit();
        })();
        """
    try:
        js(script)
    finally:
        js("delete window.__babsBddRejectFeedback")


def submit_ticket_comment(comment: str) -> None:
    js(f"window.__babsBddTicketComment = {json.dumps(comment)}")
    script = """
        (() => {
        const comment = window.__babsBddTicketComment;
        const textarea = document.querySelector('[data-testid="ticket-comment-body"]');
        if (!textarea) throw new Error("missing ticket comment textarea");
        textarea.value = comment;
        textarea.dispatchEvent(new Event("input", {bubbles: true}));
        textarea.dispatchEvent(new Event("change", {bubbles: true}));
        const form = document.querySelector('[data-testid="ticket-comment-form"]');
        if (!form) throw new Error("missing ticket comment form");
        form.requestSubmit();
        })();
        """
    try:
        js(script)
    finally:
        js("delete window.__babsBddTicketComment")


def submit_remote_ticket_comment(ticket_id: str, comment: str) -> None:
    values = json.dumps({"ticket_id": ticket_id, "comment": comment})
    js(f"window.__babsBddRemoteTicketComment = {values}")
    script = """
        (() => {
        const values = window.__babsBddRemoteTicketComment;
        const form = document.querySelector(`[data-testid="remote-ticket-comment-form-${values.ticket_id}"]`);
        if (!form) throw new Error("missing remote Ticket comment form");
        const input = form.querySelector('input[name="body"]');
        if (!input) throw new Error("missing remote Ticket comment input");
        input.value = values.comment;
        input.dispatchEvent(new Event("input", {bubbles: true}));
        input.dispatchEvent(new Event("change", {bubbles: true}));
        form.requestSubmit();
        })();
        """
    try:
        js(script)
    finally:
        js("delete window.__babsBddRemoteTicketComment")


def submit_remote_ticket_transition(ticket_id: str) -> None:
    ticket_id_json = json.dumps(ticket_id)
    js(f"window.__babsBddRemoteTicketId = {ticket_id_json}")
    script = """
        (() => {
        const ticketId = window.__babsBddRemoteTicketId;
        const form = document.querySelector(`[data-testid="remote-ticket-transition-form-${ticketId}"]`);
        if (!form) throw new Error("missing remote Ticket transition form");
        form.requestSubmit();
        })();
        """
    try:
        js(script)
    finally:
        js("delete window.__babsBddRemoteTicketId")


def submit_new_ticket_form(title: str, priority: str, body: str, assignee_role: str = "") -> None:
    values = json.dumps(
        {"title": title, "priority": priority, "body": body, "assignee_role": assignee_role}
    )
    js(f"window.__babsBddTicketValues = {values}")
    script = """
        (() => {
        const values = window.__babsBddTicketValues;
        const setValue = (selector, value) => {
          const element = document.querySelector(selector);
          if (!element) throw new Error(`missing Ticket form field ${selector}`);
          element.value = value;
          element.dispatchEvent(new Event("input", {bubbles: true}));
          element.dispatchEvent(new Event("change", {bubbles: true}));
        };
        setValue('[data-testid="ticket-title"]', values.title);
        setValue('[data-testid="ticket-priority"]', values.priority);
        setValue('[data-testid="ticket-assignee-role"]', values.assignee_role || "");
        setValue('[data-testid="ticket-body"]', values.body);
        const form = document.querySelector('[data-testid="new-ticket-form"]');
        if (!form) throw new Error("missing new Ticket form");
        form.requestSubmit();
        })();
        """
    try:
        js(script)
    finally:
        js("delete window.__babsBddTicketValues")


def submit_attach_form(slug: str, target: str) -> None:
    values = json.dumps({"slug": slug, "target": target})
    js(f"window.__babsBddAttachValues = {values}")
    script = """
        const values = window.__babsBddAttachValues;
        const setValue = (selector, value) => {
          const element = document.querySelector(selector);
          if (!element) throw new Error(`missing attach form field ${selector}`);
          element.value = value;
          element.dispatchEvent(new Event("input", {bubbles: true}));
          element.dispatchEvent(new Event("change", {bubbles: true}));
        };
        setValue('[data-testid="attach-citizen-select"]', values.slug);
        setValue('[data-testid="attach-target-select"]', values.target);
        const form = document.querySelector('[data-testid="attach-form"]');
        if (!form) throw new Error("missing attach form");
        form.requestSubmit();
        """
    try:
        js(script)
    finally:
        js("delete window.__babsBddAttachValues")


def ticket_comment_message_contains(comment: str) -> bool:
    comment_json = json.dumps(comment)
    return bool(
        js(
            f"""
            Array.from(document.querySelectorAll('[data-testid="ticket-chat-message"]'))
              .some((element) => element.innerText.includes({comment_json}))
            """
        )
    )


def assert_control_disabled(selector: str, label: str) -> None:
    selector_json = json.dumps(selector)
    disabled = js(
        f"""
        const e = document.querySelector({selector_json});
        if (!e) return false;
        return e.getAttribute("aria-disabled") === "true" && !e.hasAttribute("href");
        """
    )
    if not disabled:
        raise AssertionError(f"{label} was not disabled: {selector}")


def wait_for_index_status(slug: str, status: str) -> None:
    wait_until(
        f"{slug} index status to be {status}",
        lambda: status
        in js(f"document.querySelector('[data-testid=\"citizen-status-{slug}\"]')?.innerText || ''"),
        timeout=15,
    )


def click_terminal() -> None:
    rect = js(
        """
        const e = document.querySelector('[data-testid="terminal"]');
        if (!e) return null;
        const r = e.getBoundingClientRect();
        return {x: r.left + r.width / 2, y: r.top + r.height / 2};
        """
    )
    if not rect:
        raise AssertionError("terminal element not found")
    click_at_xy(rect["x"], rect["y"])


def submit_home_edit(content: str) -> None:
    values = json.dumps({"content": content})
    js(f"window.__babsBddHomeEdit = {values}")
    script = """
        const values = window.__babsBddHomeEdit;
        const textarea = document.querySelector('[data-testid="knowledge-edit-content"]');
        if (!textarea) throw new Error("missing Knowledge edit textarea");
        textarea.value = values.content;
        textarea.dispatchEvent(new Event("input", {bubbles: true}));
        textarea.dispatchEvent(new Event("change", {bubbles: true}));
        const form = document.querySelector('[data-testid="knowledge-edit-form"]');
        if (!form) throw new Error("missing Knowledge edit form");
        form.requestSubmit();
        """
    try:
        js(script)
    finally:
        js("delete window.__babsBddHomeEdit")


def command_exists(command: str) -> bool:
    return subprocess.run(["sh", "-lc", f"command -v {command}"], stdout=subprocess.DEVNULL).returncode == 0


def managed_beam_pid(context: BabsBddContext) -> int:
    if context.server_process is None:
        raise SkipScenario("BDD is using an externally managed server, so fd thresholds are skipped")

    pgid = os.getpgid(context.server_process.pid)
    result = subprocess.run(
        ["ps", "-axo", "pid=,pgid=,command="],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    if result.returncode != 0:
        raise SkipScenario(f"could not inspect process table for fd smoke: {result.stderr.strip()}")

    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) < 3:
            continue
        pid_text, pgid_text, command = parts
        if int(pgid_text) == pgid and "beam.smp" in command:
            return int(pid_text)

    raise SkipScenario("could not find managed BEAM process for fd smoke")


def fd_count(pid: int) -> int:
    proc_fd = Path(f"/proc/{pid}/fd")

    if proc_fd.exists():
        return len(list(proc_fd.iterdir()))

    result = subprocess.run(
        ["lsof", "-nP", "-p", str(pid)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    if result.returncode != 0:
        raise SkipScenario(f"could not sample fd count with lsof: {result.stderr.strip()}")

    lines = [line for line in result.stdout.splitlines() if line.strip()]
    return max(0, len(lines) - 1)


def http_get_status(url: str, timeout: float) -> tuple[int, str]:
    request = urllib.request.Request(url, headers={"User-Agent": "babs-browser-harness-bdd"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8", errors="replace")
            return response.status, body
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        return error.code, body


def rendered_xterm_row_count() -> int:
    return int(js("document.querySelectorAll('.xterm-rows > div').length") or 0)


def set_mobile_viewport() -> None:
    cdp(
        "Emulation.setDeviceMetricsOverride",
        width=390,
        height=844,
        deviceScaleFactor=2,
        mobile=True,
    )
    wait(1)


def status_geometry() -> dict:
    return js(
        """
        const e = document.querySelector('[data-testid="connection-status"]');
        const r = e.getBoundingClientRect();
        return {width: r.width, height: r.height};
        """
    )


def terminal_geometry() -> dict:
    info = page_info()
    rect = js(
        """
        const e = document.querySelector('[data-testid="terminal"]');
        const r = e.getBoundingClientRect();
        const page = document.querySelector('.terminal-page');
        const chrome = document.querySelector('[data-testid="terminal-chrome"]');
        const cr = chrome?.getBoundingClientRect();
        return {
          left: r.left,
          top: r.top,
          width: r.width,
          height: r.height,
          mode: page?.dataset.mode || "",
          chrome_height: cr?.height || 0
        };
        """
    )
    return {**rect, "viewport_width": info["w"], "viewport_height": info["h"]}


def assert_terminal_mode_geometry(geometry: dict) -> None:
    if geometry["mode"] == "full":
        assert abs(geometry["top"]) <= 2, geometry
        assert abs(geometry["height"] - geometry["viewport_height"]) <= 4, geometry
        return

    assert geometry["mode"] == "tabs", geometry
    assert geometry["chrome_height"] >= 40, geometry
    assert abs(geometry["top"] - geometry["chrome_height"]) <= 4, geometry
    assert status_geometry()["height"] <= 40
    assert abs((geometry["height"] + geometry["top"]) - geometry["viewport_height"]) <= 6, geometry


def terminal_text() -> str:
    return js("document.querySelector('.xterm')?.innerText || ''")


def send_tmux_output(slug: str, marker: str) -> None:
    subprocess.run(
        ["tmux", "send-keys", "-t", f"babs-{slug}:0.0", f"printf '{marker}\\n'", "Enter"],
        check=True,
    )


def start_external_tmux_session(session_name: str) -> None:
    cwd = workspace_root() / session_name
    cleanup_external_tmux_session(session_name)
    cwd.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["tmux", "new-session", "-d", "-s", session_name, "-c", str(cwd), "/bin/zsh -f"],
        check=True,
    )
    wait_until(
        f"external tmux session {session_name} to start",
        lambda: external_tmux_session_alive(session_name),
        timeout=10,
    )


def cleanup_external_tmux_session(session_name: str) -> None:
    if not session_name.startswith("bdd-external-"):
        raise AssertionError(f"refusing to clean non-BDD external tmux session: {session_name}")

    subprocess.run(
        ["tmux", "kill-session", "-t", session_name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    shutil.rmtree(workspace_root() / session_name, ignore_errors=True)


def external_tmux_session_alive(session_name: str) -> bool:
    return (
        subprocess.run(
            ["tmux", "has-session", "-t", session_name],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        == 0
    )


def external_tmux_capture_contains(session_name: str, marker: str) -> bool:
    result = subprocess.run(
        ["tmux", "capture-pane", "-p", "-t", session_name, "-S", "-80"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )

    return result.returncode == 0 and marker in result.stdout


def external_tmux_pane_id(session_name: str) -> str:
    result = subprocess.run(
        ["tmux", "list-panes", "-t", session_name, "-F", "#{pane_id}"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )

    return result.stdout.strip()


def create_shell_citizen_from_ui(context: BabsBddContext, slug: str) -> None:
    context.open_path("/citizens/new")
    assert_element_visible('[data-testid="new-citizen-form"]', "new citizen form")
    wait_until(
        "LiveView socket to connect",
        lambda: bool(js("window.liveSocket?.isConnected?.() || false")),
        timeout=10,
    )
    submit_new_citizen_form(slug, f"BDD {slug}", "shell", slug)
    wait_until(
        f"browser to redirect to /citizens/{slug}",
        lambda: js("window.location.pathname") == f"/citizens/{slug}",
        timeout=15,
    )
    assert_element_visible('[data-testid="terminal"]', "spawned terminal root")
    assert_element_visible(".xterm", "spawned xterm surface")
    wait_until(
        f"{slug} connection status to be connected",
        lambda: js("document.querySelector('[data-testid=\"connection-status\"]')?.dataset.state || ''")
        == "connected",
        timeout=15,
    )


def create_shell_citizen_from_ui_without_terminal(context: BabsBddContext, slug: str) -> None:
    context.open_path("/citizens/new")
    assert_element_visible('[data-testid="new-citizen-form"]', "new citizen form")
    wait_until(
        "LiveView socket to connect",
        lambda: bool(js("window.liveSocket?.isConnected?.() || false")),
        timeout=10,
    )
    submit_new_citizen_form(slug, f"BDD {slug}", "shell", slug)
    wait_until(
        f"browser to redirect to /citizens/{slug}",
        lambda: js("window.location.pathname") == f"/citizens/{slug}",
        timeout=15,
    )
    wait_until(
        f"{slug} Home route to finish LiveView navigation",
        lambda: js("Boolean(document.querySelector('[data-testid=\"citizen-home\"]'))"),
        timeout=10,
    )


def submit_new_citizen_form(
    slug: str,
    display_name: str,
    preset: str,
    cwd: str,
    ticket_backend: str = "hardline",
    roles: str = "",
) -> None:
    values = json.dumps(
        {
            "slug": slug,
            "display_name": display_name,
            "preset": preset,
            "cwd": cwd,
            "ticket_backend": ticket_backend,
            "roles": roles,
        }
    )
    js(f"window.__babsBddFormValues = {values}")
    script = """
        const values = window.__babsBddFormValues;
        const setValue = (selector, value) => {
          const element = document.querySelector(selector);
          if (!element) throw new Error(`missing form field ${selector}`);
          element.value = value;
          element.dispatchEvent(new Event("input", {bubbles: true}));
          element.dispatchEvent(new Event("change", {bubbles: true}));
        };
        setValue('[data-testid="citizen-slug"]', values.slug);
        setValue('[data-testid="citizen-display-name"]', values.display_name);
        setValue('[data-testid="citizen-cli-preset"]', values.preset);
        setValue('[data-testid="citizen-ticket-backend"]', values.ticket_backend);
        setValue('[data-testid="citizen-cwd"]', values.cwd);
        setValue('[data-testid="citizen-roles"]', values.roles || "");
        const description = document.querySelector('[data-testid="citizen-description"]');
        if (description) description.value = "";
        const form = document.querySelector('[data-testid="new-citizen-form"]');
        if (!form) throw new Error("missing new citizen form");
        form.requestSubmit();
        """
    try:
        js(script)
    finally:
        js("delete window.__babsBddFormValues")


def citizen_toml_path(slug: str) -> Path:
    return RUNTIME_ROOT / "citizens" / f"citizen-{slug}.toml"


def cleanup_spawned_citizen(slug: str) -> None:
    if not slug.startswith("bdd-"):
        raise AssertionError(f"refusing to clean non-BDD citizen slug: {slug}")

    subprocess.run(["tmux", "kill-session", "-t", f"babs-{slug}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    citizen_toml_path(slug).unlink(missing_ok=True)
    shutil.rmtree(workspace_root() / slug, ignore_errors=True)

    db_path = citizens_db_path()
    if db_path.exists():
        with sqlite3.connect(db_path) as connection:
            connection.execute("delete from provider_sessions where citizen_slug = ?", (slug,))
            connection.execute("delete from citizens where slug = ?", (slug,))
            connection.commit()


def tmux_session_alive(session_name: str) -> bool:
    return (
        subprocess.run(
            ["tmux", "has-session", "-t", session_name],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        == 0
    )


def cleanup_bdd_seed_sessions() -> None:
    for slug in ["sentinel", "clare", "dylan", "elena"]:
        subprocess.run(
            ["tmux", "kill-session", "-t", f"babs-{slug}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def tmux_session_count(slug: str) -> int:
    result = subprocess.run(
        ["tmux", "list-sessions", "-F", "#{session_name}"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )

    if result.returncode != 0:
        return 0

    return sum(1 for line in result.stdout.splitlines() if line.strip() == f"babs-{slug}")


def transcript_contains(slug: str, marker: str) -> bool:
    return transcript_payload_contains(slug, marker, "output")


def transcript_input_contains(slug: str, marker: str) -> bool:
    return transcript_payload_contains(slug, marker, "input")


def transcript_payload_contains(slug: str, marker: str, direction: str) -> bool:
    transcript = transcript_path(slug)

    if not transcript.exists():
        return False

    # Ticket runtime protocol prompts can push the matching input event far back
    # in transcript.jsonl, so keep this window larger than a short terminal tail.
    for line in transcript.read_text(encoding="utf-8", errors="replace").splitlines()[-2000:]:
        try:
            record = json.loads(line)
            if record.get("slug") != slug or record.get("direction") != direction:
                continue
            payload = base64.b64decode(record.get("b64", "")).decode("utf-8", "replace")
        except Exception:  # noqa: BLE001 - malformed transcript rows are ignored by design.
            continue

        if marker in payload:
            return True

    return False


def latest_transcript_output_stream_id(slug: str) -> int | None:
    transcript = transcript_path(slug)

    if not transcript.exists():
        return None

    for line in reversed(transcript.read_text(encoding="utf-8", errors="replace").splitlines()[-2000:]):
        try:
            record = json.loads(line)
        except Exception:  # noqa: BLE001 - malformed transcript rows are ignored by design.
            continue

        if record.get("slug") == slug and record.get("direction") == "output":
            stream_id = record.get("stream_id")
            return stream_id if isinstance(stream_id, int) else None

    return None


def transcript_path(slug: str) -> Path:
    return workspace_root() / slug / "transcript.jsonl"


def upsert_sqlite_citizen(slug: str, display_name: str, cwd: Path) -> None:
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    db_path = citizens_db_path()

    if not slug.startswith("bdd-"):
        raise AssertionError(f"refusing to seed non-BDD citizen slug: {slug}")

    with sqlite3.connect(db_path) as connection:
        connection.execute("delete from provider_sessions where citizen_slug = ?", (slug,))
        connection.execute("delete from citizens where slug = ?", (slug,))
        connection.execute(
            """
            insert into citizens (
              id, slug, display_name, description, cwd, cli, cli_args, env, status,
              metadata, role, is_mayor, last_error, launch_profile, ticket_backend,
              roles, inserted_at, updated_at
            ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                "BAB-CIT-" + slug.upper().replace("-", "_"),
                slug,
                display_name,
                "BDD mobile diff fixture",
                str(cwd),
                "/bin/zsh",
                json.dumps(["-f"]),
                json.dumps({}),
                "running",
                json.dumps({"source": "browser-harness"}),
                None,
                0,
                None,
                "safe_interactive",
                "hardline",
                json.dumps([]),
                now,
                now,
            ),
        )
        connection.commit()


def sqlite_citizen_row(slug: str) -> sqlite3.Row | None:
    db_path = citizens_db_path()

    if not db_path.exists():
        raise AssertionError(f"SQLite citizen registry does not exist: {db_path}")

    with sqlite3.connect(db_path) as connection:
        connection.row_factory = sqlite3.Row
        return connection.execute("select * from citizens where slug = ?", (slug,)).fetchone()


def citizens_db_path() -> Path:
    raw = os.environ.get("BABS_CITIZENS_DB_PATH")

    if raw and raw.strip():
        path = Path(raw.strip()).expanduser()
        if not path.is_absolute():
            path = RUNTIME_ROOT / path
        return path.resolve()

    return (RUNTIME_ROOT / "var" / "babs_citizens.sqlite3").resolve()


def tickets_root() -> Path:
    raw = os.environ.get("BABS_TICKETS_ROOT")

    if raw and raw.strip():
        path = Path(raw.strip()).expanduser()
        if not path.is_absolute():
            path = RUNTIME_ROOT / path
        return path.resolve()

    return (RUNTIME_ROOT / "var" / "tickets").resolve()


def knowledge_root() -> Path:
    raw = os.environ.get("BABS_KNOWLEDGE_ROOT")

    if raw and raw.strip():
        path = Path(raw.strip()).expanduser()
        if not path.is_absolute():
            path = RUNTIME_ROOT / path
        return path.resolve()

    return workspace_root()


def knowledge_file_path(slug: str, name: str) -> Path:
    return knowledge_root() / slug / name


def write_knowledge_file(slug: str, name: str, content: str) -> Path:
    if not slug.startswith("bdd-"):
        raise AssertionError(f"refusing to write non-BDD Knowledge slug: {slug}")

    path = knowledge_file_path(slug, name)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return path


def allocate_ticket_id(root: Path) -> str:
    root.mkdir(parents=True, exist_ok=True)
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    for seq in range(900, 1000):
        ticket_id = f"T-{today}-{seq:03d}"
        if not ticket_markdown_path(root, ticket_id).exists() and not ticket_history_path(root, ticket_id).exists():
            return ticket_id

    raise AssertionError("could not allocate BDD Ticket id")


def create_git_diff_workspace(slug: str, added_line: str) -> Path:
    if not slug.startswith("bdd-"):
        raise AssertionError(f"refusing to seed non-BDD workspace: {slug}")

    workspace = workspace_root() / slug
    shutil.rmtree(workspace, ignore_errors=True)
    workspace.mkdir(parents=True, exist_ok=True)
    git_command(workspace, "init")
    git_command(workspace, "config", "user.email", "babs@example.test")
    git_command(workspace, "config", "user.name", "Babs BDD")

    readme = workspace / "README.md"
    readme.write_text("old line\n", encoding="utf-8")
    git_command(workspace, "add", "README.md")
    git_command(workspace, "commit", "-m", "Initial commit")
    readme.write_text(f"old line\n{added_line}\n", encoding="utf-8")
    return workspace


def git_command(cwd: Path, *args: str) -> None:
    result = subprocess.run(
        ["git", *args],
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )

    if result.returncode != 0:
        raise AssertionError(f"git {' '.join(args)} failed in {cwd}: {result.stdout}")


def write_ticket(
    root: Path,
    ticket_id: str,
    title: str,
    body: str,
    *,
    state: str = "open",
    assignees: list[str] | None = None,
    metadata: dict | None = None,
) -> None:
    root.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    assignees = assignees or []
    metadata = metadata or {"source": "browser-harness"}

    ticket_markdown_path(root, ticket_id).write_text(
        f"""---
id: "{ticket_id}"
type: "assignment"
state: "{state}"
assigner: "bdd"
assignees: {json.dumps(assignees)}
assignee_role: null
inspector: "user"
priority: "normal"
parent_ticket: null
created_at: "{now}"
updated_at: "{now}"
metadata: {json.dumps(metadata, separators=(",", ":"))}
---

# {title}

{body}
"""
    )

    ticket_history_path(root, ticket_id).write_text(
        json.dumps({"ts": now, "event": "created", "by": "bdd"}, separators=(",", ":")) + "\n"
    )


def append_ticket_history_event(root: Path, ticket_id: str, event: dict) -> None:
    with ticket_history_path(root, ticket_id).open("a") as history_file:
        history_file.write(json.dumps(event, separators=(",", ":")) + "\n")


def auto_inspection_metadata(citizens: list[str], strategy: str) -> dict:
    return {
        "source": "browser-harness",
        "inspection": {
            "mode": "auto",
            "strategy": strategy,
            "roles": [],
            "citizens": citizens,
            "quorum": "all_pass",
            "max_inspectors": len(citizens),
            "allow_self_inspection": False,
        },
    }


def create_mayor_proposal_ticket_once(tickets_root_path: Path, proposal_id: str, child_title: str) -> str:
    script = """
    root = System.fetch_env!("BABS_BDD_TICKETS_ROOT")
    proposal_id = System.fetch_env!("BABS_BDD_PROPOSAL_ID")
    child_title = System.fetch_env!("BABS_BDD_CHILD_TITLE")

    Application.put_env(:babs_citizens, :tickets_root, root)
    {:ok, _apps} = Application.ensure_all_started(:babs_citizens)

    {:ok, ticket} =
      Babs.Citizens.Tickets.Api.create_ticket(
        %{
          type: "mission",
          title: "BDD Mayor Proposal Root",
          body: "Approve this Mayor proposal from the browser.",
          metadata: %{
            "mayor" => %{
              "mode" => "propose",
              "mayor" => "flora",
              "rules_refs" => ["BAB-1503", "COR-1616"],
              "max_children" => 5,
              "allowed_roles" => ["developer", "inspector"],
              "require_human_approval" => true
            }
          }
        },
        tickets_root: root,
        now: "2026-05-08T12:00:00Z"
      )

    proposal = %{
      "proposal_id" => proposal_id,
      "root_ticket_id" => ticket.id,
      "summary" => "Split the mission into one child Ticket.",
      "rules_refs_used" => ["BAB-1503"],
      "children" => [
        %{
          "title" => child_title,
          "body" => "Complete " <> child_title <> ".",
          "type" => "assignment",
          "priority" => "normal",
          "assignee_role" => "developer",
          "inspector" => "user",
          "metadata" => %{}
        }
      ],
      "risks" => [],
      "questions" => []
    }

    :ok =
      Babs.Citizens.Tickets.Api.append_ticket_events(
        ticket.id,
        [
          %{
            "ts" => "2026-05-08T12:01:00Z",
            "event" => "mayor_proposal_received",
            "by" => "flora",
            "ticket_id" => ticket.id,
            "proposal_id" => proposal_id,
            "proposal" => proposal
          }
        ],
        tickets_root: root
      )

    IO.puts(ticket.id)
    """

    env = os.environ.copy()
    env.update(
        {
            "BABS_BDD_TICKETS_ROOT": str(tickets_root_path),
            "BABS_BDD_PROPOSAL_ID": proposal_id,
            "BABS_BDD_CHILD_TITLE": child_title,
        }
    )
    result = subprocess.run(
        ["mise", "exec", "--", "mix", "run", "--no-start", "-e", script],
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        raise AssertionError(
            "Mayor proposal BDD setup failed:\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )

    return result.stdout.strip().splitlines()[-1]


def append_inspection_history(
    root: Path,
    ticket_id: str,
    inspectors: list[str],
    decisions: list[dict],
    result: str | None,
) -> None:
    inspection_id = "insp_20260508120000_1"
    append_ticket_history_event(
        root,
        ticket_id,
        {
            "ts": "2026-05-08T12:00:00Z",
            "event": "inspection_requested",
            "by": "system",
            "ticket_id": ticket_id,
            "inspection_id": inspection_id,
            "policy": {
                "mode": "auto",
                "strategy": "council" if len(inspectors) > 1 else "single",
                "quorum": "all_pass",
            },
            "inspectors": inspectors,
        },
    )

    for index, inspector in enumerate(inspectors, 1):
        append_ticket_history_event(
            root,
            ticket_id,
            {
                "ts": f"2026-05-08T12:0{index}:00Z",
                "event": "inspection_prompt_delivered",
                "by": "system",
                "ticket_id": ticket_id,
                "inspection_id": inspection_id,
                "to": inspector,
                "turn_id": f"turn_20260508120{index}00_bddinspect",
                "attempt_id": f"attempt_20260508120{index}00_bddinspect",
            },
        )

    for event in decisions:
        append_ticket_history_event(root, ticket_id, {"inspection_id": inspection_id, "ticket_id": ticket_id, **event})

    if result:
        append_ticket_history_event(
            root,
            ticket_id,
            {
                "ts": "2026-05-08T12:09:00Z",
                "event": "inspection_completed",
                "by": "system",
                "ticket_id": ticket_id,
                "inspection_id": inspection_id,
                "result": result,
                "quorum": "all_pass",
            },
        )


def decision(slug: str, verdict: str, summary: str, *, findings: list[dict] | None = None) -> dict:
    return {
        "ts": "2026-05-08T12:04:00Z",
        "event": "inspection_decision",
        "by": slug,
        "decision": verdict,
        "summary": summary,
        "findings": findings or [],
    }


def write_copilot_events(copilot_home: Path, ticket_id: str, started_at: str, reply: str) -> Path:
    events_path = copilot_home / "session-state" / f"bdd-{ticket_id}" / "events.jsonl"
    events_path.parent.mkdir(parents=True, exist_ok=True)
    records = [
        {
            "timestamp": started_at,
            "type": "user.message",
            "data": {
                "content": f"Babs Ticket {ticket_id}: please reply\nBABS_REPLY {ticket_id}: your response"
            },
        },
        {
            "timestamp": utc_now_iso(),
            "type": "assistant.message",
            "data": {"content": f"BABS_REPLY {ticket_id}: {reply}"},
        },
    ]
    events_path.write_text("\n".join(json.dumps(record, separators=(",", ":")) for record in records) + "\n")
    return events_path


def run_elena_reply_capture_once(
    tickets_root_path: Path,
    ticket_id: str,
    started_at: str,
    events_path: Path,
    copilot_home: Path,
) -> None:
    script = """
    root = System.fetch_env!("BABS_BDD_TICKETS_ROOT")
    ticket_id = System.fetch_env!("BABS_BDD_TICKET_ID")
    started_at = System.fetch_env!("BABS_BDD_STARTED_AT")
    events_path = System.fetch_env!("BABS_BDD_COPILOT_EVENTS_PATH")
    copilot_home = System.fetch_env!("BABS_BDD_COPILOT_HOME")

    unless Process.whereis(Babs.Citizens.Tickets.WriterRegistry) do
      {:ok, _pid} = Registry.start_link(keys: :unique, name: Babs.Citizens.Tickets.WriterRegistry)
    end

    unless Process.whereis(Babs.Citizens.Tickets.WriterSupervisor) do
      {:ok, _pid} = Babs.Citizens.Tickets.WriterSupervisor.start_link([])
    end

    config = %Babs.Citizens.CitizenConfig{
      id: "BAB-CIT-BDD-ELENA",
      slug: "elena",
      display_name: "Elena",
      cli: "copilot",
      cli_args: [],
      launch_profile: "trusted_autonomous",
      cwd: File.cwd!(),
      env: %{"COPILOT_HOME" => copilot_home}
    }

    result =
      Babs.Citizens.Tickets.ReplyCapture.capture_once(
        %{root: root, ticket_id: ticket_id, slug: "elena", started_at: started_at},
        citizen_config: config,
        paths: [events_path]
      )

    case result do
      {:captured, _body} -> :ok
      {:duplicate, _body} -> :ok
      other ->
        IO.inspect(other, label: "reply_capture")
        System.halt(1)
    end
    """
    env = os.environ.copy()
    env.update(
        {
            "BABS_BDD_TICKETS_ROOT": str(tickets_root_path),
            "BABS_BDD_TICKET_ID": ticket_id,
            "BABS_BDD_STARTED_AT": started_at,
            "BABS_BDD_COPILOT_EVENTS_PATH": str(events_path),
            "BABS_BDD_COPILOT_HOME": str(copilot_home),
        }
    )
    result = subprocess.run(
        ["mise", "exec", "--", "mix", "run", "--no-start", "-e", script],
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        raise AssertionError(
            "Elena Copilot reply capture failed:\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )


def run_fake_direct_turn_once(tickets_root_path: Path, ticket_id: str, reply: str) -> None:
    script = """
    root = System.fetch_env!("BABS_BDD_TICKETS_ROOT")
    ticket_id = System.fetch_env!("BABS_BDD_TICKET_ID")
    reply = System.fetch_env!("BABS_BDD_DIRECT_REPLY")

    Application.put_env(:babs_citizens, :autostart, false)
    Application.put_env(:babs_citizens, :tickets_root, root)
    Application.put_env(:babs_citizens, :ai_reply_capture_enabled, false)

    {:ok, _apps} = Application.ensure_all_started(:babs_citizens)

    Ecto.Migrator.with_repo(Babs.Citizens.Repo, fn repo ->
      Ecto.Migrator.run(repo, Application.app_dir(:babs_citizens, "priv/repo/migrations"), :up, all: true)
    end)

    config = %Babs.Citizens.CitizenConfig{
      id: "BAB-CIT-BDD-DYLAN",
      slug: "dylan",
      display_name: "Dylan",
      cli: "babs-fake-ai",
      cli_args: [],
      launch_profile: "trusted_autonomous",
      ticket_backend: "direct_cli",
      cwd: File.cwd!(),
      env: %{}
    }

    session_id = "bdd-direct-session-" <> ticket_id

    executor = fn command ->
      {:ok,
       %{
         stdout: Jason.encode!(%{"session_id" => command.provider_session_id || session_id, "content" => reply}),
         stderr: ""
       }}
    end

    turn = %{
      root: root,
      ticket_id: ticket_id,
      slug: "dylan",
      turn_id: "turn_bdd_direct_" <> Integer.to_string(System.unique_integer([:positive])),
      attempt_id: "attempt_bdd_direct_" <> Integer.to_string(System.unique_integer([:positive])),
      backend: "direct_cli",
      prompt: "Reply through the fake direct CLI provider.",
      config: config,
      fallback: :none
    }

    case Babs.Citizens.DirectCli.Runner.run_turn(turn,
           adapter: Babs.Citizens.DirectCli.Adapters.Fake,
           executor: executor
         ) do
      :ok ->
        :ok

      other ->
        IO.inspect(other, label: "direct_turn")
        System.halt(1)
    end
    """

    env = os.environ.copy()
    env.update(
        {
            "BABS_BDD_TICKETS_ROOT": str(tickets_root_path),
            "BABS_BDD_TICKET_ID": ticket_id,
            "BABS_BDD_DIRECT_REPLY": reply,
        }
    )
    result = subprocess.run(
        ["mise", "exec", "--", "mix", "run", "--no-start", "-e", script],
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        raise AssertionError(
            "Direct CLI fake turn failed:\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )


def cleanup_ticket(root: Path, ticket_id: str) -> None:
    ticket_markdown_path(root, ticket_id).unlink(missing_ok=True)
    ticket_history_path(root, ticket_id).unlink(missing_ok=True)


def ticket_markdown_path(root: Path, ticket_id: str) -> Path:
    return root / f"{ticket_id}.md"


def ticket_history_path(root: Path, ticket_id: str) -> Path:
    return root / f"{ticket_id}.history.jsonl"


def ticket_history_events(root: Path, ticket_id: str) -> list[dict]:
    return [
        json.loads(line)
        for line in ticket_history_path(root, ticket_id).read_text().splitlines()
        if line.strip()
    ]


def direct_prompt_events(path: Path) -> list[dict]:
    if not path.exists():
        return []

    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def history_has_event(root: Path, ticket_id: str, predicate) -> bool:
    try:
        return any(predicate(event) for event in ticket_history_events(root, ticket_id))
    except FileNotFoundError:
        return False


def workspace_root() -> Path:
    global WORKSPACE_ROOT  # noqa: PLW0603 - cached helper avoids recomputing paths in polling loops.

    if WORKSPACE_ROOT is not None:
        return WORKSPACE_ROOT

    # Keep this in sync with Babs.Citizens.Citizen.Config.workspace_root/2.
    raw = os.environ.get("BABS_WORKSPACE_ROOT")

    if raw and raw.strip():
        path = Path(raw.strip()).expanduser()
        if not path.is_absolute():
            path = RUNTIME_ROOT / path
    else:
        path = RUNTIME_ROOT / "workspaces"

    WORKSPACE_ROOT = path.absolute()
    return WORKSPACE_ROOT


def touch_source(path: Path) -> None:
    path.write_text(path.read_text())


def unique_marker(prefix: str) -> str:
    return f"{prefix}_{int(time.time() * 1000)}"


def unique_slug(prefix: str) -> str:
    return f"{prefix}-{int(time.time() * 1000)}"


def tmp_bdd_dir(prefix: str) -> Path:
    root = Path(os.environ.get("TMPDIR") or "/tmp")
    path = root / f"babs-bdd-{prefix}-{int(time.time() * 1000)}"
    path.mkdir(parents=True, exist_ok=True)
    return path


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def wait_until(label: str, predicate, timeout: float = 10.0) -> None:
    deadline = time.time() + timeout
    last_error = None

    while time.time() < deadline:
        try:
            if predicate():
                return
        except Exception as error:  # noqa: BLE001 - keep polling until timeout.
            last_error = error
        time.sleep(0.25)

    suffix = f"; last error: {last_error}" if last_error else ""
    raise AssertionError(f"timed out waiting for {label}{suffix}")
