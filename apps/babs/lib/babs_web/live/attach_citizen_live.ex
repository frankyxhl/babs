defmodule BabsWeb.AttachCitizenLive do
  @moduledoc """
  Imports an external tmux pane into an existing Citizen.
  """

  use Phoenix.LiveView

  alias Babs.Citizens.{Catalog, Lifecycle, TmuxInventory}
  alias BabsWeb.CitizenPath

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:socket_token, Map.get(session, "socket_token", ""))
     |> assign(:selected_slug, "")
     |> assign(:selected_target, "")
     |> assign(:attach_inflight, false)
     |> assign_inventory()}
  end

  @impl true
  def handle_event("select", %{"slug" => slug, "target" => target}, socket) do
    {:noreply, assign(socket, selected_slug: slug, selected_target: target)}
  end

  def handle_event("attach", %{"attach" => params}, socket) do
    slug = params["slug"] || ""
    target = params["target"] || ""

    socket =
      socket
      |> assign(:selected_slug, slug)
      |> assign(:selected_target, target)

    cond do
      slug == "" or target == "" ->
        {:noreply, put_flash(socket, :error, "Select a Citizen and tmux pane")}

      true ->
        {:noreply,
         socket
         |> assign(:attach_inflight, true)
         |> start_async({:attach, slug}, fn -> attach_action().(slug, target) end)}
    end
  end

  @impl true
  def handle_async({:attach, slug}, {:ok, {:ok, _pid}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Attached #{slug}")
     |> redirect(to: CitizenPath.terminal(slug, socket.assigns.socket_token))}
  end

  def handle_async({:attach, _slug}, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:attach_inflight, false)
     |> assign_inventory()
     |> put_flash(:error, "Attach failed: #{Catalog.redact_reason(reason)}")}
  end

  def handle_async({:attach, _slug}, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:attach_inflight, false)
     |> assign_inventory()
     |> put_flash(:error, "Attach failed: #{Catalog.redact_reason(reason)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      <%= Phoenix.HTML.raw(styles()) %>
    </style>

    <div class="attach-page" data-testid="attach-citizen-page">
      <main class="attach-shell">
        <header class="attach-header">
          <div>
            <h1>Attach tmux</h1>
            <p class="attach-subtitle">Import an external-owned pane into an existing Citizen</p>
          </div>
          <nav class="attach-nav" aria-label="Attach navigation">
            <a class="button" href={CitizenPath.index(@socket_token)}>
              <BabsWeb.Icon.icon name="arrow-left" /> Citizens
            </a>
          </nav>
        </header>

        <div :if={Phoenix.Flash.get(@flash, :error)} class="flash flash-error" data-testid="attach-flash-error">
          {Phoenix.Flash.get(@flash, :error)}
        </div>

        <form class="attach-form" phx-submit="attach" data-testid="attach-form">
          <label>
            <span>Citizen</span>
            <select name="attach[slug]" data-testid="attach-citizen-select">
              <option value="">Select Citizen</option>
              <option :for={citizen <- @eligible_citizens} value={citizen.slug} selected={citizen.slug == @selected_slug}>
                {citizen.slug}
              </option>
            </select>
          </label>

          <label>
            <span>tmux pane</span>
            <select name="attach[target]" data-testid="attach-target-select">
              <option value="">Select tmux pane</option>
              <option :for={pane <- @attachable_panes} value={pane.target} selected={pane.target == @selected_target}>
                {pane_label(pane)}
              </option>
            </select>
          </label>

          <button class="button button-primary" type="submit" disabled={@attach_inflight} phx-disable-with="Attaching" data-testid="attach-submit">
            <BabsWeb.Icon.icon name="link" /> Attach
          </button>
        </form>

        <section class="attach-grid" aria-label="Attach candidates">
          <article class="attach-panel">
            <h2>Eligible Citizens</h2>
            <div :if={@eligible_citizens == []} class="empty">No stopped or detached Citizens available.</div>
            <button
              :for={citizen <- @eligible_citizens}
              class={["candidate", citizen.slug == @selected_slug && "is-selected"]}
              type="button"
              phx-click="select"
              phx-value-slug={citizen.slug}
              phx-value-target={@selected_target}
              data-testid={"attach-citizen-#{citizen.slug}"}
            >
              <span>{citizen.slug}</span>
              <small>{citizen.display_name}</small>
            </button>
          </article>

          <article class="attach-panel">
            <h2>Attachable Panes</h2>
            <div :if={@attachable_panes == []} class="empty">No unmanaged tmux panes available.</div>
            <button
              :for={pane <- @attachable_panes}
              class={["candidate", pane.target == @selected_target && "is-selected"]}
              type="button"
              phx-click="select"
              phx-value-slug={@selected_slug}
              phx-value-target={pane.target}
              data-testid={"attach-pane-#{pane.pane_id}"}
            >
              <span>{pane_label(pane)}</span>
              <small>{pane.current_command} · {compact_path(pane.current_path)}</small>
            </button>
          </article>
        </section>

        <section class="inventory-panel" aria-label="tmux inventory">
          <h2>tmux Inventory</h2>
          <div :for={pane <- @inventory} class="inventory-row" data-testid={"inventory-pane-#{pane.pane_id}"}>
            <span>{pane_label(pane)}</span>
            <span class={"badge badge-#{pane.classification}"}>{classification_label(pane.classification)}</span>
          </div>
        </section>
      </main>
    </div>

    <script type="module" src="/js/live_boot.js">
    </script>
    """
  end

  defp assign_inventory(socket) do
    records = citizen_provider().()
    inventory = inventory_provider().(records)

    assign(socket,
      records: records,
      inventory: inventory,
      attachable_panes: Enum.filter(inventory, &(&1.classification == :attachable)),
      eligible_citizens: Enum.filter(records, &eligible_citizen?/1)
    )
  end

  defp eligible_citizen?(record) do
    case lifecycle_lookup().(record.slug) do
      {:ok, _pid} -> false
      {:error, :not_found} -> record.status in ["stopped", "failed"]
    end
  end

  defp citizen_provider do
    :babs
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:citizen_provider, &Catalog.list_citizens/0)
  end

  defp inventory_provider do
    :babs
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:inventory_provider, fn records -> TmuxInventory.candidates(records) end)
  end

  defp lifecycle_lookup do
    :babs
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:lifecycle_lookup, &Lifecycle.lookup/1)
  end

  defp attach_action do
    :babs
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:attach_action, &Lifecycle.attach_imported_citizen/2)
  end

  defp pane_label(pane),
    do: "#{pane.session_name}:#{pane.window_index}.#{pane.pane_index} #{pane.pane_id}"

  defp compact_path(path) when is_binary(path) and path != "", do: ".../" <> Path.basename(path)
  defp compact_path(_path), do: "unknown cwd"

  defp classification_label(:babs_owned), do: "Babs-owned"
  defp classification_label(:imported), do: "Imported"
  defp classification_label(:attachable), do: "Attachable"
  defp classification_label(_classification), do: "Unavailable"

  defp styles do
    """
    :root { color-scheme: dark; --bg: #0d0d10; --panel: #16181d; --panel-2: #1d2027; --line: #2a2f39; --text: #e7eaf0; --muted: #9da5b4; --field: #0b0c0f; --accent: #55b3a6; --danger: #dc6b6b; --ok: #43d17d; --wait: #d7ae55; }
    * { box-sizing: border-box; }
    html, body { min-height: 100%; margin: 0; background: var(--bg); color: var(--text); font: 15px/1.5 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    .attach-page { min-height: 100vh; padding: 28px clamp(14px, 3vw, 38px); }
    .attach-shell { width: min(1180px, 100%); margin: 0 auto; display: grid; gap: 18px; }
    .attach-header { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; }
    h1, h2 { margin: 0; letter-spacing: 0; }
    h1 { font-size: 27px; line-height: 1.12; }
    h2 { font-size: 16px; }
    .attach-subtitle { margin: 5px 0 0; color: var(--muted); font-size: 13px; }
    .button { border: 1px solid var(--line); border-radius: 6px; background: var(--panel-2); color: var(--text); display: inline-flex; align-items: center; justify-content: center; gap: 7px; min-height: 36px; padding: 7px 11px; text-decoration: none; white-space: nowrap; font: inherit; cursor: pointer; }
    .button-primary { border-color: transparent; background: var(--accent); color: #07100e; font-weight: 700; }
    .button:hover { border-color: var(--accent); }
    .button[disabled] { cursor: not-allowed; opacity: 0.6; }
    .icon { width: 16px; height: 16px; flex: 0 0 auto; }
    .flash { border: 1px solid var(--line); border-radius: 8px; background: var(--panel); padding: 10px 12px; }
    .flash-error { border-color: var(--danger); color: var(--danger); }
    .attach-form, .attach-panel, .inventory-panel { border: 1px solid var(--line); border-radius: 8px; background: var(--panel); padding: 12px; }
    .attach-form { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr) auto; gap: 12px; align-items: end; }
    label { display: grid; gap: 5px; color: var(--muted); font-size: 12px; }
    select { width: 100%; min-height: 36px; border: 1px solid var(--line); border-radius: 6px; background: var(--field); color: var(--text); padding: 6px 8px; font: inherit; }
    .attach-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
    .attach-panel { display: grid; gap: 8px; align-content: start; }
    .candidate { width: 100%; border: 1px solid var(--line); border-radius: 6px; background: var(--panel-2); color: var(--text); display: grid; gap: 2px; padding: 9px 10px; text-align: left; font: inherit; cursor: pointer; }
    .candidate:hover, .candidate.is-selected { border-color: var(--accent); }
    .candidate small, .empty { color: var(--muted); }
    .inventory-panel { display: grid; gap: 8px; }
    .inventory-row { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 10px; align-items: center; border-top: 1px solid var(--line); padding-top: 8px; }
    .badge { border: 1px solid var(--line); border-radius: 999px; padding: 3px 8px; color: var(--muted); font-size: 12px; white-space: nowrap; }
    .badge-attachable { border-color: var(--ok); color: var(--ok); }
    .badge-imported { border-color: var(--wait); color: var(--wait); }
    @media (max-width: 760px) { .attach-header { flex-direction: column; } .attach-form, .attach-grid { grid-template-columns: 1fr; } }
    """
  end
end
