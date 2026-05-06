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

    def ensure_server(self) -> None:
        if self._server_ready():
            return

        SERVER_LOG.parent.mkdir(parents=True, exist_ok=True)
        log = SERVER_LOG.open("ab")
        env = os.environ.copy()
        env["BABS_TICKETS_ROOT"] = str(self.tickets_root)
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
            status, _body = http_get_status(f"{self.base_url}/citizens/sentinel", timeout=2)
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

    try:
        create_shell_citizen_from_ui(context, slug)
        context.open_path("/citizens")
        click_selector(f'[data-testid="citizen-stop-{slug}"]')
        wait_for_index_status(slug, "stopped")

        start_external_tmux_session(external_session)
        assert external_tmux_session_alive(external_session)

        context.open_path("/citizens/attach")
        assert_element_visible('[data-testid="attach-citizen-page"]', "attach Citizen page")
        assert_element_visible('[data-testid="attach-form"]', "attach form")
        assert "Attach tmux" in js("document.body.innerText")
        assert "Attachable" in js("document.body.innerText")
        submit_attach_form(slug, target)

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


def scenario_seed_citizens_connect_when_available(context: BabsBddContext) -> None:
    command_by_slug = {"clare": "claude", "dylan": "codex", "elena": "gh"}
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
        assert_element_visible('[data-testid="ticket-comments-chat"]', "Ticket comments chat")
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
        assert_element_visible('[data-testid="ticket-comments-chat"]', "ticket comments chat")
        assert_element_visible('[data-testid="ticket-comments-empty"]', "empty ticket comments state")
        assert js("Boolean(document.querySelector('[data-testid=\"ticket-comment\"] [data-icon=\"send\"]'))")

        submit_ticket_comment(comment)
        wait_until(
            "ticket detail to show stored comment",
            lambda: "Comment stored" in js("document.body.innerText")
            and ticket_comment_message_contains(comment),
            timeout=20,
        )
        wait_until(
            "ticket comment to be recorded as terminal input",
            lambda: transcript_input_contains(slug, comment),
            timeout=25,
        )

        events = [event["event"] for event in ticket_history_events(context.tickets_root, ticket_id)]
        assert "comment" in events
        assert "comment_notification_attempted" in events
        assert "comment_notified" in events
    finally:
        cleanup_ticket(context.tickets_root, ticket_id)
        cleanup_spawned_citizen(slug)


def assert_element_visible(selector: str, label: str) -> None:
    if not wait_for_element(selector, timeout=15, visible=True):
        raise AssertionError(f"{label} was not visible: {selector}")


def assert_no_element(selector: str, label: str) -> None:
    if js(f"Boolean(document.querySelector({json.dumps(selector)}))"):
        raise AssertionError(f"{label} should not be present: {selector}")


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
        const feedback = window.__babsBddRejectFeedback;
        const textarea = document.querySelector('[data-testid="ticket-reject-feedback"]');
        if (!textarea) throw new Error("missing reject feedback textarea");
        textarea.value = feedback;
        textarea.dispatchEvent(new Event("input", {bubbles: true}));
        textarea.dispatchEvent(new Event("change", {bubbles: true}));
        const form = document.querySelector('[data-testid="ticket-reject-form"]');
        if (!form) throw new Error("missing reject feedback form");
        form.requestSubmit();
        """
    try:
        js(script)
    finally:
        js("delete window.__babsBddRejectFeedback")


def submit_ticket_comment(comment: str) -> None:
    js(f"window.__babsBddTicketComment = {json.dumps(comment)}")
    script = """
        const comment = window.__babsBddTicketComment;
        const textarea = document.querySelector('[data-testid="ticket-comment-body"]');
        if (!textarea) throw new Error("missing ticket comment textarea");
        textarea.value = comment;
        textarea.dispatchEvent(new Event("input", {bubbles: true}));
        textarea.dispatchEvent(new Event("change", {bubbles: true}));
        const form = document.querySelector('[data-testid="ticket-comment-form"]');
        if (!form) throw new Error("missing ticket comment form");
        form.requestSubmit();
        """
    try:
        js(script)
    finally:
        js("delete window.__babsBddTicketComment")


def submit_new_ticket_form(title: str, priority: str, body: str) -> None:
    values = json.dumps({"title": title, "priority": priority, "body": body})
    js(f"window.__babsBddTicketValues = {values}")
    script = """
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
        setValue('[data-testid="ticket-body"]', values.body);
        const form = document.querySelector('[data-testid="new-ticket-form"]');
        if (!form) throw new Error("missing new Ticket form");
        form.requestSubmit();
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
            Array.from(document.querySelectorAll('[data-testid="ticket-comment-message"]'))
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


def submit_new_citizen_form(slug: str, display_name: str, preset: str, cwd: str) -> None:
    values = json.dumps({"slug": slug, "display_name": display_name, "preset": preset, "cwd": cwd})
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
        setValue('[data-testid="citizen-cwd"]', values.cwd);
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
            connection.execute("delete from citizens where slug = ?", (slug,))
            connection.commit()


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


def allocate_ticket_id(root: Path) -> str:
    root.mkdir(parents=True, exist_ok=True)
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    for seq in range(900, 1000):
        ticket_id = f"T-{today}-{seq:03d}"
        if not ticket_markdown_path(root, ticket_id).exists() and not ticket_history_path(root, ticket_id).exists():
            return ticket_id

    raise AssertionError("could not allocate BDD Ticket id")


def write_ticket(root: Path, ticket_id: str, title: str, body: str) -> None:
    root.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    ticket_markdown_path(root, ticket_id).write_text(
        f"""---
id: "{ticket_id}"
type: "assignment"
state: "open"
assigner: "bdd"
assignees: []
assignee_role: null
inspector: "user"
priority: "normal"
parent_ticket: null
created_at: "{now}"
updated_at: "{now}"
metadata: {{"source": "browser-harness"}}
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
