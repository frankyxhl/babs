defmodule BabsWeb.Api.V1.ReadController do
  @moduledoc false

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn

  alias Babs.Citizens.{Catalog, Federation, StatusSnapshot}
  alias Babs.Citizens.Hardline.Transcript
  alias Babs.Citizens.Tickets.{Api, Config}

  @citizen_projection_keys [
    "id",
    "slug",
    "display_name",
    "cli_label",
    "roles",
    "ticket_backend",
    "ticket_backend_label",
    "cwd_label",
    "durable_status",
    "live_status",
    "visual_state",
    "actions",
    "provider_runtime",
    "provider_runtime_capabilities",
    "interactive_attach",
    "kill_authority",
    "detach_authority",
    "ownership",
    "imported",
    "ownership_badge",
    "lifecycle_reminder"
  ]

  @ticket_summary_keys [
    :id,
    :type,
    :state,
    :assigner,
    :assignees,
    :assignee_role,
    :inspector,
    :priority,
    :parent_ticket,
    :created_at,
    :updated_at,
    :metadata,
    :title
  ]

  def init(action), do: action

  def call(conn, action), do: apply(__MODULE__, action, [conn, conn.params])

  def node(conn, _params) do
    with_federation(conn, fn conn, %{"node" => node, "peers" => peers} ->
      json(conn, %{"node" => node, "peers" => peers})
    end)
  end

  def citizens(conn, _params) do
    with_federation(conn, fn conn, info ->
      citizens =
        StatusSnapshot.list(include_stale?: true)
        |> Enum.map(&citizen_projection/1)

      json(conn, %{"node" => node_summary(info), "citizens" => citizens})
    end)
  end

  def citizen(conn, %{"slug" => slug}) do
    with_federation(conn, fn conn, info ->
      StatusSnapshot.list(include_stale?: true)
      |> Enum.find(&(&1.slug == slug))
      |> case do
        nil ->
          error(conn, 404, "not_found", "Citizen #{slug} was not found")

        snapshot ->
          json(conn, %{"node" => node_summary(info), "citizen" => citizen_projection(snapshot)})
      end
    end)
  end

  def citizen_transcript(conn, %{"slug" => slug} = params) do
    conn = fetch_query_params(conn)
    params = Map.merge(params, conn.query_params)

    with_federation(conn, fn conn, info ->
      with {:ok, line_limit, tail_bytes} <- transcript_params(params),
           {:ok, record} <- fetch_citizen_record(slug),
           {:ok, transcript} <-
             Transcript.replay_output_info(record.cwd,
               slug: slug,
               lines: line_limit,
               tail_bytes: tail_bytes
             ) do
        json(conn, %{
          "node" => node_summary(info),
          "citizen_slug" => slug,
          "transcript" => %{
            "output" => transcript.output,
            "truncated" => transcript.truncated,
            "lines" => transcript.lines,
            "returned_lines" => transcript.returned_lines
          }
        })
      else
        {:error, :not_found} ->
          error(conn, 404, "not_found", "Citizen #{slug} was not found")

        {:error, :invalid_params} ->
          error(conn, 400, "invalid_params", "Transcript query parameters are invalid")

        {:error, _reason} ->
          error(conn, 500, "read_failed", "Transcript could not be read")
      end
    end)
  end

  def tickets(conn, _params) do
    with_federation(conn, fn conn, info ->
      with :ok <- ensure_ticket_root_readable(),
           {:ok, %{tickets: tickets, invalid: invalid}} <- Api.list_tickets() do
        json(conn, %{
          "node" => node_summary(info),
          "tickets" => Enum.map(tickets, &ticket_summary/1),
          "invalid" => %{"count" => length(invalid)}
        })
      else
        {:error, _reason} ->
          error(conn, 500, "read_failed", "Tickets could not be read")
      end
    end)
  end

  def ticket(conn, %{"id" => id}) do
    with_federation(conn, fn conn, info ->
      with :ok <- ensure_ticket_root_readable(),
           {:ok, %{ticket: ticket, history: history}} <- Api.show_ticket(id) do
        json(conn, %{
          "node" => node_summary(info),
          "ticket" =>
            ticket
            |> ticket_detail()
            |> Map.put("history", safe_history(history))
        })
      else
        {:error, {:invalid_id, _id}} ->
          error(conn, 400, "invalid_id", "Ticket id is invalid")

        {:error, {:not_found, ^id}} ->
          error(conn, 404, "not_found", "Ticket #{id} was not found")

        {:error, _reason} ->
          error(conn, 500, "read_failed", "Ticket could not be read")
      end
    end)
  end

  defp with_federation(conn, fun) do
    case Federation.node_info() do
      {:ok, info} ->
        fun.(conn, info)

      {:error, {:config_error, _reason}} ->
        error(conn, 503, "config_error", "Federation config is invalid")
    end
  end

  defp node_summary(%{"node" => node}), do: Map.take(node, ["id", "name"])

  defp citizen_projection(snapshot) do
    values = %{
      "id" => snapshot.id,
      "slug" => snapshot.slug,
      "display_name" => snapshot.display_name,
      "cli_label" => snapshot.cli_label,
      "roles" => role_names(snapshot.roles),
      "ticket_backend" => snapshot.ticket_backend,
      "ticket_backend_label" => snapshot.ticket_backend_label,
      "cwd_label" => snapshot.cwd_label,
      "durable_status" => snapshot.durable_status,
      "live_status" => string_value(snapshot.live_status),
      "visual_state" => string_value(snapshot.visual_state),
      "actions" => Enum.map(snapshot.actions || [], &string_value/1),
      "provider_runtime" => safe_provider_runtime(snapshot.provider_runtime),
      "provider_runtime_capabilities" => snapshot.provider_runtime_capabilities || %{},
      "interactive_attach" => Map.get(snapshot, :interactive_attach?),
      "kill_authority" => Map.get(snapshot, :kill_authority?),
      "detach_authority" => Map.get(snapshot, :detach_authority?),
      "ownership" => snapshot.ownership,
      "imported" => Map.get(snapshot, :imported?),
      "ownership_badge" => snapshot.ownership_badge,
      "lifecycle_reminder" => snapshot.lifecycle_reminder
    }

    Map.new(@citizen_projection_keys, &{&1, Map.get(values, &1)})
  end

  defp role_names(roles) when is_list(roles) do
    Enum.flat_map(roles, fn
      %{"name" => name} when is_binary(name) -> [name]
      %{name: name} when is_binary(name) -> [name]
      value when is_binary(value) -> [value]
      _value -> []
    end)
  end

  defp role_names(_roles), do: []

  defp safe_provider_runtime(runtime) when is_map(runtime) do
    %{
      "provider" => map_value(runtime, :provider),
      "backend" => map_value(runtime, :backend),
      "ownership" => map_value(runtime, :ownership),
      "status" => map_value(runtime, :status)
    }
  end

  defp safe_provider_runtime(_runtime) do
    %{"provider" => nil, "backend" => nil, "ownership" => nil, "status" => nil}
  end

  defp map_value(map, key) do
    if Map.has_key?(map, key) do
      Map.get(map, key)
    else
      Map.get(map, Atom.to_string(key))
    end
  end

  defp string_value(value) when is_atom(value), do: Atom.to_string(value)
  defp string_value(value) when is_binary(value), do: value
  defp string_value(value), do: value

  defp transcript_params(params) do
    with {:ok, lines} <- bounded_integer(params, "lines", 200, 1, 1000),
         {:ok, tail_bytes} <- bounded_integer(params, "tail_bytes", 1_048_576, 1, 1_048_576) do
      {:ok, lines, tail_bytes}
    else
      {:error, _reason} -> {:error, :invalid_params}
    end
  end

  defp bounded_integer(params, key, default, min, max) do
    value = Map.get(params, key)

    cond do
      value in [nil, ""] ->
        {:ok, default}

      is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} when integer >= min and integer <= max -> {:ok, integer}
          _other -> {:error, key}
        end

      true ->
        {:error, key}
    end
  end

  defp fetch_citizen_record(slug) do
    case Catalog.get_by_slug(slug) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  defp ensure_ticket_root_readable do
    root = Config.tickets_root()

    case File.stat(root) do
      {:ok, %{type: :directory}} ->
        case File.ls(root) do
          {:ok, _entries} -> :ok
          {:error, reason} -> {:error, {:read_failed, reason}}
        end

      {:error, :enoent} ->
        :ok

      {:ok, _stat} ->
        {:error, {:read_failed, :not_directory}}

      {:error, reason} ->
        {:error, {:read_failed, reason}}
    end
  end

  defp ticket_summary(ticket) do
    Map.new(@ticket_summary_keys, fn key -> {Atom.to_string(key), Map.get(ticket, key)} end)
  end

  defp ticket_detail(ticket) do
    ticket
    |> ticket_summary()
    |> Map.put("body", ticket.body)
  end

  defp safe_history(history) when is_list(history) do
    Enum.map(history, fn
      event when is_map(event) -> Map.drop(event, ["path", "warnings"])
      event -> event
    end)
  end

  defp safe_history(_history), do: []

  defp error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{"error" => %{"code" => code, "message" => message}})
  end
end
