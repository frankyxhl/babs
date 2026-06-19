defmodule Babs.Citizens.Tickets.ConversationTree do
  @moduledoc """
  Builds a nested comment tree from a Conversation for forum-style rendering.

  Each node is:
    %{comment: msg, turn_id: String.t() | nil, children: [tree_node], depth: non_neg_integer}

  Parent resolution priority (per comment):
  1. Message-level: another comment whose id == this comment's parent_id (parent_comment_id).
  2. Turn-level fallback: the latest comment (by order) belonging to this comment's
     parent_turn_id, when no parent_id is set.
  3. Root: no resolved parent, or parent not present in the message set.

  Legacy messages (turn_id nil) are always roots.
  Orphan parent references (message or turn not present) → treat as root.
  Siblings sorted by order (ascending).
  """

  alias Babs.Citizens.Tickets.Conversation

  @type tree_node :: %{
          comment: map(),
          turn_id: String.t() | nil,
          children: [tree_node()],
          depth: non_neg_integer()
        }

  @spec build(Conversation.t()) :: [tree_node()]
  def build(%Conversation{} = conversation) do
    conversation.messages
    |> build_comment_nodes(conversation)
    |> sort_siblings()
  end

  @spec path_to(Conversation.t(), String.t()) :: [map()]
  def path_to(%Conversation{} = conversation, message_id) do
    messages_by_id = Map.new(conversation.messages, &{&1.id, &1})

    case Map.get(messages_by_id, message_id) do
      nil -> []
      msg -> build_path(msg, messages_by_id, conversation.turns, [msg])
    end
  end

  # ---------------------------------------------------------------------------
  # Internal: build flat list → nested structure
  # ---------------------------------------------------------------------------

  defp build_comment_nodes(messages, conversation) do
    messages_by_id = Map.new(messages, &{&1.id, &1})
    messages_by_turn = group_messages_by_turn(messages)
    turns = conversation.turns

    # Determine the effective parent_id for each message.
    # Returns nil when the message is a root.
    resolved_parents =
      Map.new(messages, fn msg ->
        {msg.id, resolve_parent_id(msg, messages_by_id, messages_by_turn, turns)}
      end)

    # Build children map: parent_id → [child_msg_id]
    children_map =
      Enum.reduce(messages, %{}, fn msg, acc ->
        case Map.get(resolved_parents, msg.id) do
          nil -> acc
          pid -> Map.update(acc, pid, [msg.id], &[msg.id | &1])
        end
      end)

    root_messages =
      Enum.filter(messages, fn msg ->
        is_nil(Map.get(resolved_parents, msg.id))
      end)

    Enum.map(root_messages, fn msg ->
      build_node(msg, messages_by_id, children_map, 0)
    end)
  end

  defp build_node(msg, messages_by_id, children_map, depth) do
    child_ids = Map.get(children_map, msg.id, [])

    children =
      child_ids
      |> Enum.map(&Map.fetch!(messages_by_id, &1))
      |> Enum.sort_by(& &1.order)
      |> Enum.map(&build_node(&1, messages_by_id, children_map, depth + 1))

    %{comment: msg, turn_id: msg.turn_id, children: children, depth: depth}
  end

  # ---------------------------------------------------------------------------
  # Parent resolution
  # ---------------------------------------------------------------------------

  defp resolve_parent_id(msg, messages_by_id, messages_by_turn, turns) do
    cond do
      # Legacy messages are always roots
      msg.legacy? ->
        nil

      # 1. Message-level: parent_id points to a known message
      not is_nil(msg.parent_id) and Map.has_key?(messages_by_id, msg.parent_id) ->
        msg.parent_id

      # Orphan parent_id (set but not present) → root
      not is_nil(msg.parent_id) ->
        nil

      # 2. Turn-level fallback: find latest comment in parent_turn
      true ->
        turn_fallback_parent(msg, messages_by_turn, turns)
    end
  end

  defp turn_fallback_parent(msg, messages_by_turn, turns) do
    with turn_id when not is_nil(turn_id) <- msg.turn_id,
         %{parent_turn_id: parent_turn_id} when not is_nil(parent_turn_id) <-
           Map.get(turns, turn_id),
         sibling_msgs when sibling_msgs != [] <-
           Map.get(messages_by_turn, parent_turn_id, []) do
      sibling_msgs
      |> Enum.sort_by(& &1.order)
      |> List.last()
      |> Map.fetch!(:id)
    else
      _ -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Path computation
  # ---------------------------------------------------------------------------

  defp build_path(msg, messages_by_id, turns, acc) do
    case resolve_parent_id(
           msg,
           messages_by_id,
           group_messages_by_turn(Map.values(messages_by_id)),
           turns
         ) do
      nil ->
        acc

      parent_id ->
        parent = Map.fetch!(messages_by_id, parent_id)
        build_path(parent, messages_by_id, turns, [parent | acc])
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp group_messages_by_turn(messages) do
    messages
    |> Enum.reject(& &1.legacy?)
    |> Enum.group_by(& &1.turn_id)
  end

  defp sort_siblings(nodes) do
    Enum.sort_by(nodes, & &1.comment.order)
  end
end
