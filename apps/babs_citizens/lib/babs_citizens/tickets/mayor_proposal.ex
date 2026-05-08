defmodule Babs.Citizens.Tickets.MayorProposal do
  @moduledoc """
  Parses and validates Phase 16 Mayor proposal payloads.
  """

  alias Babs.Citizens.Roles
  alias Babs.Citizens.Tickets.InspectionPolicy
  alias Babs.Citizens.Tickets.TicketId

  @proposal_id_regex ~r/^prop_[a-z0-9_-]{1,72}$/
  @priorities ~w(low normal high urgent)
  @max_list 10
  @atom_fields %{
    "proposal_id" => :proposal_id,
    "root_ticket_id" => :root_ticket_id,
    "summary" => :summary,
    "rules_refs_used" => :rules_refs_used,
    "children" => :children,
    "risks" => :risks,
    "questions" => :questions,
    "title" => :title,
    "body" => :body,
    "type" => :type,
    "priority" => :priority,
    "assignee_role" => :assignee_role,
    "metadata" => :metadata,
    "inspector" => :inspector
  }

  @spec parse(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def parse(text, opts \\ [])

  def parse(text, opts) when is_binary(text) do
    with {:ok, json} <- extract_json(text),
         {:ok, decoded} <- decode_json(json),
         {:ok, normalized} <- normalize(decoded, opts) do
      {:ok, normalized}
    end
  end

  def parse(value, _opts), do: {:error, {:mayor_proposal, {:invalid_reply, value}}}

  @spec normalize(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def normalize(payload, opts \\ [])

  def normalize(payload, opts) when is_map(payload) do
    with {:ok, proposal_id} <- proposal_id(payload),
         {:ok, root_ticket_id} <- ticket_id(payload, "root_ticket_id"),
         {:ok, summary} <- required_string(payload, "summary"),
         {:ok, rules_refs_used} <- string_list(payload, "rules_refs_used", :rules_refs_used),
         {:ok, risks} <- string_list(payload, "risks", :risks),
         {:ok, questions} <- string_list(payload, "questions", :questions),
         {:ok, children} <- children(payload, opts) do
      {:ok,
       %{
         "proposal_id" => proposal_id,
         "root_ticket_id" => root_ticket_id,
         "summary" => summary,
         "rules_refs_used" => rules_refs_used,
         "children" => children,
         "risks" => risks,
         "questions" => questions
       }}
    end
  end

  def normalize(value, _opts), do: {:error, {:mayor_proposal, {:invalid_payload, value}}}

  defp extract_json(text) do
    case Regex.run(~r/```(?:json)?\s*(.*?)\s*```/s, text) do
      [_, json] -> {:ok, String.trim(json)}
      _missing -> {:ok, String.trim(text)}
    end
  end

  defp decode_json(json) do
    case Jason.decode(json) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, decoded} -> {:error, {:mayor_proposal, {:invalid_payload, decoded}}}
      {:error, _reason} -> {:error, {:mayor_proposal, :invalid_json}}
    end
  end

  defp proposal_id(payload) do
    with {:ok, value} <- required_string(payload, "proposal_id") do
      if Regex.match?(@proposal_id_regex, value) do
        {:ok, value}
      else
        {:error, {:mayor_proposal, {:invalid_proposal_id, value}}}
      end
    end
  end

  defp ticket_id(payload, key) do
    with {:ok, value} <- required_string(payload, key) do
      case TicketId.validate(value) do
        :ok -> {:ok, value}
        {:error, reason} -> {:error, {:mayor_proposal, reason}}
      end
    end
  end

  defp children(payload, opts) do
    max_children = Keyword.get(opts, :max_children, @max_list)

    case required_field(payload, "children") do
      {:error, reason} ->
        {:error, {:mayor_proposal, reason}}

      [] ->
        {:error, {:mayor_proposal, :empty_children}}

      children when is_list(children) and length(children) <= max_children ->
        with {:ok, allowed_roles} <-
               normalize_allowed_roles(Keyword.get(opts, :allowed_roles, [])) do
          children
          |> Enum.with_index()
          |> Enum.reduce_while({:ok, []}, fn {child, index}, {:ok, acc} ->
            case normalize_child(child, index, allowed_roles) do
              {:ok, normalized} -> {:cont, {:ok, acc ++ [normalized]}}
              {:error, reason} -> {:halt, {:error, reason}}
            end
          end)
        end

      children when is_list(children) ->
        {:error, {:mayor_proposal, {:too_many_children, length(children)}}}

      value ->
        {:error, {:mayor_proposal, {:invalid_children, value}}}
    end
  end

  defp normalize_allowed_roles(value) do
    case Roles.normalize(value) do
      {:ok, roles} -> {:ok, Enum.map(roles, & &1["name"])}
      {:error, reason} -> {:error, {:mayor_proposal, {:invalid_allowed_roles, reason}}}
    end
  end

  defp normalize_child(child, index, allowed_roles) when is_map(child) do
    with {:ok, title} <- child_required_string(child, index, "title"),
         {:ok, body} <- child_required_string(child, index, "body"),
         {:ok, type} <- child_type(child, index),
         {:ok, priority} <- child_priority(child, index),
         {:ok, assignee_role} <- child_assignee_role(child, index, allowed_roles),
         {:ok, metadata} <- child_metadata(child, index),
         {:ok, inspector} <- child_inspector(child, index, metadata) do
      {:ok,
       %{
         "title" => title,
         "body" => body,
         "type" => type,
         "priority" => priority,
         "assignee_role" => assignee_role,
         "inspector" => inspector,
         "metadata" => metadata
       }}
    end
  end

  defp normalize_child(child, index, _allowed_roles),
    do: {:error, {:mayor_proposal, {:invalid_child, index, {:invalid_child, child}}}}

  defp child_type(child, index) do
    case field(child, "type", "assignment") do
      "assignment" -> {:ok, "assignment"}
      value -> child_error(index, {:invalid_type, value})
    end
  end

  defp child_priority(child, index) do
    case field(child, "priority", "normal") do
      value when is_binary(value) and value in @priorities -> {:ok, value}
      value -> child_error(index, {:invalid_priority, value})
    end
  end

  defp child_assignee_role(child, index, allowed_roles) do
    case field(child, "assignee_role", nil) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        case Roles.normalize(value) do
          {:ok, [%{"name" => role}]} ->
            if allowed_roles == [] or role in allowed_roles do
              {:ok, role}
            else
              child_error(index, {:disallowed_assignee_role, role})
            end

          {:ok, []} ->
            {:ok, nil}

          {:error, reason} ->
            child_error(index, reason)
        end

      value ->
        child_error(index, {:invalid_assignee_role, value})
    end
  end

  defp child_metadata(child, index) do
    case field(child, "metadata", %{}) do
      metadata when is_map(metadata) ->
        case InspectionPolicy.normalize_metadata(metadata) do
          {:ok, normalized} -> {:ok, normalized}
          {:error, reason} -> child_error(index, reason)
        end

      value ->
        child_error(index, {:invalid_metadata, value})
    end
  end

  defp child_inspector(child, index, metadata) do
    requested = field(child, "inspector", nil)
    derived = derived_inspector(metadata)

    case normalize_inspector(requested) do
      {:ok, nil} ->
        {:ok, derived}

      {:ok, ^derived} ->
        {:ok, derived}

      {:ok, inspector} ->
        child_error(index, {:conflicting_inspector, inspector})

      {:error, reason} ->
        child_error(index, reason)
    end
  end

  defp derived_inspector(%{"inspection" => %{"mode" => "auto"}}), do: "auto"
  defp derived_inspector(_metadata), do: "user"

  defp normalize_inspector(nil), do: {:ok, nil}
  defp normalize_inspector(""), do: {:ok, nil}
  defp normalize_inspector("human"), do: {:ok, "user"}
  defp normalize_inspector("user"), do: {:ok, "user"}
  defp normalize_inspector("auto"), do: {:ok, "auto"}
  defp normalize_inspector(value), do: {:error, {:invalid_inspector, value}}

  defp child_required_string(map, index, key) do
    case required_string(map, key) do
      {:ok, value} -> {:ok, value}
      {:error, {:mayor_proposal, reason}} -> child_error(index, reason)
    end
  end

  defp required_string(map, key) do
    case required_field(map, key) do
      {:error, reason} ->
        {:error, {:mayor_proposal, reason}}

      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, {:mayor_proposal, {:blank, key}}}
          trimmed -> {:ok, trimmed}
        end

      value ->
        {:error, {:mayor_proposal, {:invalid_string, key, value}}}
    end
  end

  defp string_list(map, key, error_key) do
    case required_field(map, key) do
      {:error, reason} ->
        {:error, {:mayor_proposal, reason}}

      values when is_list(values) ->
        values
        |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
          case normalize_string(value) do
            {:ok, normalized} ->
              {:cont, {:ok, append_unique(acc, normalized)}}

            {:error, _reason} ->
              {:halt, {:error, {:mayor_proposal, {:"invalid_#{error_key}", value}}}}
          end
        end)
        |> case do
          {:ok, normalized} when length(normalized) <= @max_list ->
            {:ok, normalized}

          {:ok, normalized} ->
            {:error, {:mayor_proposal, {:"too_many_#{error_key}", length(normalized)}}}

          {:error, reason} ->
            {:error, reason}
        end

      value ->
        {:error, {:mayor_proposal, {:"invalid_#{error_key}", value}}}
    end
  end

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, :blank}
      trimmed -> {:ok, trimmed}
    end
  end

  defp normalize_string(_value), do: {:error, :invalid}

  defp child_error(index, reason),
    do: {:error, {:mayor_proposal, {:invalid_child, index, reason}}}

  defp append_unique(values, value) do
    if value in values, do: values, else: values ++ [value]
  end

  defp field(map, key, default), do: Map.get(map, key, Map.get(map, @atom_fields[key], default))

  defp required_field(map, key) do
    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, @atom_fields[key]) -> Map.get(map, @atom_fields[key])
      true -> {:error, {:missing_field, key}}
    end
  end
end
