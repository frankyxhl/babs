defmodule Babs.Citizens.Tickets.ConversationTreeTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.Conversation
  alias Babs.Citizens.Tickets.ConversationTree

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Build a sequence: turn_created + one comment per body, all sharing turn_id.
  defp history_with_turn(turn_id, parent_turn_id, author, bodies) do
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
      |> Enum.with_index(1)
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

  defp turn_created(turn_id, parent_turn_id, _order) do
    %{
      "ts" => "2026-06-01T10:00:00Z",
      "event" => "turn_created",
      "by" => "user",
      "ticket_id" => "T-1",
      "turn_id" => turn_id,
      "parent_turn_id" => parent_turn_id
    }
  end

  # A comment with explicit turn_id (no parent_comment_id).
  defp comment(turn_id, by, body, order) do
    %{
      "ts" => "2026-06-01T10:00:00Z",
      "event" => "comment",
      "by" => by,
      "ticket_id" => "T-1",
      "message_id" => "msg_#{turn_id}_#{order}",
      "turn_id" => turn_id,
      "body" => body
    }
  end

  # A comment with an explicit parent_comment_id (message-level reply).
  defp comment_reply(message_id, turn_id, parent_comment_id, by, body) do
    %{
      "ts" => "2026-06-01T10:00:01Z",
      "event" => "comment",
      "by" => by,
      "ticket_id" => "T-1",
      "message_id" => message_id,
      "turn_id" => turn_id,
      "parent_comment_id" => parent_comment_id,
      "body" => body
    }
  end

  # ---------------------------------------------------------------------------
  # Node shape: each node is %{comment: msg, turn_id, children, depth}
  # ---------------------------------------------------------------------------

  test "flat single turn with one message produces one root node at depth 0" do
    conversation = Conversation.from_history(history_with_turn("t1", nil, "user", ["Hello"]))

    [node] = ConversationTree.build(conversation)

    assert node.turn_id == "t1"
    assert node.depth == 0
    assert node.children == []
    assert node.comment.body == "Hello"
  end

  # ---------------------------------------------------------------------------
  # Turn-level fallback: no parent_comment_id → nest by parent_turn_id
  # ---------------------------------------------------------------------------

  test "turn-level fallback: child turn's comments nest under last parent-turn comment" do
    history =
      history_with_turn("t1", nil, "user", ["Parent message"]) ++
        history_with_turn("t2", "t1", "citizen", ["Child reply"])

    conversation = Conversation.from_history(history)
    tree = ConversationTree.build(conversation)

    # Root should be msg_t1_1
    assert [root] = tree
    assert root.comment.body == "Parent message"
    assert root.depth == 0

    # Child reply under root
    assert [child] = root.children
    assert child.comment.body == "Child reply"
    assert child.depth == 1
    assert child.turn_id == "t2"
  end

  test "three levels of nesting via turn-level fallback produce depths 0, 1, 2" do
    history =
      history_with_turn("t1", nil, "user", ["Level 0"]) ++
        history_with_turn("t2", "t1", "citizen", ["Level 1"]) ++
        history_with_turn("t3", "t2", "citizen", ["Level 2"])

    conversation = Conversation.from_history(history)
    tree = ConversationTree.build(conversation)

    assert [root] = tree
    assert root.depth == 0
    assert root.comment.body == "Level 0"
    assert [mid] = root.children
    assert mid.depth == 1
    assert mid.comment.body == "Level 1"
    assert [leaf] = mid.children
    assert leaf.depth == 2
    assert leaf.comment.body == "Level 2"
  end

  test "comment carrying a turn_id with no turn_created event is preserved as a root node" do
    history = [comment("t-orphan", "clare", "Reply with no turn record", 0)]

    conversation = Conversation.from_history(history)
    tree = ConversationTree.build(conversation)

    assert [node] = tree
    assert node.turn_id == "t-orphan"
    assert node.depth == 0
    assert node.children == []
    assert node.comment.body == "Reply with no turn record"
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
    assert node.comment.body == "Legacy message"
  end

  test "orphan parent_turn_id (pointing to absent turn) makes turn comments roots" do
    history = history_with_turn("t2", "t-absent", "user", ["Orphan root"])

    conversation = Conversation.from_history(history)
    tree = ConversationTree.build(conversation)

    assert [node] = tree
    assert node.turn_id == "t2"
    assert node.depth == 0
  end

  test "siblings sorted by order within same parent" do
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

    # t2's comment has order=2, t1's comment has order=4, so t2's comment is first
    bodies = Enum.map(tree, & &1.comment.body)
    assert "Second root first msg" in bodies
    assert "First root msg" in bodies
    # The sibling with lower order (t2 comment) comes first
    assert hd(bodies) == "Second root first msg"
  end

  test "multi-author conversation shows correct authors per node" do
    history =
      history_with_turn("t1", nil, "user", ["User prompt"]) ++
        history_with_turn("t2", "t1", "clare", ["Clare response"])

    conversation = Conversation.from_history(history)
    tree = ConversationTree.build(conversation)

    assert [root] = tree
    assert root.comment.author == "user"
    assert [child] = root.children
    assert child.comment.author == "clare"
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

  # ---------------------------------------------------------------------------
  # NEW: Message-level threading via parent_comment_id
  # ---------------------------------------------------------------------------

  test "message-level: reply with parent_comment_id nests under the referenced comment" do
    # t1 has two comments: msg_a (depth 0) and msg_b replies to msg_a (depth 1)
    history = [
      turn_created("t1", nil, 0),
      %{
        "ts" => "2026-06-01T10:00:01Z",
        "event" => "comment",
        "by" => "user",
        "ticket_id" => "T-1",
        "message_id" => "msg_a",
        "turn_id" => "t1",
        "body" => "Top level"
      },
      comment_reply("msg_b", "t1", "msg_a", "clare", "Reply to top")
    ]

    conversation = Conversation.from_history(history)
    tree = ConversationTree.build(conversation)

    assert [root] = tree
    assert root.comment.id == "msg_a"
    assert root.depth == 0
    assert [child] = root.children
    assert child.comment.id == "msg_b"
    assert child.comment.body == "Reply to top"
    assert child.depth == 1
  end

  test "message-level: three levels of nesting via parent_comment_id" do
    history = [
      turn_created("t1", nil, 0),
      %{
        "ts" => "2026-06-01T10:00:01Z",
        "event" => "comment",
        "by" => "user",
        "ticket_id" => "T-1",
        "message_id" => "msg_l0",
        "turn_id" => "t1",
        "body" => "L0"
      },
      comment_reply("msg_l1", "t1", "msg_l0", "alice", "L1"),
      comment_reply("msg_l2", "t1", "msg_l1", "bob", "L2")
    ]

    conversation = Conversation.from_history(history)
    tree = ConversationTree.build(conversation)

    assert [root] = tree
    assert root.comment.id == "msg_l0"
    assert root.depth == 0
    assert [mid] = root.children
    assert mid.comment.id == "msg_l1"
    assert mid.depth == 1
    assert [leaf] = mid.children
    assert leaf.comment.id == "msg_l2"
    assert leaf.depth == 2
  end

  test "orphan parent_comment_id (pointing to absent message) makes comment a root" do
    history = [
      turn_created("t1", nil, 0),
      comment_reply("msg_b", "t1", "msg_nonexistent", "clare", "Orphan reply")
    ]

    conversation = Conversation.from_history(history)
    tree = ConversationTree.build(conversation)

    assert [node] = tree
    assert node.comment.id == "msg_b"
    assert node.depth == 0
    assert node.children == []
  end

  test "mixed: some comments use parent_comment_id, some use turn-level fallback" do
    # t1: msg_a (root via turn)
    # t2 (child of t1 via parent_turn_id): msg_b (turn-level fallback under msg_a)
    # msg_c: explicit reply to msg_b via parent_comment_id
    history = [
      turn_created("t1", nil, 0),
      %{
        "ts" => "2026-06-01T10:00:01Z",
        "event" => "comment",
        "by" => "user",
        "ticket_id" => "T-1",
        "message_id" => "msg_a",
        "turn_id" => "t1",
        "body" => "Root"
      },
      turn_created("t2", "t1", 2),
      %{
        "ts" => "2026-06-01T10:00:03Z",
        "event" => "comment",
        "by" => "citizen",
        "ticket_id" => "T-1",
        "message_id" => "msg_b",
        "turn_id" => "t2",
        "body" => "Turn fallback reply"
      },
      comment_reply("msg_c", "t2", "msg_b", "user", "Message-level reply to msg_b")
    ]

    conversation = Conversation.from_history(history)
    tree = ConversationTree.build(conversation)

    assert [root] = tree
    assert root.comment.id == "msg_a"
    assert [turn_child] = root.children
    assert turn_child.comment.id == "msg_b"
    assert turn_child.depth == 1
    assert [msg_child] = turn_child.children
    assert msg_child.comment.id == "msg_c"
    assert msg_child.depth == 2
  end

  # ---------------------------------------------------------------------------
  # NEW: path_to/2
  # ---------------------------------------------------------------------------

  test "path_to returns [] for unknown message id" do
    conversation = Conversation.from_history(history_with_turn("t1", nil, "user", ["Hello"]))

    assert ConversationTree.path_to(conversation, "nonexistent") == []
  end

  test "path_to returns [msg] for a root-level comment" do
    conversation = Conversation.from_history(history_with_turn("t1", nil, "user", ["Hello"]))
    msg = hd(conversation.messages)

    path = ConversationTree.path_to(conversation, msg.id)
    assert [only] = path
    assert only.id == msg.id
  end

  test "path_to returns [root, child] for a depth-1 comment via turn fallback" do
    history =
      history_with_turn("t1", nil, "user", ["Root msg"]) ++
        history_with_turn("t2", "t1", "citizen", ["Child msg"])

    conversation = Conversation.from_history(history)
    root_msg = Enum.find(conversation.messages, &(&1.body == "Root msg"))
    child_msg = Enum.find(conversation.messages, &(&1.body == "Child msg"))

    path = ConversationTree.path_to(conversation, child_msg.id)
    assert [first, second] = path
    assert first.id == root_msg.id
    assert second.id == child_msg.id
  end

  test "path_to returns correct lineage for a 3-level message-level thread" do
    history = [
      turn_created("t1", nil, 0),
      %{
        "ts" => "2026-06-01T10:00:01Z",
        "event" => "comment",
        "by" => "user",
        "ticket_id" => "T-1",
        "message_id" => "msg_l0",
        "turn_id" => "t1",
        "body" => "L0"
      },
      comment_reply("msg_l1", "t1", "msg_l0", "alice", "L1"),
      comment_reply("msg_l2", "t1", "msg_l1", "bob", "L2")
    ]

    conversation = Conversation.from_history(history)
    path = ConversationTree.path_to(conversation, "msg_l2")

    assert length(path) == 3
    assert Enum.map(path, & &1.id) == ["msg_l0", "msg_l1", "msg_l2"]
  end
end
