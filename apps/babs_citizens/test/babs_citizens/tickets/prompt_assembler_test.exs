defmodule Babs.Citizens.Tickets.PromptAssemblerTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.CitizenRecord
  alias Babs.Citizens.Tickets.PromptAssembler
  alias Babs.Citizens.Tickets.Ticket

  test "builds a compact follow-up prompt for resumed provider sessions" do
    ticket = %Ticket{
      id: "T-2026-05-08-001",
      type: "assignment",
      state: "in_progress",
      assigner: "user",
      assignees: ["dylan"],
      assignee_role: nil,
      inspector: "user",
      priority: "normal",
      parent_ticket: nil,
      created_at: "2026-05-08T10:00:00Z",
      updated_at: "2026-05-08T10:01:00Z",
      metadata: %{},
      title: "Do not resend this title",
      body: "Do not resend this body from /Users/operator/private.",
      path: nil,
      warnings: []
    }

    prompt =
      PromptAssembler.compact_follow_up_prompt(ticket,
        latest_message: "Only send this message with token: secret-value."
      )

    assert prompt =~ "Ticket: T-2026-05-08-001"
    assert prompt =~ "Latest operator message:\nOnly send this message"
    assert prompt =~ "BABS_REPLY T-2026-05-08-001:"

    refute prompt =~ "Do not resend this title"
    refute prompt =~ "Do not resend this body"
    refute prompt =~ "/Users/operator"
    refute prompt =~ "secret-value"
  end

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
      body:
        "Read /home/frank/private, /root/.config, /workspace/babs/tmp.log, and /tmp/scratch with api-key: my long secret value",
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
    refute prompt =~ "/workspace/babs"
    refute prompt =~ "/tmp/scratch"
    refute prompt =~ "my long secret value"
    refute prompt =~ "another long secret value"
    assert prompt =~ "[local-path]"
    assert prompt =~ "[secret]"
  end

  test "builds redacted inspection prompts from visible chat only" do
    raw_credential = "api_" <> "key=super-value"

    ticket = %Ticket{
      id: "T-2026-05-08-010",
      type: "assignment",
      state: "pending_approval",
      assigner: "user",
      assignees: ["clare"],
      assignee_role: nil,
      inspector: "user",
      priority: "high",
      parent_ticket: nil,
      created_at: "2026-05-08T10:00:00Z",
      updated_at: "2026-05-08T10:02:00Z",
      metadata: %{"inspection" => %{"mode" => "auto"}},
      title: "Inspect safely",
      body: "Check /home/operator/private on 10.1.2.3 via lab-host.local #{raw_credential}",
      path: nil,
      warnings: []
    }

    history = [
      %{
        "ts" => "2026-05-08T10:01:00Z",
        "event" => "comment",
        "by" => "clare",
        "body" => "Implemented the requested change.",
        "message_id" => "msg_1"
      },
      %{
        "ts" => "2026-05-08T10:01:30Z",
        "event" => "inspection_requested",
        "by" => "system",
        "ticket_id" => "T-2026-05-08-010",
        "inspection_id" => "insp_20260508100130_1",
        "inspectors" => ["dylan"],
        "policy" => %{}
      }
    ]

    prompt =
      PromptAssembler.inspection_prompt(ticket, history, "dylan",
        inspection_id: "insp_20260508100130_1",
        max_messages: 5
      )

    assert prompt =~ "You are dylan, a Babs Inspector Citizen."
    assert prompt =~ "Ticket: T-2026-05-08-010"
    assert prompt =~ "State: pending_approval"
    assert prompt =~ "Implemented the requested change."
    assert prompt =~ ~s("decision": "approve")
    assert prompt =~ ~s("needs_changes")

    refute prompt =~ "inspection_requested"
    refute prompt =~ "/home/operator"
    refute prompt =~ "10.1.2.3"
    refute prompt =~ "lab-host.local"
    refute prompt =~ "super-value"
  end

  test "builds a sanitized Mayor proposal prompt with opaque rule refs" do
    ticket = %Ticket{
      id: "T-2026-05-08-016",
      type: "mission",
      state: "open",
      assigner: "user",
      assignees: [],
      assignee_role: nil,
      inspector: "user",
      priority: "high",
      parent_ticket: nil,
      created_at: "2026-05-08T10:00:00Z",
      updated_at: "2026-05-08T10:02:00Z",
      metadata: %{},
      title: "Mayor prompt",
      body: "Use /Users/operator/private and 10.1.2.3 only after redaction.",
      path: nil,
      warnings: []
    }

    policy = %{
      "rules_refs" => ["BAB-1503", "COR-1616"],
      "max_children" => 5,
      "allowed_roles" => ["developer", "inspector"]
    }

    mayor = %{
      slug: "flora",
      role: "mayor",
      citizen: citizen("flora", "Flora", ["mayor"], "Mayor with token secret-value")
    }

    citizens = [
      mayor.citizen,
      citizen("clare", "Clare", ["developer"], "Developer on lab-host.local")
    ]

    history = [
      %{
        "ts" => "2026-05-08T10:01:00Z",
        "event" => "comment",
        "by" => "user",
        "body" => "Split this safely."
      }
    ]

    prompt =
      PromptAssembler.mayor_proposal_prompt(ticket, history, mayor, policy, citizens,
        max_messages: 5
      )

    assert prompt =~ "You are flora, a Babs Mayor Citizen."
    assert prompt =~ "Ticket: T-2026-05-08-016"
    assert prompt =~ "Rules refs:"
    assert prompt =~ "- BAB-1503"
    assert prompt =~ "- COR-1616"
    assert prompt =~ "You may run `af read` or `af plan`"
    assert prompt =~ "Allowed assignee role labels:"
    assert prompt =~ "- developer"
    assert prompt =~ "- inspector"
    assert prompt =~ "Eligible Citizens:"
    assert prompt =~ "clare"
    assert prompt =~ ~s("proposal_id")
    assert prompt =~ ~s("children")

    refute prompt =~ "/Users/operator"
    refute prompt =~ "10.1.2.3"
    refute prompt =~ "lab-host.local"
    refute prompt =~ "secret-value"
    refute prompt =~ "SOP body"
  end

  defp citizen(slug, display_name, roles, description) do
    %CitizenRecord{
      id: "BAB-CIT-#{slug}",
      slug: slug,
      display_name: display_name,
      description: description,
      cwd: "/Users/operator/#{slug}",
      cli: "claude",
      cli_args: [],
      launch_profile: "safe_interactive",
      ticket_backend: "hardline",
      env: %{"API_TOKEN" => "must-not-leak"},
      status: "running",
      metadata: %{},
      role: List.first(roles),
      roles: Enum.map(roles, &%{"name" => &1, "skills" => []}),
      is_mayor: slug == "flora"
    }
  end
end
