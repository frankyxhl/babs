defmodule Babs.Citizens.Tickets.ApiWriterStoreTest do
  use ExUnit.Case, async: false

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.WriterSupervisor

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

    assert {:ok, %{ticket: updated, delivery: :deferred}} =
             Api.comment_ticket(ticket.id, %{body: "Working on it.", by: "clare"},
               tickets_root: root,
               now: "2026-05-06T00:01:00Z"
             )

    assert updated.updated_at == "2026-05-06T00:01:00Z"

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)
    assert Enum.map(history, & &1["event"]) == ["created", "comment"]
    assert List.last(history)["body"] == "Working on it."
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

    assert {:ok, %{ticket: rejected}} =
             Api.transition_ticket(ticket.id, "in_progress", "rejected",
               tickets_root: root,
               now: "2026-05-06T00:04:00Z"
             )

    assert rejected.state == "in_progress"

    assert {:ok, %{ticket: open}} =
             Api.unassign_ticket(ticket.id, "clare",
               tickets_root: root,
               now: "2026-05-06T00:05:00Z"
             )

    assert open.state == "open"
    assert open.assignees == []
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
end
