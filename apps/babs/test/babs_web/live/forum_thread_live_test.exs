defmodule BabsWeb.ForumThreadLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Watcher
  alias Babs.Citizens.{Repo, CitizenRecord}

  @endpoint BabsWeb.Endpoint

  setup do
    ensure_apps!()
    root = tmp_root!()
    previous_root = Application.get_env(:babs_citizens, :tickets_root)
    Application.put_env(:babs_citizens, :tickets_root, root)
    Babs.Citizens.RepoCase.ensure_repo!()
    Repo.delete_all(CitizenRecord)

    on_exit(fn ->
      File.rm_rf!(root)
      Repo.delete_all(CitizenRecord)

      if previous_root do
        Application.put_env(:babs_citizens, :tickets_root, previous_root)
      else
        Application.delete_env(:babs_citizens, :tickets_root)
      end
    end)

    {:ok, root: root}
  end

  test "renders ticket title as post header and nested comment tree", %{root: root} do
    ticket = create_ticket!(root, "Threaded Discussion", "Topic body.")

    history = threaded_history(ticket.id)

    Enum.each(history, fn event ->
      :ok = Babs.Citizens.Tickets.History.append(root, ticket.id, event)
    end)

    {:ok, _view, html} = live(build_conn(), "/forum/#{ticket.id}")

    assert html =~ "Threaded Discussion"
    assert html =~ ~s(data-testid="forum-thread")
    assert html =~ ~s(data-testid="forum-comment")
    assert html =~ "Parent comment"
    assert html =~ "Child reply"
    assert html =~ ~s(data-testid="forum-role-badge")
  end

  test "child comment is nested under parent (depth > 0)", %{root: root} do
    ticket = create_ticket!(root, "Nesting Test", "Body.")

    history = threaded_history(ticket.id)

    Enum.each(history, fn event ->
      :ok = Babs.Citizens.Tickets.History.append(root, ticket.id, event)
    end)

    {:ok, _view, html} = live(build_conn(), "/forum/#{ticket.id}")

    assert html =~ ~s(data-testid="forum-comment-depth-0")
    assert html =~ ~s(data-testid="forum-comment-depth-1")
  end

  test "both authors (user and citizen) are shown with role badges", %{root: root} do
    ticket = create_ticket!(root, "Author Test", "Body.")

    history = threaded_history(ticket.id)

    Enum.each(history, fn event ->
      :ok = Babs.Citizens.Tickets.History.append(root, ticket.id, event)
    end)

    {:ok, _view, html} = live(build_conn(), "/forum/#{ticket.id}")

    assert html =~ "user"
    assert html =~ "clare"
  end

  test "tickets_changed broadcast triggers re-render with new comment", %{root: root} do
    ticket = create_ticket!(root, "Live Update Test", "Body.")

    {:ok, view, html} = live(build_conn(), "/forum/#{ticket.id}")
    refute html =~ "After broadcast comment"

    :ok =
      Babs.Citizens.Tickets.History.append(root, ticket.id, %{
        "ts" => "2026-06-01T10:01:00Z",
        "event" => "comment",
        "by" => "user",
        "body" => "After broadcast comment",
        "message_id" => "msg_broadcast_1"
      })

    Phoenix.PubSub.broadcast(Babs.Citizens.PubSub, Watcher.topic(), {:tickets_changed, %{}})

    assert render(view) =~ "After broadcast comment"
  end

  test "renders read-only with no composer/input", %{root: root} do
    ticket = create_ticket!(root, "Read Only Forum", "No input.")

    {:ok, _view, html} = live(build_conn(), "/forum/#{ticket.id}")

    refute html =~ ~s(<form)
    refute html =~ ~s(<textarea)
    refute html =~ ~s(<input type="text")
  end

  defp threaded_history(ticket_id) do
    [
      %{
        "ts" => "2026-06-01T10:00:00Z",
        "event" => "turn_created",
        "by" => "user",
        "ticket_id" => ticket_id,
        "turn_id" => "turn_parent_1"
      },
      %{
        "ts" => "2026-06-01T10:00:01Z",
        "event" => "comment",
        "by" => "user",
        "ticket_id" => ticket_id,
        "message_id" => "msg_parent_1",
        "turn_id" => "turn_parent_1",
        "body" => "Parent comment"
      },
      %{
        "ts" => "2026-06-01T10:00:02Z",
        "event" => "turn_created",
        "by" => "clare",
        "ticket_id" => ticket_id,
        "turn_id" => "turn_child_1",
        "parent_turn_id" => "turn_parent_1"
      },
      %{
        "ts" => "2026-06-01T10:00:03Z",
        "event" => "comment",
        "by" => "clare",
        "ticket_id" => ticket_id,
        "message_id" => "msg_child_1",
        "turn_id" => "turn_child_1",
        "body" => "Child reply"
      }
    ]
  end

  defp create_ticket!(root, title, body, opts \\ []) do
    attrs = Enum.into(opts, %{title: title, body: body})

    api_opts =
      [
        tickets_root: root,
        date: ~D[2026-06-01],
        now: "2026-06-01T10:00:00Z"
      ]

    {:ok, ticket} = Api.create_ticket(attrs, api_opts)
    ticket
  end

  defp ensure_apps! do
    {:ok, _apps} = Application.ensure_all_started(:babs)
  end

  defp tmp_root! do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-forum-thread-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end
end
