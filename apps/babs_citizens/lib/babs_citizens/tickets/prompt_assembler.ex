defmodule Babs.Citizens.Tickets.PromptAssembler do
  @moduledoc """
  Builds provider-neutral, sanitized prompts for multi-turn Ticket follow-ups.
  """

  alias Babs.Citizens.Tickets.Conversation
  alias Babs.Citizens.Tickets.Ticket

  @default_max_messages 12

  @spec follow_up_prompt(Ticket.t(), [map()] | Conversation.t(), keyword()) :: String.t()
  def follow_up_prompt(ticket, history_or_conversation, opts \\ [])

  def follow_up_prompt(%Ticket{} = ticket, history, opts) when is_list(history) do
    follow_up_prompt(ticket, Conversation.from_history(history), opts)
  end

  def follow_up_prompt(%Ticket{} = ticket, %Conversation{} = conversation, opts) do
    citizen_slug = Keyword.fetch!(opts, :citizen_slug)
    latest_message = Keyword.get(opts, :latest_message, "")
    max_messages = Keyword.get(opts, :max_messages, @default_max_messages)

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

  defp format_message(message) do
    "- #{message.ts || "unknown"} #{message.author}: #{sanitize(message.body)}"
  end

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
    |> String.replace(~r{/(?:Users|home)/[^\s]+|/root(?:/[^\s]+)?}, "[local-path]")
    |> String.replace(~r/\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/, "[private-ip]")
    |> String.replace(
      ~r/\b100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3}\b/,
      "[private-ip]"
    )
    |> String.replace(~r/\b192\.168\.\d{1,3}\.\d{1,3}\b/, "[private-ip]")
    |> String.replace(~r/\b172\.(?:1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3}\b/, "[private-ip]")
    |> String.replace(~r{\b(token|secret|password|api[_-]?key)(\s*[:=]\s*)[^\r\n]+}i, "[secret]")
    |> String.replace(~r{\b(token|secret|password|api[_-]?key)\s+\S+}i, "[secret]")
  end

  defp sanitize(nil), do: ""

  defp sanitize(value) when is_atom(value) or is_number(value),
    do: sanitize(to_string(value))

  defp sanitize(_value), do: "[unsupported-value]"
end
