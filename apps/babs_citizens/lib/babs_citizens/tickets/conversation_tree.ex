defmodule Babs.Citizens.Tickets.ConversationTree do
  @moduledoc """
  Builds a nested comment tree from a Conversation for forum-style rendering.

  Each node is:
    %{turn_id: id | nil, messages: [msg], children: [node], depth: non_neg_integer}

  Turns nest via parent_turn_id -> turn_id. Legacy messages (turn_id nil,
  legacy?: true) become standalone root nodes with no children.

  Orphan turns (parent_turn_id points to an absent turn) are treated as roots.

  Empty turns (no messages) are included only when they have children;
  otherwise they are excluded.
  """

  alias Babs.Citizens.Tickets.Conversation

  @type tree_node :: %{
          turn_id: String.t() | nil,
          messages: [map()],
          children: [tree_node()],
          depth: non_neg_integer()
        }

  @spec build(Conversation.t()) :: [tree_node()]
  def build(%Conversation{} = conversation) do
    legacy_nodes = build_legacy_nodes(conversation.messages)
    turn_nodes = build_turn_nodes(conversation)

    (legacy_nodes ++ turn_nodes)
    |> sort_siblings()
  end

  defp build_legacy_nodes(messages) do
    messages
    |> Enum.filter(& &1.legacy?)
    |> Enum.map(fn msg ->
      %{turn_id: nil, messages: [msg], children: [], depth: 0}
    end)
  end

  defp build_turn_nodes(conversation) do
    turns = conversation.turns
    messages_by_turn = group_messages_by_turn(conversation.messages)
    # Include turn ids that only appear on messages (a comment can carry a turn_id
    # with no matching turn_created event); otherwise such replies are silently
    # dropped. Message-only turn ids have no parent record, so they become roots.
    turn_ids = Enum.uniq(Map.keys(turns) ++ Map.keys(messages_by_turn))

    children_map =
      Enum.reduce(turns, %{}, fn {_id, turn}, acc ->
        parent = turn.parent_turn_id

        if is_nil(parent) or parent not in turn_ids do
          acc
        else
          Map.update(acc, parent, [turn.turn_id], fn existing -> [turn.turn_id | existing] end)
        end
      end)

    root_turn_ids =
      Enum.filter(turn_ids, fn id ->
        case Map.get(turns, id) do
          nil -> true
          turn -> is_nil(turn.parent_turn_id) or turn.parent_turn_id not in turn_ids
        end
      end)

    root_nodes =
      root_turn_ids
      |> Enum.map(fn turn_id ->
        build_node(turn_id, turns, messages_by_turn, children_map, 0)
      end)
      |> Enum.reject(&skip_empty_childless_node?/1)

    root_nodes
  end

  defp build_node(turn_id, turns, messages_by_turn, children_map, depth) do
    messages =
      messages_by_turn
      |> Map.get(turn_id, [])
      |> Enum.sort_by(& &1.order)

    child_turn_ids = Map.get(children_map, turn_id, [])

    children =
      child_turn_ids
      |> Enum.map(fn child_id ->
        build_node(child_id, turns, messages_by_turn, children_map, depth + 1)
      end)
      |> Enum.reject(&skip_empty_childless_node?/1)
      |> sort_siblings()

    %{turn_id: turn_id, messages: messages, children: children, depth: depth}
  end

  defp skip_empty_childless_node?(%{messages: [], children: []}), do: true
  defp skip_empty_childless_node?(_node), do: false

  defp group_messages_by_turn(messages) do
    messages
    |> Enum.reject(& &1.legacy?)
    |> Enum.group_by(& &1.turn_id)
  end

  defp sort_siblings(nodes) do
    Enum.sort_by(nodes, &earliest_order/1)
  end

  defp earliest_order(%{messages: [], turn_id: turn_id}) do
    {1, turn_id}
  end

  defp earliest_order(%{messages: messages}) do
    {0, messages |> Enum.map(& &1.order) |> Enum.min()}
  end
end
