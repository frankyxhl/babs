defmodule Babs.Citizens.Tickets.CitizenReplyLoopTest do
  @moduledoc """
  End-to-end regression for the Citizen-to-Citizen auto-reply loop.

  Drives the real `CitizenReplyTrigger.maybe_trigger/5` one hop at a time with a
  deterministic, no-AI delivery function (posts a canned reply that @mentions the
  partner), and asserts the integrated result: the chain threads into a nested
  forum tree, the per-thread budget caps it, and `path_to/2` yields the
  token-efficient ancestor lineage.

  The delivery is driven sequentially from the test (not via the writer hook):
  posting a reply re-enters the per-ticket Writer GenServer, so in production the
  reply is posted asynchronously by reply capture — here we serialise it to keep
  the assertions deterministic.
  """
  use ExUnit.Case, async: false

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.CitizenReplyTrigger
  alias Babs.Citizens.Tickets.Conversation
  alias Babs.Citizens.Tickets.ConversationTree

  setup do
    {:ok, _apps} = Application.ensure_all_started(:babs_citizens)

    root =
      Path.join(System.tmp_dir!(), "babs-a2a-loop-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "A2A auto-reply chain threads into a tree and is capped by the budget", %{root: root} do
    slugs = ["clare", "dylan"]
    budget = 3
    now = "2026-06-20T00:00:00Z"

    {:ok, ticket} =
      Api.create_ticket(%{title: "A2A loop", body: "demo"},
        tickets_root: root,
        date: ~D[2026-06-20],
        now: now
      )

    id = ticket.id

    {:ok, _} =
      Api.comment_ticket(
        id,
        %{
          "body" => "@clare what's first?",
          "by" => "user",
          "message_id" => "msg_kickoff",
          "turn_id" => "t_kickoff"
        },
        tickets_root: root,
        now: now
      )

    deliver = fn slug, _root, tk, _conv, opts ->
      partner = Enum.find(opts[:citizen_slugs], &(&1 != slug))
      body = "[#{slug}] ok." <> if(partner, do: " @#{partner}?", else: "")

      {:ok, _} =
        Api.comment_ticket(
          tk.id,
          %{
            "body" => body,
            "by" => slug,
            "auto_reply" => true,
            "parent_comment_id" => opts[:focus_message_id],
            "turn_id" => "t_#{System.unique_integer([:positive])}"
          },
          tickets_root: root,
          notify_assignees: false
        )

      :ok
    end

    # Process each new comment's trigger sequentially until the chain stops.
    Enum.reduce_while(1..30, MapSet.new(), fn _i, processed ->
      {:ok, %{history: history}} = Api.show_ticket(id, tickets_root: root)
      conv = Conversation.from_history(history)

      new =
        history
        |> Enum.filter(&(&1["event"] == "comment"))
        |> Enum.reject(&MapSet.member?(processed, &1["message_id"]))

      if new == [] do
        {:halt, processed}
      else
        Enum.each(new, fn c ->
          CitizenReplyTrigger.maybe_trigger(root, ticket, c, conv,
            citizen_auto_reply_enabled: true,
            citizen_auto_reply_budget: budget,
            citizen_slugs: slugs,
            history: history,
            deliver_fn: deliver
          )
        end)

        {:cont, MapSet.union(processed, MapSet.new(Enum.map(new, & &1["message_id"])))}
      end
    end)

    {:ok, %{history: history}} = Api.show_ticket(id, tickets_root: root)
    comments = Enum.filter(history, &(&1["event"] == "comment"))
    auto_replies = Enum.filter(comments, &(&1["auto_reply"] == true))

    # the per-thread budget caps the loop
    assert length(auto_replies) == budget

    # the chain alternates between the two citizens
    assert Enum.map(auto_replies, & &1["by"]) == ["clare", "dylan", "clare"]

    # replies thread into a deep tree: user(0) -> clare(1) -> dylan(2) -> clare(3)
    conv = Conversation.from_history(history)
    tree = ConversationTree.build(conv)
    assert Enum.max(depths(tree)) == 3
    assert [%{comment: %{author: "user"}}] = tree

    # path_to yields the ancestor lineage, not the whole tree
    last = List.last(comments)
    lineage = conv |> ConversationTree.path_to(last["message_id"]) |> Enum.map(& &1.author)
    assert lineage == ["user", "clare", "dylan", "clare"]
  end

  defp depths(nodes) do
    Enum.flat_map(nodes, fn n -> [n.depth | depths(n.children)] end)
  end
end
