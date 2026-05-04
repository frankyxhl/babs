import {
  commandLabel,
  fullModeDeadSessionMessage,
  fullModeMissingSessionMessage,
  fullUrl,
  nextActiveSession,
  parsePageMode,
  selectedCommand,
  statusDotDescriptor,
  suggestSlug
} from "./hardline_core.js";

export function resolveElements(document) {
  return {
    list: document.getElementById("session-list"),
    form: document.getElementById("create-form"),
    slug: document.getElementById("slug"),
    slugReroll: document.getElementById("slug-reroll"),
    commandPreset: document.getElementById("command-preset"),
    refresh: document.getElementById("refresh"),
    stop: document.getElementById("stop"),
    openFull: document.getElementById("open-full"),
    title: document.getElementById("active-title"),
    subtitle: document.getElementById("active-subtitle"),
    metaSession: document.getElementById("meta-session"),
    metaSessionId: document.getElementById("meta-session-id"),
    metaPanePid: document.getElementById("meta-pane-pid"),
    metaCommand: document.getElementById("meta-command"),
    socketStatus: document.getElementById("socket-status"),
    sizeStatus: document.getElementById("size-status"),
    inputStatus: document.getElementById("input-status"),
    outputStatus: document.getElementById("output-status"),
    dupStatus: document.getElementById("dup-status"),
    messageStatus: document.getElementById("message-status"),
    fullBack: document.getElementById("full-back"),
    fullOverlay: document.getElementById("full-overlay"),
    fullOverlayTitle: document.getElementById("full-overlay-title"),
    fullOverlayMessage: document.getElementById("full-overlay-message"),
    terminal: document.getElementById("terminal")
  };
}

export function renderSessions({ document, list, sessions, activeSlug, onSelect }) {
  list.innerHTML = "";

  if (sessions.length === 0) {
    const empty = document.createElement("div");
    empty.className = "empty";
    empty.textContent = "No managed sessions";
    list.appendChild(empty);
    return;
  }

  for (const session of sessions) {
    const row = document.createElement("div");
    row.className = "session-row";
    row.dataset.testid = `session-row-${session.slug}`;

    const button = document.createElement("button");
    button.type = "button";
    button.className = `session-select${activeSlug === session.slug ? " active" : ""}`;
    button.dataset.testid = `session-select-${session.slug}`;
    button.addEventListener("click", () => onSelect(session.slug));

    const label = document.createElement("div");
    label.innerHTML = `<div class="session-name"></div><div class="session-meta"></div>`;
    label.querySelector(".session-name").textContent = session.slug;
    label.querySelector(".session-meta").textContent = session.session;

    const descriptor = statusDotDescriptor(session);
    const status = document.createElement("span");
    status.className = descriptor.className;
    status.title = descriptor.title;
    status.dataset.testid = `session-status-${session.slug}`;
    status.setAttribute("aria-label", descriptor.ariaLabel);

    button.append(label, status);
    row.append(button);
    list.appendChild(row);
  }
}

export function renderActiveSession(elements, active) {
  if (!active) {
    elements.title.textContent = "No session selected";
    elements.subtitle.textContent = "Create or select a hardline session";
    elements.metaSession.textContent = "-";
    elements.metaSessionId.textContent = "-";
    elements.metaPanePid.textContent = "-";
    elements.metaCommand.textContent = "-";
    elements.stop.disabled = true;
    elements.openFull.disabled = true;
    return;
  }

  elements.title.textContent = active.slug;
  elements.subtitle.textContent = active.session;
  elements.metaSession.textContent = active.session || "-";
  elements.metaSessionId.textContent = active.session_id || "-";
  elements.metaPanePid.textContent = active.pane_pid || "-";
  elements.metaCommand.textContent = commandLabel(active);
  elements.stop.disabled = false;
  elements.openFull.disabled = !active.alive;
}

export function renderStatus(elements, status) {
  elements.sizeStatus.textContent = `size:${status.size.cols}x${status.size.rows}`;
  elements.inputStatus.textContent = `in:${status.inputEvents}`;
  elements.outputStatus.textContent = `out:${status.outputEvents}/${status.outputBytes}B`;
  elements.dupStatus.textContent = `dup:${status.duplicateOutputs}`;
}

export function showFullError(elements, text) {
  elements.fullOverlayTitle.textContent = "Session unavailable";
  elements.fullOverlayMessage.textContent = text;
  elements.fullOverlay.hidden = false;
}

export function hideFullError(elements) {
  elements.fullOverlay.hidden = true;
  elements.fullOverlayMessage.textContent = "";
}

