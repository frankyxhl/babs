defmodule Babs.Citizens.Tickets.ApiWriterStoreTest do
  use ExUnit.Case, async: false

  alias Babs.Citizens.CitizenConfig
  alias Babs.Citizens.DirectCli.Adapters.Fake
  alias Babs.Citizens.ExecutionLock
  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.InspectionEvents
  alias Babs.Citizens.Tickets.MayorProposalReview
  alias Babs.Citizens.Tickets.TicketMarkdown
  alias Babs.Citizens.Tickets.WriterSupervisor
  alias Babs.Knowledge

  setup do
    original = Application.get_env(:babs_citizens, :ai_reply_capture_enabled)
    Application.put_env(:babs_citizens, :ai_reply_capture_enabled, false)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:babs_citizens, :ai_reply_capture_enabled)
        value -> Application.put_env(:babs_citizens, :ai_reply_capture_enabled, value)
      end
    end)

    :ok
  end

  test "creates lists and shows tickets without Phoenix" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Storage core", body: "Create the ticket storage layer."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    assert ticket.id == "T-2026-05-06-001"
    assert File.exists?(Path.join(root, "#{ticket.id}.md"))
    assert File.exists?(Path.join(root, "#{ticket.id}.history.jsonl"))

    assert {:ok, %{tickets: [listed], invalid: []}} = Api.list_tickets(tickets_root: root)
    assert listed.id == ticket.id

    assert {:ok, %{ticket: shown, history: [%{"event" => "created"}]}} =
             Api.show_ticket(ticket.id, tickets_root: root)

    assert shown.title == "Storage core"
  end

  test "concurrent creates claim unique ids and leave valid files" do
    root = tmp_root()

    results =
      1..10
      |> Task.async_stream(
        fn index ->
          Api.create_ticket(%{title: "Ticket #{index}", body: "Body #{index}"},
            tickets_root: root,
            date: ~D[2026-05-06],
            now: "2026-05-06T00:00:00Z"
          )
        end,
        max_concurrency: 10,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, _ticket}, &1))
    ids = Enum.map(results, fn {:ok, ticket} -> ticket.id end)

    assert Enum.sort(ids) ==
             Enum.map(1..10, &"T-2026-05-06-#{String.pad_leading(to_string(&1), 3, "0")}")

    assert {:ok, %{tickets: tickets, invalid: []}} = Api.list_tickets(tickets_root: root)
    assert length(tickets) == 10
  end

  test "storage-only comments append history and update updated_at" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Commentable", body: "Initial body."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    assert {:ok, %{ticket: updated, delivery: {:comment_notified, []}}} =
             Api.comment_ticket(ticket.id, %{body: "Working on it.", by: "clare"},
               tickets_root: root,
               now: "2026-05-06T00:01:00Z"
             )

    assert updated.updated_at == "2026-05-06T00:01:00Z"

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)
    assert Enum.map(history, & &1["event"]) == ["created", "comment"]
    assert List.last(history)["body"] == "Working on it."
    assert List.last(history)["ticket_id"] == ticket.id
  end

  test "append_ticket_events stores inspection events through the writer path" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Inspection event", body: "Record inspection request."},
               tickets_root: root,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:00:00Z"
             )

    policy = %{
      "mode" => "auto",
      "strategy" => "single",
      "roles" => ["inspector"],
      "citizens" => [],
      "quorum" => "all_pass",
      "max_inspectors" => 3,
      "allow_self_inspection" => false
    }

    assert {:ok, event} =
             InspectionEvents.requested(ticket.id, "insp_20260508000000_42", policy, ["clare"],
               now: "2026-05-08T00:01:00Z"
             )

    assert :ok = Api.append_ticket_events(ticket.id, [event], tickets_root: root)

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)
    assert Enum.map(history, & &1["event"]) == ["created", "inspection_requested"]
    assert List.last(history)["inspection_id"] == "insp_20260508000000_42"
  end

  test "mayor proposal review actions append history through the writer path" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 type: "mission",
                 title: "Mission root",
                 body: "Split this mission.",
                 metadata: mayor_metadata()
               },
               tickets_root: root,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:00:00Z"
             )

    proposal = proposal(ticket.id, "prop_review", ["Build backend", "Build frontend"])

    assert :ok =
             Api.append_ticket_events(ticket.id, [proposal_received(ticket.id, proposal)],
               tickets_root: root
             )

    first_revision = proposal_revision(root, ticket.id)

    assert {:ok, %{event: revised}} =
             Api.revise_mayor_proposal_child(
               ticket.id,
               "prop_review",
               0,
               %{title: "Build API", inspector: "auto"},
               tickets_root: root,
               proposal_revision: first_revision,
               now: "2026-05-08T00:02:00Z"
             )

    assert revised["event"] == "mayor_proposal_revised"
    assert revised["proposal"]["children"] |> hd() |> Map.fetch!("title") == "Build API"

    second_revision = proposal_revision(root, ticket.id)

    assert {:ok, %{event: removed}} =
             Api.remove_mayor_proposal_child(ticket.id, "prop_review", 1,
               tickets_root: root,
               proposal_revision: second_revision,
               now: "2026-05-08T00:03:00Z"
             )

    assert removed["action"] == "remove_child"
    assert length(removed["proposal"]["children"]) == 1

    third_revision = proposal_revision(root, ticket.id)

    assert {:ok, %{event: approved}} =
             Api.approve_mayor_proposal(ticket.id, "prop_review",
               tickets_root: root,
               proposal_revision: third_revision,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:04:00Z"
             )

    assert approved["event"] == "mayor_proposal_approved"

    assert {:error, {:mayor_proposal_review, {:already_decided, :approved}}} =
             Api.reject_mayor_proposal(ticket.id, "prop_review", "Too broad.",
               tickets_root: root,
               now: "2026-05-08T00:05:00Z"
             )

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

    assert Enum.map(history, & &1["event"]) == [
             "created",
             "mayor_proposal_received",
             "mayor_proposal_revised",
             "mayor_proposal_revised",
             "mayor_children_created",
             "mayor_proposal_approved"
           ]

    assert root
           |> Path.join("T-2026-05-08-*.md")
           |> Path.wildcard()
           |> length() == 2
  end

  test "mayor proposal approval creates child tickets and is idempotent" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 type: "mission",
                 title: "Mission root",
                 body: "Split this mission.",
                 metadata: mayor_metadata()
               },
               tickets_root: root,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:00:00Z"
             )

    proposal =
      proposal(ticket.id, "prop_children", ["Build backend", "Build frontend"])
      |> put_in(["children", Access.at(0), "inspector"], "auto")
      |> put_in(["children", Access.at(0), "metadata"], %{
        "inspection" => %{"mode" => "auto", "roles" => ["inspector"]}
      })

    assert :ok =
             Api.append_ticket_events(ticket.id, [proposal_received(ticket.id, proposal)],
               tickets_root: root
             )

    revision = proposal_revision(root, ticket.id)

    assert {:ok, %{event: approved, children_created: children_created}} =
             Api.approve_mayor_proposal(ticket.id, "prop_children",
               tickets_root: root,
               proposal_revision: revision,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:02:00Z"
             )

    assert approved["event"] == "mayor_proposal_approved"
    assert children_created["event"] == "mayor_children_created"
    assert children_created["proposal_id"] == "prop_children"
    assert [first_child, second_child] = children_created["children"]
    assert first_child["child_index"] == 0
    assert first_child["title"] == "Build backend"
    assert first_child["priority"] == "normal"
    assert first_child["inspector"] == "auto"
    assert first_child["routing"]["status"] == "failed"
    assert first_child["routing"]["reason"] == "No eligible Citizen found for role developer"
    assert second_child["routing"]["status"] == "failed"
    assert second_child["routing"]["reason"] == "No eligible Citizen found for role developer"

    assert {:ok, %{ticket: first_ticket}} =
             Api.show_ticket(first_child["ticket_id"], tickets_root: root)

    assert first_ticket.parent_ticket == ticket.id
    assert first_ticket.assigner == "mayor:flora"
    assert first_ticket.title == "Build backend"
    assert first_ticket.body == "Complete Build backend."
    assert first_ticket.assignee_role == "developer"
    assert first_ticket.inspector == "auto"
    assert first_ticket.metadata["inspection"]["mode"] == "auto"

    assert {:ok,
            %{
              event: ^approved,
              children_created: ^children_created,
              already_materialized?: true
            }} =
             Api.approve_mayor_proposal(ticket.id, "prop_children",
               tickets_root: root,
               proposal_revision: revision,
               now: "2026-05-08T00:03:00Z"
             )

    assert {:error,
            {:mayor_proposal_review, {:stale_proposal_revision, _current_revision, "old"}}} =
             Api.approve_mayor_proposal(ticket.id, "prop_children",
               tickets_root: root,
               proposal_revision: "old",
               now: "2026-05-08T00:04:00Z"
             )

    assert root
           |> Path.join("T-2026-05-08-*.md")
           |> Path.wildcard()
           |> length() == 3

    assert {:ok, %{history: root_history}} = Api.show_ticket(ticket.id, tickets_root: root)

    assert Enum.map(root_history, & &1["event"]) == [
             "created",
             "mayor_proposal_received",
             "mayor_children_created",
             "mayor_proposal_approved"
           ]
  end

  test "mayor proposal approval ignores unrelated malformed ticket files during recovery scan" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 type: "mission",
                 title: "Mission root",
                 body: "Split this mission.",
                 metadata: mayor_metadata()
               },
               tickets_root: root,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:00:00Z"
             )

    invalid_path = Path.join(root, "T-2026-05-07-999.md")
    File.write!(invalid_path, "not ticket markdown")

    proposal = proposal(ticket.id, "prop_invalid_unrelated", ["Build backend"])

    assert :ok =
             Api.append_ticket_events(ticket.id, [proposal_received(ticket.id, proposal)],
               tickets_root: root
             )

    revision = proposal_revision(root, ticket.id)

    assert {:ok, %{children_created: children_created}} =
             Api.approve_mayor_proposal(ticket.id, "prop_invalid_unrelated",
               tickets_root: root,
               proposal_revision: revision,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:02:00Z"
             )

    assert [child] = children_created["children"]

    assert {:ok, %{ticket: child_ticket}} =
             Api.show_ticket(child["ticket_id"], tickets_root: root)

    assert child_ticket.parent_ticket == ticket.id

    assert child_ticket.metadata["mayor_materialization"]["proposal_id"] ==
             "prop_invalid_unrelated"

    assert {:ok, %{invalid: [%{path: ^invalid_path}]}} = Api.list_tickets(tickets_root: root)
  end

  test "mayor proposal approval validates root marker size before creating child tickets" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 type: "mission",
                 title: "Mission root",
                 body: "Split this mission.",
                 metadata: mayor_metadata()
               },
               tickets_root: root,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:00:00Z"
             )

    oversized_title = String.duplicate("A", 17_000)
    proposal = proposal(ticket.id, "prop_oversized_marker", [oversized_title])
    ticket_id = ticket.id

    TicketMarkdown.history_path(root, ticket.id)
    |> File.write!(Jason.encode!(proposal_received(ticket.id, proposal)) <> "\n", [:append])

    assert {:error, {:history_event_too_large, ^ticket_id}} =
             Api.approve_mayor_proposal(ticket.id, "prop_oversized_marker",
               tickets_root: root,
               now: "2026-05-08T00:02:00Z"
             )

    assert root
           |> Path.join("T-2026-05-08-*.md")
           |> Path.wildcard()
           |> length() == 1
  end

  test "mayor proposal approval recovers existing children after root marker append failure" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 type: "mission",
                 title: "Mission root",
                 body: "Split this mission.",
                 metadata: mayor_metadata()
               },
               tickets_root: root,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:00:00Z"
             )

    proposal = proposal(ticket.id, "prop_recover_marker", ["Build backend", "Build frontend"])

    assert :ok =
             Api.append_ticket_events(ticket.id, [proposal_received(ticket.id, proposal)],
               tickets_root: root
             )

    history_path = TicketMarkdown.history_path(root, ticket.id)
    File.chmod!(history_path, 0o444)

    try do
      assert {:error, {:redacted_io_error, {:append_history, _reason}}} =
               Api.approve_mayor_proposal(ticket.id, "prop_recover_marker",
                 tickets_root: root,
                 date: ~D[2026-05-08],
                 now: "2026-05-08T00:02:00Z"
               )
    after
      File.chmod!(history_path, 0o644)
    end

    assert root
           |> Path.join("T-2026-05-08-*.md")
           |> Path.wildcard()
           |> length() == 3

    revision = proposal_revision(root, ticket.id)

    assert {:error, {:mayor_proposal_review, {:already_materialized, :children_started}}} =
             Api.revise_mayor_proposal_child(
               ticket.id,
               "prop_recover_marker",
               0,
               %{
                 title: "Changed"
               },
               tickets_root: root,
               proposal_revision: revision
             )

    assert {:error, {:mayor_proposal_review, {:already_materialized, :children_started}}} =
             Api.remove_mayor_proposal_child(ticket.id, "prop_recover_marker", 1,
               tickets_root: root,
               proposal_revision: revision
             )

    assert {:error, {:mayor_proposal_review, {:already_materialized, :children_started}}} =
             Api.reject_mayor_proposal(ticket.id, "prop_recover_marker", "Stop.",
               tickets_root: root,
               proposal_revision: revision
             )

    child_ids =
      root
      |> Path.join("T-2026-05-08-*.md")
      |> Path.wildcard()
      |> Enum.map(&Path.basename(&1, ".md"))
      |> Enum.reject(&(&1 == ticket.id))
      |> Enum.sort()

    [first_child_id | _rest] = child_ids
    File.rm!(TicketMarkdown.history_path(root, first_child_id))

    assert {:ok, %{event: approved, children_created: children_created}} =
             Api.approve_mayor_proposal(ticket.id, "prop_recover_marker",
               tickets_root: root,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:03:00Z"
             )

    assert approved["event"] == "mayor_proposal_approved"
    assert [first_child, second_child] = children_created["children"]
    assert first_child["title"] == "Build backend"
    assert second_child["title"] == "Build frontend"

    assert root
           |> Path.join("T-2026-05-08-*.md")
           |> Path.wildcard()
           |> length() == 3

    assert {:ok, %{history: child_history}} = Api.show_ticket(first_child_id, tickets_root: root)
    assert Enum.any?(child_history, &(&1["event"] == "created"))

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

    assert Enum.map(history, & &1["event"]) == [
             "created",
             "mayor_proposal_received",
             "mayor_children_created",
             "mayor_proposal_approved"
           ]
  end

  test "mayor proposal retry preserves failed child route after assignment injection failure" do
    root = tmp_root()

    with_role_catalog(fn config_root ->
      Babs.Citizens.RepoCase.write_citizen_toml!(config_root, "clare")

      Babs.Citizens.RepoCase.insert_citizen!(%{
        slug: "clare",
        display_name: "Clare",
        roles: ["developer"]
      })

      assert {:ok, ticket} =
               Api.create_ticket(
                 %{
                   type: "mission",
                   title: "Mission root",
                   body: "Split this mission.",
                   metadata: mayor_metadata()
                 },
                 tickets_root: root,
                 date: ~D[2026-05-08],
                 now: "2026-05-08T00:00:00Z"
               )

      proposal = proposal(ticket.id, "prop_recover_failed_route", ["Build backend"])

      assert :ok =
               Api.append_ticket_events(ticket.id, [proposal_received(ticket.id, proposal)],
                 tickets_root: root
               )

      history_path = TicketMarkdown.history_path(root, ticket.id)
      File.chmod!(history_path, 0o444)

      try do
        assert {:error, {:redacted_io_error, {:append_history, _reason}}} =
                 Api.approve_mayor_proposal(ticket.id, "prop_recover_failed_route",
                   tickets_root: root,
                   date: ~D[2026-05-08],
                   now: "2026-05-08T00:02:00Z",
                   citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
                   pane_lookup: fn "clare" -> {:ok, self()} end,
                   pane_injector: fn "clare", _prompt -> {:error, :offline} end
                 )
      after
        File.chmod!(history_path, 0o644)
      end

      [child_id] =
        root
        |> Path.join("T-2026-05-08-*.md")
        |> Path.wildcard()
        |> Enum.map(&Path.basename(&1, ".md"))
        |> Enum.reject(&(&1 == ticket.id))

      assert {:ok, %{ticket: child_ticket, history: child_history}} =
               Api.show_ticket(child_id, tickets_root: root)

      assert child_ticket.assignees == ["clare"]
      assert Enum.any?(child_history, &match?(%{"event" => "injection_failed"}, &1))
      refute Enum.any?(child_history, &match?(%{"event" => "injected"}, &1))

      assert {:ok, %{children_created: children_created}} =
               Api.approve_mayor_proposal(ticket.id, "prop_recover_failed_route",
                 tickets_root: root,
                 date: ~D[2026-05-08],
                 now: "2026-05-08T00:03:00Z",
                 pane_injector: fn "clare", _prompt ->
                   flunk("failed recovered route should not be reinjected")
                 end
               )

      assert [child] = children_created["children"]
      assert child["routing"]["status"] == "failed"
      assert child["routing"]["reason"] == "Ticket prompt could not be injected into clare"
    end)
  end

  test "mayor proposal approval rejects stale recovered child tickets" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 type: "mission",
                 title: "Mission root",
                 body: "Split this mission.",
                 metadata: mayor_metadata()
               },
               tickets_root: root,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:00:00Z"
             )

    proposal = proposal(ticket.id, "prop_stale_recover", ["Build backend"])

    assert :ok =
             Api.append_ticket_events(ticket.id, [proposal_received(ticket.id, proposal)],
               tickets_root: root
             )

    history_path = TicketMarkdown.history_path(root, ticket.id)
    File.chmod!(history_path, 0o444)

    try do
      assert {:error, {:redacted_io_error, {:append_history, _reason}}} =
               Api.approve_mayor_proposal(ticket.id, "prop_stale_recover",
                 tickets_root: root,
                 date: ~D[2026-05-08],
                 now: "2026-05-08T00:02:00Z"
               )
    after
      File.chmod!(history_path, 0o644)
    end

    child_id =
      root
      |> Path.join("T-2026-05-08-*.md")
      |> Path.wildcard()
      |> Enum.map(&Path.basename(&1, ".md"))
      |> Enum.reject(&(&1 == ticket.id))
      |> List.first()

    child_path = TicketMarkdown.path(root, child_id)

    child_path
    |> File.read!()
    |> String.replace("# Build backend", "# Build stale backend")
    |> then(&File.write!(child_path, &1))

    assert {:error, {:mayor_child_tickets, {:stale_materialized_child, ^child_id}}} =
             Api.approve_mayor_proposal(ticket.id, "prop_stale_recover",
               tickets_root: root,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:03:00Z"
             )

    assert root
           |> Path.join("T-2026-05-08-*.md")
           |> Path.wildcard()
           |> length() == 2
  end

  test "mayor proposal approval rejects multiline child titles before creating child tickets" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 type: "mission",
                 title: "Mission root",
                 body: "Split this mission.",
                 metadata: mayor_metadata()
               },
               tickets_root: root,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:00:00Z"
             )

    proposal = proposal(ticket.id, "prop_multiline_title", ["Bad\nTitle"])

    assert :ok =
             Api.append_ticket_events(ticket.id, [proposal_received(ticket.id, proposal)],
               tickets_root: root
             )

    assert {:error, {:mayor_child_tickets, {:invalid_child_title, 0, :multiline}}} =
             Api.approve_mayor_proposal(ticket.id, "prop_multiline_title",
               tickets_root: root,
               now: "2026-05-08T00:02:00Z"
             )

    assert root
           |> Path.join("T-2026-05-08-*.md")
           |> Path.wildcard()
           |> length() == 1
  end

  test "mayor proposal approval repairs missing approval after children are recorded" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 type: "mission",
                 title: "Repair approval root",
                 body: "Children were already materialized.",
                 metadata: mayor_metadata()
               },
               tickets_root: root,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:00:00Z"
             )

    proposal = proposal(ticket.id, "prop_repair", ["Build backend"])

    children_created = %{
      "ts" => "2026-05-08T00:02:00Z",
      "event" => "mayor_children_created",
      "by" => "user",
      "ticket_id" => ticket.id,
      "proposal_id" => "prop_repair",
      "children" => [
        %{
          "child_index" => 0,
          "ticket_id" => "T-2026-05-08-099",
          "title" => "Build backend",
          "priority" => "normal",
          "inspector" => "user",
          "assignee_role" => "developer",
          "routing" => %{"status" => "assigned", "assignees" => ["dylan"]}
        }
      ]
    }

    assert :ok =
             Api.append_ticket_events(
               ticket.id,
               [proposal_received(ticket.id, proposal), children_created],
               tickets_root: root
             )

    revision = proposal_revision(root, ticket.id)

    assert {:error, {:mayor_proposal_review, {:already_materialized, :children_created}}} =
             Api.revise_mayor_proposal_child(ticket.id, "prop_repair", 0, %{title: "Changed"},
               tickets_root: root,
               proposal_revision: revision
             )

    assert {:error, {:mayor_proposal_review, {:already_materialized, :children_created}}} =
             Api.reject_mayor_proposal(ticket.id, "prop_repair", "Stop.",
               tickets_root: root,
               proposal_revision: revision
             )

    assert {:ok,
            %{
              event: approved,
              children_created: ^children_created,
              already_materialized?: true
            }} =
             Api.approve_mayor_proposal(ticket.id, "prop_repair",
               tickets_root: root,
               proposal_revision: revision,
               now: "2026-05-08T00:03:00Z"
             )

    assert approved["event"] == "mayor_proposal_approved"

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

    assert Enum.map(history, & &1["event"]) == [
             "created",
             "mayor_proposal_received",
             "mayor_children_created",
             "mayor_proposal_approved"
           ]

    assert root
           |> Path.join("T-2026-05-08-*.md")
           |> Path.wildcard()
           |> length() == 1
  end

  test "mayor proposal API rejects invalid and terminal actions without appending history" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 type: "mission",
                 title: "Mission root",
                 body: "Split this mission.",
                 metadata: mayor_metadata()
               },
               tickets_root: root,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:00:00Z"
             )

    proposal = proposal(ticket.id, "prop_review", ["Build backend"])

    assert :ok =
             Api.append_ticket_events(ticket.id, [proposal_received(ticket.id, proposal)],
               tickets_root: root
             )

    assert {:error, {:mayor_proposal_review, {:invalid_edit, _reason}}} =
             Api.revise_mayor_proposal_child(ticket.id, "prop_review", 0, %{title: " "},
               tickets_root: root
             )

    assert {:error, {:mayor_proposal_review, {:invalid_edit, :empty_children}}} =
             Api.remove_mayor_proposal_child(ticket.id, "prop_review", 0, tickets_root: root)

    assert {:error, {:mayor_proposal_review, {:stale_proposal_id, "prop_review", "old"}}} =
             Api.approve_mayor_proposal(ticket.id, "old", tickets_root: root)

    stale_revision = proposal_revision(root, ticket.id)

    assert {:ok, %{event: _revised}} =
             Api.revise_mayor_proposal_child(ticket.id, "prop_review", 0, %{title: "Build API"},
               tickets_root: root,
               proposal_revision: stale_revision
             )

    assert {:error,
            {:mayor_proposal_review,
             {:stale_proposal_revision, _current_revision, ^stale_revision}}} =
             Api.approve_mayor_proposal(ticket.id, "prop_review",
               tickets_root: root,
               proposal_revision: stale_revision
             )

    fresh_revision = proposal_revision(root, ticket.id)

    assert {:ok, %{event: approved}} =
             Api.approve_mayor_proposal(ticket.id, "prop_review",
               tickets_root: root,
               proposal_revision: fresh_revision,
               date: ~D[2026-05-08]
             )

    assert approved["event"] == "mayor_proposal_approved"

    assert {:error, {:mayor_proposal_review, {:already_decided, :approved}}} =
             Api.remove_mayor_proposal_child(ticket.id, "prop_review", 0, tickets_root: root)

    assert {:ok, closed} =
             Api.create_ticket(
               %{
                 type: "mission",
                 title: "Closed mission",
                 body: "Already closed.",
                 state: "closed",
                 assignees: ["clare"],
                 metadata: mayor_metadata()
               },
               tickets_root: root,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:01:00Z"
             )

    closed_proposal = proposal(closed.id, "prop_closed", ["Build closed"])

    assert :ok =
             Api.append_ticket_events(closed.id, [proposal_received(closed.id, closed_proposal)],
               tickets_root: root
             )

    assert {:error, {:mayor_proposal_review, {:terminal_ticket, closed_id, "closed"}}} =
             Api.approve_mayor_proposal(closed.id, "prop_closed", tickets_root: root)

    assert closed_id == closed.id

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

    assert Enum.map(history, & &1["event"]) == [
             "created",
             "mayor_proposal_received",
             "mayor_proposal_revised",
             "mayor_children_created",
             "mayor_proposal_approved"
           ]
  end

  test "create_ticket persists normalized inspection metadata" do
    root = tmp_root()

    metadata = %{
      "inspection" => %{
        "mode" => "auto",
        "strategy" => "council",
        "roles" => ["Inspector", "inspector", "QA Reviewer"],
        "citizens" => ["clare", "clare", "dylan"],
        "quorum" => "all_pass",
        "max_inspectors" => 2,
        "allow_self_inspection" => true
      }
    }

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 title: "Normalize inspection",
                 body: "Inspection policy metadata should be canonical.",
                 metadata: metadata
               },
               tickets_root: root,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:00:00Z"
             )

    expected = %{
      "mode" => "auto",
      "strategy" => "council",
      "roles" => ["inspector", "qa-reviewer"],
      "citizens" => ["clare", "dylan"],
      "quorum" => "all_pass",
      "max_inspectors" => 2,
      "allow_self_inspection" => true
    }

    assert ticket.metadata["inspection"] == expected
    assert {:ok, %{ticket: shown}} = Api.show_ticket(ticket.id, tickets_root: root)
    assert shown.metadata["inspection"] == expected
  end

  test "comment_ticket notifies every current assignee including the author" do
    root = tmp_root()
    parent = self()

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 title: "Comment fanout",
                 body: "Coordinate through ticket comments.",
                 state: "in_progress",
                 assignees: ["clare", "dylan"]
               },
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    assert {:ok, %{delivery: {:comment_notified, ["clare", "dylan"]}}} =
             Api.comment_ticket(ticket.id, %{body: "Branch is ready.", by: "clare"},
               tickets_root: root,
               now: "2026-05-06T00:01:00Z",
               citizen_fetcher: fn slug when slug in ["clare", "dylan"] -> %{slug: slug} end,
               pane_lookup: fn slug when slug in ["clare", "dylan"] -> {:ok, self()} end,
               pane_injector: fn slug, prompt ->
                 send(parent, {:comment_prompt, slug, prompt})
                 :ok
               end
             )

    assert_receive {:comment_prompt, "clare", clare_prompt}
    assert_receive {:comment_prompt, "dylan", dylan_prompt}
    assert clare_prompt =~ "From: clare"
    assert clare_prompt =~ "Branch is ready."
    assert dylan_prompt =~ "Branch is ready."

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)
    events = Enum.map(history, & &1["event"])

    assert events == [
             "created",
             "comment",
             "comment_notification_attempted",
             "comment_notified",
             "comment_notified"
           ]

    assert Enum.find(history, &(&1["event"] == "comment"))["by"] == "clare"

    attempted = Enum.find(history, &(&1["event"] == "comment_notification_attempted"))
    assert attempted["by"] == "clare"
    assert attempted["injected_to"] == ["clare", "dylan"]
  end

  test "comment_ticket threads Knowledge opts into delivered comment prompts" do
    root = tmp_root()
    tickets_root = Path.join(root, "tickets")
    parent = self()

    assert :ok =
             Knowledge.write("clare", "Readme.md", "Prefer concise replies.\n",
               root: root,
               knowledge_root: "knowledge"
             )

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 title: "Comment context",
                 body: "Use standing context.",
                 state: "in_progress",
                 assignees: ["clare"]
               },
               root: root,
               tickets_root: tickets_root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    assert {:ok, %{delivery: {:comment_notified, ["clare"]}}} =
             Api.comment_ticket(ticket.id, %{body: "Continue.", by: "user"},
               root: root,
               tickets_root: tickets_root,
               knowledge_root: "knowledge",
               now: "2026-05-06T00:01:00Z",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:ok, self()} end,
               pane_injector: fn "clare", prompt ->
                 send(parent, {:comment_prompt, prompt})
                 :ok
               end
             )

    assert_receive {:comment_prompt, prompt}
    assert prompt =~ "Citizen standing context:"
    assert prompt =~ "[file: Readme.md]\nPrefer concise replies."
    assert prompt =~ "Ticket body:\nUse standing context."
  end

  test "comment_ticket emits turn events and attempt ids for hardline fanout" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 title: "Turn fanout",
                 body: "Coordinate through turn events.",
                 state: "in_progress",
                 assignees: ["clare", "dylan"]
               },
               tickets_root: root,
               date: ~D[2026-05-07],
               now: "2026-05-07T10:00:00Z"
             )

    assert {:ok, %{delivery: {:comment_notified, ["clare", "dylan"]}}} =
             Api.comment_ticket(ticket.id, %{body: "Second turn.", by: "user"},
               tickets_root: root,
               now: "2026-05-07T10:01:00Z",
               citizen_fetcher: fn slug when slug in ["clare", "dylan"] -> %{slug: slug} end,
               pane_lookup: fn slug when slug in ["clare", "dylan"] -> {:ok, self()} end,
               pane_injector: fn _slug, _prompt -> :ok end
             )

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

    comment = Enum.find(history, &(&1["event"] == "comment" and &1["body"] == "Second turn."))
    assert comment["turn_id"] =~ ~r/\Aturn_20260507100100_[a-z0-9]{10}\z/
    assert comment["message_id"] =~ ~r/\Amsg_20260507100100_[a-z0-9]{10}\z/

    assert %{
             "event" => "turn_created",
             "turn_id" => turn_id,
             "prompt_message_id" => prompt_message_id,
             "to" => ["clare", "dylan"]
           } = Enum.find(history, &(&1["event"] == "turn_created"))

    assert turn_id == comment["turn_id"]
    assert prompt_message_id == comment["message_id"]

    attempted = Enum.filter(history, &(&1["event"] == "turn_delivery_attempted"))
    assert Enum.map(attempted, & &1["to"]) |> Enum.sort() == ["clare", "dylan"]
    assert Enum.all?(attempted, &(&1["status"] == "queued"))
    assert Enum.all?(attempted, &(&1["backend"] == "hardline"))

    delivered = Enum.filter(history, &(&1["event"] == "turn_delivered"))
    assert Enum.map(delivered, & &1["to"]) |> Enum.sort() == ["clare", "dylan"]

    for attempted_event <- attempted do
      assert Enum.any?(
               delivered,
               &(&1["turn_id"] == turn_id and &1["attempt_id"] == attempted_event["attempt_id"] and
                   &1["to"] == attempted_event["to"])
             )
    end
  end

  test "captured replies can reference the source turn and attempt without renotifying" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 title: "Captured turn reply",
                 body: "Captured replies should keep turn ids.",
                 state: "in_progress",
                 assignees: ["clare"]
               },
               tickets_root: root,
               date: ~D[2026-05-07],
               now: "2026-05-07T10:00:00Z"
             )

    assert {:ok, %{delivery: :comment_stored}} =
             Api.comment_ticket(
               ticket.id,
               %{
                 body: "Captured answer.",
                 by: "clare",
                 turn_id: "turn_20260507100100_abc123def0",
                 attempt_id: "attempt_20260507100100_abc123def0"
               },
               tickets_root: root,
               now: "2026-05-07T10:02:00Z",
               notify_assignees: false
             )

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

    comment = Enum.find(history, &(&1["event"] == "comment" and &1["body"] == "Captured answer."))
    assert comment["turn_id"] == "turn_20260507100100_abc123def0"
    assert comment["message_id"] =~ ~r/\Amsg_20260507100200_[a-z0-9]{10}\z/

    assert %{
             "event" => "turn_reply_captured",
             "turn_id" => "turn_20260507100100_abc123def0",
             "attempt_id" => "attempt_20260507100100_abc123def0",
             "message_id" => message_id,
             "by_citizen" => "clare"
           } = Enum.find(history, &(&1["event"] == "turn_reply_captured"))

    assert message_id == comment["message_id"]
    refute Enum.any?(history, &(&1["event"] == "comment_notification_attempted"))
  end

  test "comment_ticket with notify_assignees false omits notification attempt history" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 title: "Captured reply",
                 body: "Captured replies should not renotify assignees.",
                 state: "in_progress",
                 assignees: ["clare"]
               },
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    assert {:ok, %{delivery: :comment_stored}} =
             Api.comment_ticket(ticket.id, %{body: "Captured answer.", by: "clare"},
               tickets_root: root,
               now: "2026-05-06T00:01:00Z",
               notify_assignees: false
             )

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)
    assert Enum.map(history, & &1["event"]) == ["created", "comment"]
  end

  test "user comment with notify_assignees false is stored without turn fanout" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 title: "User note",
                 body: "Operator-only note should not notify assignees.",
                 state: "in_progress",
                 assignees: ["clare"]
               },
               tickets_root: root,
               date: ~D[2026-05-07],
               now: "2026-05-07T10:00:00Z"
             )

    assert {:ok, %{delivery: :comment_stored}} =
             Api.comment_ticket(ticket.id, %{body: "Hold delivery for now.", by: "user"},
               tickets_root: root,
               now: "2026-05-07T10:01:00Z",
               notify_assignees: false
             )

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)
    assert Enum.map(history, & &1["event"]) == ["created", "comment"]

    comment = List.last(history)
    assert comment["by"] == "user"
    assert comment["message_id"] =~ ~r/\Amsg_20260507100100_[a-z0-9]{10}\z/
    refute Map.has_key?(comment, "turn_id")
  end

  test "comment_ticket tracks AI reply capture after successful notification injection" do
    root = tmp_root()
    parent = self()

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 title: "Comment reply capture",
                 body: "Comment notifications should be reply-captured.",
                 state: "in_progress",
                 assignees: ["clare"]
               },
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    assert {:ok, %{delivery: {:comment_notified, ["clare"]}}} =
             Api.comment_ticket(ticket.id, %{body: "Please respond.", by: "user"},
               tickets_root: root,
               now: "2026-05-06T00:01:00Z",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:ok, self()} end,
               pane_injector: fn "clare", _prompt -> :ok end,
               reply_capture: fn turn ->
                 send(parent, {:reply_capture, turn})
                 :ok
               end
             )

    assert_receive {:reply_capture,
                    %{
                      root: ^root,
                      ticket_id: ticket_id,
                      slug: "clare",
                      started_at: "2026-05-06T00:01:00Z"
                    }}

    assert ticket_id == ticket.id
  end

  test "comment_ticket keeps comment durable when one assignee notification fails" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 title: "Partial comment fanout",
                 body: "One pane will fail.",
                 state: "pending_approval",
                 assignees: ["clare", "dylan"]
               },
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    assert {:ok,
            %{
              delivery:
                {:comment_notification_failed, ["clare"],
                 [{"dylan", {:ticket_injection_failed, "dylan", message}}]}
            }} =
             Api.comment_ticket(ticket.id, %{body: "Please inspect.", by: "dylan"},
               tickets_root: root,
               now: "2026-05-06T00:01:00Z",
               citizen_fetcher: fn slug when slug in ["clare", "dylan"] -> %{slug: slug} end,
               pane_lookup: fn slug when slug in ["clare", "dylan"] -> {:ok, self()} end,
               pane_injector: fn
                 "clare", _prompt -> :ok
                 "dylan", _prompt -> {:error, %{api_token: "fixture-value"}}
               end
             )

    refute message =~ "fixture-value"

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)
    events = Enum.map(history, & &1["event"])

    assert events == [
             "created",
             "comment",
             "comment_notification_attempted",
             "comment_notified",
             "comment_notification_failed"
           ]

    assert Enum.find(history, &(&1["event"] == "comment"))["body"] == "Please inspect."
    refute List.last(history)["error"] =~ "fixture-value"
  end

  test "comment_ticket records hardline delivery busy when the assignee lock is held" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 title: "Busy hardline delivery",
                 body: "The assignee is already executing.",
                 state: "in_progress",
                 assignees: ["clare"]
               },
               tickets_root: root,
               date: ~D[2026-05-07],
               now: "2026-05-07T10:00:00Z"
             )

    assert {:ok,
            %{
              delivery:
                {:comment_notification_failed, [], [{"clare", {:execution_busy, "clare"}}]}
            }} =
             ExecutionLock.with_lock("clare", fn ->
               Api.comment_ticket(ticket.id, %{body: "Please queue safely.", by: "user"},
                 tickets_root: root,
                 now: "2026-05-07T10:01:00Z",
                 citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
                 pane_lookup: fn "clare" -> {:ok, self()} end,
                 pane_injector: fn _slug, _prompt -> flunk("busy hardline delivery injected") end
               )
             end)

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

    assert Enum.any?(
             history,
             &match?(%{"event" => "turn_delivery_failed", "backend" => "hardline"}, &1)
           )

    assert Enum.any?(
             history,
             &match?(
               %{"event" => "comment_notification_failed", "error" => error}
               when is_binary(error),
               &1
             )
           )
  end

  test "comment_ticket rejects terminal tickets and invalid authors before rewriting" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(
               %{title: "Closed comment", body: "This should stay closed."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    closed = %{ticket | state: "closed", assignees: ["clare"]}
    File.write!(Path.join(root, "#{ticket.id}.md"), TicketMarkdown.render(closed))

    assert {:error, {:terminal_ticket, ticket_id, "closed"}} =
             Api.comment_ticket(ticket.id, %{body: "Please reopen.", by: "clare"},
               tickets_root: root,
               now: "2026-05-06T00:01:00Z"
             )

    assert ticket_id == ticket.id

    assert {:error, {:invalid_comment_author, "not valid!"}} =
             Api.comment_ticket(ticket.id, %{body: "Please reopen.", by: "not valid!"},
               tickets_root: root,
               now: "2026-05-06T00:01:00Z"
             )

    assert {:ok, %{ticket: unchanged, history: history}} =
             Api.show_ticket(ticket.id, tickets_root: root)

    assert unchanged.updated_at == "2026-05-06T00:00:00Z"
    assert Enum.map(history, & &1["event"]) == ["created"]
  end

  test "concurrent comment_ticket attempts serialize and preserve every comment" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Concurrent comments", body: "Collect notes."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    results =
      1..6
      |> Task.async_stream(
        fn index ->
          Api.comment_ticket(ticket.id, %{body: "Note #{index}", by: "clare"},
            tickets_root: root,
            now: "2026-05-06T00:01:00Z"
          )
        end,
        max_concurrency: 6,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, %{delivery: {:comment_notified, []}}}, &1))

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)
    assert Enum.count(history, &(&1["event"] == "comment")) == 6

    assert Enum.map(Enum.filter(history, &(&1["event"] == "comment")), & &1["body"])
           |> Enum.sort() ==
             Enum.map(1..6, &"Note #{&1}")
  end

  test "assign_ticket persists assignment before injecting prompt" do
    root = tmp_root()
    parent = self()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Assign me", body: "Ticket assignment body."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    assert {:ok, %{ticket: assigned, delivery: {:injected, "clare"}}} =
             Api.assign_ticket(ticket.id, "clare",
               tickets_root: root,
               now: "2026-05-06T00:01:00Z",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:ok, self()} end,
               pane_injector: fn "clare", prompt ->
                 send(parent, {:injected, prompt})
                 :ok
               end
             )

    assert assigned.state == "in_progress"
    assert assigned.assignees == ["clare"]
    assert assigned.updated_at == "2026-05-06T00:01:00Z"

    assert_receive {:injected, prompt}
    assert prompt =~ "[Babs Ticket #{ticket.id} assigned]"
    assert prompt =~ "Ticket assignment body."

    assert {:ok, %{ticket: shown, history: history}} =
             Api.show_ticket(ticket.id, tickets_root: root)

    assert shown.state == "in_progress"
    assert shown.assignees == ["clare"]

    assert Enum.map(history, & &1["event"]) == [
             "created",
             "assigned",
             "state_change",
             "injection_attempted",
             "injected"
           ]

    assert Enum.at(history, 1)["to"] == ["clare"]
    assert Enum.at(history, 3)["injected_to"] == ["clare"]
  end

  test "assign_ticket tracks AI reply capture after successful injection" do
    root = tmp_root()
    parent = self()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Track reply", body: "Capture this reply."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    assert {:ok, %{ticket: assigned, delivery: {:injected, "clare"}}} =
             Api.assign_ticket(ticket.id, "clare",
               tickets_root: root,
               now: "2026-05-06T00:01:00Z",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:ok, self()} end,
               pane_injector: fn "clare", _prompt -> :ok end,
               reply_capture: fn turn ->
                 send(parent, {:reply_capture, turn})
                 :ok
               end
             )

    assert assigned.state == "in_progress"

    assert_receive {:reply_capture,
                    %{
                      root: ^root,
                      ticket_id: ticket_id,
                      slug: "clare",
                      started_at: "2026-05-06T00:01:00Z"
                    }}

    assert ticket_id == ticket.id
  end

  test "assign_ticket records start failure without changing ticket assignment" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Start failure", body: "Do not assign yet."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    assert {:error, {:citizen_start_failed, "clare", message}} =
             Api.assign_ticket(ticket.id, "clare",
               tickets_root: root,
               now: "2026-05-06T00:01:00Z",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:error, :not_found} end,
               citizen_starter: fn "clare" -> {:error, %{api_token: "fixture-value"}} end
             )

    refute message =~ "fixture-value"

    assert {:ok, %{ticket: shown, history: history}} =
             Api.show_ticket(ticket.id, tickets_root: root)

    assert shown.state == "open"
    assert shown.assignees == []
    assert Enum.map(history, & &1["event"]) == ["created", "assignment_failed"]
    assert List.last(history)["to"] == ["clare"]
    refute List.last(history)["error"] =~ "fixture-value"
  end

  test "assign_ticket records injection failure after durable assignment facts" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Injection failure", body: "Persist assignment."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    assert {:error, {:ticket_injection_failed, "clare", message}} =
             Api.assign_ticket(ticket.id, "clare",
               tickets_root: root,
               now: "2026-05-06T00:01:00Z",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:ok, self()} end,
               pane_injector: fn "clare", _prompt ->
                 {:error, %{api_token: "fixture-value"}}
               end
             )

    refute message =~ "fixture-value"

    assert {:ok, %{ticket: shown, history: history}} =
             Api.show_ticket(ticket.id, tickets_root: root)

    assert shown.state == "in_progress"
    assert shown.assignees == ["clare"]

    assert Enum.map(history, & &1["event"]) == [
             "created",
             "assigned",
             "state_change",
             "injection_attempted",
             "injection_failed"
           ]

    refute List.last(history)["error"] =~ "fixture-value"
  end

  test "assign_ticket records busy hardline assignment without injecting when lock is held" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Busy assignment", body: "Persist without pane write."},
               tickets_root: root,
               date: ~D[2026-05-07],
               now: "2026-05-07T10:00:00Z"
             )

    assert {:error, {:execution_busy, "clare"}} =
             ExecutionLock.with_lock("clare", fn ->
               Api.assign_ticket(ticket.id, "clare",
                 tickets_root: root,
                 now: "2026-05-07T10:01:00Z",
                 citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
                 pane_lookup: fn "clare" -> {:ok, self()} end,
                 pane_injector: fn "clare", _prompt ->
                   flunk("busy hardline assignment should not inject into the pane")
                 end
               )
             end)

    assert {:ok, %{ticket: shown, history: history}} =
             Api.show_ticket(ticket.id, tickets_root: root)

    assert shown.state == "in_progress"
    assert shown.assignees == ["clare"]

    assert Enum.map(history, & &1["event"]) == [
             "created",
             "assigned",
             "state_change",
             "injection_attempted",
             "injection_failed"
           ]

    assert List.last(history)["error"] =~ "execution_busy"
    refute Enum.any?(history, &match?(%{"event" => "injected"}, &1))
  end

  test "concurrent assign_ticket attempts serialize through the per-ticket writer" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Concurrent assign", body: "Only one citizen gets it."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    results =
      ["clare", "dylan"]
      |> Task.async_stream(
        fn slug ->
          Api.assign_ticket(ticket.id, slug,
            tickets_root: root,
            now: "2026-05-06T00:01:00Z",
            citizen_fetcher: fn ^slug -> %{slug: slug} end,
            pane_lookup: fn ^slug -> {:ok, self()} end,
            pane_injector: fn ^slug, _prompt -> :ok end
          )
        end,
        max_concurrency: 2,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _result}, &1)) == 1

    assert Enum.count(
             results,
             &match?({:error, {:invalid_transition, "in_progress", "in_progress"}}, &1)
           ) == 1

    assert {:ok, %{ticket: shown, history: history}} =
             Api.show_ticket(ticket.id, tickets_root: root)

    assert shown.state == "in_progress"
    assert length(shown.assignees) == 1

    assert Enum.map(history, & &1["event"]) == [
             "created",
             "assigned",
             "state_change",
             "injection_attempted",
             "injected"
           ]
  end

  test "transition_ticket and unassign_ticket persist legal state changes" do
    root = tmp_root()
    parent = self()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Transition", body: "Move through states."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    assert {:ok, _result} =
             Api.assign_ticket(ticket.id, "clare",
               tickets_root: root,
               now: "2026-05-06T00:01:00Z",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:ok, self()} end,
               pane_injector: fn "clare", _prompt -> :ok end
             )

    assert {:ok, %{ticket: pending}} =
             Api.transition_ticket(ticket.id, "pending_approval", nil,
               tickets_root: root,
               now: "2026-05-06T00:02:00Z"
             )

    assert pending.state == "pending_approval"

    assert {:error, {:invalid_transition, "pending_approval", "open"}} =
             Api.unassign_ticket(ticket.id, "clare",
               tickets_root: root,
               now: "2026-05-06T00:03:00Z"
             )

    assert {:error, {:use_reject_ticket, ticket_id}} =
             Api.transition_ticket(ticket.id, "in_progress", "rejected",
               tickets_root: root,
               now: "2026-05-06T00:04:00Z"
             )

    assert ticket_id == ticket.id

    assert {:error, {:use_reject_ticket, ticket_id}} =
             Api.transition_ticket(ticket.id, "in_progress", nil,
               tickets_root: root,
               now: "2026-05-06T00:04:00Z"
             )

    assert ticket_id == ticket.id

    assert {:ok, %{ticket: rejected, delivery: {:feedback_injected, ["clare"]}}} =
             Api.reject_ticket(ticket.id, "Needs docs.",
               tickets_root: root,
               now: "2026-05-06T00:04:00Z",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:ok, self()} end,
               pane_injector: fn "clare", prompt ->
                 send(parent, {:feedback, prompt})
                 :ok
               end
             )

    assert rejected.state == "in_progress"
    assert_receive {:feedback, prompt}
    assert prompt =~ "Needs docs."

    assert {:ok, %{ticket: open}} =
             Api.unassign_ticket(ticket.id, "clare",
               tickets_root: root,
               now: "2026-05-06T00:05:00Z"
             )

    assert open.state == "open"
    assert open.assignees == []
  end

  test "approve_ticket closes pending approval tickets with explicit history" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Approve", body: "Ready to close."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    assert {:ok, _result} =
             Api.assign_ticket(ticket.id, "clare",
               tickets_root: root,
               now: "2026-05-06T00:01:00Z",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:ok, self()} end,
               pane_injector: fn "clare", _prompt -> :ok end
             )

    assert {:ok, _result} =
             Api.transition_ticket(ticket.id, "pending_approval", nil,
               tickets_root: root,
               now: "2026-05-06T00:02:00Z"
             )

    assert {:error, {:use_approve_ticket, ticket_id}} =
             Api.transition_ticket(ticket.id, "closed", "approved",
               tickets_root: root,
               now: "2026-05-06T00:03:00Z"
             )

    assert ticket_id == ticket.id

    assert {:ok, %{ticket: approved}} =
             Api.approve_ticket(ticket.id,
               tickets_root: root,
               now: "2026-05-06T00:03:00Z"
             )

    assert approved.state == "closed"

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)
    events = Enum.map(history, & &1["event"])
    assert Enum.take(events, -2) == ["approved", "state_change"]
  end

  test "reject_ticket requires feedback and assignees before rewriting" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Reject", body: "Needs review."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    assert {:ok, _result} =
             Api.assign_ticket(ticket.id, "clare",
               tickets_root: root,
               now: "2026-05-06T00:01:00Z",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:ok, self()} end,
               pane_injector: fn "clare", _prompt -> :ok end
             )

    assert {:ok, _result} =
             Api.transition_ticket(ticket.id, "pending_approval", nil,
               tickets_root: root,
               now: "2026-05-06T00:02:00Z"
             )

    assert {:error, {:invalid_history_event, :empty_feedback}} =
             Api.reject_ticket(ticket.id, "   ",
               tickets_root: root,
               now: "2026-05-06T00:03:00Z"
             )

    assert {:ok, %{ticket: shown, history: history}} =
             Api.show_ticket(ticket.id, tickets_root: root)

    assert shown.state == "pending_approval"
    refute "rejected" in Enum.map(history, & &1["event"])
  end

  test "reject_ticket validates history size before rewriting ticket markdown" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Reject size", body: "Needs review."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    assert {:ok, _result} =
             Api.assign_ticket(ticket.id, "clare",
               tickets_root: root,
               now: "2026-05-06T00:01:00Z",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:ok, self()} end,
               pane_injector: fn "clare", _prompt -> :ok end
             )

    assert {:ok, _result} =
             Api.transition_ticket(ticket.id, "pending_approval", nil,
               tickets_root: root,
               now: "2026-05-06T00:02:00Z"
             )

    ticket_id = ticket.id

    assert {:error, {:history_event_too_large, ^ticket_id}} =
             Api.reject_ticket(ticket.id, String.duplicate("x", 20_000),
               tickets_root: root,
               now: "2026-05-06T00:03:00Z"
             )

    assert {:ok, %{ticket: shown, history: history}} =
             Api.show_ticket(ticket.id, tickets_root: root)

    assert shown.state == "pending_approval"
    refute "rejected" in Enum.map(history, & &1["event"])
  end

  test "reject_ticket keeps rejection state when feedback injection fails" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Feedback failure", body: "Needs review."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    assert {:ok, _result} =
             Api.assign_ticket(ticket.id, "clare",
               tickets_root: root,
               now: "2026-05-06T00:01:00Z",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:ok, self()} end,
               pane_injector: fn "clare", _prompt -> :ok end
             )

    assert {:ok, _result} =
             Api.transition_ticket(ticket.id, "pending_approval", nil,
               tickets_root: root,
               now: "2026-05-06T00:02:00Z"
             )

    assert {:error, {:feedback_injection_failed, ticket_id, [{"clare", _reason}]}} =
             Api.reject_ticket(ticket.id, "Please add tests.",
               tickets_root: root,
               now: "2026-05-06T00:03:00Z",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:ok, self()} end,
               pane_injector: fn "clare", _prompt -> {:error, %{api_token: "fixture-value"}} end
             )

    assert ticket_id == ticket.id

    assert {:ok, %{ticket: shown, history: history}} =
             Api.show_ticket(ticket.id, tickets_root: root)

    assert shown.state == "in_progress"
    assert shown.assignees == ["clare"]

    assert Enum.take(Enum.map(history, & &1["event"]), -4) == [
             "rejected",
             "state_change",
             "feedback_injection_attempted",
             "feedback_injection_failed"
           ]

    refute List.last(history)["error"] =~ "fixture-value"
  end

  test "reject_ticket records busy hardline feedback without injecting when lock is held" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Busy feedback", body: "Needs review."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    assert {:ok, _result} =
             Api.assign_ticket(ticket.id, "clare",
               tickets_root: root,
               now: "2026-05-06T00:01:00Z",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:ok, self()} end,
               pane_injector: fn "clare", _prompt -> :ok end
             )

    assert {:ok, _result} =
             Api.transition_ticket(ticket.id, "pending_approval", nil,
               tickets_root: root,
               now: "2026-05-06T00:02:00Z"
             )

    assert {:error,
            {:feedback_injection_failed, ticket_id, [{"clare", {:execution_busy, "clare"}}]}} =
             ExecutionLock.with_lock("clare", fn ->
               Api.reject_ticket(ticket.id, "Please add tests.",
                 tickets_root: root,
                 now: "2026-05-06T00:03:00Z",
                 citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
                 pane_lookup: fn "clare" -> {:ok, self()} end,
                 pane_injector: fn "clare", _prompt ->
                   flunk("busy hardline feedback should not inject into the pane")
                 end
               )
             end)

    assert ticket_id == ticket.id

    assert {:ok, %{ticket: shown, history: history}} =
             Api.show_ticket(ticket.id, tickets_root: root)

    assert shown.state == "in_progress"
    assert shown.assignees == ["clare"]

    assert Enum.take(Enum.map(history, & &1["event"]), -4) == [
             "rejected",
             "state_change",
             "feedback_injection_attempted",
             "feedback_injection_failed"
           ]

    assert List.last(history)["error"] =~ "execution_busy"
    refute Enum.any?(history, &match?(%{"event" => "feedback_injected"}, &1))
  end

  test "reject_ticket injects feedback to every current assignee" do
    root = tmp_root()
    parent = self()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Multi feedback", body: "Needs review."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    pending = %{ticket | state: "pending_approval", assignees: ["clare", "dylan"]}
    File.write!(Path.join(root, "#{ticket.id}.md"), TicketMarkdown.render(pending))

    assert {:ok, %{ticket: rejected, delivery: {:feedback_injected, ["clare", "dylan"]}}} =
             Api.reject_ticket(ticket.id, "Please split the patch.",
               tickets_root: root,
               now: "2026-05-06T00:03:00Z",
               citizen_fetcher: fn slug when slug in ["clare", "dylan"] -> %{slug: slug} end,
               pane_lookup: fn slug when slug in ["clare", "dylan"] -> {:ok, self()} end,
               pane_injector: fn slug, prompt ->
                 send(parent, {:feedback, slug, prompt})
                 :ok
               end
             )

    assert rejected.state == "in_progress"
    assert rejected.assignees == ["clare", "dylan"]

    assert_receive {:feedback, "clare", clare_prompt}
    assert_receive {:feedback, "dylan", dylan_prompt}
    assert clare_prompt =~ "Please split the patch."
    assert dylan_prompt =~ "Please split the patch."

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)
    events = Enum.map(history, & &1["event"])
    assert Enum.count(events, &(&1 == "feedback_injected")) == 2

    attempted =
      Enum.find(history, fn event -> event["event"] == "feedback_injection_attempted" end)

    assert attempted["injected_to"] == ["clare", "dylan"]
  end

  test "reject_ticket tracks AI reply capture after successful feedback injection" do
    root = tmp_root()
    parent = self()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Feedback reply capture", body: "Needs review."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    pending = %{ticket | state: "pending_approval", assignees: ["clare"]}
    File.write!(Path.join(root, "#{ticket.id}.md"), TicketMarkdown.render(pending))

    assert {:ok, %{delivery: {:feedback_injected, ["clare"]}}} =
             Api.reject_ticket(ticket.id, "Please add the missing test.",
               tickets_root: root,
               now: "2026-05-06T00:03:00Z",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:ok, self()} end,
               pane_injector: fn "clare", _prompt -> :ok end,
               reply_capture: fn turn ->
                 send(parent, {:reply_capture, turn})
                 :ok
               end
             )

    assert_receive {:reply_capture,
                    %{
                      root: ^root,
                      ticket_id: ticket_id,
                      slug: "clare",
                      started_at: "2026-05-06T00:03:00Z"
                    }}

    assert ticket_id == ticket.id
  end

  test "assign_ticket_by_role selects citizen and records role-routed history" do
    root = tmp_root()
    parent = self()

    with_role_catalog(fn config_root ->
      Babs.Citizens.RepoCase.write_citizen_toml!(config_root, "clare")

      Babs.Citizens.RepoCase.insert_citizen!(%{
        slug: "clare",
        display_name: "Clare",
        roles: [
          %{"name" => "inspector", "skills" => []},
          %{"name" => "developer", "skills" => []}
        ]
      })

      assert {:ok, ticket} =
               Api.create_ticket(
                 %{title: "Role route", body: "Pick a developer.", assignee_role: "developer"},
                 tickets_root: root,
                 date: ~D[2026-05-08],
                 now: "2026-05-08T00:00:00Z"
               )

      assert {:ok, %{ticket: assigned, delivery: {:injected, "clare"}}} =
               Api.assign_ticket_by_role(ticket.id,
                 tickets_root: root,
                 now: "2026-05-08T00:01:00Z",
                 citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
                 pane_lookup: fn "clare" -> {:ok, self()} end,
                 pane_injector: fn "clare", prompt ->
                   send(parent, {:role_prompt, prompt})
                   :ok
                 end
               )

      assert assigned.state == "in_progress"
      assert assigned.assignees == ["clare"]
      assert_receive {:role_prompt, prompt}
      assert prompt =~ "Pick a developer."

      assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)
      assigned_event = Enum.find(history, &(&1["event"] == "assigned"))
      assert assigned_event["to"] == ["clare"]
      assert assigned_event["via_role"] == "developer"
      assert assigned_event["body"] == "assigned to clare via role developer"
    end)
  end

  test "assign_ticket_by_role reserves direct backend before persisting assignment" do
    root = tmp_root()
    parent = self()
    config = fake_direct_config("flora")

    with_role_catalog(fn config_root ->
      Babs.Citizens.RepoCase.write_citizen_toml!(config_root, "flora")

      Babs.Citizens.RepoCase.insert_citizen!(%{
        slug: "flora",
        display_name: "Flora",
        cwd: config.cwd,
        cli: config.cli,
        ticket_backend: "direct_cli",
        roles: ["developer"]
      })

      assert {:ok, ticket} =
               Api.create_ticket(
                 %{
                   title: "Direct role route",
                   body: "Use direct role routing.",
                   assignee_role: "developer"
                 },
                 tickets_root: root,
                 date: ~D[2026-05-08],
                 now: "2026-05-08T00:00:00Z"
               )

      executor = fn command ->
        send(parent, {:direct_role_command, command})

        {:ok,
         %{
           stdout:
             Jason.encode!(%{
               "session_id" => "fake-session-flora",
               "content" => "direct role acknowledged"
             })
         }}
      end

      assert {:ok, %{ticket: assigned, delivery: {:injected, "flora"}}} =
               Api.assign_ticket_by_role(ticket.id,
                 tickets_root: root,
                 now: "2026-05-08T00:01:00Z",
                 citizen_config_fetcher: fn "flora" -> config end,
                 adapter: Fake,
                 executor: executor,
                 reply_capture: fn _turn -> :ok end
               )

      assert assigned.state == "in_progress"
      assert assigned.assignees == ["flora"]

      assert_receive {:direct_role_command, command}, 1_000
      prompt = List.last(command.args)
      assert prompt =~ "[Babs Ticket #{ticket.id} assigned]"
      assert prompt =~ "Use direct role routing."

      assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)
      assert Enum.find(history, &(&1["event"] == "assigned"))["via_role"] == "developer"

      assert Enum.any?(
               history,
               &match?(%{"event" => "turn_delivery_attempted", "backend" => "direct_cli"}, &1)
             )

      assert Enum.any?(history, &match?(%{"event" => "injected", "injected_to" => ["flora"]}, &1))
    end)
  end

  test "assign_ticket_by_role reports missing role and already assigned tickets" do
    root = tmp_root()

    assert {:ok, no_role} =
             Api.create_ticket(%{title: "No role", body: "No role."},
               tickets_root: root,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:00:00Z"
             )

    assert {:error, {:missing_assignee_role, no_role_id}} =
             Api.assign_ticket_by_role(no_role.id, tickets_root: root)

    assert no_role_id == no_role.id

    assert {:ok, assigned} =
             Api.create_ticket(
               %{
                 title: "Already assigned",
                 body: "Already assigned.",
                 state: "in_progress",
                 assignees: ["clare"],
                 assignee_role: "developer"
               },
               tickets_root: root,
               date: ~D[2026-05-08],
               now: "2026-05-08T00:01:00Z"
             )

    assert {:error, {:role_route_already_assigned, assigned_id}} =
             Api.assign_ticket_by_role(assigned.id, tickets_root: root)

    assert assigned_id == assigned.id
  end

  test "oversized comments fail before rewriting ticket markdown" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Large comment", body: "Initial body."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    ticket_id = ticket.id

    assert {:error, {:history_event_too_large, ^ticket_id}} =
             Api.comment_ticket(ticket.id, %{body: String.duplicate("x", 20_000), by: "clare"},
               tickets_root: root,
               now: "2026-05-06T00:01:00Z"
             )

    assert {:ok, %{ticket: unchanged, history: history}} =
             Api.show_ticket(ticket.id, tickets_root: root)

    assert unchanged.updated_at == "2026-05-06T00:00:00Z"
    assert Enum.map(history, & &1["event"]) == ["created"]
  end

  test "oversized comment notification attempts fail before rewriting ticket markdown" do
    root = tmp_root()
    assignees = Enum.map(1..2_000, &"assignee-#{&1}")

    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 title: "Large notification attempt",
                 body: "Initial body.",
                 state: "in_progress",
                 assignees: assignees
               },
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    ticket_id = ticket.id

    assert {:error, {:history_event_too_large, ^ticket_id}} =
             Api.comment_ticket(ticket.id, %{body: "Small comment.", by: "clare"},
               tickets_root: root,
               now: "2026-05-06T00:01:00Z"
             )

    assert {:ok, %{ticket: unchanged, history: history}} =
             Api.show_ticket(ticket.id, tickets_root: root)

    assert unchanged.updated_at == "2026-05-06T00:00:00Z"
    assert unchanged.assignees == assignees
    assert Enum.map(history, & &1["event"]) == ["created"]
  end

  test "detects manual write conflicts before writer mutation" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Conflict", body: "Initial body."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    ticket_id = ticket.id

    assert {:error, {:write_conflict, ^ticket_id}} =
             Api.comment_ticket(ticket.id, %{body: "This should fail."},
               tickets_root: root,
               now: "2026-05-06T00:01:00Z",
               before_write: fn path ->
                 File.write!(
                   path,
                   String.replace(File.read!(path), "Initial body.", "Manual edit.")
                 )
               end
             )
  end

  test "list surfaces invalid ticket files without crashing" do
    root = tmp_root()
    File.write!(Path.join(root, "T-2026-05-06-001.md"), "not frontmatter")

    assert {:ok,
            %{
              tickets: [],
              invalid: [%{path: path, reason: {:invalid_frontmatter, :missing_frontmatter}}]
            }} =
             Api.list_tickets(tickets_root: root)

    assert Path.basename(path) == "T-2026-05-06-001.md"
  end

  test "list treats markdown without history as incomplete" do
    root = tmp_root()

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Incomplete", body: "Will lose history."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    File.rm!(Path.join(root, "#{ticket.id}.history.jsonl"))

    assert {:ok,
            %{
              tickets: [],
              invalid: [%{reason: {:invalid_history, {ticket_id, 0, :missing_history}}}]
            }} = Api.list_tickets(tickets_root: root)

    assert ticket_id == ticket.id
  end

  test "list surfaces history files without matching markdown as invalid" do
    root = tmp_root()
    File.write!(Path.join(root, "T-2026-05-06-001.history.jsonl"), "{}\n")

    assert {:ok,
            %{
              tickets: [],
              invalid: [
                %{
                  path: path,
                  reason: {:invalid_history, {"T-2026-05-06-001", 0, :orphan_history}}
                }
              ]
            }} = Api.list_tickets(tickets_root: root)

    assert Path.basename(path) == "T-2026-05-06-001.history.jsonl"
  end

  test "create validates generated ticket and removes empty id claim on failure" do
    root = tmp_root()

    assert {:error, {:invalid_frontmatter, {:invalid_billboard_state, "in_progress"}}} =
             Api.create_ticket(
               %{title: "Invalid", body: "Invalid state.", state: "in_progress", assignees: []},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    refute File.exists?(Path.join(root, "T-2026-05-06-001.md"))

    assert {:ok, ticket} =
             Api.create_ticket(%{title: "Valid", body: "Uses the first id."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:01:00Z"
             )

    assert ticket.id == "T-2026-05-06-001"
  end

  test "create rejects multiline titles before rendering markdown" do
    root = tmp_root()

    assert {:error, {:invalid_frontmatter, {:multiline, "title"}}} =
             Api.create_ticket(%{title: "Bad\nTitle", body: "Body."},
               tickets_root: root,
               date: ~D[2026-05-06],
               now: "2026-05-06T00:00:00Z"
             )

    refute File.exists?(Path.join(root, "T-2026-05-06-001.md"))
  end

  test "writer ignores stale idle timeout refs" do
    root = tmp_root()
    File.mkdir_p!(root)

    assert {:ok, pid} =
             WriterSupervisor.start_writer("T-2026-05-06-001",
               tickets_root: root,
               idle_timeout: 1_000
             )

    send(pid, {:idle_timeout, make_ref()})
    Process.sleep(20)

    assert Process.alive?(pid)
  end

  defp tmp_root do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-ticket-api-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end

  defp mayor_metadata do
    %{
      "mayor" => %{
        "mode" => "propose",
        "mayor" => "flora",
        "rules_refs" => ["BAB-1503", "COR-1616"],
        "max_children" => 5,
        "allowed_roles" => ["developer", "inspector"],
        "require_human_approval" => true
      }
    }
  end

  defp proposal(ticket_id, proposal_id, titles) do
    %{
      "proposal_id" => proposal_id,
      "root_ticket_id" => ticket_id,
      "summary" => "Split the work.",
      "rules_refs_used" => ["BAB-1503"],
      "children" =>
        Enum.map(titles, fn title ->
          %{
            "title" => title,
            "body" => "Complete #{title}.",
            "type" => "assignment",
            "priority" => "normal",
            "assignee_role" => "developer",
            "inspector" => "user",
            "metadata" => %{}
          }
        end),
      "risks" => ["Keep slices small."],
      "questions" => []
    }
  end

  defp proposal_received(ticket_id, proposal) do
    %{
      "ts" => "2026-05-08T00:01:00Z",
      "event" => "mayor_proposal_received",
      "by" => "flora",
      "ticket_id" => ticket_id,
      "proposal_id" => proposal["proposal_id"],
      "proposal" => proposal
    }
  end

  defp proposal_revision(root, ticket_id) do
    assert {:ok, %{ticket: ticket, history: history}} =
             Api.show_ticket(ticket_id, tickets_root: root)

    assert {:ok, state} = MayorProposalReview.from_history(ticket, history)
    state.revision_token
  end

  defp with_role_catalog(fun) do
    Babs.Citizens.RepoCase.ensure_repo!()
    Babs.Citizens.Repo.delete_all(Babs.Citizens.CitizenRecord)
    config_root = Babs.Citizens.RepoCase.tmp_root!()
    previous_root = Application.get_env(:babs_citizens, :root)
    Application.put_env(:babs_citizens, :root, config_root)

    try do
      fun.(config_root)
    after
      File.rm_rf!(config_root)
      Babs.Citizens.Repo.delete_all(Babs.Citizens.CitizenRecord)

      if previous_root do
        Application.put_env(:babs_citizens, :root, previous_root)
      else
        Application.delete_env(:babs_citizens, :root)
      end
    end
  end

  defp fake_direct_config(slug) do
    %CitizenConfig{
      id: "BAB-CIT-#{String.upcase(slug)}",
      slug: slug,
      display_name: String.capitalize(slug),
      cli: "babs-fake-ai",
      cli_args: [],
      launch_profile: "trusted_autonomous",
      ticket_backend: "direct_cli",
      cwd: tmp_root(),
      env: %{}
    }
  end
end
