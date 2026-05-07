defmodule Babs.Citizens.Tickets.PromptAssemblerTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.PromptAssembler
  alias Babs.Citizens.Tickets.Ticket

  test "builds a sanitized follow-up prompt from ticket metadata and recent chat" do
    ticket = %Ticket{
      id: "T-2026-05-07-001",
      type: "assignment",
      state: "in_progress",
      assigner: "user",
      assignees: ["clare"],
      assignee_role: nil,
      inspector: "user",
      priority: "high",
      parent_ticket: nil,
      created_at: "2026-05-07T10:00:00Z",
      updated_at: "2026-05-07T10:01:00Z",
      metadata: %{},
      title: "Multi-turn",
      body: "Work from /Users/operator/private with token secret-value and host 192.168.12.34",
      path: "/Users/operator/Projects/babs-runtime/T-2026-05-07-001.md",
      warnings: []
    }

    history =
      for index <- 1..14 do
        %{
          "ts" => "2026-05-07T10:00:#{String.pad_leading(to_string(index), 2, "0")}Z",
          "event" => "comment",
          "by" => if(rem(index, 2) == 0, do: "clare", else: "user"),
          "body" => "message #{index}",
          "turn_id" => "turn_#{index}",
          "message_id" => "msg_#{index}"
        }
      end

    prompt =
      PromptAssembler.follow_up_prompt(ticket, history,
        citizen_slug: "clare",
        latest_message: "Please continue with 10.0.0.5 hidden.",
        max_messages: 12
      )

    assert prompt =~ "Ticket: T-2026-05-07-001"
    assert prompt =~ "Title: Multi-turn"
    assert prompt =~ "Citizen: clare"
    assert prompt =~ "message 14"
    refute prompt =~ "- 2026-05-07T10:00:01Z user: message 1\n"
    assert prompt =~ "BABS_REPLY T-2026-05-07-001:"

    refute prompt =~ "/Users/operator"
    refute prompt =~ "192.168.12.34"
    refute prompt =~ "10.0.0.5"
    refute prompt =~ "secret-value"
    refute prompt =~ ticket.path
  end

  test "does not duplicate the latest operator message already present in history" do
    ticket = %Ticket{
      id: "T-2026-05-07-002",
      type: "assignment",
      state: "in_progress",
      assigner: "user",
      assignees: ["dylan"],
      assignee_role: nil,
      inspector: "user",
      priority: "normal",
      parent_ticket: nil,
      created_at: "2026-05-07T10:00:00Z",
      updated_at: "2026-05-07T10:01:00Z",
      metadata: %{},
      title: "Follow-up",
      body: "Continue in the same Ticket.",
      path: nil,
      warnings: []
    }

    history = [
      %{
        "ts" => "2026-05-07T10:01:00Z",
        "event" => "comment",
        "by" => "user",
        "body" => "Please add one more check.",
        "turn_id" => "turn_20260507100100_abc123def0",
        "message_id" => "msg_20260507100100_abc123def0"
      }
    ]

    prompt =
      PromptAssembler.follow_up_prompt(ticket, history,
        citizen_slug: "dylan",
        latest_message: "Please add one more check."
      )

    assert prompt =~ "Latest operator message:\nPlease add one more check."
    refute prompt =~ "- 2026-05-07T10:01:00Z user: Please add one more check."
  end

  test "does not duplicate latest operator message when a citizen reply follows it" do
    ticket = %Ticket{
      id: "T-2026-05-07-003",
      type: "assignment",
      state: "in_progress",
      assigner: "user",
      assignees: ["clare"],
      assignee_role: nil,
      inspector: "user",
      priority: "normal",
      parent_ticket: nil,
      created_at: "2026-05-07T10:00:00Z",
      updated_at: "2026-05-07T10:02:00Z",
      metadata: %{},
      title: "Follow-up after reply",
      body: "Keep context concise.",
      path: nil,
      warnings: []
    }

    history = [
      %{
        "ts" => "2026-05-07T10:01:00Z",
        "event" => "comment",
        "by" => "user",
        "body" => "Please add one more check.",
        "turn_id" => "turn_20260507100100_abc123def0",
        "message_id" => "msg_20260507100100_abc123def0"
      },
      %{
        "ts" => "2026-05-07T10:01:30Z",
        "event" => "comment",
        "by" => "clare",
        "body" => "I added the first check.",
        "turn_id" => "turn_20260507100100_abc123def0",
        "message_id" => "msg_20260507100130_abc123def0"
      }
    ]

    prompt =
      PromptAssembler.follow_up_prompt(ticket, history,
        citizen_slug: "clare",
        latest_message: "Please add one more check."
      )

    assert prompt =~ "Latest operator message:\nPlease add one more check."
    assert prompt =~ "- 2026-05-07T10:01:30Z clare: I added the first check."
    refute prompt =~ "- 2026-05-07T10:01:00Z user: Please add one more check."
  end

  test "redacts Linux local paths and space-containing secret values" do
    ticket = %Ticket{
      id: "T-2026-05-07-004",
      type: "assignment",
      state: "in_progress",
      assigner: "user",
      assignees: ["elena"],
      assignee_role: nil,
      inspector: "user",
      priority: "normal",
      parent_ticket: nil,
      created_at: "2026-05-07T10:00:00Z",
      updated_at: "2026-05-07T10:02:00Z",
      metadata: %{},
      title: "Redaction",
      body: "Read /home/frank/private and /root/.config with api-key: my long secret value",
      path: nil,
      warnings: []
    }

    prompt =
      PromptAssembler.follow_up_prompt(ticket, [],
        citizen_slug: "elena",
        latest_message: "password: another long secret value"
      )

    refute prompt =~ "/home/frank"
    refute prompt =~ "/root/.config"
    refute prompt =~ "my long secret value"
    refute prompt =~ "another long secret value"
    assert prompt =~ "[local-path]"
    assert prompt =~ "[secret]"
  end
end
