defmodule BabsWeb.TerminalLive do
  @moduledoc """
  Phase 1 browser terminal for one Citizen.

  The LiveView owns the page shell and client-side xterm bootstrap. PTY bytes and
  keyboard input still flow through `BabsWeb.PaneChannel`, so reloads do not bind
  Hardline.Pane to a LiveView process.
  """

  use Phoenix.LiveView

  alias Babs.Knowledge
  alias Babs.Knowledge.{Markdown, Watcher}
  alias Babs.Citizens.{Catalog, Lifecycle, StatusSnapshot}
  alias BabsWeb.CitizenPath
  alias Phoenix.LiveView.JS

  @refresh_ms 1_000
  @readme "Readme.md"
  @max_home_edit_bytes 256 * 1024
  @note_name_pattern ~r/^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$/

  @impl true
  def mount(_params, %{"slug" => slug} = session, socket) do
    full? = full?(session)

    if connected?(socket) and not full? do
      schedule_refresh()
      :ok = Phoenix.PubSub.subscribe(Babs.Citizens.PubSub, Watcher.topic())
    end

    default_page_tab = session_page_tab(session)

    socket =
      socket
      |> assign(:slug, slug)
      |> assign(:socket_token, Map.get(session, "socket_token", ""))
      |> assign(:full?, full?)
      |> assign(:default_page_tab, default_page_tab)
      |> assign(:default_params, session_default_params(session))
      |> assign(:page_tab, default_page_tab)
      |> assign(:home, empty_home())
      |> assign(:lifecycle_inflight, %{})
      |> assign_tabs()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{full?: true}} = socket), do: {:noreply, socket}

  def handle_params(params, _uri, socket) do
    params = Map.merge(socket.assigns.default_params, normalize_params(params))
    page_tab = parse_page_tab(Map.get(params, "tab"), socket.assigns.default_page_tab)

    socket = assign(socket, :page_tab, page_tab)
    socket = if page_tab == :home, do: assign_home(socket, params), else: socket

    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh_terminal_tabs, socket) do
    if connected?(socket) and not socket.assigns.full?, do: schedule_refresh()

    {:noreply, assign_tabs(socket)}
  end

  def handle_info({:knowledge_changed, slug, _name}, %{assigns: %{slug: slug}} = socket) do
    if page_tab(socket.assigns) == :home and not home_editing?(socket.assigns.home) do
      {:noreply, refresh_home(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:knowledge_changed, _slug, _name}, socket), do: {:noreply, socket}

  @impl true
  def handle_event("home_edit", _params, socket) do
    {:noreply, start_home_edit(socket)}
  end

  def handle_event("home_cancel_edit", _params, socket) do
    {:noreply, cancel_home_edit(socket)}
  end

  def handle_event("home_validate", params, %{assigns: %{home: home}} = socket) do
    if home_editing?(home) do
      validate_home_edit(socket, params)
    else
      {:noreply, socket}
    end
  end

  def handle_event("home_save", params, %{assigns: %{home: home}} = socket) do
    if home_editing?(home) do
      submit_home_edit(socket, params)
    else
      {:noreply, socket}
    end
  end

  def handle_event("home_note_validate", params, socket) do
    name = home_note_name(params)
    error = if name == "", do: nil, else: validate_home_note_name(name)

    {:noreply, update_home_note_form(socket, %{name: name, error: error})}
  end

  def handle_event("home_note_create", params, socket) do
    name = home_note_name(params)

    case validate_home_note_name(name) do
      nil -> create_home_note(socket, name)
      error -> {:noreply, update_home_note_form(socket, %{name: name, error: error})}
    end
  end

  def handle_event("lifecycle", %{"action" => action, "slug" => slug}, socket) do
    case parse_action(action) do
      {:ok, action} ->
        {:noreply, start_lifecycle(socket, action, slug)}

      :error ->
        {:noreply, put_flash(socket, :error, "Unknown lifecycle action")}
    end
  end

  defp validate_home_edit(socket, params) do
    content = home_edit_content(params)
    error = validate_home_edit_content(content)

    socket =
      socket
      |> update_home_edit(&Map.merge(&1, %{content: content, error: error}))

    {:noreply, socket}
  end

  defp submit_home_edit(socket, params) do
    content = home_edit_content(params)

    case validate_home_edit_content(content) do
      nil ->
        {:noreply, save_home_edit(socket, content)}

      error ->
        {:noreply, update_home_edit(socket, &Map.merge(&1, %{content: content, error: error}))}
    end
  end

  @impl true
  def handle_async({:lifecycle, slug, action}, {:ok, result}, socket) do
    socket =
      socket
      |> clear_lifecycle_inflight(slug)
      |> apply_lifecycle_result(action, slug, result)

    {:noreply, socket}
  end

  def handle_async({:lifecycle, slug, action}, {:exit, reason}, socket) do
    socket =
      socket
      |> clear_lifecycle_inflight(slug)
      |> apply_lifecycle_result(action, slug, {:error, reason})

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <link rel="stylesheet" href="/css/xterm.css" />
    <style>
      :root {
        color-scheme: dark;
        --bg: #0d0d10;
        --terminal-bg: #000000;
        --line: #2a2a30;
        --text: #e7eaf0;
        --muted: #9c9caa;
        --ok: #43d17d;
        --wait: #d7ae55;
        --paused: #9da5b4;
        --danger: #dc6b6b;
        --accent: #55b3a6;
      }

      * {
        box-sizing: border-box;
      }

      html, body, body > div, .terminal-page {
        height: 100%;
        margin: 0;
        background: var(--bg);
      }

      .terminal-page {
        --terminal-chrome-height: 46px;
        min-height: 100vh;
        width: 100vw;
        overflow: hidden;
      }

      .terminal-chrome {
        height: var(--terminal-chrome-height);
        display: grid;
        grid-template-columns: auto auto minmax(0, 1fr) auto auto auto;
        align-items: center;
        gap: 8px;
        border-bottom: 1px solid var(--line);
        background: #14151a;
        padding: 6px 8px;
      }

      .terminal-link,
      .citizen-page-tab,
      .terminal-tab {
        min-height: 32px;
        border: 1px solid var(--line);
        border-radius: 6px;
        background: #1a1d24;
        color: var(--muted);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 7px;
        padding: 5px 9px;
        text-decoration: none;
        white-space: nowrap;
      }

      button.terminal-link {
        font: inherit;
        cursor: pointer;
      }

      .terminal-link:hover,
      .citizen-page-tab:hover,
      .terminal-tab:hover {
        border-color: var(--accent);
        color: var(--text);
      }

      .terminal-link[disabled],
      .terminal-link.is-disabled {
        cursor: not-allowed;
        opacity: 0.55;
      }

      .terminal-link[disabled]:hover,
      .terminal-link.is-disabled:hover {
        border-color: var(--line);
        color: var(--muted);
      }

      .terminal-danger:hover {
        border-color: var(--danger);
      }

      .terminal-tabs {
        min-width: 0;
        display: flex;
        gap: 6px;
        overflow-x: auto;
        scrollbar-width: thin;
      }

      .citizen-page-tabs {
        display: inline-flex;
        gap: 6px;
      }

      .citizen-page-tab,
      .terminal-tab {
        max-width: 180px;
        flex: 0 0 auto;
      }

      .terminal-tab-label {
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .citizen-page-tab.is-active,
      .terminal-tab.is-active {
        border-color: var(--accent);
        color: var(--text);
        background: #20252b;
      }

      .terminal-actions {
        display: flex;
        gap: 6px;
      }

      .terminal-roles {
        min-width: 0;
        max-width: min(260px, 24vw);
        display: flex;
        gap: 5px;
        overflow-x: auto;
        scrollbar-width: thin;
      }

      .terminal-role-chip {
        min-width: 0;
        max-width: 150px;
        border: 1px solid var(--line);
        border-radius: 999px;
        color: var(--accent);
        display: inline-flex;
        align-items: center;
        gap: 5px;
        padding: 4px 8px;
        font-size: 12px;
        white-space: nowrap;
      }

      .terminal-role-chip .icon {
        width: 13px;
        height: 13px;
        flex: 0 0 auto;
      }

      .terminal-role-name,
      .terminal-role-skills {
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .terminal-role-skills {
        color: var(--muted);
      }

      .terminal-flash {
        min-width: 0;
        color: var(--muted);
        font-size: 12px;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .terminal-flash-error {
        color: var(--danger);
      }

      .ownership-badge,
      .lifecycle-reminder {
        border: 1px solid var(--line);
        border-radius: 999px;
        padding: 4px 8px;
        color: var(--wait);
        font-size: 12px;
        white-space: nowrap;
      }

      .lifecycle-reminder {
        color: var(--muted);
      }

      .status-dot {
        width: 8px;
        height: 8px;
        flex: 0 0 auto;
        border-radius: 999px;
        background: var(--paused);
      }

      .status-up .status-dot { background: var(--ok); }
      .status-reattaching .status-dot { background: var(--wait); }
      .status-stopped .status-dot { background: var(--paused); }
      .status-failed .status-dot { background: var(--danger); }

      #terminal {
        width: 100vw;
        overflow: hidden;
        background: var(--terminal-bg);
      }

      .terminal-page[data-mode="tabs"][data-page-tab="terminal"] #terminal {
        height: calc(100vh - var(--terminal-chrome-height));
      }

      .terminal-page[data-mode="full"] #terminal {
        height: 100vh;
      }

      #terminal[data-terminal-visible="false"] {
        visibility: hidden;
        height: 0;
        min-height: 0;
        overflow: hidden;
        pointer-events: none;
      }

      .terminal-page[data-page-tab="home"] {
        overflow: auto;
      }

      .terminal-page[data-page-tab="home"] #connection-status {
        display: none;
      }

      .citizen-home {
        min-height: calc(100vh - var(--terminal-chrome-height));
        background: var(--bg);
        color: var(--text);
        padding: 20px;
      }

      .citizen-home[data-home-visible="false"] {
        display: none;
      }

      .citizen-home-layout {
        width: min(1180px, 100%);
        margin: 0 auto;
        display: grid;
        grid-template-columns: minmax(180px, 260px) minmax(0, 1fr);
        gap: 20px;
        align-items: start;
      }

      .knowledge-sidebar {
        border-right: 1px solid var(--line);
        padding-right: 16px;
      }

      .knowledge-sidebar-title {
        margin: 0 0 10px;
        color: var(--muted);
        font: 600 12px/1.4 system-ui, sans-serif;
        text-transform: uppercase;
      }

      .knowledge-files {
        display: grid;
        gap: 6px;
      }

      .knowledge-sidebar-section {
        margin-top: 16px;
      }

      .knowledge-sidebar-subtitle,
      .knowledge-note-create-label {
        margin: 0 0 8px;
        color: var(--muted);
        display: block;
        font: 600 12px/1.4 system-ui, sans-serif;
        text-transform: uppercase;
      }

      .knowledge-file-link {
        min-width: 0;
        border: 1px solid transparent;
        border-radius: 6px;
        color: var(--text);
        padding: 7px 8px;
        text-decoration: none;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .knowledge-file-link:hover,
      .knowledge-file-link.is-active {
        border-color: var(--accent);
        background: #171c23;
      }

      .knowledge-empty,
      .knowledge-error {
        color: var(--muted);
        font: 14px/1.5 system-ui, sans-serif;
      }

      .knowledge-error {
        color: var(--danger);
      }

      .knowledge-note-create-form {
        margin-top: 18px;
        display: grid;
        gap: 8px;
      }

      .knowledge-note-create-row {
        display: flex;
        gap: 6px;
      }

      .knowledge-note-create-input {
        min-width: 0;
        min-height: 32px;
        flex: 1 1 auto;
        border: 1px solid var(--line);
        border-radius: 6px;
        background: #101217;
        color: var(--text);
        padding: 5px 8px;
        font: 13px/1.4 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      }

      .knowledge-note-create-input:focus {
        outline: none;
        border-color: var(--accent);
        box-shadow: 0 0 0 2px rgba(85, 179, 166, 0.18);
      }

      .knowledge-note-create-button {
        min-height: 32px;
        border: 1px solid var(--line);
        border-radius: 6px;
        background: #18342f;
        color: var(--text);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        padding: 5px 10px;
        font: inherit;
        cursor: pointer;
        white-space: nowrap;
      }

      .knowledge-note-create-button:hover {
        border-color: var(--accent);
      }

      .knowledge-document {
        min-width: 0;
        color: var(--text);
      }

      .knowledge-document-header {
        max-width: 760px;
        margin: 0 0 16px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
      }

      .knowledge-document-title {
        min-width: 0;
        margin: 0;
        color: var(--muted);
        font: 600 13px/1.4 system-ui, sans-serif;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .knowledge-edit-button,
      .knowledge-save-button,
      .knowledge-cancel-button {
        min-height: 32px;
        border: 1px solid var(--line);
        border-radius: 6px;
        background: #1a1d24;
        color: var(--text);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        padding: 5px 10px;
        font: inherit;
        cursor: pointer;
        white-space: nowrap;
      }

      .knowledge-edit-button:hover,
      .knowledge-save-button:hover,
      .knowledge-cancel-button:hover {
        border-color: var(--accent);
      }

      .knowledge-save-button {
        background: #18342f;
      }

      .knowledge-edit-form {
        max-width: 760px;
        display: grid;
        gap: 10px;
      }

      .knowledge-edit-textarea {
        width: 100%;
        min-height: 340px;
        border: 1px solid var(--line);
        border-radius: 6px;
        background: #101217;
        color: var(--text);
        padding: 12px;
        font: 14px/1.55 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
        resize: vertical;
      }

      .knowledge-edit-textarea:focus {
        outline: none;
        border-color: var(--accent);
        box-shadow: 0 0 0 2px rgba(85, 179, 166, 0.18);
      }

      .knowledge-edit-actions {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
        align-items: center;
      }

      .knowledge-edit-meta {
        color: var(--muted);
        font: 12px/1.5 system-ui, sans-serif;
      }

      .knowledge-edit-error {
        margin: 0;
        color: var(--danger);
        font: 14px/1.5 system-ui, sans-serif;
      }

      .knowledge-rendered {
        max-width: 760px;
        color: var(--text);
        font: 15px/1.65 system-ui, sans-serif;
      }

      .knowledge-rendered h1,
      .knowledge-rendered h2,
      .knowledge-rendered h3 {
        line-height: 1.2;
        margin: 0 0 14px;
      }

      .knowledge-rendered p {
        margin: 0 0 12px;
      }

      .knowledge-rendered a {
        color: var(--accent);
      }

      #connection-status {
        position: fixed;
        top: 8px;
        right: 10px;
        z-index: 10;
        padding: 5px 8px;
        border: 1px solid var(--line);
        border-radius: 6px;
        background: rgba(16, 16, 20, 0.82);
        color: var(--muted);
        display: inline-flex;
        align-items: center;
        gap: 6px;
        font: 12px/1.4 system-ui, sans-serif;
      }

      #connection-status::before {
        content: "";
        width: 7px;
        height: 7px;
        border-radius: 999px;
        background: var(--muted);
        box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.35);
      }

      #connection-status[data-state="connected"] { color: var(--ok); }
      #connection-status[data-state="error"] { color: var(--danger); }
      #connection-status[data-state="connected"]::before { background: var(--ok); }
      #connection-status[data-state="error"]::before { background: var(--danger); }

      .terminal-page[data-mode="tabs"] #connection-status {
        top: calc(var(--terminal-chrome-height) + 8px);
      }

      @media (max-width: 680px) {
        .terminal-page { --terminal-chrome-height: 176px; }
        .terminal-chrome {
          height: auto;
          min-height: var(--terminal-chrome-height);
          grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
          grid-auto-rows: auto;
          align-items: stretch;
        }
        .terminal-chrome [data-testid="citizens-link"] {
          grid-column: 1 / -1;
        }
        .terminal-actions {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
        .terminal-tabs {
          grid-column: 1 / -1;
        }
        .citizen-page-tabs {
          grid-column: 1 / -1;
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
        .terminal-chrome [data-testid="terminal-full-link"] {
          min-width: 0;
        }
        .terminal-flash {
          grid-column: 1 / -1;
          white-space: normal;
          overflow-wrap: anywhere;
        }
        .terminal-roles {
          grid-column: 1 / -1;
          max-width: 100%;
        }
        .citizen-home {
          padding: 14px;
        }
        .citizen-home-layout {
          grid-template-columns: minmax(0, 1fr);
        }
        .knowledge-sidebar {
          border-right: 0;
          border-bottom: 1px solid var(--line);
          padding: 0 0 14px;
        }
        .knowledge-document-header {
          align-items: stretch;
          flex-direction: column;
        }
        .knowledge-note-create-row {
          align-items: stretch;
          flex-direction: column;
        }
        .knowledge-edit-button {
          width: 100%;
        }
        .knowledge-note-create-button {
          width: 100%;
        }
      }
    </style>
    <% page_tab = page_tab(assigns) %>
    <% home = home(assigns) %>
    <div
      class="terminal-page"
      data-mode={if @full?, do: "full", else: "tabs"}
      data-page-tab={page_tab}
    >
      <nav :if={!@full?} class="terminal-chrome" data-testid="terminal-chrome" aria-label="Citizen terminal navigation">
        <a class="terminal-link" href={CitizenPath.index(@socket_token)} data-testid="citizens-link">Citizens</a>
        <div class="citizen-page-tabs" aria-label="Citizen page tabs">
          <.terminal_nav_link
            slug={@slug}
            class={page_tab_class(page_tab, :home)}
            to={page_tab_path(@slug, @socket_token, :home)}
            testid="citizen-page-tab-home"
          >
            Home
          </.terminal_nav_link>
          <.terminal_nav_link
            slug={@slug}
            class={page_tab_class(page_tab, :terminal)}
            to={page_tab_path(@slug, @socket_token, :terminal)}
            testid="citizen-page-tab-terminal"
          >
            Terminal
          </.terminal_nav_link>
        </div>
        <div class="terminal-tabs" aria-label="Citizen tabs">
          <a
            :for={citizen <- live_tabs(@tabs, @slug)}
            class={tab_class(citizen, @slug)}
            href={citizen_tab_path(citizen.slug, @socket_token, page_tab)}
            data-testid={"citizen-tab-#{citizen.slug}"}
          >
            <span class="status-dot" aria-hidden="true"></span>
            <span class="terminal-tab-label">{citizen.slug}</span>
          </a>
         </div>
        <div
          :if={active_roles(active_tab(@tabs, @slug)) != []}
          class="terminal-roles"
          data-testid={"terminal-roles-#{@slug}"}
        >
          <span
            :for={{role, index} <- Enum.with_index(active_roles(active_tab(@tabs, @slug)))}
            class="terminal-role-chip"
            data-testid={"terminal-role-#{@slug}-#{index}"}
            title={role_title(role)}
          >
            <BabsWeb.Icon.icon name="tag" />
            <span class="terminal-role-name">{role_name(role)}</span>
            <span :if={role_skills(role) != []} class="terminal-role-skills">
              {Enum.join(role_skills(role), ", ")}
            </span>
          </span>
        </div>
        <span
          :if={ownership_badge(active_tab(@tabs, @slug))}
          class="ownership-badge"
          data-testid="terminal-ownership-badge"
        >
          {ownership_badge(active_tab(@tabs, @slug))}
        </span>
        <div
          class="terminal-actions"
          data-testid="terminal-lifecycle-controls"
          data-terminal-lifecycle-scope={@slug}
        >
          <button
            :if={action?(active_tab(@tabs, @slug), :start)}
            type="button"
            class={["terminal-link", lifecycle_busy?(@lifecycle_inflight, @slug) && "is-disabled"]}
            phx-click={lifecycle_click(@slug, :start)}
            disabled={lifecycle_busy?(@lifecycle_inflight, @slug)}
            phx-disable-with="Starting"
             data-testid="terminal-start"
           >
             {button_label(active_tab(@tabs, @slug), :start)}
           </button>
          <button
            :if={action?(active_tab(@tabs, @slug), :stop)}
            type="button"
            class={[
              "terminal-link terminal-danger",
              lifecycle_busy?(@lifecycle_inflight, @slug) && "is-disabled"
            ]}
            phx-click={lifecycle_click(@slug, :stop)}
            disabled={lifecycle_busy?(@lifecycle_inflight, @slug)}
            phx-disable-with="Stopping"
             data-testid="terminal-stop"
           >
             {button_label(active_tab(@tabs, @slug), :stop)}
           </button>
          <span
            :if={action?(active_tab(@tabs, @slug), :stop) && lifecycle_reminder(active_tab(@tabs, @slug))}
            class="lifecycle-reminder"
            data-testid="terminal-lifecycle-reminder"
          >
            {lifecycle_reminder(active_tab(@tabs, @slug))}
          </span>
          <button
            :if={action?(active_tab(@tabs, @slug), :restart)}
            type="button"
            class={["terminal-link", lifecycle_busy?(@lifecycle_inflight, @slug) && "is-disabled"]}
            phx-click={lifecycle_click(@slug, :restart)}
            disabled={lifecycle_busy?(@lifecycle_inflight, @slug)}
            phx-disable-with="Restarting"
             data-testid="terminal-restart"
           >
             {button_label(active_tab(@tabs, @slug), :restart)}
           </button>
        </div>
        <a
          class="terminal-link"
          href={CitizenPath.terminal(@slug, @socket_token, full?: true)}
          data-testid="terminal-full-link"
        >
          Full
        </a>
        <span
          :if={flash(assigns, :info)}
          class="terminal-flash"
          data-testid="terminal-flash-info"
        >
          {flash(assigns, :info)}
        </span>
        <span
          :if={flash(assigns, :error)}
          class="terminal-flash terminal-flash-error"
          data-testid="terminal-flash-error"
        >
          {flash(assigns, :error)}
        </span>
      </nav>
      <section
        :if={!@full?}
        class="citizen-home"
        data-testid="citizen-home"
        data-home-visible={visible_attr(page_tab == :home)}
      >
        <div class="citizen-home-layout">
          <aside class="knowledge-sidebar" aria-label="Knowledge files">
            <h2 class="knowledge-sidebar-title">Knowledge</h2>
            <p :if={home.list_error} class="knowledge-error" data-testid="knowledge-list-error">
              {home.list_error}
            </p>
            <div :if={home.files == []} class="knowledge-empty" data-testid="knowledge-file-empty">
              No knowledge files yet.
            </div>
            <% root_files = knowledge_root_files(home.files) %>
            <% note_files = knowledge_note_files(home.files) %>
            <nav :if={root_files != []} class="knowledge-files">
              <.terminal_nav_link
                :for={file <- root_files}
                slug={@slug}
                class={knowledge_file_class(file, home.selected_file)}
                to={knowledge_file_path(@slug, @socket_token, file)}
                testid={"knowledge-file-#{file}"}
              >
                {knowledge_file_label(file)}
              </.terminal_nav_link>
            </nav>
            <section
              :if={note_files != []}
              class="knowledge-sidebar-section"
              data-testid="knowledge-notes"
            >
              <h3 class="knowledge-sidebar-subtitle">Notes</h3>
              <nav class="knowledge-files">
                <.terminal_nav_link
                  :for={file <- note_files}
                  slug={@slug}
                  class={knowledge_file_class(file, home.selected_file)}
                  to={knowledge_file_path(@slug, @socket_token, file)}
                  testid={"knowledge-file-#{file}"}
                >
                  {knowledge_file_label(file)}
                </.terminal_nav_link>
              </nav>
            </section>
            <form
              :if={home_note_create_available?(home)}
              class="knowledge-note-create-form"
              phx-change="home_note_validate"
              phx-submit="home_note_create"
              data-testid="knowledge-note-create-form"
            >
              <label class="knowledge-note-create-label" for="knowledge-note-name">
                New note
              </label>
              <div class="knowledge-note-create-row">
                <input
                  id="knowledge-note-name"
                  class="knowledge-note-create-input"
                  type="text"
                  name="note[name]"
                  value={home.note_form.name}
                  placeholder="build-plan"
                  autocomplete="off"
                  data-testid="knowledge-note-create-name"
                />
                <button
                  type="submit"
                  class="knowledge-note-create-button"
                  phx-disable-with="Creating"
                  data-testid="knowledge-note-create-button"
                >
                  Create
                </button>
              </div>
              <p
                :if={home.note_form.error}
                class="knowledge-edit-error"
                data-testid="knowledge-note-create-error"
              >
                {home.note_form.error}
              </p>
            </form>
          </aside>
          <article class="knowledge-document" data-testid="knowledge-document">
            <div class="knowledge-document-header">
              <h1 class="knowledge-document-title">{home.selected_file}</h1>
              <button
                :if={home_edit_available?(home)}
                type="button"
                class="knowledge-edit-button"
                phx-click="home_edit"
                data-testid="knowledge-edit-button"
              >
                Edit
              </button>
            </div>
            <form
              :if={home_editing?(home)}
              class="knowledge-edit-form"
              phx-change="home_validate"
              phx-submit="home_save"
              data-testid="knowledge-edit-form"
            >
              <textarea
                class="knowledge-edit-textarea"
                name="home[content]"
                phx-debounce="300"
                data-testid="knowledge-edit-content"
              >{home.edit.content}</textarea>
              <p
                :if={home.edit.error}
                class="knowledge-edit-error"
                data-testid="knowledge-edit-error"
              >
                {home.edit.error}
              </p>
              <div class="knowledge-edit-actions">
                <button
                  type="submit"
                  class="knowledge-save-button"
                  phx-disable-with="Saving"
                  data-testid="knowledge-save-button"
                >
                  Save
                </button>
                <button
                  type="button"
                  class="knowledge-cancel-button"
                  phx-click="home_cancel_edit"
                  phx-disable-with="Canceling"
                  data-testid="knowledge-cancel-edit"
                >
                  Cancel
                </button>
                <span class="knowledge-edit-meta">
                  {home_edit_size(home.edit.content)} / {max_home_edit_bytes()} bytes
                </span>
              </div>
            </form>
            <div
              :if={!home_editing?(home) && home.document.status == :ok}
              class="knowledge-rendered"
              data-testid="knowledge-rendered"
            >
              {safe_html(home.document.html)}
            </div>
            <p
              :if={!home_editing?(home) && home.document.status == :empty}
              class="knowledge-empty"
              data-testid="knowledge-empty-state"
            >
              {home.document.message}
            </p>
            <p
              :if={!home_editing?(home) && home.document.status == :error}
              class="knowledge-error"
              data-testid="knowledge-render-error"
            >
              {home.document.message}
            </p>
          </article>
        </div>
      </section>
      <div
        id="connection-status"
        phx-update="ignore"
        data-testid="connection-status"
        data-state="connecting"
      >
        connecting
      </div>
      <div
        id="terminal"
        phx-update="ignore"
        data-testid="terminal"
        data-slug={@slug}
        data-socket-token={@socket_token}
        data-terminal-visible={visible_attr(terminal_visible?(@full?, page_tab))}
      >
      </div>
    </div>
    <script src="/js/xterm.js">
    </script>
    <script src="/js/xterm-addon-fit.js">
    </script>
    <script type="module" src="/js/terminal_boot.js">
    </script>
    <script :if={!@full?} type="module" src="/js/live_boot.js">
    </script>
    """
  end

  defp normalize_params(params) when is_map(params), do: params
  defp normalize_params(_params), do: %{}

  defp session_page_tab(%{"tab" => "terminal"}), do: :terminal
  defp session_page_tab(%{"tab" => "home"}), do: :home
  defp session_page_tab(_session), do: :home

  defp session_default_params(session) do
    %{}
    |> maybe_put_default_param("tab", Map.get(session, "tab"))
    |> maybe_put_default_param("file", Map.get(session, "file"))
  end

  defp maybe_put_default_param(params, key, value) when is_binary(value) do
    case String.trim(value) do
      "" -> params
      value -> Map.put(params, key, value)
    end
  end

  defp maybe_put_default_param(params, _key, _value), do: params

  defp parse_page_tab("terminal", _default), do: :terminal
  defp parse_page_tab("home", _default), do: :home
  defp parse_page_tab(nil, default) when default in [:home, :terminal], do: default
  defp parse_page_tab(_tab, _default), do: :home

  defp page_tab(%{page_tab: tab}) when tab in [:home, :terminal], do: tab
  defp page_tab(_assigns), do: :terminal

  defp page_tab_class(active, tab) do
    if active == tab do
      "citizen-page-tab is-active"
    else
      "citizen-page-tab"
    end
  end

  defp terminal_visible?(true, _page_tab), do: true
  defp terminal_visible?(false, :terminal), do: true
  defp terminal_visible?(_full?, _page_tab), do: false

  defp visible_attr(true), do: "true"
  defp visible_attr(false), do: "false"

  defp terminal_nav_link(%{slug: "new"} = assigns) do
    ~H"""
    <a class={@class} href={@to} data-testid={@testid}>
      {render_slot(@inner_block)}
    </a>
    """
  end

  defp terminal_nav_link(assigns) do
    ~H"""
    <.link class={@class} patch={@to} data-testid={@testid}>
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp page_tab_path("new", socket_token, :home),
    do: CitizenPath.terminal("new", socket_token, tab: :home, explicit_tab?: true)

  defp page_tab_path(slug, socket_token, :home), do: CitizenPath.terminal(slug, socket_token)

  defp page_tab_path(slug, socket_token, :terminal),
    do: CitizenPath.terminal(slug, socket_token, tab: :terminal)

  defp citizen_tab_path(slug, socket_token, :terminal) do
    CitizenPath.terminal(slug, socket_token, tab: :terminal)
  end

  defp citizen_tab_path(slug, socket_token, _page_tab),
    do: CitizenPath.terminal(slug, socket_token)

  defp home(%{home: home}), do: home
  defp home(_assigns), do: empty_home()

  defp empty_home do
    %{
      files: [],
      selected_file: @readme,
      list_error: nil,
      document: %{status: :empty, html: "", message: "This file does not exist yet."},
      edit: inactive_home_edit(),
      note_form: inactive_home_note_form()
    }
  end

  defp inactive_home_edit do
    %{
      active?: false,
      file: nil,
      content: "",
      base_content: nil,
      base_missing?: false,
      error: nil
    }
  end

  defp inactive_home_note_form do
    %{
      name: "",
      error: nil
    }
  end

  defp assign_home(socket, params) do
    assign(socket, :home, load_home(socket.assigns.slug, Map.get(params, "file")))
  end

  defp refresh_home(socket) do
    selected_file = socket.assigns.home.selected_file
    assign(socket, :home, load_home(socket.assigns.slug, selected_file))
  end

  defp load_home(slug, requested_file) do
    case Knowledge.list(slug) do
      {:ok, files} ->
        selected_file = selected_knowledge_file(files, requested_file)

        %{
          files: files,
          selected_file: selected_file,
          list_error: nil,
          document: load_document(slug, selected_file),
          edit: inactive_home_edit(),
          note_form: inactive_home_note_form()
        }

      {:error, reason} ->
        %{
          files: [],
          selected_file: @readme,
          list_error: friendly_list_error(reason),
          document: load_document(slug, @readme),
          edit: inactive_home_edit(),
          note_form: inactive_home_note_form()
        }
    end
  end

  defp selected_knowledge_file(files, requested_file) when is_binary(requested_file) do
    requested_file = String.trim(requested_file)

    if requested_file in files do
      requested_file
    else
      @readme
    end
  end

  defp selected_knowledge_file(_files, _requested_file), do: @readme

  defp load_document(slug, file) do
    with {:ok, markdown} <- Knowledge.read(slug, file),
         :ok <- validate_utf8(markdown),
         {:ok, rendered} <- Markdown.render(markdown) do
      if String.trim(rendered.body) == "" do
        %{status: :empty, html: "", message: "This file is empty."}
      else
        %{status: :ok, html: rendered.html, message: nil}
      end
    else
      {:error, {:not_found, _path}} ->
        %{status: :empty, html: "", message: "This file does not exist yet."}

      {:error, reason} ->
        %{status: :error, html: "", message: friendly_document_error(reason)}
    end
  end

  defp validate_utf8(markdown) do
    if String.valid?(markdown), do: :ok, else: {:error, {:invalid_markdown, :invalid_utf8}}
  end

  defp start_home_edit(socket) do
    file = socket.assigns.home.selected_file || @readme

    case read_home_edit_source(socket.assigns.slug, file) do
      {:ok, content, base_missing?} ->
        assign_home_edit(socket, %{
          active?: true,
          file: file,
          content: content,
          base_content: content,
          base_missing?: base_missing?,
          error: nil
        })

      {:error, reason} ->
        socket
        |> cancel_home_edit()
        |> put_flash(:error, friendly_edit_error(reason))
    end
  end

  defp cancel_home_edit(socket),
    do: refresh_home(socket)

  defp save_home_edit(socket, content) do
    edit = socket.assigns.home.edit
    file = edit.file || @readme

    case Knowledge.write(socket.assigns.slug, file, content, before_rename: stale_guard(edit)) do
      :ok ->
        socket
        |> assign(:home, load_home(socket.assigns.slug, file))
        |> put_flash(:info, "Saved #{file}")

      {:error, reason} ->
        update_home_edit(
          socket,
          &Map.merge(&1, %{content: content, error: friendly_save_error(reason)})
        )
    end
  end

  defp create_home_note(socket, name) do
    file = Path.join("notes", "#{name}.md")
    content = "# #{name}\n\n"

    case Knowledge.write(socket.assigns.slug, file, content, if_exists: :error) do
      :ok ->
        socket =
          socket
          |> put_flash(:info, "Created #{file}")
          |> push_patch(
            to: knowledge_file_path(socket.assigns.slug, socket.assigns.socket_token, file)
          )

        {:noreply, socket}

      {:error, reason} ->
        {:noreply,
         update_home_note_form(socket, %{name: name, error: friendly_note_create_error(reason)})}
    end
  end

  defp read_home_edit_source(slug, file) do
    case Knowledge.read(slug, file) do
      {:ok, content} ->
        if String.valid?(content) do
          {:ok, content, false}
        else
          {:error, {:invalid_markdown, :invalid_utf8}}
        end

      {:error, {:not_found, _path}} ->
        {:ok, "", true}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stale_guard(%{base_missing?: true}) do
    fn _temp_path, final_path ->
      case File.read(final_path) do
        {:error, :enoent} -> :ok
        {:ok, _content} -> {:error, :stale_home_edit}
        {:error, reason} -> {:error, {:verify_home_edit, reason}}
      end
    end
  end

  defp stale_guard(%{base_content: base_content}) do
    fn _temp_path, final_path ->
      case File.read(final_path) do
        {:ok, ^base_content} -> :ok
        {:ok, _content} -> {:error, :stale_home_edit}
        {:error, reason} -> {:error, {:verify_home_edit, reason}}
      end
    end
  end

  defp home_edit_content(%{"home" => %{"content" => content}}) when is_binary(content),
    do: content

  defp home_edit_content(_params), do: ""

  defp home_note_name(%{"note" => %{"name" => name}}) when is_binary(name),
    do: String.trim(name)

  defp home_note_name(_params), do: ""

  defp validate_home_note_name(""), do: "Note name is required."

  defp validate_home_note_name(name) do
    if Regex.match?(@note_name_pattern, name) do
      nil
    else
      "Use a-z, 0-9, and hyphens."
    end
  end

  defp validate_home_edit_content(content) when is_binary(content) do
    cond do
      not String.valid?(content) ->
        "Knowledge home must be valid UTF-8 text."

      byte_size(content) > @max_home_edit_bytes ->
        "Knowledge home must be 256 KiB or smaller."

      true ->
        nil
    end
  end

  defp validate_home_edit_content(_content), do: "Knowledge home must be valid UTF-8 text."

  defp assign_home_edit(socket, edit) do
    assign(socket, :home, Map.put(socket.assigns.home, :edit, edit))
  end

  defp update_home_edit(socket, fun) do
    edit = socket.assigns.home |> Map.get(:edit, inactive_home_edit()) |> fun.()
    assign_home_edit(socket, edit)
  end

  defp update_home_note_form(socket, attrs) do
    note_form =
      socket.assigns.home
      |> Map.get(:note_form, inactive_home_note_form())
      |> Map.merge(attrs)

    assign(socket, :home, Map.put(socket.assigns.home, :note_form, note_form))
  end

  defp home_edit_available?(home), do: home.list_error == nil and not home_editing?(home)
  defp home_note_create_available?(home), do: home.list_error == nil and not home_editing?(home)

  defp home_editing?(%{edit: %{active?: true}}), do: true
  defp home_editing?(_home), do: false

  defp home_edit_size(content) when is_binary(content), do: byte_size(content)
  defp home_edit_size(_content), do: 0

  defp max_home_edit_bytes, do: @max_home_edit_bytes

  defp friendly_edit_error(_reason), do: "Unable to edit this knowledge file."

  defp friendly_save_error({:redacted_io_error, {:before_rename_knowledge, :stale_home_edit}}),
    do: "This file changed on disk. Reload before saving."

  defp friendly_save_error(
         {:redacted_io_error, {:before_rename_knowledge, {:verify_home_edit, _reason}}}
       ),
       do: "Unable to verify this file before saving. Try again."

  defp friendly_save_error(_reason), do: "Unable to save this knowledge file."

  defp friendly_note_create_error({:knowledge_file_exists, _file}),
    do: "That note already exists."

  defp friendly_note_create_error(_reason), do: "Unable to create this note."

  defp friendly_list_error(_reason), do: "Unable to read knowledge files."

  defp friendly_document_error({:invalid_frontmatter, _reason}),
    do: "Unable to render this knowledge file."

  defp friendly_document_error({:invalid_markdown, _reason}),
    do: "Unable to render this knowledge file."

  defp friendly_document_error({:render_failed, _reason}),
    do: "Unable to render this knowledge file."

  defp friendly_document_error(_reason), do: "Unable to read this knowledge file."

  defp knowledge_file_class(file, selected_file) do
    if file == selected_file do
      "knowledge-file-link is-active"
    else
      "knowledge-file-link"
    end
  end

  defp knowledge_root_files(files) do
    Enum.reject(files, &String.starts_with?(&1, "notes/"))
  end

  defp knowledge_note_files(files) do
    Enum.filter(files, &String.starts_with?(&1, "notes/"))
  end

  defp knowledge_file_label("notes/" <> note), do: Path.basename(note, ".md")
  defp knowledge_file_label(file), do: file

  defp knowledge_file_path("new", socket_token, @readme),
    do: CitizenPath.terminal("new", socket_token, tab: :home, explicit_tab?: true)

  defp knowledge_file_path(slug, socket_token, @readme),
    do: CitizenPath.terminal(slug, socket_token)

  defp knowledge_file_path("new", socket_token, file),
    do: CitizenPath.terminal("new", socket_token, tab: :home, file: file, explicit_tab?: true)

  defp knowledge_file_path(slug, socket_token, file),
    do: CitizenPath.terminal(slug, socket_token, file: file)

  defp safe_html(html), do: {:safe, html}

  defp assign_tabs(socket) do
    tabs = tab_provider().(socket.assigns.slug)

    assign(socket, :tabs, tabs)
  end

  defp live_tabs(tabs, slug) do
    tabs
    |> Enum.filter(&(&1.live_status == :up or &1.slug == slug))
    |> ensure_active_tab(slug)
    |> Enum.sort_by(& &1.slug)
  end

  defp ensure_active_tab(tabs, slug) do
    if Enum.any?(tabs, &(&1.slug == slug)) do
      tabs
    else
      tabs ++ [fallback_tab(slug)]
    end
  end

  defp active_tab(tabs, slug) do
    Enum.find(tabs, &(&1.slug == slug)) || fallback_tab(slug)
  end

  defp fallback_tab(slug) do
    %{
      slug: slug,
      display_name: slug,
      live_status: :up,
      actions: [:open, :full, :stop, :restart],
      cli_label: "",
      cwd_label: "",
      last_error: nil,
      imported?: false,
      kill_authority?: true,
      detach_authority?: true,
      ownership_badge: nil,
      lifecycle_reminder: nil,
      roles: []
    }
  end

  defp tab_class(citizen, slug) do
    base =
      if citizen.slug == slug do
        "terminal-tab is-active"
      else
        "terminal-tab"
      end

    base <> " status-#{citizen.live_status}"
  end

  defp action?(citizen, action), do: Enum.member?(Map.get(citizen, :actions, []), action)

  defp ownership_badge(citizen), do: Map.get(citizen, :ownership_badge)
  defp lifecycle_reminder(citizen), do: Map.get(citizen, :lifecycle_reminder)

  defp active_roles(citizen), do: Map.get(citizen, :roles, []) || []

  defp role_name(%{"name" => name}) when is_binary(name), do: name
  defp role_name(_role), do: ""

  defp role_skills(%{"skills" => skills}) when is_list(skills), do: skills
  defp role_skills(_role), do: []

  defp role_title(role) do
    case role_skills(role) do
      [] -> role_name(role)
      skills -> "#{role_name(role)}: #{Enum.join(skills, ", ")}"
    end
  end

  defp button_label(citizen, :start), do: if(detach_only?(citizen), do: "Attach", else: "Start")
  defp button_label(citizen, :stop), do: if(detach_only?(citizen), do: "Detach", else: "Stop")

  defp button_label(citizen, :restart),
    do: if(detach_only?(citizen), do: "Reattach", else: "Restart")

  defp detach_only?(citizen) do
    Map.get(citizen, :detach_authority?) == true and Map.get(citizen, :kill_authority?) != true
  end

  defp lifecycle_click(slug, action) do
    selector = lifecycle_button_selector(slug)

    JS.set_attribute({"disabled", "disabled"}, to: selector)
    |> JS.add_class("is-disabled", to: selector)
    |> JS.push("lifecycle", value: %{"action" => Atom.to_string(action), "slug" => slug})
  end

  defp lifecycle_button_selector(slug), do: ~s([data-terminal-lifecycle-scope="#{slug}"] button)

  defp lifecycle_busy?(inflight, slug), do: Map.has_key?(inflight, slug)

  defp parse_action("start"), do: {:ok, :start}
  defp parse_action("stop"), do: {:ok, :stop}
  defp parse_action("restart"), do: {:ok, :restart}
  defp parse_action(_action), do: :error

  defp start_lifecycle(socket, action, slug) do
    if lifecycle_busy?(socket.assigns.lifecycle_inflight, slug) do
      put_flash(socket, :error, "Lifecycle action already running for #{slug}")
    else
      socket
      |> assign(:lifecycle_inflight, Map.put(socket.assigns.lifecycle_inflight, slug, action))
      |> start_async({:lifecycle, slug, action}, fn -> lifecycle_action(action, slug) end)
    end
  end

  defp clear_lifecycle_inflight(socket, slug) do
    assign(socket, :lifecycle_inflight, Map.delete(socket.assigns.lifecycle_inflight, slug))
  end

  defp apply_lifecycle_result(socket, :stop, slug, result) do
    case result do
      :ok ->
        socket
        |> put_flash(:info, "Stopped #{slug}")
        |> redirect(to: CitizenPath.index(socket.assigns.socket_token))

      {:ok, _pid} ->
        socket
        |> put_flash(:info, "Stopped #{slug}")
        |> redirect(to: CitizenPath.index(socket.assigns.socket_token))

      {:error, reason} ->
        assign_lifecycle_result({:error, reason}, socket, :stop, slug)
    end
  end

  defp apply_lifecycle_result(socket, action, slug, result) when action in [:start, :restart] do
    case result do
      {:error, reason} when action == :restart ->
        {:error, reason}
        |> assign_lifecycle_result(socket, action, slug)
        |> redirect(to: CitizenPath.index(socket.assigns.socket_token))

      {:ok, _pid} = result when action == :restart ->
        result
        |> assign_lifecycle_result(socket, action, slug)
        |> redirect(
          to:
            CitizenPath.terminal(
              slug,
              socket.assigns.socket_token,
              terminal_redirect_opts(socket)
            )
        )

      result ->
        result
        |> assign_lifecycle_result(socket, action, slug)
        |> assign_tabs()
    end
  end

  defp lifecycle_action(action, slug) do
    :babs
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:lifecycle_action, &default_lifecycle_action/2)
    |> then(fn handler -> handler.(action, slug) end)
  end

  defp default_lifecycle_action(:start, slug), do: Lifecycle.start_registered_citizen(slug)
  defp default_lifecycle_action(:stop, slug), do: Lifecycle.stop_citizen(slug)
  defp default_lifecycle_action(:restart, slug), do: Lifecycle.restart_registered_citizen(slug)

  defp assign_lifecycle_result(:ok, socket, action, slug) do
    put_flash(socket, :info, "#{action_label(action)} #{slug}")
  end

  defp assign_lifecycle_result({:ok, _pid}, socket, action, slug) do
    put_flash(socket, :info, "#{action_label(action)} #{slug}")
  end

  defp assign_lifecycle_result({:error, reason}, socket, action, slug) do
    message = "#{action_error_label(action)} failed for #{slug}: #{Catalog.redact_reason(reason)}"
    put_flash(socket, :error, message)
  end

  defp action_label(:start), do: "Started"
  defp action_label(:stop), do: "Stopped"
  defp action_label(:restart), do: "Restarted"

  defp action_error_label(:start), do: "Start"
  defp action_error_label(:stop), do: "Stop"
  defp action_error_label(:restart), do: "Restart"

  defp terminal_redirect_opts(%{assigns: %{full?: true}}), do: [full?: true]

  defp terminal_redirect_opts(%{assigns: assigns}) do
    if page_tab(assigns) == :terminal do
      [tab: :terminal]
    else
      []
    end
  end

  defp flash(assigns, kind) do
    assigns
    |> Map.get(:flash, %{})
    |> Phoenix.Flash.get(kind)
  end

  defp tab_provider do
    :babs
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:status_snapshot_provider, fn -> StatusSnapshot.list() end)
    |> then(fn provider -> fn _slug -> provider.() end end)
  end

  defp full?(%{"full?" => true}), do: true
  defp full?(%{"full?" => "true"}), do: true
  defp full?(%{"full" => value}) when value in ["1", "true"], do: true
  defp full?(_session), do: false

  defp schedule_refresh do
    Process.send_after(self(), :refresh_terminal_tabs, @refresh_ms)
  end
end
