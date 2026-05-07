defmodule BabsWeb.NewCitizenLive do
  @moduledoc """
  Browser form for spawning a new Citizen.
  """

  use Phoenix.LiveView

  alias Babs.Citizens.Spawner
  alias BabsWeb.CitizenPath

  @empty_form %{
    "slug" => "",
    "display_name" => "",
    "description" => "",
    "cli_preset" => "shell",
    "ticket_backend" => "hardline",
    "cwd" => ""
  }

  @impl true
  def mount(params, session, socket) do
    {:ok,
     socket
     |> assign(:form, @empty_form)
     |> assign(:errors, %{})
     |> assign(:status, nil)
     |> assign(:socket_token, socket_token(params, session))
     |> assign(:presets, Spawner.presets())
     |> assign(:ticket_backend_options, Spawner.ticket_backend_options())}
  end

  @impl true
  def handle_event("validate", %{"citizen" => params}, socket) do
    {:noreply, assign(socket, :form, normalize_form(params))}
  end

  def handle_event("create", %{"citizen" => params}, socket) do
    params = normalize_form(params)

    case spawner().(params) do
      {:ok, record} ->
        {:noreply, redirect(socket, to: success_path(record, socket.assigns.socket_token))}

      {:error, {:validation_failed, errors}} ->
        {:noreply,
         socket |> assign(:form, params) |> assign(:errors, errors) |> assign(:status, nil)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:form, params)
         |> assign(:errors, %{})
         |> assign(:status, error_message(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      :root {
        color-scheme: dark;
        --bg: #101114;
        --panel: #17191f;
        --line: #30343d;
        --text: #f0f2f5;
        --muted: #a8afbd;
        --field: #0b0c0f;
        --accent: #55b3a6;
        --danger: #ef8b7b;
      }

      * { box-sizing: border-box; }

      html, body {
        min-height: 100%;
        margin: 0;
        background: var(--bg);
        color: var(--text);
        font: 15px/1.5 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }

      .new-citizen-page {
        min-height: 100vh;
        padding: 32px clamp(16px, 4vw, 44px);
      }

      .new-citizen-shell {
        max-width: 760px;
        margin: 0 auto;
      }

      .new-citizen-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 16px;
        margin-bottom: 22px;
      }

      h1 {
        margin: 0;
        font-size: 26px;
        line-height: 1.15;
        font-weight: 700;
        letter-spacing: 0;
      }

      .terminal-link {
        color: var(--muted);
        text-decoration: none;
        border: 1px solid var(--line);
        border-radius: 6px;
        padding: 8px 10px;
        white-space: nowrap;
      }

      .terminal-link:hover { color: var(--text); border-color: var(--accent); }

      form {
        display: grid;
        gap: 16px;
        padding: 20px;
        border: 1px solid var(--line);
        border-radius: 8px;
        background: var(--panel);
      }

      .field-grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 16px;
      }

      label {
        display: grid;
        gap: 6px;
        min-width: 0;
        color: var(--muted);
        font-size: 13px;
      }

      .label-with-icon {
        display: inline-flex;
        align-items: center;
        gap: 6px;
      }

      .icon {
        width: 15px;
        height: 15px;
        flex: 0 0 auto;
      }

      input, select, textarea {
        width: 100%;
        min-width: 0;
        border: 1px solid var(--line);
        border-radius: 6px;
        background: var(--field);
        color: var(--text);
        padding: 10px 11px;
        font: inherit;
      }

      textarea {
        min-height: 84px;
        resize: vertical;
      }

      input:focus, select:focus, textarea:focus {
        outline: 2px solid color-mix(in srgb, var(--accent) 55%, transparent);
        outline-offset: 1px;
        border-color: var(--accent);
      }

      .wide { grid-column: 1 / -1; }

      .field-error {
        color: var(--danger);
        font-size: 12px;
      }

      .status-error {
        border: 1px solid color-mix(in srgb, var(--danger) 65%, var(--line));
        border-radius: 6px;
        padding: 10px 12px;
        color: var(--danger);
        background: color-mix(in srgb, var(--danger) 10%, transparent);
      }

      .actions {
        display: flex;
        justify-content: flex-end;
      }

      button {
        border: 0;
        border-radius: 6px;
        background: var(--accent);
        color: #07100e;
        padding: 10px 14px;
        font: inherit;
        font-weight: 700;
        cursor: pointer;
      }

      button:disabled { opacity: 0.65; cursor: wait; }

      @media (max-width: 680px) {
        .new-citizen-page { padding: 18px 12px; }
        .new-citizen-header { align-items: flex-start; flex-direction: column; }
        form { padding: 14px; }
        .field-grid { grid-template-columns: 1fr; }
      }
    </style>

    <div class="new-citizen-page">
      <main class="new-citizen-shell">
        <div class="new-citizen-header">
          <h1>New Citizen</h1>
          <a class="terminal-link" href="/citizens/sentinel">Sentinel</a>
        </div>

        <form phx-change="validate" phx-submit="create" data-testid="new-citizen-form">
          <div :if={@status} class="status-error" data-testid="spawn-error">
            {@status}
          </div>

          <div class="field-grid">
            <label>
              Slug
              <input name="citizen[slug]" value={@form["slug"]} data-testid="citizen-slug" autocomplete="off" />
              <span :if={@errors[:slug]} class="field-error" data-testid="slug-error">{@errors[:slug]}</span>
            </label>

            <label>
              Display name
              <input
                name="citizen[display_name]"
                value={@form["display_name"]}
                data-testid="citizen-display-name"
                autocomplete="off"
              />
              <span :if={@errors[:display_name]} class="field-error" data-testid="display-name-error">
                {@errors[:display_name]}
              </span>
            </label>

            <label>
              Preset
              <select name="citizen[cli_preset]" data-testid="citizen-cli-preset">
                <option :for={preset <- @presets} value={preset} selected={@form["cli_preset"] == preset}>
                  {preset}
                </option>
              </select>
              <span :if={@errors[:cli_preset]} class="field-error" data-testid="cli-preset-error">
                {@errors[:cli_preset]}
              </span>
            </label>

            <label>
              <span class="label-with-icon">
                <BabsWeb.Icon.icon name="route" /> Ticket backend
              </span>
              <select name="citizen[ticket_backend]" data-testid="citizen-ticket-backend">
                <option
                  :for={option <- @ticket_backend_options}
                  value={option.value}
                  selected={@form["ticket_backend"] == option.value}
                >
                  {option.label} - {option.description}
                </option>
              </select>
              <span :if={@errors[:ticket_backend]} class="field-error" data-testid="ticket-backend-error">
                {@errors[:ticket_backend]}
              </span>
            </label>

            <label>
              Cwd
              <input name="citizen[cwd]" value={@form["cwd"]} data-testid="citizen-cwd" autocomplete="off" />
              <span :if={@errors[:cwd]} class="field-error" data-testid="cwd-error">{@errors[:cwd]}</span>
            </label>

            <label class="wide">
              Description
              <textarea name="citizen[description]" data-testid="citizen-description">{@form["description"]}</textarea>
            </label>
          </div>

          <div class="actions">
            <button type="submit" data-testid="create-citizen-button" phx-disable-with="Creating">Create</button>
          </div>
        </form>
      </main>
    </div>

    <script type="module" src="/js/live_boot.js">
    </script>
    """
  end

  defp normalize_form(params) do
    Map.merge(@empty_form, Map.take(params, Map.keys(@empty_form)))
  end

  defp spawner do
    :babs
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:spawner, &Spawner.create_and_start/1)
  end

  defp socket_token(%{"socket_token" => token}, _session) when is_binary(token),
    do: String.trim(token)

  defp socket_token(_params, %{"socket_token" => token}) when is_binary(token),
    do: String.trim(token)

  defp socket_token(_params, _session), do: ""

  defp terminal_path(slug, ""), do: "/citizens/#{slug}"

  defp terminal_path(slug, socket_token) do
    "/citizens/#{slug}?#{URI.encode_query(%{"socket_token" => socket_token})}"
  end

  defp success_path(%{ticket_backend: "direct_cli"}, socket_token),
    do: CitizenPath.index(socket_token)

  defp success_path(record, socket_token), do: terminal_path(record.slug, socket_token)

  defp error_message({:duplicate_toml, _path}), do: "Citizen TOML already exists"
  defp error_message({:duplicate_sqlite, _slug}), do: "Citizen already exists"
  defp error_message({:toml_write_failed, _reason}), do: "Could not write Citizen TOML"
  defp error_message({:toml_write_failed, _path, _reason}), do: "Could not write Citizen TOML"
  defp error_message({:workspace_mkdir_failed, _reason}), do: "Could not create workspace"
  defp error_message({:sqlite_insert_failed, _reason}), do: "Could not save Citizen"
  defp error_message({:lifecycle_start_failed, reason}), do: "Could not start Citizen: #{reason}"
  defp error_message({:spawn_lock_timeout, _slug}), do: "Citizen is already being created"
  defp error_message(_reason), do: "Could not create Citizen due to an unexpected error"
end
