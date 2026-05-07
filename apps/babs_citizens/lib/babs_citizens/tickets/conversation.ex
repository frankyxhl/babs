defmodule Babs.Citizens.Tickets.Conversation do
  @moduledoc """
  Reduces append-only Ticket history events into chat messages and turn status.
  """

  defstruct messages: [], attempts: %{}, turns: %{}

  @type t :: %__MODULE__{
          messages: [map()],
          attempts: map(),
          turns: map()
        }

  @spec from_history([map()]) :: t()
  def from_history(history) when is_list(history) do
    history
    |> Enum.with_index()
    |> Enum.reduce(%__MODULE__{}, fn {event, index}, conversation ->
      reduce_event(conversation, event, index)
    end)
    |> sort_messages()
  end

  @spec attempt(t(), String.t(), String.t(), String.t()) :: map() | nil
  def attempt(%__MODULE__{} = conversation, turn_id, citizen_slug, attempt_id) do
    Map.get(conversation.attempts, {turn_id, citizen_slug, attempt_id})
  end

  @spec attempts_for_turn(t(), String.t() | nil) :: [map()]
  def attempts_for_turn(_conversation, nil), do: []

  def attempts_for_turn(%__MODULE__{} = conversation, turn_id) do
    conversation.attempts
    |> Map.values()
    |> Enum.filter(&(&1.turn_id == turn_id))
    |> Enum.sort_by(&{&1.citizen_slug, &1.attempt_id})
  end

  defp reduce_event(conversation, %{"event" => "comment", "body" => body} = event, index)
       when is_binary(body) and body != "" do
    id = event["message_id"] || "legacy_#{index}"
    turn_id = event["turn_id"]

    message = %{
      id: id,
      turn_id: turn_id,
      author: event["by"] || "unknown",
      role: role(event["by"]),
      body: body,
      ts: event["ts"],
      order: index,
      legacy?: is_nil(turn_id)
    }

    %{conversation | messages: [message | conversation.messages]}
  end

  defp reduce_event(
         conversation,
         %{"event" => "turn_created", "turn_id" => turn_id} = event,
         index
       ) do
    turn = %{
      turn_id: turn_id,
      prompt_message_id: event["prompt_message_id"],
      parent_turn_id: event["parent_turn_id"],
      to: list(event["to"]),
      ts: event["ts"],
      order: index
    }

    put_in(conversation.turns[turn_id], turn)
  end

  defp reduce_event(
         conversation,
         %{
           "event" => "turn_delivery_attempted",
           "turn_id" => turn_id,
           "attempt_id" => attempt_id,
           "to" => slug
         } = event,
         index
       ) do
    put_attempt(conversation, turn_id, slug, attempt_id, %{
      turn_id: turn_id,
      citizen_slug: slug,
      attempt_id: attempt_id,
      parent_attempt_id: event["parent_attempt_id"],
      backend: event["backend"] || "hardline",
      status: event["status"] || "queued",
      ts: event["ts"],
      order: index
    })
  end

  defp reduce_event(
         conversation,
         %{
           "event" => "turn_delivered",
           "turn_id" => turn_id,
           "attempt_id" => attempt_id,
           "to" => slug
         } = event,
         _index
       ) do
    update_attempt(conversation, turn_id, slug, attempt_id, %{
      backend: event["backend"] || "hardline",
      status: "delivered",
      delivered_at: event["ts"]
    })
  end

  defp reduce_event(
         conversation,
         %{
           "event" => "turn_delivery_failed",
           "turn_id" => turn_id,
           "attempt_id" => attempt_id,
           "to" => slug
         } = event,
         _index
       ) do
    update_attempt(conversation, turn_id, slug, attempt_id, %{
      backend: event["backend"] || "hardline",
      status: "failed",
      error: event["error"],
      failed_at: event["ts"]
    })
  end

  defp reduce_event(
         conversation,
         %{
           "event" => "turn_reply_captured",
           "turn_id" => turn_id,
           "attempt_id" => attempt_id,
           "message_id" => message_id
         } = event,
         _index
       ) do
    slug = event["by_citizen"] || event["by"] || "unknown"

    update_attempt(conversation, turn_id, slug, attempt_id, %{
      status: "captured",
      message_id: message_id,
      captured_at: event["ts"]
    })
  end

  defp reduce_event(conversation, _event, _index), do: conversation

  defp put_attempt(conversation, turn_id, slug, attempt_id, attempt) do
    put_in(conversation.attempts[{turn_id, slug, attempt_id}], attempt)
  end

  defp update_attempt(conversation, turn_id, slug, attempt_id, updates) do
    key = {turn_id, slug, attempt_id}

    original =
      Map.get(conversation.attempts, key, %{
        turn_id: turn_id,
        citizen_slug: slug,
        attempt_id: attempt_id
      })

    put_in(conversation.attempts[key], Map.merge(original, updates))
  end

  defp sort_messages(conversation) do
    %{conversation | messages: Enum.sort_by(conversation.messages, & &1.order)}
  end

  defp role("user"), do: :user
  defp role("system"), do: :system
  defp role(_author), do: :citizen

  defp list(values) when is_list(values), do: values
  defp list(value) when is_binary(value), do: [value]
  defp list(_value), do: []
end
