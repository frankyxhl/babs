defmodule BabsWeb.NewTicketLive do
  @moduledoc """
  Browser form for creating a Ticket.
  """

  use Phoenix.LiveView

  alias Babs.Citizens.Catalog
  alias Babs.Citizens.Roles
  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Error
  alias Babs.Citizens.Tickets.InspectionPolicy
  alias BabsWeb.TicketPath

  @empty_form %{
    "title" => "",
    "body" => "",
    "priority" => "normal",
    "assignee_role" => "",
    "inspection_mode" => "human",
    "inspection_strategy" => "single",
    "inspection_role" => "inspector",
    "inspection_citizen" => "",
    "inspection_max_inspectors" => "1"
  }
  @priorities ~w(low normal high urgent)
  @inspection_modes ~w(human auto)
  @inspection_strategies ~w(single council)

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:form, @empty_form)
     |> assign(:errors, %{})
     |> assign(:status, nil)
     |> assign(:priorities, @priorities)
     |> assign(:assignee_role_options, known_role_labels())
     |> assign(:inspection_role_options, known_role_labels())
     |> assign(:inspection_citizen_options, known_inspector_citizens())
     |> assign(:socket_token, Map.get(session, "socket_token", ""))}
  end

  @impl true
  def handle_event("validate", %{"ticket" => params}, socket) do
    {:noreply, assign(socket, :form, normalize_form(params))}
  end

  def handle_event("create", %{"ticket" => params}, socket) do
    params = normalize_form(params)

    case validate_form(params) do
      {:ok, attrs} ->
        create_ticket(socket, params, attrs)

      {:error, errors} ->
        {:noreply,
         socket |> assign(:form, params) |> assign(:errors, errors) |> assign(:status, nil)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      <%= Phoenix.HTML.raw(styles()) %>
    </style>

    <div class="new-ticket-page">
      <main class="new-ticket-shell">
        <header class="new-ticket-header">
          <div>
            <a class="back-link" href={TicketPath.index(@socket_token)}>
              <BabsWeb.Icon.icon name="arrow-left" /> Tickets
            </a>
            <h1>New Ticket</h1>
            <p class="new-ticket-subtitle">Create a Billboard item for Citizens to pick up</p>
          </div>
        </header>

        <form phx-change="validate" phx-submit="create" data-testid="new-ticket-form">
          <div :if={@status} class="status-error" data-testid="ticket-create-error">
            {@status}
          </div>

          <label>
            Title
            <input name="ticket[title]" value={@form["title"]} data-testid="ticket-title" autocomplete="off" />
            <span :if={@errors[:title]} class="field-error" data-testid="title-error">{@errors[:title]}</span>
          </label>

          <label>
            <span class="label-with-icon"><BabsWeb.Icon.icon name="tag" /> Priority</span>
            <select name="ticket[priority]" data-testid="ticket-priority">
              <option :for={priority <- @priorities} value={priority} selected={@form["priority"] == priority}>
                {priority}
              </option>
            </select>
          </label>

          <label>
            <span class="label-with-icon"><BabsWeb.Icon.icon name="route" /> Assignee Role</span>
            <select name="ticket[assignee_role]" data-testid="ticket-assignee-role">
              <option value="" selected={@form["assignee_role"] == ""}>Unassigned</option>
              <option :for={role <- @assignee_role_options} value={role} selected={@form["assignee_role"] == role}>
                {role}
              </option>
            </select>
          </label>

          <section class="inspection-fields" data-testid="new-ticket-inspection-fields">
            <label>
              <span class="label-with-icon"><BabsWeb.Icon.icon name="shield-check" /> Approval</span>
              <select name="ticket[inspection_mode]" data-testid="ticket-inspection-mode">
                <option value="human" selected={@form["inspection_mode"] == "human"}>Human</option>
                <option value="auto" selected={@form["inspection_mode"] == "auto"}>Auto inspection</option>
              </select>
            </label>

            <div :if={@form["inspection_mode"] == "auto"} class="inspection-grid" data-testid="ticket-auto-inspection-controls">
              <label>
                Strategy
                <select name="ticket[inspection_strategy]" data-testid="ticket-inspection-strategy">
                  <option value="single" selected={@form["inspection_strategy"] == "single"}>Single</option>
                  <option value="council" selected={@form["inspection_strategy"] == "council"}>Council</option>
                </select>
              </label>

              <label>
                Inspector Role
                <select name="ticket[inspection_role]" data-testid="ticket-inspection-role">
                  <option value="" selected={@form["inspection_role"] == ""}>No role</option>
                  <option :for={role <- @inspection_role_options} value={role} selected={@form["inspection_role"] == role}>
                    {role}
                  </option>
                </select>
              </label>

              <label>
                Inspector Citizen
                <select name="ticket[inspection_citizen]" data-testid="ticket-inspection-citizen">
                  <option value="" selected={@form["inspection_citizen"] == ""}>Any</option>
                  <option :for={citizen <- @inspection_citizen_options} value={citizen.slug} selected={@form["inspection_citizen"] == citizen.slug}>
                    {citizen.display_name}
                  </option>
                </select>
              </label>

              <label>
                Max Inspectors
                <input
                  name="ticket[inspection_max_inspectors]"
                  value={@form["inspection_max_inspectors"]}
                  data-testid="ticket-inspection-max"
                  inputmode="numeric"
                  autocomplete="off"
                />
                <span :if={@errors[:inspection]} class="field-error" data-testid="inspection-error">{@errors[:inspection]}</span>
              </label>
            </div>
          </section>

          <label>
            Body
            <textarea name="ticket[body]" data-testid="ticket-body" rows="8">{@form["body"]}</textarea>
            <span :if={@errors[:body]} class="field-error" data-testid="body-error">{@errors[:body]}</span>
          </label>

          <div class="actions">
            <a class="button" href={TicketPath.index(@socket_token)}>
              Cancel
            </a>
            <button type="submit" class="button button-primary" data-testid="create-ticket-button" phx-disable-with="Creating">
              <BabsWeb.Icon.icon name="plus" /> Create
            </button>
          </div>
        </form>
      </main>
    </div>

    <script type="module" src="/js/live_boot.js">
    </script>
    """
  end

  defp create_ticket(socket, params, attrs) do
    case Api.create_ticket(attrs) do
      {:ok, ticket} ->
        {:noreply,
         redirect(socket, to: TicketPath.detail(ticket.id, socket.assigns.socket_token))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:form, params)
         |> assign(:errors, %{})
         |> assign(:status, Error.message(reason))}
    end
  end

  defp normalize_form(params) do
    @empty_form
    |> Map.merge(Map.take(params, Map.keys(@empty_form)))
    |> Map.update!("priority", fn priority ->
      if priority in @priorities, do: priority, else: "normal"
    end)
    |> Map.update!("inspection_mode", fn mode ->
      if mode in @inspection_modes, do: mode, else: "human"
    end)
    |> Map.update!("inspection_strategy", fn strategy ->
      if strategy in @inspection_strategies, do: strategy, else: "single"
    end)
  end

  defp validate_form(params) do
    errors =
      %{}
      |> require_text(:title, params["title"], "Title is required")
      |> require_text(:body, params["body"], "Body is required")

    with true <- errors == %{},
         {:ok, inspection_attrs} <- inspection_attrs(params) do
      {:ok,
       Map.merge(
         %{
           title: String.trim(params["title"]),
           body: String.trim(params["body"]),
           priority: params["priority"],
           assignee_role: blank_to_nil(params["assignee_role"])
         },
         inspection_attrs
       )}
    else
      false -> {:error, errors}
      {:error, message} -> {:error, Map.put(errors, :inspection, message)}
    end
  end

  defp inspection_attrs(%{"inspection_mode" => "human"}), do: {:ok, %{}}

  defp inspection_attrs(params) do
    roles = maybe_list(params["inspection_role"])
    citizens = maybe_list(params["inspection_citizen"])

    policy = %{
      "mode" => "auto",
      "strategy" => params["inspection_strategy"],
      "roles" => roles,
      "citizens" => citizens,
      "quorum" => "all_pass",
      "max_inspectors" => max_inspectors(params["inspection_max_inspectors"]),
      "allow_self_inspection" => false
    }

    case InspectionPolicy.normalize(policy) do
      {:ok, policy} -> {:ok, %{metadata: %{"inspection" => policy}}}
      {:error, reason} -> {:error, inspection_error(reason)}
    end
  end

  defp require_text(errors, key, value, message) do
    if String.trim(value || "") == "" do
      Map.put(errors, key, message)
    else
      errors
    end
  end

  defp known_role_labels do
    Catalog.list_configured_or_imported_citizens()
    |> Enum.flat_map(&role_names/1)
    |> Enum.uniq()
    |> Enum.sort()
  rescue
    _error -> []
  end

  defp known_inspector_citizens do
    Catalog.list_configured_or_imported_citizens()
    |> Enum.map(fn citizen ->
      config = Catalog.to_config(citizen)
      roles = Map.get(config, :roles, [])

      with {:ok, normalized} <- Roles.normalize(roles),
           true <- Enum.any?(normalized, &(&1["name"] == "inspector")) do
        %{
          slug: citizen.slug,
          display_name: citizen.display_name || citizen.slug
        }
      else
        _other -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.slug)
  rescue
    _error -> []
  end

  defp role_names(citizen) do
    citizen
    |> Catalog.to_config()
    |> Map.get(:roles, [])
    |> Roles.normalize()
    |> case do
      {:ok, roles} -> Enum.map(roles, & &1["name"])
      {:error, _reason} -> []
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp maybe_list(value) when is_binary(value) do
    case String.trim(value) do
      "" -> []
      trimmed -> [trimmed]
    end
  end

  defp maybe_list(_value), do: []

  defp max_inspectors(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} -> number
      _other -> value
    end
  end

  defp max_inspectors(value), do: value

  defp inspection_error({:inspection_policy, :missing_inspection_candidates}),
    do: "Choose an inspector role or citizen"

  defp inspection_error({:inspection_policy, {:invalid_max_inspectors, _value}}),
    do: "Max inspectors must be between 1 and 10"

  defp inspection_error(_reason), do: "Inspection settings are invalid"

  def styles do
    """
    :root {
      color-scheme: dark;
      --bg: #0d0d10;
      --panel: #16181d;
      --panel-2: #1d2027;
      --line: #2a2f39;
      --text: #e7eaf0;
      --muted: #9da5b4;
      --field: #0b0c0f;
      --accent: #55b3a6;
      --accent-text: #07100e;
      --danger: #dc6b6b;
    }
    * { box-sizing: border-box; }
    html, body {
      min-height: 100%;
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font: 15px/1.5 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    .new-ticket-page { min-height: 100vh; padding: 28px clamp(14px, 3vw, 38px); }
    .new-ticket-shell { width: min(780px, 100%); margin: 0 auto; display: grid; gap: 18px; }
    .new-ticket-header { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; }
    h1 { margin: 6px 0 0; font-size: 27px; line-height: 1.12; font-weight: 700; letter-spacing: 0; }
    .new-ticket-subtitle { margin: 5px 0 0; color: var(--muted); font-size: 13px; }
    form {
      display: grid;
      gap: 16px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      padding: 18px;
    }
    label { display: grid; gap: 6px; min-width: 0; color: var(--muted); font-size: 13px; }
    .inspection-fields { display: grid; gap: 12px; }
    .inspection-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
    .label-with-icon { display: inline-flex; align-items: center; gap: 6px; }
    .label-with-icon .icon { width: 14px; height: 14px; }
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
    textarea { min-height: 180px; resize: vertical; }
    input:focus, select:focus, textarea:focus {
      outline: 2px solid color-mix(in srgb, var(--accent) 55%, transparent);
      outline-offset: 1px;
      border-color: var(--accent);
    }
    .field-error { color: var(--danger); font-size: 12px; }
    .status-error {
      border: 1px solid rgba(220, 107, 107, 0.55);
      border-radius: 8px;
      background: rgba(220, 107, 107, 0.12);
      padding: 10px 12px;
      color: var(--danger);
      font-size: 13px;
    }
    .actions { display: flex; align-items: center; justify-content: flex-end; gap: 8px; flex-wrap: wrap; }
    .button, .back-link {
      border: 1px solid var(--line);
      border-radius: 6px;
      background: var(--panel-2);
      color: var(--text);
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 7px;
      min-height: 36px;
      padding: 7px 11px;
      text-decoration: none;
      white-space: nowrap;
      font: inherit;
      cursor: pointer;
    }
    .button:hover, .back-link:hover { border-color: var(--accent); }
    .button-primary { border-color: transparent; background: var(--accent); color: var(--accent-text); font-weight: 700; }
    .icon { width: 16px; height: 16px; flex: 0 0 auto; }
    .back-link { width: fit-content; min-height: 30px; padding: 5px 9px; color: var(--muted); font-size: 13px; }
    @media (max-width: 560px) {
      .new-ticket-page { padding: 18px 10px; }
      form { padding: 14px; }
      .inspection-grid { grid-template-columns: 1fr; }
      .actions { justify-content: flex-start; }
    }
    """
  end
end
