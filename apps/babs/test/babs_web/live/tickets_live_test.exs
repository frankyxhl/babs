defmodule BabsWeb.TicketsLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Watcher

  @endpoint BabsWeb.Endpoint

  setup do
    ensure_apps!()
    root = tmp_root!()
    previous_root = Application.get_env(:babs_citizens, :tickets_root)
    Application.put_env(:babs_citizens, :tickets_root, root)

    on_exit(fn ->
      File.rm_rf!(root)

      if previous_root do
        Application.put_env(:babs_citizens, :tickets_root, previous_root)
      else
        Application.delete_env(:babs_citizens, :tickets_root)
      end
    end)

    {:ok, root: root}
  end

  test "renders grouped tickets, invalid rows, navigation, and icon-labeled actions", %{
    root: root
  } do
    billboard = create_ticket!(root, "Billboard task", "Ready for pickup.", priority: "urgent")

    open_assigned =
      create_ticket!(root, "Open assigned task", "Still open but assigned manually.",
        state: "open",
        assignees: ["clare"],
        now: "2026-05-06T00:01:00Z"
      )

    in_progress =
      create_ticket!(root, "Assigned task", "Clare is working.",
        state: "in_progress",
        assignees: ["clare"],
        priority: "high",
        now: "2026-05-06T00:02:00Z"
      )

    File.write!(Path.join(root, "T-2026-05-06-099.md"), "not frontmatter")

    {:ok, _view, html} = live(build_conn(), "/tickets?socket_token=token-1")

    assert html =~ ~s(data-testid="tickets-index")
    assert html =~ ~s(data-testid="tickets-nav-citizens")
    assert html =~ ~s(href="/citizens?socket_token=token-1")
    assert html =~ ~s(data-icon="refresh")
    assert html =~ ~s(aria-label="Refresh tickets")

    assert html =~ ~s(data-testid="ticket-group-billboard")
    assert html =~ ~s(data-testid="ticket-row-#{billboard.id}")
    assert html =~ "Billboard task"
    assert html =~ "urgent"
    assert html =~ ~s(href="/tickets/#{billboard.id}?socket_token=token-1")

    assert html =~ ~s(data-testid="ticket-group-open")
    assert html =~ ~s(data-testid="ticket-row-#{open_assigned.id}")
    assert html =~ "Open assigned task"

    assert html =~ ~s(data-testid="ticket-group-in_progress")
    assert html =~ ~s(data-testid="ticket-row-#{in_progress.id}")
    assert html =~ "Assigned task"
    assert html =~ "clare"

    assert html =~ ~s(data-testid="ticket-group-invalid")
    assert html =~ ~s(data-testid="ticket-invalid-row")
    assert html =~ "T-2026-05-06-099.md"
    refute html =~ ~s(href="/tickets/T-2026-05-06-099)
  end

  test "renders empty state when the ticket root has no files" do
    {:ok, _view, html} = live(build_conn(), "/tickets")

    assert html =~ ~s(data-testid="tickets-empty-state")
    assert html =~ "No tickets yet."
  end

  test "renders ticket detail with escaped body, frontmatter, warnings, and history", %{
    root: root
  } do
    ticket =
      create_ticket!(
        root,
        "Inspect detail",
        "Render **markdown** safely.\n\n<script>alert(1)</script>",
        assignees: ["ghost"],
        state: "in_progress",
        known_citizens: ["clare"]
      )

    assert {:ok, _result} =
             Api.comment_ticket(ticket.id, %{body: "Detail comment.", by: "clare"},
               tickets_root: root,
               now: "2026-05-06T00:05:00Z"
             )

    {:ok, _view, html} = live(build_conn(), "/tickets/#{ticket.id}")

    assert html =~ ~s(data-testid="ticket-detail")
    assert html =~ "Inspect detail"
    assert html =~ "in_progress"
    assert html =~ "ghost"
    assert html =~ "unknown citizen: ghost"
    assert html =~ "Render **markdown** safely."
    assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    refute html =~ "<script>alert(1)</script>"
    assert html =~ ~s(data-testid="ticket-history-event")
    assert html =~ "created"
    assert html =~ "comment"
    assert html =~ "Detail comment."
    assert html =~ ~s(data-icon="arrow-left")
    assert html =~ ~s(data-icon="users")
  end

  test "renders controlled error for missing ticket ids" do
    {:ok, _view, html} = live(build_conn(), "/tickets/T-2026-05-06-404")

    assert html =~ ~s(data-testid="ticket-detail-error")
    assert html =~ "Ticket not found"
  end

  test "refreshes list when watcher broadcasts a ticket change", %{root: root} do
    {:ok, view, html} = live(build_conn(), "/tickets")
    assert html =~ ~s(data-testid="tickets-empty-state")

    ticket = create_ticket!(root, "Live refresh", "Appears after PubSub.")

    Phoenix.PubSub.broadcast(Babs.Citizens.PubSub, Watcher.topic(), {:tickets_changed, %{}})

    assert render(view) =~ ~s(data-testid="ticket-row-#{ticket.id}")
  end

  test "refreshes detail when watcher broadcasts a ticket change", %{root: root} do
    ticket = create_ticket!(root, "Before refresh", "Initial detail body.")

    {:ok, view, html} = live(build_conn(), "/tickets/#{ticket.id}")
    assert html =~ "Before refresh"

    ticket_path = Path.join(root, "#{ticket.id}.md")

    File.write!(
      ticket_path,
      ticket_path
      |> File.read!()
      |> String.replace("Before refresh", "After refresh")
      |> String.replace("Initial detail body.", "Updated detail body.")
    )

    Phoenix.PubSub.broadcast(Babs.Citizens.PubSub, Watcher.topic(), {:tickets_changed, %{}})

    html = render(view)
    assert html =~ "After refresh"
    assert html =~ "Updated detail body."
  end

  defp create_ticket!(root, title, body, opts \\ []) do
    attrs =
      opts
      |> Keyword.take([:state, :assignees, :priority])
      |> Enum.into(%{title: title, body: body})

    api_opts =
      opts
      |> Keyword.take([:known_citizens])
      |> Keyword.merge(
        tickets_root: root,
        date: ~D[2026-05-06],
        now: Keyword.get(opts, :now, "2026-05-06T00:00:00Z")
      )

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
        "babs-ticket-web-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end
end
