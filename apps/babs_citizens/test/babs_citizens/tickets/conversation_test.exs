defmodule Babs.Citizens.Tickets.ConversationTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.Conversation

  test "reduces append-order history into visible messages and per-attempt status" do
    history = [
      comment("2026-05-07T10:00:00Z", "msg_a", "turn_a", "user", "First turn"),
      %{
        "ts" => "2026-05-07T10:00:00Z",
        "event" => "turn_created",
        "by" => "user",
        "ticket_id" => "T-1",
        "turn_id" => "turn_a",
        "prompt_message_id" => "msg_a"
      },
      attempted("turn_a", "attempt_a", "clare", "queued"),
      delivered("turn_a", "attempt_a", "clare"),
      comment("2026-05-07T10:00:00Z", "msg_b", "turn_b", "user", "Second turn"),
      attempted("turn_b", "attempt_b", "clare", "queued"),
      comment("2026-05-07T10:00:01Z", "msg_c", "turn_a", "clare", "Reply to first"),
      captured("turn_a", "attempt_a", "clare", "msg_c"),
      %{
        "ts" => "2026-05-07T10:00:02Z",
        "event" => "comment",
        "by" => "dylan",
        "body" => "Legacy reply"
      }
    ]

    conversation = Conversation.from_history(history)

    assert Enum.map(conversation.messages, & &1.body) == [
             "First turn",
             "Second turn",
             "Reply to first",
             "Legacy reply"
           ]

    assert [%{legacy?: true, author: "dylan"}] =
             Enum.filter(conversation.messages, & &1.legacy?)

    assert %{status: "captured", citizen_slug: "clare", message_id: "msg_c"} =
             Conversation.attempt(conversation, "turn_a", "clare", "attempt_a")

    assert %{status: "queued"} =
             Conversation.attempt(conversation, "turn_b", "clare", "attempt_b")
  end

  test "tracks retry attempts without losing the parent turn" do
    history = [
      comment("2026-05-07T10:00:00Z", "msg_a", "turn_a", "user", "Please try"),
      attempted("turn_a", "attempt_a", "clare", "queued"),
      failed("turn_a", "attempt_a", "clare", "pane closed"),
      %{
        "ts" => "2026-05-07T10:00:03Z",
        "event" => "turn_delivery_attempted",
        "by" => "system",
        "ticket_id" => "T-1",
        "turn_id" => "turn_a",
        "attempt_id" => "attempt_b",
        "parent_attempt_id" => "attempt_a",
        "to" => "clare",
        "backend" => "hardline",
        "status" => "queued"
      }
    ]

    conversation = Conversation.from_history(history)

    assert %{status: "failed"} =
             Conversation.attempt(conversation, "turn_a", "clare", "attempt_a")

    assert %{status: "queued", parent_attempt_id: "attempt_a"} =
             Conversation.attempt(conversation, "turn_a", "clare", "attempt_b")
  end

  test "marks a direct CLI attempt running after execution starts" do
    history = [
      attempted("turn_a", "attempt_a", "dylan", "queued", "direct_cli"),
      %{
        "ts" => "2026-05-07T10:00:01Z",
        "event" => "turn_execution_started",
        "by" => "system",
        "ticket_id" => "T-1",
        "turn_id" => "turn_a",
        "attempt_id" => "attempt_a",
        "to" => "dylan"
      }
    ]

    conversation = Conversation.from_history(history)

    assert %{status: "running", backend: "direct_cli", started_at: "2026-05-07T10:00:01Z"} =
             Conversation.attempt(conversation, "turn_a", "dylan", "attempt_a")
  end

  defp comment(ts, message_id, turn_id, by, body) do
    %{
      "ts" => ts,
      "event" => "comment",
      "by" => by,
      "ticket_id" => "T-1",
      "message_id" => message_id,
      "turn_id" => turn_id,
      "body" => body
    }
  end

  defp attempted(turn_id, attempt_id, slug, status) do
    attempted(turn_id, attempt_id, slug, status, "hardline")
  end

  defp attempted(turn_id, attempt_id, slug, status, backend) do
    %{
      "ts" => "2026-05-07T10:00:00Z",
      "event" => "turn_delivery_attempted",
      "by" => "system",
      "ticket_id" => "T-1",
      "turn_id" => turn_id,
      "attempt_id" => attempt_id,
      "to" => slug,
      "backend" => backend,
      "status" => status
    }
  end

  defp delivered(turn_id, attempt_id, slug) do
    %{
      "ts" => "2026-05-07T10:00:00Z",
      "event" => "turn_delivered",
      "by" => "system",
      "ticket_id" => "T-1",
      "turn_id" => turn_id,
      "attempt_id" => attempt_id,
      "to" => slug,
      "backend" => "hardline"
    }
  end

  defp failed(turn_id, attempt_id, slug, reason) do
    %{
      "ts" => "2026-05-07T10:00:02Z",
      "event" => "turn_delivery_failed",
      "by" => "system",
      "ticket_id" => "T-1",
      "turn_id" => turn_id,
      "attempt_id" => attempt_id,
      "to" => slug,
      "backend" => "hardline",
      "error" => reason
    }
  end

  defp captured(turn_id, attempt_id, slug, message_id) do
    %{
      "ts" => "2026-05-07T10:00:01Z",
      "event" => "turn_reply_captured",
      "by" => "system",
      "ticket_id" => "T-1",
      "turn_id" => turn_id,
      "attempt_id" => attempt_id,
      "by_citizen" => slug,
      "message_id" => message_id
    }
  end
end
