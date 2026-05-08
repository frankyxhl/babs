defmodule Babs.Citizens.Tickets.TicketMarkdown do
  @moduledoc """
  Parses and renders Ticket markdown files with strict YAML frontmatter.
  """

  alias Babs.Citizens.Tickets.Ticket
  alias Babs.Citizens.Tickets.TicketId
  alias Babs.Citizens.Tickets.InspectionPolicy
  alias Babs.Citizens.Tickets.MayorPolicy

  @keys ~w(
    id
    type
    state
    assigner
    assignees
    assignee_role
    inspector
    priority
    parent_ticket
    created_at
    updated_at
    metadata
  )
  @types ~w(assignment mission proposal comment-thread)
  @states ~w(open in_progress pending_approval closed cancelled)
  @priorities ~w(low normal high urgent)

  @spec parse(String.t(), keyword()) :: {:ok, Ticket.t()} | {:error, term()}
  def parse(content, opts \\ []) when is_binary(content) do
    with {:ok, yaml, markdown} <- split_frontmatter(content),
         {:ok, raw} <- decode_yaml(yaml),
         :ok <- validate_keys(raw),
         :ok <- validate_path_id(raw["id"], Keyword.get(opts, :path)),
         {:ok, title, body} <- parse_markdown_body(markdown),
         {:ok, ticket} <- build_ticket(raw, title, body, opts) do
      {:ok, ticket}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec render(Ticket.t()) :: String.t()
  def render(%Ticket{} = ticket) do
    frontmatter =
      [
        line("id", ticket.id),
        line("type", ticket.type),
        line("state", ticket.state),
        line("assigner", ticket.assigner),
        line("assignees", ticket.assignees),
        line("assignee_role", ticket.assignee_role),
        line("inspector", ticket.inspector),
        line("priority", ticket.priority),
        line("parent_ticket", ticket.parent_ticket),
        line("created_at", ticket.created_at),
        line("updated_at", ticket.updated_at),
        line("metadata", ticket.metadata)
      ]
      |> Enum.join("\n")

    """
    ---
    #{frontmatter}
    ---

    # #{ticket.title}

    #{String.trim(ticket.body)}
    """
  end

  def path(root, id), do: Path.join(root, "#{id}.md")
  def history_path(root, id), do: Path.join(root, "#{id}.history.jsonl")

  defp split_frontmatter(content) do
    case Regex.run(~r/\A---\s*\n(.*?)\n---\s*\n?(.*)\z/s, content) do
      [_, yaml, markdown] -> {:ok, yaml, markdown}
      _ -> {:error, {:invalid_frontmatter, :missing_frontmatter}}
    end
  end

  defp decode_yaml(yaml) do
    case YamlElixir.read_from_string(yaml) do
      {:ok, raw} when is_map(raw) -> {:ok, raw}
      {:ok, _value} -> {:error, {:invalid_frontmatter, :frontmatter_not_map}}
      {:error, reason} -> {:error, {:invalid_frontmatter, {:yaml_decode_failed, reason}}}
    end
  rescue
    error -> {:error, {:invalid_frontmatter, {:yaml_decode_failed, error.__struct__}}}
  end

  defp validate_keys(raw) do
    keys = Map.keys(raw)
    missing = Enum.reject(@keys, &Map.has_key?(raw, &1))
    unknown = Enum.sort(keys -- @keys)

    cond do
      unknown != [] -> {:error, {:invalid_frontmatter, {:unknown_keys, unknown}}}
      missing != [] -> {:error, {:invalid_frontmatter, {:missing_keys, missing}}}
      true -> :ok
    end
  end

  defp validate_path_id(_id, nil), do: :ok

  defp validate_path_id(id, path) do
    stem = Path.basename(path, ".md")

    if id == stem do
      :ok
    else
      {:error, {:invalid_frontmatter, {:id_mismatch, id, stem}}}
    end
  end

  defp parse_markdown_body(markdown) do
    markdown = String.trim_leading(markdown)

    case String.split(markdown, "\n", parts: 2) do
      ["# " <> title, rest] ->
        body = String.trim(rest)

        cond do
          String.trim(title) == "" -> {:error, {:invalid_frontmatter, :missing_title}}
          body == "" -> {:error, {:invalid_frontmatter, :empty_body}}
          true -> {:ok, String.trim(title), body}
        end

      _ ->
        {:error, {:invalid_frontmatter, :missing_title}}
    end
  end

  defp build_ticket(raw, title, body, opts) do
    with :ok <- TicketId.validate(raw["id"]),
         {:ok, type} <- enum_value(raw, "type", @types),
         {:ok, state} <- enum_value(raw, "state", @states),
         {:ok, assigner} <- required_string(raw, "assigner"),
         {:ok, assignees} <- string_list(raw, "assignees"),
         {:ok, assignee_role} <- nullable_string(raw, "assignee_role"),
         {:ok, inspector} <- required_string(raw, "inspector"),
         {:ok, priority} <- enum_value(raw, "priority", @priorities),
         {:ok, parent_ticket} <- nullable_ticket_id(raw, "parent_ticket"),
         {:ok, created_at} <- iso8601_string(raw, "created_at"),
         {:ok, updated_at} <- iso8601_string(raw, "updated_at"),
         {:ok, metadata} <- metadata(raw),
         :ok <- validate_mayor_ticket_type(type, metadata),
         :ok <- validate_billboard_state(assignees, state) do
      {:ok,
       %Ticket{
         id: raw["id"],
         type: type,
         state: state,
         assigner: assigner,
         assignees: assignees,
         assignee_role: assignee_role,
         inspector: inspector,
         priority: priority,
         parent_ticket: parent_ticket,
         created_at: created_at,
         updated_at: updated_at,
         metadata: metadata,
         title: title,
         body: body,
         path: Keyword.get(opts, :path),
         warnings: unknown_assignee_warnings(assignees, Keyword.get(opts, :known_citizens))
       }}
    end
  end

  defp enum_value(raw, key, allowed) do
    case raw[key] do
      value when is_binary(value) ->
        if value in allowed,
          do: {:ok, value},
          else: {:error, {:invalid_frontmatter, {:invalid_value, key, value}}}

      value ->
        {:error, {:invalid_frontmatter, {:invalid_value, key, value}}}
    end
  end

  defp required_string(raw, key) do
    case raw[key] do
      value when is_binary(value) ->
        if String.trim(value) == "",
          do: {:error, {:invalid_frontmatter, {:blank, key}}},
          else: {:ok, value}

      value ->
        {:error, {:invalid_frontmatter, {:invalid_value, key, value}}}
    end
  end

  defp nullable_string(raw, key) do
    case raw[key] do
      nil -> {:ok, nil}
      value when is_binary(value) -> {:ok, value}
      value -> {:error, {:invalid_frontmatter, {:invalid_value, key, value}}}
    end
  end

  defp nullable_ticket_id(raw, key) do
    case raw[key] do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        case TicketId.validate(value) do
          :ok -> {:ok, value}
          {:error, reason} -> {:error, {:invalid_frontmatter, reason}}
        end

      value ->
        {:error, {:invalid_frontmatter, {:invalid_value, key, value}}}
    end
  end

  defp string_list(raw, key) do
    case raw[key] do
      values when is_list(values) ->
        if Enum.all?(values, &is_binary/1) do
          {:ok, values}
        else
          {:error, {:invalid_frontmatter, {:invalid_value, key, values}}}
        end

      value ->
        {:error, {:invalid_frontmatter, {:invalid_value, key, value}}}
    end
  end

  defp iso8601_string(raw, key) do
    case raw[key] do
      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, _datetime, _offset} -> {:ok, value}
          {:error, _reason} -> {:error, {:invalid_frontmatter, {:invalid_datetime, key, value}}}
        end

      value ->
        {:error, {:invalid_frontmatter, {:invalid_value, key, value}}}
    end
  end

  defp metadata(raw) do
    case raw["metadata"] do
      value when is_map(value) ->
        with {:ok, metadata} <- InspectionPolicy.normalize_metadata(value),
             {:ok, metadata} <- MayorPolicy.normalize_metadata(metadata) do
          {:ok, metadata}
        else
          {:error, {:inspection_policy, reason}} ->
            {:error, {:invalid_frontmatter, {:inspection_policy, reason}}}

          {:error, {:mayor_policy, reason}} ->
            {:error, {:invalid_frontmatter, {:mayor_policy, reason}}}
        end

      value ->
        {:error, {:invalid_frontmatter, {:invalid_value, "metadata", value}}}
    end
  end

  defp validate_billboard_state([], state) when state not in ["open", "cancelled"] do
    {:error, {:invalid_frontmatter, {:invalid_billboard_state, state}}}
  end

  defp validate_billboard_state(_assignees, _state), do: :ok

  defp validate_mayor_ticket_type("mission", _metadata), do: :ok

  defp validate_mayor_ticket_type(type, metadata) do
    case MayorPolicy.from_metadata(metadata) do
      :missing ->
        :ok

      {:ok, _policy} ->
        {:error, {:invalid_frontmatter, {:mayor_policy, {:invalid_ticket_type, type}}}}

      {:error, {:mayor_policy, reason}} ->
        {:error, {:invalid_frontmatter, {:mayor_policy, reason}}}
    end
  end

  defp unknown_assignee_warnings(_assignees, nil), do: []

  defp unknown_assignee_warnings(assignees, known_citizens) when is_list(known_citizens) do
    known = MapSet.new(known_citizens)

    assignees
    |> Enum.reject(&MapSet.member?(known, &1))
    |> Enum.map(&{:unknown_citizen, &1})
  end

  defp unknown_assignee_warnings(_assignees, _known_citizens), do: []

  defp line(key, value), do: "#{key}: #{yaml_inline(value)}"

  defp yaml_inline(nil), do: "null"
  defp yaml_inline(value) when is_binary(value), do: Jason.encode!(value)
  defp yaml_inline(value) when is_list(value), do: Jason.encode!(value)
  defp yaml_inline(value) when is_map(value), do: Jason.encode!(value)
end
