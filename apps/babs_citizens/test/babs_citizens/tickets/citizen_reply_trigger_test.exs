defmodule Babs.Citizens.Tickets.CitizenReplyTriggerTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.CitizenReplyTrigger
  alias Babs.Citizens.Tickets.Conversation
  alias Babs.Citizens.Tickets.Ticket

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp conversation_from_comments(comments) do
    comments
    |> Enum.with_index()
    |> Enum.flat_map(fn {c, idx} ->
      events = [
        %{
          "ts" => "2026-06-01T10:00:0#{idx}Z",
          "event" => "comment",
          "by" => c[:by],
          "ticket_id" => "T-1",
          "message_id" => c[:id],
          "turn_id" => c[:turn_id],
          "body" => c[:body]
        }
        |> maybe_put("parent_comment_id", c[:parent_id])
      ]

      if turn_id = c[:turn_id] do
        turn_event = %{
          "ts" => "2026-06-01T10:00:0#{idx}Z",
          "event" => "turn_created",
          "by" => c[:by],
          "ticket_id" => "T-1",
          "turn_id" => turn_id
        }

        [turn_event | events]
      else
        events
      end
    end)
    |> Conversation.from_history()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp ticket(overrides \\ []) do
    %Ticket{
      id: "T-2026-06-01-001",
      type: "assignment",
      state: "in_progress",
      assigner: "user",
      assignees: ["alice"],
      assignee_role: nil,
      inspector: "user",
      priority: "normal",
      parent_ticket: nil,
      created_at: "2026-06-01T10:00:00Z",
      updated_at: "2026-06-01T10:01:00Z",
      metadata: %{},
      title: "Test ticket",
      body: "Do the work.",
      path: nil,
      warnings: []
    }
    |> struct(overrides)
  end

  # A comment map (as seen by CitizenReplyTrigger from a just-appended comment event)
  defp comment(opts) do
    %{
      "message_id" => opts[:id] || "msg_1",
      "by" => opts[:by] || "user",
      "body" => opts[:body] || "hello",
      "parent_comment_id" => opts[:parent_id]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # targets/3 — pure detection
  # ---------------------------------------------------------------------------

  describe "targets/3" do
    test "reply to a citizen comment wakes that citizen" do
      conversation =
        conversation_from_comments([
          %{id: "msg_a", by: "alice", body: "I can help", turn_id: "turn_a"}
        ])

      c = comment(id: "msg_2", by: "user", body: "thanks", parent_id: "msg_a")

      assert CitizenReplyTrigger.targets(c, conversation, ["alice", "bob"]) ==
               MapSet.new(["alice"])
    end

    test "reply to a human comment wakes nobody via reply path" do
      conversation =
        conversation_from_comments([
          %{id: "msg_u", by: "user", body: "start", turn_id: nil}
        ])

      c = comment(id: "msg_2", by: "alice", body: "working", parent_id: "msg_u")

      assert CitizenReplyTrigger.targets(c, conversation, ["alice", "bob"]) == MapSet.new()
    end

    test "reply to a citizen but commenter is the same citizen — no self-trigger" do
      conversation =
        conversation_from_comments([
          %{id: "msg_a", by: "alice", body: "I started", turn_id: "turn_a"}
        ])

      c = comment(id: "msg_2", by: "alice", body: "I continue", parent_id: "msg_a")

      assert CitizenReplyTrigger.targets(c, conversation, ["alice"]) == MapSet.new()
    end

    test "@-mention wakes the mentioned citizen" do
      conversation = conversation_from_comments([])
      c = comment(id: "msg_1", by: "user", body: "Hey @bob can you review?")

      assert CitizenReplyTrigger.targets(c, conversation, ["alice", "bob"]) == MapSet.new(["bob"])
    end

    test "@-mention of a non-citizen slug is ignored" do
      conversation = conversation_from_comments([])
      c = comment(id: "msg_1", by: "user", body: "Hey @charlie can you review?")

      assert CitizenReplyTrigger.targets(c, conversation, ["alice", "bob"]) == MapSet.new()
    end

    test "@-mention of self is not included" do
      conversation = conversation_from_comments([])
      c = comment(id: "msg_1", by: "alice", body: "@alice do something")

      assert CitizenReplyTrigger.targets(c, conversation, ["alice", "bob"]) == MapSet.new()
    end

    test "reply to citizen + @-mention deduplicated" do
      conversation =
        conversation_from_comments([
          %{id: "msg_a", by: "alice", body: "I can help", turn_id: "turn_a"}
        ])

      c = comment(id: "msg_2", by: "user", body: "hey @alice thanks", parent_id: "msg_a")

      assert CitizenReplyTrigger.targets(c, conversation, ["alice", "bob"]) ==
               MapSet.new(["alice"])
    end

    test "both reply and @-mention of different citizens returns both" do
      conversation =
        conversation_from_comments([
          %{id: "msg_a", by: "alice", body: "I can help", turn_id: "turn_a"}
        ])

      c = comment(id: "msg_2", by: "user", body: "@bob review this too", parent_id: "msg_a")

      assert CitizenReplyTrigger.targets(c, conversation, ["alice", "bob"]) ==
               MapSet.new(["alice", "bob"])
    end

    test "human author replying to citizen wakes the citizen" do
      conversation =
        conversation_from_comments([
          %{id: "msg_c", by: "bob", body: "I finished", turn_id: "turn_b"}
        ])

      c = comment(id: "msg_2", by: "user", body: "good job", parent_id: "msg_c")

      assert CitizenReplyTrigger.targets(c, conversation, ["alice", "bob"]) == MapSet.new(["bob"])
    end

    test "reply to unknown message id wakes nobody" do
      conversation = conversation_from_comments([])
      c = comment(id: "msg_2", by: "user", body: "reply", parent_id: "msg_nonexistent")

      assert CitizenReplyTrigger.targets(c, conversation, ["alice"]) == MapSet.new()
    end

    test "no parent_id and no @-mentions returns empty set" do
      conversation = conversation_from_comments([])
      c = comment(id: "msg_1", by: "user", body: "just a comment")

      assert CitizenReplyTrigger.targets(c, conversation, ["alice", "bob"]) == MapSet.new()
    end
  end

  # ---------------------------------------------------------------------------
  # Budget: auto_reply counting
  # ---------------------------------------------------------------------------

  describe "budget counting" do
    test "trigger fires when auto_reply count is under the cap" do
      history = [
        %{"event" => "comment", "by" => "alice", "body" => "1", "auto_reply" => true},
        %{"event" => "comment", "by" => "alice", "body" => "2", "auto_reply" => true}
      ]

      conversation =
        conversation_from_comments([
          %{id: "msg_alice", by: "alice", body: "do it", turn_id: "turn_a"}
        ])

      c = comment(id: "msg_2", by: "user", body: "go @alice", parent_id: "msg_alice")
      deliver_calls = collect_deliver_calls()

      CitizenReplyTrigger.maybe_trigger(
        "/tmp/root",
        ticket(),
        c,
        conversation,
        deliver_fn: deliver_calls.fun,
        citizen_auto_reply_enabled: true,
        citizen_auto_reply_budget: 6,
        citizen_slugs: ["alice"],
        history: history
      )

      assert length(deliver_calls.calls.()) >= 1
    end

    test "fan-out is capped at the remaining budget" do
      # 5 prior auto-replies, cap 6 → only 1 of two targeted citizens may fire
      history =
        Enum.map(1..5, fn i ->
          %{"event" => "comment", "by" => "alice", "body" => "msg #{i}", "auto_reply" => true}
        end)

      conversation = conversation_from_comments([])
      c = comment(id: "msg_x", by: "user", body: "go @alice @bob")
      deliver_calls = collect_deliver_calls()

      CitizenReplyTrigger.maybe_trigger(
        "/tmp/root",
        ticket(),
        c,
        conversation,
        deliver_fn: deliver_calls.fun,
        citizen_auto_reply_enabled: true,
        citizen_auto_reply_budget: 6,
        citizen_slugs: ["alice", "bob"],
        history: history
      )

      assert length(deliver_calls.calls.()) == 1
    end

    test "trigger is blocked when auto_reply count is at the cap" do
      history =
        Enum.map(1..6, fn i ->
          %{"event" => "comment", "by" => "alice", "body" => "msg #{i}", "auto_reply" => true}
        end)

      conversation =
        conversation_from_comments([
          %{id: "msg_alice", by: "alice", body: "start", turn_id: "turn_a"}
        ])

      c = comment(id: "msg_7", by: "user", body: "go @alice")
      deliver_calls = collect_deliver_calls()

      CitizenReplyTrigger.maybe_trigger(
        "/tmp/root",
        ticket(),
        c,
        conversation,
        deliver_fn: deliver_calls.fun,
        citizen_auto_reply_enabled: true,
        citizen_auto_reply_budget: 6,
        citizen_slugs: ["alice"],
        history: history
      )

      assert deliver_calls.calls.() == []
    end

    test "trigger is blocked when auto_reply count exceeds cap" do
      history =
        Enum.map(1..8, fn i ->
          %{"event" => "comment", "by" => "alice", "body" => "msg #{i}", "auto_reply" => true}
        end)

      conversation =
        conversation_from_comments([
          %{id: "msg_alice", by: "alice", body: "start", turn_id: "turn_a"}
        ])

      c = comment(id: "msg_9", by: "user", body: "@alice continue")
      deliver_calls = collect_deliver_calls()

      CitizenReplyTrigger.maybe_trigger(
        "/tmp/root",
        ticket(),
        c,
        conversation,
        deliver_fn: deliver_calls.fun,
        citizen_auto_reply_enabled: true,
        citizen_auto_reply_budget: 6,
        citizen_slugs: ["alice"],
        history: history
      )

      assert deliver_calls.calls.() == []
    end

    test "auto_reply budget uses configurable cap" do
      history =
        Enum.map(1..3, fn i ->
          %{"event" => "comment", "by" => "alice", "body" => "msg #{i}", "auto_reply" => true}
        end)

      conversation =
        conversation_from_comments([
          %{id: "msg_alice", by: "alice", body: "start", turn_id: "turn_a"}
        ])

      c = comment(id: "msg_4", by: "user", body: "@alice go")
      deliver_calls = collect_deliver_calls()

      CitizenReplyTrigger.maybe_trigger(
        "/tmp/root",
        ticket(),
        c,
        conversation,
        deliver_fn: deliver_calls.fun,
        citizen_auto_reply_enabled: true,
        citizen_auto_reply_budget: 3,
        citizen_slugs: ["alice"],
        history: history
      )

      assert deliver_calls.calls.() == []
    end
  end

  # ---------------------------------------------------------------------------
  # Gate: citizen_auto_reply_enabled defaults false
  # ---------------------------------------------------------------------------

  describe "gate" do
    test "gate off (default) — deliver_fn is never called" do
      conversation =
        conversation_from_comments([
          %{id: "msg_a", by: "alice", body: "ready", turn_id: "turn_a"}
        ])

      c = comment(id: "msg_2", by: "user", body: "@alice go", parent_id: "msg_a")
      deliver_calls = collect_deliver_calls()

      CitizenReplyTrigger.maybe_trigger(
        "/tmp/root",
        ticket(),
        c,
        conversation,
        deliver_fn: deliver_calls.fun,
        citizen_slugs: ["alice"]
        # citizen_auto_reply_enabled NOT set — defaults to false
      )

      assert deliver_calls.calls.() == []
    end

    test "gate explicitly false — deliver_fn is never called" do
      conversation =
        conversation_from_comments([
          %{id: "msg_a", by: "alice", body: "ready", turn_id: "turn_a"}
        ])

      c = comment(id: "msg_2", by: "user", body: "@alice go")
      deliver_calls = collect_deliver_calls()

      CitizenReplyTrigger.maybe_trigger(
        "/tmp/root",
        ticket(),
        c,
        conversation,
        deliver_fn: deliver_calls.fun,
        citizen_auto_reply_enabled: false,
        citizen_slugs: ["alice"]
      )

      assert deliver_calls.calls.() == []
    end

    test "gate on — deliver_fn called once per target with focus_message_id" do
      conversation =
        conversation_from_comments([
          %{id: "msg_a", by: "alice", body: "ready", turn_id: "turn_a"}
        ])

      c = comment(id: "msg_trigger", by: "user", body: "@alice go")
      deliver_calls = collect_deliver_calls()

      CitizenReplyTrigger.maybe_trigger(
        "/tmp/root",
        ticket(),
        c,
        conversation,
        deliver_fn: deliver_calls.fun,
        citizen_auto_reply_enabled: true,
        citizen_slugs: ["alice"]
      )

      calls = deliver_calls.calls.()
      assert length(calls) == 1
      {_slug, call_opts} = hd(calls)
      assert Keyword.get(call_opts, :focus_message_id) == "msg_trigger"
    end

    test "gate on — deliver_fn called once per target (two targets)" do
      conversation =
        conversation_from_comments([
          %{id: "msg_a", by: "alice", body: "ready", turn_id: "turn_a"}
        ])

      c = comment(id: "msg_trigger", by: "user", body: "@alice @bob go")
      deliver_calls = collect_deliver_calls()

      CitizenReplyTrigger.maybe_trigger(
        "/tmp/root",
        ticket(),
        c,
        conversation,
        deliver_fn: deliver_calls.fun,
        citizen_auto_reply_enabled: true,
        citizen_slugs: ["alice", "bob"]
      )

      calls = deliver_calls.calls.()
      assert length(calls) == 2
      slugs = Enum.map(calls, fn {slug, _opts} -> slug end) |> Enum.sort()
      assert slugs == ["alice", "bob"]

      for {_slug, call_opts} <- calls do
        assert Keyword.get(call_opts, :focus_message_id) == "msg_trigger"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helper: collect_deliver_calls builds a stub deliver_fn + calls inspector
  # ---------------------------------------------------------------------------

  defp collect_deliver_calls do
    parent = self()
    ref = make_ref()

    fun = fn slug, _root, _ticket, _conversation, opts ->
      send(parent, {ref, slug, opts})
      :ok
    end

    calls_fn = fn ->
      receive_all(ref, [])
    end

    %{fun: fun, calls: calls_fn}
  end

  defp receive_all(ref, acc) do
    receive do
      {^ref, slug, opts} -> receive_all(ref, acc ++ [{slug, opts}])
    after
      0 -> acc
    end
  end
end