export function createHardlineManager(deps = {}) {
  const win = deps.window || window;
  const document = deps.document || win.document;
  const fetchImpl = deps.fetch || win.fetch.bind(win);
  const elements = deps.elements || resolveElements(document);
  const pageMode = parsePageMode(win.location.search);

  if (pageMode.fullMode) {
    document.body.classList.add("full-mode");
  }

  const TerminalCtor = deps.Terminal || win.Terminal;
  const FitAddonCtor = deps.FitAddon || win.FitAddon;
  const PhoenixCtor = deps.Phoenix || win.Phoenix;
  const confirmImpl = deps.confirm || win.confirm.bind(win);
  const openImpl = deps.open || win.open.bind(win);
  const atobImpl = deps.atob || win.atob.bind(win);
  const TextDecoderCtor = deps.TextDecoder || win.TextDecoder;

  let sessions = [];
  let active = null;
  let socket = null;
  let channel = null;
  let joined = false;
  let resizeTimer = null;
  let outputEvents = 0;
  let outputBytes = 0;
  let inputEvents = 0;
  let duplicateOutputs = 0;
  let currentStreamId = null;
  let outputDecoder = new TextDecoderCtor();
  let fullSelectionAttempted = false;
  const lastSize = { cols: 100, rows: 32 };
  const seenOutputSeqs = new Set();
  const seenOutputSeqQueue = [];
  const maxSeenOutputSeqs = 4096;

  const term = new TerminalCtor({
    cols: 100,
    rows: 32,
    cursorBlink: true,
    fontFamily: 'Menlo, Monaco, Consolas, "Liberation Mono", monospace',
    fontSize: 13,
    theme: {
      background: "#101014",
      foreground: "#e5e7eb",
      cursor: "#f3c969",
      selectionBackground: "#3d3d45"
    }
  });

  const fitAddon = new FitAddonCtor.FitAddon();
  term.loadAddon(fitAddon);
  term.open(elements.terminal);
  term.focus();

  function statusSnapshot() {
    return {
      size: lastSize,
      inputEvents,
      outputEvents,
      outputBytes,
      duplicateOutputs
    };
  }

  function setMessage(text) {
    elements.messageStatus.textContent = text;
  }

  function setSocketStatus(text) {
    elements.socketStatus.textContent = `socket: ${text}`;
  }

  async function api(path, options = {}) {
    const response = await fetchImpl(path, {
      headers: { "content-type": "application/json" },
      ...options
    });

    const body = await response.json().catch(() => ({}));

    if (!response.ok) {
      throw new Error(body.error || response.statusText);
    }

    return body;
  }

  async function loadSessions() {
    const body = await api("/api/sessions");
    sessions = body.sessions || [];
    renderSessionList();
    suggestSlugIfEmpty();

    if (active) {
      const nextActive = nextActiveSession(sessions, active);

      if (nextActive) {
        active = nextActive;
        renderActive();
      } else {
        clearActiveSession(fullModeMissingSessionMessage(active.slug));
      }
    }

    if (pageMode.fullMode && !fullSelectionAttempted) {
      fullSelectionAttempted = true;
      await selectSession(pageMode.requestedSession);
    }

    return sessions;
  }

  function renderSessionList() {
    renderSessions({
      document,
      list: elements.list,
      sessions,
      activeSlug: active?.slug,
      onSelect: selectSession
    });
  }

  function setSuggestedSlug() {
    elements.slug.value = suggestSlug(sessions);
  }

  function suggestSlugIfEmpty() {
    if (elements.slug.value.trim() === "") {
      setSuggestedSlug();
    }
  }

  function renderActive() {
    renderActiveSession(elements, active);
  }

  function clearActiveSession(message) {
    if (channel) {
      channel.leave();
      channel = null;
    }

    active = null;
    joined = false;
    term.clear();
    renderSessionList();
    renderActive();
    setSocketStatus("idle");

    if (pageMode.fullMode) {
      showFullError(elements, message);
    } else {
      setMessage(message);
    }
  }

  async function selectSession(slug) {
    const next = sessions.find((session) => session.slug === slug);

    if (!next) {
      const message = fullModeMissingSessionMessage(slug);

      if (pageMode.fullMode) {
        showFullError(elements, message);
      } else {
        setMessage(message);
      }

      return;
    }

    if (pageMode.fullMode && !next.alive) {
      showFullError(elements, fullModeDeadSessionMessage(slug));
      return;
    }

    hideFullError(elements);
    active = next;
    renderSessionList();
    renderActive();
    resetCounters();
    await connectPane(next);
  }

  async function connectPane(session) {
    joined = false;

    if (channel) {
      channel.leave();
      channel = null;
    }

    term.clear();
    setSocketStatus("connecting");
    setMessage("");

    try {
      const capture = await api(`/api/sessions/${encodeURIComponent(session.slug)}/screen`);

      if (capture.screen) {
        term.write(capture.screen);
      }
    } catch (error) {
      const message = `capture: ${error.message}`;
      setMessage(message);
      setSocketStatus("unavailable");

      if (pageMode.fullMode) {
        showFullError(elements, `Session unavailable: ${session.slug}`);
      }

      return;
    }

    if (!socket) {
      socket = new PhoenixCtor.Socket("/socket", {});
      socket.onError(() => setSocketStatus("error"));
      socket.onClose(() => setSocketStatus("closed"));
      socket.connect();
    }

    channel = socket.channel(`pane:${session.slug}`, {});

    channel
      .join()
      .receive("ok", () => {
        joined = true;
        fitTerminal(true);
        setSocketStatus(`connected ${session.slug}`);
        term.focus();
      })
      .receive("error", () => {
        setSocketStatus("join failed");

        if (pageMode.fullMode) {
          showFullError(elements, `Could not connect to ${session.slug}`);
        }
      });

    channel.on("output", handleOutput);
  }

  function openFullSession(slug) {
    const opened = openImpl(fullUrl(win.location.href, slug), "_blank");

    if (!opened) {
      setMessage(`open full blocked: ${slug}`);
    }
  }

  function handleOutput({ stream_id, seq, base64 }) {
    if (stream_id !== currentStreamId) {
      currentStreamId = stream_id;
      seenOutputSeqs.clear();
      seenOutputSeqQueue.length = 0;
      outputDecoder = new TextDecoderCtor();
    }

    const seqKey = seq === null ? null : `${stream_id ?? "legacy"}:${seq}`;

    if (seqKey !== null && seenOutputSeqs.has(seqKey)) {
      duplicateOutputs += 1;
      renderStatus(elements, statusSnapshot());
      return;
    }

    if (seqKey !== null) {
      seenOutputSeqs.add(seqKey);
      seenOutputSeqQueue.push(seqKey);

      while (seenOutputSeqQueue.length > maxSeenOutputSeqs) {
        seenOutputSeqs.delete(seenOutputSeqQueue.shift());
      }
    }

    const bytes = Uint8Array.from(atobImpl(base64), (char) => char.charCodeAt(0));
    outputEvents += 1;
    outputBytes += bytes.length;
    renderStatus(elements, statusSnapshot());
    term.write(outputDecoder.decode(bytes, { stream: true }));
  }

  function resetCounters() {
    outputEvents = 0;
    outputBytes = 0;
    inputEvents = 0;
    duplicateOutputs = 0;
    currentStreamId = null;
    seenOutputSeqs.clear();
    seenOutputSeqQueue.length = 0;
    outputDecoder = new TextDecoderCtor();
    renderStatus(elements, statusSnapshot());
  }

  function fitTerminal(forceNotify = false) {
    fitAddon.fit();
    const nextSize = { cols: term.cols, rows: term.rows };
    const changed = nextSize.cols !== lastSize.cols || nextSize.rows !== lastSize.rows;

    if (!changed && !forceNotify) {
      return;
    }

    lastSize.cols = nextSize.cols;
    lastSize.rows = nextSize.rows;
    renderStatus(elements, statusSnapshot());

    if (joined && channel) {
      channel.push("resize", nextSize);
    }
  }

  function scheduleFit() {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(fitTerminal, 50);
  }

  function bindEvents() {
    elements.form.addEventListener("submit", async (event) => {
      event.preventDefault();
      setMessage("");

      try {
        const body = await api("/api/sessions", {
          method: "POST",
          body: JSON.stringify({
            slug: elements.slug.value.trim(),
            command: selectedCommand(elements.commandPreset.value)
          })
        });

        elements.slug.value = "";
        await loadSessions();
        await selectSession(body.session.slug);
        setSuggestedSlug();
      } catch (error) {
        setMessage(`create: ${error.message}`);
      }
    });

    elements.refresh.addEventListener("click", async () => {
      try {
        await loadSessions();
        setMessage("refreshed");
      } catch (error) {
        setMessage(`refresh: ${error.message}`);
      }
    });

    elements.openFull.addEventListener("click", () => {
      if (active && active.alive) {
        openFullSession(active.slug);
      }
    });

    elements.slugReroll.addEventListener("click", () => {
      setSuggestedSlug();
      elements.slug.focus();
    });

    elements.stop.addEventListener("click", async () => {
      if (!active) {
        return;
      }

      if (!confirmImpl(`Stop ${active.session}?`)) {
        return;
      }

      try {
        const stopped = active.slug;
        await api(`/api/sessions/${encodeURIComponent(stopped)}`, { method: "DELETE" });

        if (channel) {
          channel.leave();
          channel = null;
        }

        active = null;
        joined = false;
        term.clear();
        renderActive();
        await loadSessions();
        setSocketStatus("idle");
        setMessage(`stopped ${stopped}`);
      } catch (error) {
        setMessage(`stop: ${error.message}`);
      }
    });

    term.onData((data) => {
      if (!channel || !joined) {
        return;
      }

      inputEvents += 1;
      renderStatus(elements, statusSnapshot());
      channel.push("input", { data });
    });

    win.addEventListener("resize", scheduleFit);
    new win.ResizeObserver(scheduleFit).observe(elements.terminal);
  }

  async function boot() {
    bindEvents();
    fitTerminal();

    if (win.lucide) {
      win.lucide.createIcons();
    }

    renderStatus(elements, statusSnapshot());
    await loadSessions().catch((error) => setMessage(`load: ${error.message}`));
  }

  return {
    boot,
    loadSessions,
    selectSession,
    renderSessionList,
    statusSnapshot
  };
}

export function bootHardlineManager(deps = {}) {
  const manager = createHardlineManager(deps);
  manager.boot();
  return manager;
}
