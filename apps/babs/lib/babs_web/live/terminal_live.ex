defmodule BabsWeb.TerminalLive do
  @moduledoc """
  Phase 1 browser terminal for one Citizen.

  The LiveView owns the page shell and client-side xterm bootstrap. PTY bytes and
  keyboard input still flow through `BabsWeb.PaneChannel`, so reloads do not bind
  Hardline.Pane to a LiveView process.
  """

  use Phoenix.LiveView

  alias Babs.Citizens.{Catalog, Lifecycle, StatusSnapshot}
  alias BabsWeb.CitizenPath
  alias Phoenix.LiveView.JS

  @refresh_ms 1_000

  @impl true
  def mount(_params, %{"slug" => slug} = session, socket) do
    full? = full?(session)

    if connected?(socket) and not full?, do: schedule_refresh()

    socket =
      socket
      |> assign(:slug, slug)
      |> assign(:socket_token, Map.get(session, "socket_token", ""))
      |> assign(:full?, full?)
      |> assign(:lifecycle_inflight, %{})
      |> assign_tabs()

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh_terminal_tabs, socket) do
    if connected?(socket) and not socket.assigns.full?, do: schedule_refresh()

    {:noreply, assign_tabs(socket)}
  end

  @impl true
  def handle_event("lifecycle", %{"action" => action, "slug" => slug}, socket) do
    case parse_action(action) do
      {:ok, action} ->
        {:noreply, start_lifecycle(socket, action, slug)}

      :error ->
        {:noreply, put_flash(socket, :error, "Unknown lifecycle action")}
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
        grid-template-columns: auto minmax(0, 1fr) auto auto;
        align-items: center;
        gap: 8px;
        border-bottom: 1px solid var(--line);
        background: #14151a;
        padding: 6px 8px;
      }

      .terminal-link,
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

      .terminal-tab {
        max-width: 180px;
        flex: 0 0 auto;
      }

      .terminal-tab-label {
        overflow: hidden;
        text-overflow: ellipsis;
      }

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
        color: var(--muted);
        font-size: 12px;
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

      .terminal-page[data-mode="tabs"] #terminal {
        height: calc(100vh - var(--terminal-chrome-height));
      }

      .terminal-page[data-mode="full"] #terminal {
        height: 100vh;
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
        .terminal-page { --terminal-chrome-height: 84px; }
        .terminal-chrome {
          grid-template-columns: auto auto;
          grid-template-rows: auto auto;
          align-items: stretch;
        }
        .terminal-actions {
          justify-content: flex-end;
        }
        .terminal-tabs {
          grid-column: 1 / -1;
          grid-row: 2;
          order: 3;
        }
        .terminal-roles {
          max-width: 100%;
        }
      }
    </style>
    <div class="terminal-page" data-mode={if @full?, do: "full", else: "tabs"}>
      <nav :if={!@full?} class="terminal-chrome" data-testid="terminal-chrome" aria-label="Citizen terminal navigation">
        <a class="terminal-link" href={CitizenPath.index(@socket_token)} data-testid="citizens-link">Citizens</a>
        <div class="terminal-tabs" aria-label="Citizen tabs">
          <a
            :for={citizen <- live_tabs(@tabs, @slug)}
            class={tab_class(citizen, @slug)}
            href={CitizenPath.terminal(citizen.slug, @socket_token)}
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
          to: CitizenPath.terminal(slug, socket.assigns.socket_token, full?: socket.assigns.full?)
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
