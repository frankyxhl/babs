from __future__ import annotations

import base64
import json
import os
import signal
import subprocess
import time
import urllib.error
import urllib.request
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

    def ensure_server(self) -> None:
        if self._server_ready():
            return

        SERVER_LOG.parent.mkdir(parents=True, exist_ok=True)
        log = SERVER_LOG.open("ab")
        self.server_process = subprocess.Popen(
            ["mise", "exec", "--", "mix", "phx.server"],
            cwd=ROOT,
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

    def connect_citizen(self, slug: str = "sentinel") -> None:
        self.open_path(f"/citizens/{slug}")
        assert_element_visible('[data-testid="terminal"]', "terminal root")
        assert_element_visible(".xterm", "xterm surface")
        wait_until(
            f"{slug} connection status to be connected",
            lambda: js("document.querySelector('[data-testid=\"connection-status\"]')?.dataset.state || ''")
            == "connected",
            timeout=15,
        )

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
            name="configured workspace root stores transcript outside app root",
            given="BABS_WORKSPACE_ROOT is configured",
            when="sentinel produces output while the browser tab is closed",
            then="the transcript replay marker is read from the configured workspace root",
            run=scenario_configured_workspace_root_stores_transcript,
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


def scenario_terminal_fills_viewport(context: BabsBddContext) -> None:
    context.connect_citizen("sentinel")

    try:
        before = terminal_geometry()
        assert before["width"] > 400
        assert before["height"] > 300
        assert status_geometry()["height"] <= 40

        cdp(
            "Emulation.setDeviceMetricsOverride",
            width=1200,
            height=700,
            deviceScaleFactor=1,
            mobile=False,
        )
        wait(1)

        after = terminal_geometry()
        assert abs(after["width"] - 1200) <= 4, after
        assert abs(after["height"] - 700) <= 4, after
        assert rendered_xterm_row_count() > 0
    finally:
        cdp("Emulation.clearDeviceMetricsOverride")


def scenario_seed_citizens_connect_when_available(context: BabsBddContext) -> None:
    command_by_slug = {"clare": "claude", "dylan": "codex", "elena": "gh"}
    checked = 0

    for slug, command in command_by_slug.items():
        if not command_exists(command):
            print(f"  SKIP {slug}: {command} CLI is not installed")
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


def assert_element_visible(selector: str, label: str) -> None:
    if not wait_for_element(selector, timeout=15, visible=True):
        raise AssertionError(f"{label} was not visible: {selector}")


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
        return {left: r.left, top: r.top, width: r.width, height: r.height};
        """
    )
    return {**rect, "viewport_width": info["w"], "viewport_height": info["h"]}


def terminal_text() -> str:
    return js("document.querySelector('.xterm')?.innerText || ''")


def send_tmux_output(slug: str, marker: str) -> None:
    subprocess.run(
        ["tmux", "send-keys", "-t", f"babs-{slug}", f"printf '{marker}\\n'", "Enter"],
        check=True,
    )


def transcript_contains(slug: str, marker: str) -> bool:
    transcript = transcript_path(slug)

    if not transcript.exists():
        return False

    for line in transcript.read_text(encoding="utf-8", errors="replace").splitlines()[-100:]:
        try:
            record = json.loads(line)
            if record.get("slug") != slug or record.get("direction") != "output":
                continue
            payload = base64.b64decode(record.get("b64", "")).decode("utf-8", "replace")
        except Exception:  # noqa: BLE001 - malformed transcript rows are ignored by design.
            continue

        if marker in payload:
            return True

    return False


def transcript_path(slug: str) -> Path:
    return workspace_root() / slug / "transcript.jsonl"


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

    WORKSPACE_ROOT = path.resolve()
    return WORKSPACE_ROOT


def touch_source(path: Path) -> None:
    path.write_text(path.read_text())


def unique_marker(prefix: str) -> str:
    return f"{prefix}_{int(time.time() * 1000)}"


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
