defmodule Babs.Citizens.Tickets.PromptAssembler do
  @moduledoc """
  Builds provider-neutral, sanitized prompts for multi-turn Ticket follow-ups.
  """

  alias Babs.Citizens.CitizenRecord
  alias Babs.Citizens.Tickets.Conversation
  alias Babs.Citizens.Tickets.Ticket
  alias Babs.Knowledge

  require Logger

  @default_max_messages 12
  @default_max_children 5
  @standing_context_files ["Readme.md", "GOAL.md"]

  @spec compact_follow_up_prompt(Ticket.t(), keyword()) :: String.t()
  def compact_follow_up_prompt(%Ticket{} = ticket, opts \\ []) do
    latest_message = Keyword.get(opts, :latest_message, "")

    """
    Ticket: #{ticket.id}

    Latest operator message:
    #{sanitize(latest_message)}

    Reply with:
    BABS_REPLY #{ticket.id}: your response
    """
    |> String.trim()
  end

  @spec follow_up_prompt(Ticket.t(), [map()] | Conversation.t(), keyword()) :: String.t()
  def follow_up_prompt(ticket, history_or_conversation, opts \\ [])

  def follow_up_prompt(%Ticket{} = ticket, history, opts) when is_list(history) do
    follow_up_prompt(ticket, Conversation.from_history(history), opts)
  end

  def follow_up_prompt(%Ticket{} = ticket, %Conversation{} = conversation, opts) do
    citizen_slug = Keyword.fetch!(opts, :citizen_slug)
    latest_message = Keyword.get(opts, :latest_message, "")
    max_messages = Keyword.get(opts, :max_messages, @default_max_messages)
    standing_context = standing_context_section(citizen_slug, opts)

    messages =
      conversation.messages
      |> drop_latest_operator_message(latest_message)
      |> Enum.take(-max_messages)
      |> Enum.map_join("\n", &format_message/1)

    """
    You are #{citizen_slug}, a Babs Citizen.
    Continue this Ticket conversation. Keep your reply concise and actionable.

    Ticket: #{ticket.id}
    Title: #{sanitize(ticket.title)}
    State: #{ticket.state}
    Priority: #{ticket.priority}
    Assignees: #{Enum.join(ticket.assignees, ", ")}
    Citizen: #{citizen_slug}
    #{standing_context}

    Ticket body:
    #{sanitize(ticket.body)}

    Recent visible chat messages:
    #{messages}

    Latest operator message:
    #{sanitize(latest_message)}

    Reply normally in this AI CLI transcript with:
    BABS_REPLY #{ticket.id}: your response
    """
    |> String.trim()
  end

  @spec inspection_prompt(Ticket.t(), [map()] | Conversation.t(), String.t(), keyword()) ::
          String.t()
  def inspection_prompt(ticket, history_or_conversation, inspector_slug, opts \\ [])

  def inspection_prompt(%Ticket{} = ticket, history, inspector_slug, opts)
      when is_list(history) do
    inspection_prompt(ticket, Conversation.from_history(history), inspector_slug, opts)
  end

  def inspection_prompt(
        %Ticket{} = ticket,
        %Conversation{} = conversation,
        inspector_slug,
        opts
      )
      when is_binary(inspector_slug) do
    inspection_id = Keyword.get(opts, :inspection_id, "")
    max_messages = Keyword.get(opts, :max_messages, @default_max_messages)

    messages =
      conversation.messages
      |> Enum.reject(&(&1.role == :system))
      |> Enum.take(-max_messages)
      |> Enum.map_join("\n", &format_message/1)

    """
    You are #{inspector_slug}, a Babs Inspector Citizen.
    Inspect this pending-approval Ticket. Be conservative: approve only when the Ticket body and visible conversation show the acceptance criteria are satisfied.

    Ticket: #{ticket.id}
    Inspection: #{sanitize(inspection_id)}
    Title: #{sanitize(ticket.title)}
    State: #{ticket.state}
    Priority: #{ticket.priority}
    Assignees: #{Enum.join(ticket.assignees, ", ")}
    Inspector: #{inspector_slug}

    Ticket body:
    #{sanitize(ticket.body)}

    Recent visible chat messages:
    #{messages}

    Reply with exactly one fenced JSON object using this shape:
    ```json
    {
      "decision": "approve",
      "summary": "One concise sentence.",
      "findings": []
    }
    ```

    Allowed decision values: "approve", "reject", "needs_changes".
    """
    |> String.trim()
  end

  @spec mayor_proposal_prompt(
          Ticket.t(),
          [map()] | Conversation.t(),
          map(),
          map(),
          [
            CitizenRecord.t()
          ],
          keyword()
        ) :: String.t()
  def mayor_proposal_prompt(ticket, history_or_conversation, mayor, policy, citizens, opts \\ [])

  def mayor_proposal_prompt(%Ticket{} = ticket, history, mayor, policy, citizens, opts)
      when is_list(history) do
    mayor_proposal_prompt(
      ticket,
      Conversation.from_history(history),
      mayor,
      policy,
      citizens,
      opts
    )
  end

  def mayor_proposal_prompt(
        %Ticket{} = ticket,
        %Conversation{} = conversation,
        mayor,
        policy,
        citizens,
        opts
      )
      when is_map(mayor) and is_map(policy) and is_list(citizens) do
    max_messages = Keyword.get(opts, :max_messages, @default_max_messages)
    mayor_slug = sanitize(Map.get(mayor, :slug) || Map.get(mayor, "slug"))
    rules_refs = string_list(policy, "rules_refs")
    allowed_roles = string_list(policy, "allowed_roles")
    max_children = policy_value(policy, "max_children", @default_max_children)

    messages =
      conversation.messages
      |> Enum.reject(&(&1.role == :system))
      |> Enum.take(-max_messages)
      |> Enum.map_join("\n", &format_message/1)

    """
    You are #{mayor_slug}, a Babs Mayor Citizen.
    Propose a human-reviewed child Ticket plan. Do not execute the work and do not create files.

    Ticket: #{ticket.id}
    Title: #{sanitize(ticket.title)}
    Type: #{ticket.type}
    State: #{ticket.state}
    Priority: #{ticket.priority}
    Assignees: #{Enum.join(ticket.assignees, ", ")}
    Mayor: #{mayor_slug}
    Max children: #{max_children}

    Ticket body:
    #{sanitize(ticket.body)}

    Recent visible chat messages:
    #{messages}

    Rules refs:
    #{format_lines(rules_refs)}

    You may run `af read` or `af plan` for the rule refs when useful. Babs has not embedded full Alfred SOP bodies in this prompt.

    Allowed assignee role labels:
    #{format_lines(assignee_roles_for_prompt(allowed_roles, citizens))}

    Eligible Citizens:
    #{format_lines(Enum.map(citizens, &citizen_summary/1))}

    Inspection options:
    - user: human review
    - auto: Inspector Council review through metadata.inspection.mode = "auto"

    Reply with exactly one fenced JSON object using this shape:
    ```json
    {
      "proposal_id": "prop_short_lowercase_id",
      "root_ticket_id": "#{ticket.id}",
      "summary": "One concise proposal summary.",
      "rules_refs_used": [],
      "children": [
        {
          "title": "Child Ticket title",
          "body": "Child Ticket body with acceptance criteria.",
          "type": "assignment",
          "priority": "normal",
          "assignee_role": "developer",
          "metadata": {
            "inspection": {"mode": "human"}
          }
        }
      ],
      "risks": [],
      "questions": []
    }
    ```
    """
    |> String.trim()
  end

  defp format_message(message) do
    "- #{message.ts || "unknown"} #{message.author}: #{sanitize(message.body)}"
  end

  defp standing_context_section(citizen_slug, opts) do
    @standing_context_files
    |> Enum.flat_map(&standing_context_entry(citizen_slug, &1, opts))
    |> case do
      [] ->
        ""

      entries ->
        body =
          Enum.map_join(entries, "\n\n", fn {file, content} ->
            "[file: #{file}]\n#{content |> String.trim() |> sanitize()}"
          end)

        "\nCitizen standing context:\n\n" <> body
    end
  end

  defp standing_context_entry(citizen_slug, file, opts) do
    case Knowledge.read(citizen_slug, file, opts) do
      {:ok, content} when is_binary(content) ->
        cond do
          not String.valid?(content) ->
            Logger.warning("Babs standing context #{file} for #{citizen_slug} skipped")
            []

          String.trim(content) == "" ->
            []

          true ->
            [{file, content}]
        end

      {:ok, _content} ->
        Logger.warning("Babs standing context #{file} for #{citizen_slug} skipped")
        []

      {:error, {:not_found, ^file}} ->
        []

      {:error, _reason} ->
        Logger.warning("Babs standing context #{file} for #{citizen_slug} skipped")
        []
    end
  end

  defp format_lines([]), do: "- none"
  defp format_lines(values), do: Enum.map_join(values, "\n", &"- #{sanitize(&1)}")

  defp string_list(map, key) do
    case policy_value(map, key, []) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp policy_atom_field("rules_refs"), do: :rules_refs
  defp policy_atom_field("allowed_roles"), do: :allowed_roles
  defp policy_atom_field("max_children"), do: :max_children
  defp policy_atom_field(_key), do: nil

  defp policy_value(map, key, default) do
    Map.get(map, key, Map.get(map, policy_atom_field(key), default))
  end

  defp assignee_roles_for_prompt([], citizens) do
    citizens
    |> Enum.flat_map(&citizen_roles/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp assignee_roles_for_prompt(allowed_roles, _citizens) do
    allowed_roles
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp citizen_summary(%CitizenRecord{} = citizen) do
    roles =
      citizen
      |> citizen_roles()
      |> Enum.join(", ")

    [
      citizen.slug,
      " (roles: ",
      if(roles == "", do: "none", else: roles),
      "; status: ",
      citizen.status || "unknown",
      "; backend: ",
      citizen.ticket_backend || "unknown",
      ")",
      description(citizen.description)
    ]
    |> IO.iodata_to_binary()
  end

  defp citizen_summary(_citizen), do: "unknown"

  defp description(nil), do: ""
  defp description(""), do: ""
  defp description(value), do: " - " <> sanitize(value)

  defp citizen_roles(%CitizenRecord{} = citizen), do: CitizenRecord.role_names(citizen)

  defp drop_latest_operator_message(messages, latest_message) when is_binary(latest_message) do
    latest = String.trim(latest_message)

    duplicate =
      messages
      |> Enum.with_index()
      |> Enum.reverse()
      |> Enum.find(fn
        {%{role: :user, body: body}, _index} when is_binary(body) ->
          latest != "" and String.trim(body) == latest

        _other ->
          false
      end)

    case duplicate do
      {_message, index} -> List.delete_at(messages, index)
      nil -> messages
    end
  end

  defp sanitize(value) when is_binary(value) do
    value
    |> String.replace(
      ~r{/(?:Users|home|workspace|tmp|var|private|opt|Volumes|Applications)/[^\s]+|/root(?:/[^\s]+)?},
      "[local-path]"
    )
    |> String.replace(~r/\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/, "[private-ip]")
    |> String.replace(
      ~r/\b100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3}\b/,
      "[private-ip]"
    )
    |> String.replace(~r/\b192\.168\.\d{1,3}\.\d{1,3}\b/, "[private-ip]")
    |> String.replace(~r/\b172\.(?:1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3}\b/, "[private-ip]")
    |> String.replace(~r/\b[a-z0-9][a-z0-9-]*\.local\b/i, "[private-host]")
    |> String.replace(~r{\b(token|secret|password|api[_-]?key)(\s*[:=]\s*)[^\r\n]+}i, "[secret]")
    |> String.replace(~r{\b(token|secret|password|api[_-]?key)\s+\S+}i, "[secret]")
  end

  defp sanitize(nil), do: ""

  defp sanitize(value) when is_atom(value) or is_number(value),
    do: sanitize(to_string(value))

  defp sanitize(_value), do: "[unsupported-value]"
end
