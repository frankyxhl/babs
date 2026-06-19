defmodule Babs.Citizens.Tickets.ConversationTreeTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.Conversation
  alias Babs.Citizens.Tickets.ConversationTree

  test "flat single turn with messages produces one root node at depth 0" do
    conversation = Conversation.from_history(history_with_turn("t1", nil, "user", ["Hello"]))

    [node] = ConversationTree.build(conversation)

    assert node.turn_id == "t1"
    assert node.depth == 0
    assert node.children == []
    assert [msg] = node.messages
    assert msg.body == "Hello"
  end

  test "nested turns nest child under parent at depth 1" do
    history =
      history_with_turn("t1", nil, "user", ["Parent message"]) ++
        history_with_turn("t2", "t1", "citizen", ["Child reply"])

    conversation = Conversation.from_history(history)
    tree = ConversationTree.build(conversation)

    assert [root] = tree
    assert root.turn_id == "t1"
    assert root.depth == 0
    assert [child] = root.children
    assert child.turn_id == "t2"
    assert child.depth == 1
    assert [msg] = child.messages
    assert msg.body == "Child reply"
  end

  test "three levels of nesting produce depths 0, 1, 2" do
    history =
      history_with_turn("t1", nil, "user", ["Level 0"]) ++
        history_with_turn("t2", "t1", "citizen", ["Level 1"]) ++
        history_with_turn("t3", "t2", "citizen", ["Level 2"])

    conversation = Conversation.from_history(history)
    tree = ConversationTree.build(conversation)

    assert [root] = tree
    assert root.depth == 0
    assert [mid] = root.children
    assert mid.depth == 1
    assert [leaf] = mid.children
    assert leaf.depth == 2
    assert [%{body: "Level 2"}] = leaf.messages
  end

  test "legacy messages (turn_id nil) become standalone root nodes with no children" do
    history = [
      %{
        "ts" => "2026-06-01T10:00:00Z",
        "event" => "comment",
        "by" => "user",
        "body" => "Legacy message"
      }
    ]

    conversation = Conversation.from_history(history)
    tree = ConversationTree.build(conversation)

    assert [node] = tree
    assert is_nil(node.turn_id)
    assert node.depth == 0
    assert node.children == []
    assert [msg] = node.messages
    assert msg.body == "Legacy message"
  end

  test "orphan parent_turn_id (pointing to absent turn) makes turn a root" do
    history = history_with_turn("t2", "t-absent", "user", ["Orphan root"])

    conversation = Conversation.from_history(history)
    tree = ConversationTree.build(conversation)

    assert [node] = tree
    assert node.turn_id == "t2"
    assert node.depth == 0
  end

  test "siblings sorted by earliest message order, then messages within node sorted by order" do
    history =
      [
        turn_created("t1", nil, 0),
        turn_created("t2", nil, 1),
        comment("t2", "user", "Second root first msg", 2),
        comment("t2", "citizen", "Second root second msg", 3),
        comment("t1", "user", "First root msg", 4)
      ]

    conversation = Conversation.from_history(history)
    tree = ConversationTree.build(conversation)

    assert [first, second] = tree
    assert first.turn_id == "t2"
    assert second.turn_id == "t1"

    assert Enum.map(first.messages, & &1.body) == [
             "Second root first msg",
             "Second root second msg"
           ]
  end

  test "multi-author conversation shows both authors in messages" do
    history =
      history_with_turn("t1", nil, "user", ["User prompt"]) ++
        history_with_turn("t2", "t1", "clare", ["Clare response"])

    conversation = Conversation.from_history(history)
    tree = ConversationTree.build(conversation)

    assert [root] = tree
    assert [user_msg] = root.messages
    assert user_msg.author == "user"

    assert [child] = root.children
    assert [citizen_msg] = child.messages
    assert citizen_msg.author == "clare"
  end

  test "empty turn (no messages) without children is excluded" do
    history = [turn_created("t-empty", nil, 0)]

    conversation = Conversation.from_history(history)
    tree = ConversationTree.build(conversation)

    assert tree == []
  end

  test "empty turn with children is included" do
    history =
      [turn_created("t-empty", nil, 0)] ++ history_with_turn("t1", "t-empty", "user", ["Child"])

    conversation = Conversation.from_history(history)
    tree = ConversationTree.build(conversation)

    assert [node] = tree
    assert node.turn_id == "t-empty"
    assert node.messages == []
    assert [child] = node.children
    assert child.turn_id == "t1"
  end

  test "mixed legacy and turn messages: legacy as root, turned as root" do
    history =
      [
        %{
          "ts" => "2026-06-01T09:00:00Z",
          "event" => "comment",
          "by" => "user",
          "body" => "Legacy first"
        }
      ] ++ history_with_turn("t1", nil, "citizen", ["Turn root"])

    conversation = Conversation.from_history(history)
    tree = ConversationTree.build(conversation)

    assert length(tree) == 2
    legacy_node = Enum.find(tree, &is_nil(&1.turn_id))
    turn_node = Enum.find(tree, &(&1.turn_id == "t1"))
    assert legacy_node != nil
    assert turn_node != nil
  end

  defp history_with_turn(turn_id, parent_turn_id, author, bodies) do
    turn_order = 0

    turn_event = %{
      "ts" => "2026-06-01T10:00:00Z",
      "event" => "turn_created",
      "by" => author,
      "ticket_id" => "T-1",
      "turn_id" => turn_id,
      "parent_turn_id" => parent_turn_id
    }

    comment_events =
      bodies
      |> Enum.with_index(turn_order + 1)
      |> Enum.map(fn {body, idx} ->
        %{
          "ts" => "2026-06-01T10:00:0#{idx}Z",
          "event" => "comment",
          "by" => author,
          "ticket_id" => "T-1",
          "message_id" => "msg_#{turn_id}_#{idx}",
          "turn_id" => turn_id,
          "body" => body
        }
      end)

    [turn_event | comment_events]
  end

  defp turn_created(turn_id, parent_turn_id, order) do
    %{
      "ts" => "2026-06-01T10:00:00Z",
      "event" => "turn_created",
      "by" => "user",
      "ticket_id" => "T-1",
      "turn_id" => turn_id,
      "parent_turn_id" => parent_turn_id,
      "_order" => order
    }
  end

  defp comment(turn_id, by, body, order) do
    %{
      "ts" => "2026-06-01T10:00:00Z",
      "event" => "comment",
      "by" => by,
      "ticket_id" => "T-1",
      "message_id" => "msg_#{turn_id}_#{order}",
      "turn_id" => turn_id,
      "body" => body,
      "_order" => order
    }
  end
end
