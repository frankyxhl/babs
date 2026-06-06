defmodule BabsWeb.TicketsLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.History
  alias Babs.Citizens.Tickets.Watcher
  alias Babs.Citizens.{Catalog, CitizenRecord, Repo}

  @endpoint BabsWeb.Endpoint

  setup do
    ensure_apps!()
    root = tmp_root!()
    previous_root = Application.get_env(:babs_citizens, :tickets_root)
    previous_runtime_opts = Application.get_env(:babs_citizens, :ticket_runtime_opts)
    previous_live = Application.get_env(:babs, BabsWeb.TicketsLive)
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

      if previous_runtime_opts do
        Application.put_env(:babs_citizens, :ticket_runtime_opts, previous_runtime_opts)
      else
        Application.delete_env(:babs_citizens, :ticket_runtime_opts)
      end

      if previous_live do
        Application.put_env(:babs, BabsWeb.TicketsLive, previous_live)
      else
        Application.delete_env(:babs, BabsWeb.TicketsLive)
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
    refute html =~ "--bg: #f6f8fa"
    refute html =~ "color-scheme: light"
    refute html =~ "Phoenix.HTML.raw(styles())"
    assert html =~ ~s(data-testid="tickets-new")
    assert html =~ ~s(href="/tickets/new?socket_token=token-1")
    assert html =~ ~s(data-icon="plus")
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

  test "closed group renders as a collapsed details element when count > 0", %{root: root} do
    ticket =
      create_ticket!(root, "Closed ticket title", "Done.",
        state: "pending_approval",
        assignees: ["clare"]
      )

    {:ok, %{ticket: closed}} = Api.approve_ticket(ticket.id, tickets_root: root)

    {:ok, _view, html} = live(build_conn(), "/tickets?socket_token=token-1")

    assert html =~ ~s(<details)
    assert html =~ ~s(data-testid="ticket-group-closed")
    assert html =~ "Closed ticket title"
    assert html =~ ~s(href="/tickets/#{closed.id}?socket_token=token-1")
  end

  test "invalid group is absent when invalid count is zero" do
    {:ok, _view, html} = live(build_conn(), "/tickets")

    refute html =~ ~s(data-testid="ticket-group-invalid")
  end

  test "renders empty state when the ticket root has no files" do
    {:ok, _view, html} = live(build_conn(), "/tickets")

    assert html =~ ~s(data-testid="tickets-empty-state")
    assert html =~ "No tickets yet."
  end

  test "skips remote peer fetch during disconnected render" do
    Application.put_env(:babs, BabsWeb.TicketsLive,
      remote_peer_provider: fn -> raise "remote peer provider should wait for connected mount" end
    )

    html = build_conn() |> get("/tickets") |> html_response(200)

    assert html =~ ~s(data-testid="tickets-index")
    refute html =~ ~s(data-testid="remote-peer-tickets")
  end

  test "renders one read-only remote peer and refreshes remote tickets" do
    {:ok, agent} =
      Agent.start_link(fn ->
        remote_peer(%{
          tickets: [
            %{
              "id" => "T-2026-05-09-101",
              "title" => "Remote ticket one",
              "state" => "open"
            }
          ]
        })
      end)

    Application.put_env(:babs, BabsWeb.TicketsLive,
      remote_peer_provider: fn -> Agent.get(agent, & &1) end
    )

    {:ok, view, _html} = live(build_conn(), "/tickets")
    html = render_async(view, 1_000)

    assert html =~ ~s(data-testid="remote-peer-tickets")
    assert html =~ "Peer Node"
    assert html =~ "Read-only"
    assert html =~ "fresh"
    assert html =~ ~s(data-testid="remote-ticket-T-2026-05-09-101")
    assert html =~ "Remote ticket one"
    refute html =~ ~s(data-testid="remote-ticket-comment-form-T-2026-05-09-101")
    refute html =~ ~s(data-testid="remote-ticket-transition-T-2026-05-09-101")
    refute html =~ ~s(href="/tickets/T-2026-05-09-101")

    Agent.update(agent, fn peer ->
      %{peer | tickets: [%{"id" => "T-2026-05-09-102", "title" => "Remote ticket two"}]}
    end)

    send(view.pid, :refresh_remote_peer)
    html = render_async(view, 1_000)

    assert html =~ ~s(data-testid="remote-ticket-T-2026-05-09-102")
    assert html =~ "Remote ticket two"
    refute html =~ "Remote ticket one"
  end

  test "writable remote peer can comment and transition remote tickets" do
    parent = self()

    Application.put_env(:babs, BabsWeb.TicketsLive,
      remote_peer_provider: fn ->
        remote_peer(%{
          read_only?: false,
          capabilities: ["read", "write"],
          tickets: [
            %{
              "id" => "T-2026-05-09-201",
              "title" => "Remote writable ticket",
              "state" => "in_progress"
            }
          ]
        })
      end,
      remote_ticket_action: fn action, peer, ticket_id, value ->
        send(parent, {:remote_ticket_action, action, peer.peer_id, ticket_id, value})
        {:ok, %{"ok" => true}}
      end
    )

    {:ok, view, _html} = live(build_conn(), "/tickets")
    html = render_async(view, 1_000)

    assert html =~ "Writable"
    assert html =~ ~s(data-testid="remote-ticket-comment-form-T-2026-05-09-201")
    assert html =~ ~s(data-testid="remote-ticket-transition-T-2026-05-09-201")

    view
    |> form(~s([data-testid="remote-ticket-comment-form-T-2026-05-09-201"]),
      ticket_id: "T-2026-05-09-201",
      body: "Remote browser comment"
    )
    |> render_submit()

    assert_receive {:remote_ticket_action, :comment, "peer-a", "T-2026-05-09-201",
                    "Remote browser comment"}

    assert render(view) =~ "Remote comment sent"

    view
    |> form(~s([data-testid="remote-ticket-transition-form-T-2026-05-09-201"]),
      ticket_id: "T-2026-05-09-201",
      to: "pending_approval"
    )
    |> render_submit()

    assert_receive {:remote_ticket_action, :transition, "peer-a", "T-2026-05-09-201",
                    "pending_approval"}

    assert render(view) =~ "Remote transition sent"

    view
    |> form(~s([data-testid="remote-ticket-comment-form-T-2026-05-09-201"]),
      ticket_id: "T-2026-05-09-201",
      body: "   "
    )
    |> render_submit()

    assert render(view) =~ "Remote comment cannot be blank"

    render_submit(view, "remote_ticket_transition", %{
      "ticket_id" => "T-2026-05-09-201",
      "to" => "closed"
    })

    assert render(view) =~ "Remote transition is not available"
  end

  test "GET /tickets/new routes to NewTicketLive before the ticket detail route" do
    {:ok, _view, html} = live(build_conn(), "/tickets/new?socket_token=token-1")

    assert html =~ ~s(data-testid="new-ticket-form")
    assert html =~ ~s(href="/tickets?socket_token=token-1")
    refute html =~ ~s(data-testid="ticket-detail-error")
  end

  test "new ticket form creates a ticket and redirects to detail", %{root: root} do
    with_role_catalog(fn config_root ->
      Babs.Citizens.RepoCase.write_citizen_toml!(config_root, "clare")
      Babs.Citizens.RepoCase.insert_citizen!(%{slug: "clare", roles: ["developer"]})

      {:ok, view, _html} = live(build_conn(), "/tickets/new?socket_token=token-1")

      assert {:error, {:redirect, %{to: to}}} =
               view
               |> form("[data-testid='new-ticket-form']",
                 ticket: %{
                   title: "UI new ticket",
                   body: "Created from the browser.",
                   priority: "high",
                   assignee_role: "developer"
                 }
               )
               |> render_submit()

      assert to =~ ~r(\A/tickets/T-\d{4}-\d{2}-\d{2}-\d{3}\?socket_token=token-1\z)

      id =
        to
        |> URI.parse()
        |> Map.fetch!(:path)
        |> Path.basename()

      assert File.exists?(Path.join(root, "#{id}.md"))
      assert {:ok, %{ticket: ticket}} = Api.show_ticket(id, tickets_root: root)
      assert ticket.title == "UI new ticket"
      assert ticket.body == "Created from the browser."
      assert ticket.priority == "high"
      assert ticket.assignee_role == "developer"
    end)
  end

  test "new ticket form lists known role labels from non-stale citizens" do
    with_role_catalog(fn config_root ->
      Babs.Citizens.RepoCase.write_citizen_toml!(config_root, "clare")
      Babs.Citizens.RepoCase.insert_citizen!(%{slug: "clare", roles: ["developer"]})
      Babs.Citizens.RepoCase.insert_citizen!(%{slug: "json", roles: ["json-only"]})

      {:ok, _view, html} = live(build_conn(), "/tickets/new")

      assert html =~ ~s(data-testid="ticket-assignee-role")
      assert html =~ ~s(value="developer")
      refute html =~ ~s(value="json-only")
    end)
  end

  test "new ticket form renders blank field validation without creating a file", %{root: root} do
    {:ok, view, _html} = live(build_conn(), "/tickets/new")

    html =
      view
      |> form("[data-testid='new-ticket-form']",
        ticket: %{title: " ", body: "", priority: "normal"}
      )
      |> render_submit()

    assert html =~ ~s(data-testid="title-error")
    assert html =~ ~s(data-testid="body-error")
    assert File.ls!(root) == []
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

    assert :ok =
             History.append(root, ticket.id, %{
               "ts" => "2026-05-06T00:06:00Z",
               "event" => "comment",
               "by" => "clare",
               "body" => "Legacy comment without ticket_id."
             })

    {:ok, _view, html} = live(build_conn(), "/tickets/#{ticket.id}")

    assert html =~ ~s(data-testid="ticket-detail")
    refute html =~ "Phoenix.HTML.raw(styles())"
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
    assert html =~ "Legacy comment without ticket_id."
    assert html =~ ~s(data-testid="ticket-detail-chat")
    assert html =~ ~s(data-testid="ticket-chat-message")
    assert html =~ ~s(class="meta")
    assert html =~ "clare"
    assert html =~ ~s(data-icon="arrow-left")
    assert html =~ ~s(data-icon="users")
  end

  test "ticket detail renders multi-turn chat messages with delivery status", %{root: root} do
    Babs.Citizens.RepoCase.insert_citizen!(%{slug: "clare", display_name: "Clare"})
    Babs.Citizens.RepoCase.insert_citizen!(%{slug: "dylan", display_name: "Dylan"})

    ticket =
      create_ticket!(root, "Multi-turn detail", "Initial assignment body.",
        state: "in_progress",
        assignees: ["clare", "dylan"]
      )

    assert {:ok, %{delivery: {:comment_notification_failed, ["clare"], [{"dylan", _reason}]}}} =
             Api.comment_ticket(ticket.id, %{body: "Please take a second pass.", by: "user"},
               tickets_root: root,
               now: "2026-05-07T10:01:00Z",
               citizen_fetcher: fn slug when slug in ["clare", "dylan"] -> %{slug: slug} end,
               pane_lookup: fn slug when slug in ["clare", "dylan"] -> {:ok, self()} end,
               pane_injector: fn
                 "clare", _prompt -> :ok
                 "dylan", _prompt -> {:error, :pane_closed}
               end
             )

    {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)
    user_message = Enum.find(history, &(&1["event"] == "comment" and &1["by"] == "user"))
    clare_attempt = Enum.find(history, &(&1["event"] == "turn_delivered" and &1["to"] == "clare"))

    assert {:ok, %{delivery: :comment_stored}} =
             Api.comment_ticket(
               ticket.id,
               %{
                 body: "Clare reply for the second pass.",
                 by: "clare",
                 turn_id: user_message["turn_id"],
                 attempt_id: clare_attempt["attempt_id"]
               },
               tickets_root: root,
               now: "2026-05-07T10:02:00Z",
               notify_assignees: false
             )

    assert :ok =
             History.append(root, ticket.id, %{
               "ts" => "2026-05-07T10:03:00Z",
               "event" => "comment",
               "by" => "dylan",
               "body" => "Legacy reply without turn id."
             })

    {:ok, _view, html} = live(build_conn(), "/tickets/#{ticket.id}?socket_token=token-1")

    assert html =~ ~s(data-testid="ticket-detail-chat")
    assert html =~ ~s(data-testid="ticket-chat-message")
    assert html =~ ~s(data-testid="ticket-turn-status")
    assert html =~ "Please take a second pass."
    assert html =~ "Clare reply for the second pass."
    assert html =~ "Legacy reply without turn id."
    assert html =~ "delivered"
    assert html =~ "captured"
    assert html =~ "failed"
    assert html =~ ~s(data-testid="ticket-retry-delivery")
    assert html =~ ~s(data-testid="ticket-open-terminal")
    assert html =~ ~s(href="/tickets?socket_token=token-1")
    refute html =~ "<style>"
  end

  test "ticket detail renders a chat empty state when there are no comments", %{root: root} do
    ticket = create_ticket!(root, "No comments", "No chat yet.")

    {:ok, _view, html} = live(build_conn(), "/tickets/#{ticket.id}")

    assert html =~ ~s(data-testid="ticket-comments-empty")
    assert html =~ "No comments yet."
  end

  test "renders controlled error for missing ticket ids" do
    {:ok, _view, html} = live(build_conn(), "/tickets/T-2026-05-06-404")

    assert html =~ ~s(data-testid="ticket-detail-error")
    assert html =~ ~s(href="/css/app.css")
    refute html =~ "--bg: #0d0d10"
    refute html =~ "Phoenix.HTML.raw(styles())"
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

  test "assign action injects prompt and exposes legal transition controls", %{root: root} do
    parent = self()

    Babs.Citizens.RepoCase.insert_citizen!(%{
      slug: "clare",
      display_name: "Clare",
      ticket_backend: "hardline"
    })

    Babs.Citizens.RepoCase.insert_citizen!(%{
      slug: "dylan",
      display_name: "Dylan",
      ticket_backend: "direct_cli"
    })

    Application.put_env(:babs_citizens, :ticket_runtime_opts,
      citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
      pane_lookup: fn "clare" -> {:ok, self()} end,
      pane_injector: fn "clare", prompt ->
        send(parent, {:injected, prompt})
        :ok
      end
    )

    ticket = create_ticket!(root, "Assignable", "Send this to Clare.")

    {:ok, view, html} = live(build_conn(), "/tickets/#{ticket.id}?socket_token=token-1")
    assert html =~ ~s(data-testid="ticket-assign-clare")
    assert html =~ ~s(data-testid="ticket-assign-dylan")
    assert html =~ ~s(data-icon="user-plus")
    assert html =~ "Hardline"
    assert html =~ "starts tmux if stopped"
    assert html =~ "Direct CLI"
    assert html =~ "no tmux start"

    view
    |> element(~s(button[data-testid="ticket-assign-clare"]))
    |> render_click()

    assert_receive {:injected, prompt}
    assert prompt =~ "Send this to Clare."

    html = render_async(view, 1_000)
    assert html =~ "Assigned to clare"
    assert html =~ "in_progress"
    assert html =~ ~s(data-testid="ticket-transition-pending_approval")
    assert html =~ ~s(data-testid="ticket-unassign-clare")
    assert html =~ ~s(data-icon="route")
    assert html =~ ~s(data-icon="undo")
  end

  test "role route action assigns through assignee_role", %{root: root} do
    parent = self()

    with_role_catalog(fn config_root ->
      Babs.Citizens.RepoCase.write_citizen_toml!(config_root, "clare")

      Babs.Citizens.RepoCase.insert_citizen!(%{
        slug: "clare",
        display_name: "Clare",
        ticket_backend: "hardline",
        roles: ["developer"]
      })

      Application.put_env(:babs_citizens, :ticket_runtime_opts,
        citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
        pane_lookup: fn "clare" -> {:ok, self()} end,
        pane_injector: fn "clare", prompt ->
          send(parent, {:role_injected, prompt})
          :ok
        end
      )

      ticket =
        create_ticket!(root, "Role assignable", "Route this by role.", assignee_role: "developer")

      {:ok, view, html} = live(build_conn(), "/tickets/#{ticket.id}")
      assert html =~ ~s(data-testid="ticket-assign-role-developer")
      assert html =~ ~s(data-icon="route")

      view
      |> element(~s(button[data-testid="ticket-assign-role-developer"]))
      |> render_click()

      assert_receive {:role_injected, prompt}
      assert prompt =~ "Route this by role."

      html = render_async(view, 1_000)
      assert html =~ "Assigned by role developer"
      assert html =~ ~s(data-testid="ticket-unassign-clare")
      assert html =~ "assigned to clare via role developer"
    end)
  end

  test "ticket assignment options exclude stale SQLite-only citizens", %{root: root} do
    config_root = Babs.Citizens.RepoCase.tmp_root!()
    previous_babs_root = Application.get_env(:babs_citizens, :root)

    Application.put_env(:babs_citizens, :root, config_root)

    on_exit(fn ->
      File.rm_rf!(config_root)

      if previous_babs_root do
        Application.put_env(:babs_citizens, :root, previous_babs_root)
      else
        Application.delete_env(:babs_citizens, :root)
      end
    end)

    Babs.Citizens.RepoCase.write_citizen_toml!(config_root, "clare")

    Babs.Citizens.RepoCase.insert_citizen!(%{
      slug: "clare",
      display_name: "Clare",
      ticket_backend: "hardline"
    })

    Babs.Citizens.RepoCase.insert_citizen!(%{
      slug: "json",
      display_name: "Json",
      ticket_backend: "direct_cli",
      status: "stopped"
    })

    external =
      Babs.Citizens.RepoCase.insert_citizen!(%{
        slug: "external",
        display_name: "External",
        ticket_backend: "hardline"
      })

    assert {:ok, _external} =
             Catalog.mark_imported_external(external, %{
               session_name: "operator-session",
               window_index: "0",
               pane_index: "0",
               pane_id: "%42"
             })

    ticket = create_ticket!(root, "Assignable", "Only real Citizens should be assignable.")

    {:ok, view, html} = live(build_conn(), "/tickets/#{ticket.id}")

    assert html =~ ~s(data-testid="ticket-assign-clare")
    assert html =~ ~s(data-testid="ticket-assign-external")
    refute html =~ ~s(data-testid="ticket-assign-json")
    refute html =~ "Json"

    render_click(view, "assign", %{"slug" => "json"})
    html = render_async(view, 1_000)

    assert html =~ "Unknown Citizen: json"
    assert {:ok, %{ticket: ticket}} = Api.show_ticket(ticket.id, tickets_root: root)
    assert ticket.state == "open"
    assert ticket.assignees == []

    stale_ticket =
      create_ticket!(root, "Stale assignment", "This row is no longer backed by TOML.",
        state: "in_progress",
        assignees: ["json"]
      )

    {:ok, _view, html} = live(build_conn(), "/tickets/#{stale_ticket.id}")

    assert html =~ "unknown citizen: json"
    refute html =~ ~s(data-testid="ticket-assign-json")
  end

  test "comment action stores history and notifies assignees", %{root: root} do
    parent = self()
    Babs.Citizens.RepoCase.insert_citizen!(%{slug: "clare", display_name: "Clare"})

    Application.put_env(:babs_citizens, :ticket_runtime_opts,
      citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
      pane_lookup: fn "clare" -> {:ok, self()} end,
      pane_injector: fn "clare", prompt ->
        send(parent, {:comment_prompt, prompt})
        :ok
      end
    )

    ticket =
      create_ticket!(root, "Commentable detail", "Send notes to Clare.",
        state: "in_progress",
        assignees: ["clare"]
      )

    {:ok, view, html} = live(build_conn(), "/tickets/#{ticket.id}")
    assert html =~ ~s(data-testid="ticket-comment-form")
    assert html =~ ~s(data-icon="send")

    view
    |> form(~s(form[data-testid="ticket-comment-form"]), %{body: ""})
    |> render_submit()

    assert render(view) =~ "Comment body is required"

    view
    |> form(~s(form[data-testid="ticket-comment-form"]), %{body: "Operator note."})
    |> render_submit()

    html = render_async(view, 1_000)
    assert html =~ "Comment stored"
    assert html =~ "Operator note."
    assert_receive {:comment_prompt, prompt}
    assert prompt =~ "Operator note."
  end

  test "comment action warns when notification fails but keeps stored history", %{root: root} do
    Babs.Citizens.RepoCase.insert_citizen!(%{slug: "clare", display_name: "Clare"})

    Application.put_env(:babs_citizens, :ticket_runtime_opts,
      citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
      pane_lookup: fn "clare" -> {:ok, self()} end,
      pane_injector: fn "clare", _prompt -> {:error, %{api_token: "fixture-value"}} end
    )

    ticket =
      create_ticket!(root, "Comment failure detail", "Keep stored comments.",
        state: "in_progress",
        assignees: ["clare"]
      )

    {:ok, view, _html} = live(build_conn(), "/tickets/#{ticket.id}")

    view
    |> form(~s(form[data-testid="ticket-comment-form"]), %{body: "Stored despite failure."})
    |> render_submit()

    html = render_async(view, 1_000)
    assert html =~ "Comment stored; notification failed for clare"
    assert html =~ "Stored despite failure."
    refute html =~ "fixture-value"
  end

  test "transition and unassign actions show only legal phase controls", %{root: root} do
    parent = self()
    Babs.Citizens.RepoCase.insert_citizen!(%{slug: "clare", display_name: "Clare"})

    Application.put_env(:babs_citizens, :ticket_runtime_opts,
      citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
      pane_lookup: fn "clare" -> {:ok, self()} end,
      pane_injector: fn "clare", prompt ->
        send(parent, {:feedback, prompt})
        :ok
      end
    )

    ticket =
      create_ticket!(root, "Transitionable", "Move through states.",
        state: "in_progress",
        assignees: ["clare"]
      )

    {:ok, view, html} = live(build_conn(), "/tickets/#{ticket.id}")
    assert html =~ ~s(data-testid="ticket-transition-pending_approval")
    assert html =~ ~s(data-testid="ticket-unassign-clare")

    view
    |> element(~s(button[data-testid="ticket-transition-pending_approval"]))
    |> render_click()

    html = render_async(view, 1_000)
    assert html =~ "Moved to pending_approval"
    assert html =~ "pending_approval"
    refute html =~ ~s(data-testid="ticket-unassign-clare")
    assert html =~ ~s(data-testid="ticket-approve")
    assert html =~ ~s(data-testid="ticket-reject-form")
    assert html =~ ~s(data-icon="check")
    assert html =~ ~s(data-icon="x")
    assert html =~ ~s(data-testid="ticket-transition-cancelled")

    assert {:error, {:invalid_transition, "pending_approval", "open"}} =
             Api.unassign_ticket(ticket.id, "clare", tickets_root: root)

    view
    |> form(~s(form[data-testid="ticket-reject-form"]), %{feedback: ""})
    |> render_submit()

    assert render(view) =~ "Rejection feedback is required"

    view
    |> form(~s(form[data-testid="ticket-reject-form"]), %{feedback: "Add docs."})
    |> render_submit()

    html = render_async(view, 1_000)
    assert html =~ "Rejected ticket"
    assert html =~ "in_progress"
    assert html =~ "Add docs."
    assert html =~ ~s(data-testid="ticket-unassign-clare")
    assert_receive {:feedback, prompt}
    assert prompt =~ "Add docs."
  end

  test "pending approval detail renders assignee git diff and still approves", %{root: root} do
    workspace = tmp_git_workspace!()

    Babs.Citizens.RepoCase.insert_citizen!(%{
      slug: "clare",
      display_name: "Clare",
      cwd: workspace
    })

    ticket =
      create_ticket!(root, "Review diff", "Approve after reading the diff.",
        state: "pending_approval",
        assignees: ["clare"]
      )

    {:ok, view, html} = live(build_conn(), "/tickets/#{ticket.id}")

    assert html =~ ~s(data-testid="ticket-review-diff")
    assert html =~ ~s(data-testid="git-diff-component")
    assert html =~ "README.md"
    assert html =~ "new line"
    assert html =~ ~s(data-line-kind="addition")
    assert html =~ ~s(data-testid="ticket-approve")
    assert html =~ ~s(data-testid="ticket-reject-form")

    view
    |> element(~s(button[data-testid="ticket-approve"]))
    |> render_click()

    html = render_async(view, 1_000)
    assert html =~ "Approved ticket"
    assert html =~ "closed"
    refute html =~ ~s(data-testid="ticket-review-diff")
  end

  test "non approval detail does not render or fetch the assignee git diff", %{root: root} do
    missing_workspace = Path.join(root, "missing-workspace")

    Babs.Citizens.RepoCase.insert_citizen!(%{
      slug: "clare",
      display_name: "Clare",
      cwd: missing_workspace
    })

    ticket =
      create_ticket!(root, "Working ticket", "Do not fetch diff yet.",
        state: "in_progress",
        assignees: ["clare"]
      )

    {:ok, _view, html} = live(build_conn(), "/tickets/#{ticket.id}")

    refute html =~ ~s(data-testid="ticket-review-diff")
    refute html =~ ~s(data-testid="git-diff-error")
    refute html =~ "Workspace is unavailable"
  end

  test "pending approval detail renders inline git resolution errors", %{root: root} do
    workspace = Path.join(root, "not-a-repo")
    File.mkdir_p!(workspace)

    Babs.Citizens.RepoCase.insert_citizen!(%{
      slug: "clare",
      display_name: "Clare",
      cwd: workspace
    })

    ticket =
      create_ticket!(root, "Broken workspace", "Show an inline diff error.",
        state: "pending_approval",
        assignees: ["clare"]
      )

    {:ok, _view, html} = live(build_conn(), "/tickets/#{ticket.id}")

    assert html =~ ~s(data-testid="ticket-review-diff")
    assert html =~ ~s(data-testid="git-diff-error")
    assert html =~ "Workspace is not a git repository"
    assert html =~ ~s(data-testid="ticket-approve")
    assert html =~ ~s(data-testid="ticket-reject-form")
  end

  test "approve action closes pending approval ticket", %{root: root} do
    Babs.Citizens.RepoCase.insert_citizen!(%{slug: "clare", display_name: "Clare"})

    ticket =
      create_ticket!(root, "Approvable", "Close this.",
        state: "pending_approval",
        assignees: ["clare"]
      )

    {:ok, view, html} = live(build_conn(), "/tickets/#{ticket.id}")
    assert html =~ ~s(data-testid="ticket-inspection-panel")
    assert html =~ "Human approval"
    assert html =~ ~s(data-testid="ticket-approve")
    assert html =~ ~s(data-testid="ticket-reject-form")

    view
    |> element(~s(button[data-testid="ticket-approve"]))
    |> render_click()

    html = render_async(view, 1_000)
    assert html =~ "Approved ticket"
    assert html =~ "closed"
    refute html =~ ~s(data-testid="ticket-approve")
    refute html =~ ~s(data-testid="ticket-reject-form")
    refute html =~ ~s(data-testid="ticket-comment-form")
  end

  test "ticket detail renders inspection council status and keeps human override controls", %{
    root: root
  } do
    ticket =
      create_ticket!(root, "Council inspection", "Show inspector verdicts.",
        state: "pending_approval",
        assignees: ["clare"],
        metadata: %{
          "inspection" => %{
            "mode" => "auto",
            "strategy" => "council",
            "roles" => ["inspector"],
            "citizens" => ["dylan", "elena"],
            "quorum" => "all_pass",
            "max_inspectors" => 2,
            "allow_self_inspection" => false
          }
        }
      )

    :ok =
      Api.append_ticket_events(
        ticket.id,
        [
          %{
            "ts" => "2026-05-06T00:01:00Z",
            "event" => "inspection_requested",
            "by" => "system",
            "ticket_id" => ticket.id,
            "inspection_id" => "insp_20260506000100_1",
            "policy" => %{"mode" => "auto", "strategy" => "council", "quorum" => "all_pass"},
            "inspectors" => ["dylan", "elena"]
          },
          %{
            "ts" => "2026-05-06T00:02:00Z",
            "event" => "inspection_decision",
            "by" => "dylan",
            "ticket_id" => ticket.id,
            "inspection_id" => "insp_20260506000100_1",
            "decision" => "approve",
            "summary" => "Dylan approves.",
            "findings" => []
          },
          %{
            "ts" => "2026-05-06T00:03:00Z",
            "event" => "inspection_decision",
            "by" => "elena",
            "ticket_id" => ticket.id,
            "inspection_id" => "insp_20260506000100_1",
            "decision" => "needs_changes",
            "summary" => "Add release notes.",
            "findings" => [%{"path" => "README.md", "line" => 12}]
          },
          %{
            "ts" => "2026-05-06T00:04:00Z",
            "event" => "inspection_completed",
            "by" => "system",
            "ticket_id" => ticket.id,
            "inspection_id" => "insp_20260506000100_1",
            "result" => "rejected",
            "quorum" => "all_pass"
          }
        ],
        tickets_root: root
      )

    {:ok, _view, html} = live(build_conn(), "/tickets/#{ticket.id}")

    assert html =~ ~s(data-testid="ticket-inspection-panel")
    assert html =~ ~s(data-testid="ticket-inspection-mode")
    assert html =~ "Auto council"
    assert html =~ "all_pass"
    assert html =~ "rejected"
    assert html =~ ~s(data-testid="ticket-inspector-dylan")
    assert html =~ "Dylan approves."
    assert html =~ ~s(data-testid="ticket-inspector-elena")
    assert html =~ "Needs changes"
    assert html =~ "Add release notes."
    assert html =~ "README.md:12"
    assert html =~ ~s(data-testid="ticket-approve")
    assert html =~ ~s(data-testid="ticket-reject-form")
  end

  test "ticket detail renders mayor awaiting state for opted-in missions", %{root: root} do
    ticket =
      create_ticket!(root, "Mayor mission", "Ask a Mayor to split this.",
        type: "mission",
        metadata: mayor_metadata()
      )

    {:ok, _view, html} = live(build_conn(), "/tickets/#{ticket.id}")

    assert html =~ ~s(data-testid="ticket-proposal-panel")
    assert html =~ ~s(data-testid="ticket-proposal-awaiting")
    assert html =~ "Awaiting Mayor proposal"
    assert html =~ "flora"
    assert html =~ "BAB-1503"
    refute html =~ ~s(data-testid="ticket-proposal-approve")
  end

  test "ticket detail edits removes and approves a mayor proposal into linked child tickets", %{
    root: root
  } do
    ticket =
      create_ticket!(root, "Mayor proposal mission", "Review the Mayor proposal.",
        type: "mission",
        metadata: mayor_metadata()
      )

    proposal = proposal(ticket.id, "prop_ui", ["Build backend", "Build UI"])

    assert :ok =
             Api.append_ticket_events(ticket.id, [proposal_received(ticket.id, proposal)],
               tickets_root: root
             )

    {:ok, view, html} = live(build_conn(), "/tickets/#{ticket.id}")

    assert html =~ ~s(data-testid="ticket-proposal-panel")
    assert html =~ ~s(data-testid="ticket-proposal-tree")
    assert html =~ ~s(data-testid="ticket-proposal-child-0")
    assert html =~ "Build backend"
    assert html =~ "Build UI"
    assert html =~ ~s(name="proposal_revision")
    assert html =~ ~s(data-icon="git-branch")
    assert html =~ ~s(data-icon="edit")
    assert html =~ ~s(data-icon="trash")
    assert html =~ ~s(data-icon="check")

    view
    |> form(~s(form[data-testid="ticket-proposal-edit-0"]),
      child: %{
        title: "Build API",
        body: "Implement the API.",
        assignee_role: "developer",
        priority: "high",
        inspector: "auto"
      }
    )
    |> render_submit()

    html = render_async(view, 1_000)
    assert html =~ "Updated proposed child 1"
    assert html =~ "Build API"
    assert html =~ "high"
    assert html =~ "auto"

    view
    |> element(~s(button[data-testid="ticket-proposal-remove-1"]))
    |> render_click()

    html = render_async(view, 1_000)
    assert html =~ "Removed proposed child 2"
    refute html =~ "Build UI"

    view
    |> element(~s(button[data-testid="ticket-proposal-approve"]))
    |> render_click()

    html = render_async(view, 1_000)
    assert html =~ "Approved proposal"
    assert html =~ "approved"
    assert html =~ ~s(data-testid="ticket-proposal-created")
    assert html =~ "Created child Tickets"
    assert html =~ "Build API"
    assert html =~ "routing failed"
    refute html =~ ~s(data-testid="ticket-proposal-edit-0")
    refute html =~ ~s(data-testid="ticket-proposal-remove-0")

    assert [child_file, root_file] =
             root
             |> Path.join("*.md")
             |> Path.wildcard()
             |> Enum.reject(&(Path.basename(&1) == "#{ticket.id}.md"))
             |> Kernel.++([Path.join(root, "#{ticket.id}.md")])

    assert Path.basename(root_file) == "#{ticket.id}.md"
    child_id = Path.basename(child_file, ".md")
    assert html =~ ~s(href="/tickets/#{child_id}")

    assert {:ok, %{ticket: child}} = Api.show_ticket(child_id, tickets_root: root)
    assert child.parent_ticket == ticket.id
    assert child.assigner == "mayor:flora"
  end

  test "ticket detail shows proposal validation errors and rejects proposals", %{root: root} do
    ticket =
      create_ticket!(root, "Mayor reject mission", "Reject or edit the proposal.",
        type: "mission",
        metadata: mayor_metadata()
      )

    proposal = proposal(ticket.id, "prop_reject", ["Build backend"])

    assert :ok =
             Api.append_ticket_events(ticket.id, [proposal_received(ticket.id, proposal)],
               tickets_root: root
             )

    {:ok, view, _html} = live(build_conn(), "/tickets/#{ticket.id}")

    view
    |> form(~s(form[data-testid="ticket-proposal-edit-0"]),
      child: %{
        title: " ",
        body: "Still body.",
        assignee_role: "developer",
        priority: "normal",
        inspector: "user"
      }
    )
    |> render_submit()

    assert render_async(view, 1_000) =~ "Invalid proposal edit"

    view
    |> form(~s(form[data-testid="ticket-proposal-reject-form"]), %{
      feedback: "Needs a smaller slice."
    })
    |> render_submit()

    html = render_async(view, 1_000)
    assert html =~ "Rejected proposal"
    assert html =~ "Needs a smaller slice."
    assert html =~ "rejected"
    refute html =~ ~s(data-testid="ticket-proposal-approve")
  end

  test "ticket detail rejects stale proposal revision submissions", %{root: root} do
    ticket =
      create_ticket!(root, "Mayor stale mission", "Reject stale proposal edits.",
        type: "mission",
        metadata: mayor_metadata()
      )

    proposal = proposal(ticket.id, "prop_stale", ["Build backend", "Build UI"])

    assert :ok =
             Api.append_ticket_events(ticket.id, [proposal_received(ticket.id, proposal)],
               tickets_root: root
             )

    {:ok, view, html} = live(build_conn(), "/tickets/#{ticket.id}")
    assert html =~ ~s(name="proposal_revision")

    assert {:ok, %{event: _revision}} =
             Api.revise_mayor_proposal_child(ticket.id, "prop_stale", 0, %{title: "Fresh API"},
               tickets_root: root
             )

    view
    |> form(~s(form[data-testid="ticket-proposal-edit-0"]),
      child: %{
        title: "Stale API",
        body: "This form came from an older browser state.",
        assignee_role: "developer",
        priority: "normal",
        inspector: "user"
      }
    )
    |> render_submit()

    assert render_async(view, 1_000) =~ "Mayor proposal changed; refresh before editing again"
  end

  defp create_ticket!(root, title, body, opts \\ []) do
    attrs =
      opts
      |> Keyword.take([:type, :state, :assignees, :priority, :assignee_role, :metadata])
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

  defp tmp_git_workspace! do
    workspace =
      Path.join([
        System.tmp_dir!(),
        "babs-ticket-git-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(workspace)
    File.mkdir_p!(workspace)

    git!(workspace, ["init"])
    git!(workspace, ["config", "user.email", "babs@example.test"])
    git!(workspace, ["config", "user.name", "Babs Test"])

    File.write!(Path.join(workspace, "README.md"), "old line\n")
    git!(workspace, ["add", "README.md"])
    git!(workspace, ["commit", "-m", "Initial commit"])

    File.write!(Path.join(workspace, "README.md"), "old line\nnew line\n")
    workspace
  end

  defp git!(workspace, args) do
    {output, status} = System.cmd("git", args, cd: workspace, stderr_to_stdout: true)

    if status != 0 do
      raise "git #{Enum.join(args, " ")} failed: #{output}"
    end

    output
  end

  defp with_role_catalog(fun) do
    config_root = Babs.Citizens.RepoCase.tmp_root!()
    previous_root = Application.get_env(:babs_citizens, :root)
    Application.put_env(:babs_citizens, :root, config_root)

    try do
      fun.(config_root)
    after
      File.rm_rf!(config_root)

      if previous_root do
        Application.put_env(:babs_citizens, :root, previous_root)
      else
        Application.delete_env(:babs_citizens, :root)
      end
    end
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

  defp remote_peer(attrs) do
    Map.merge(
      %{
        peer_id: "peer-a",
        peer_name: "Peer Node",
        peer_url: "http://babs-peer.example:4000",
        status: :fresh,
        read_only?: true,
        capabilities: ["read"],
        citizen_capabilities: %{},
        fetched_at: ~U[2026-05-09 00:00:00Z],
        node: %{"id" => "peer-a", "name" => "Peer Node"},
        citizens: [],
        tickets: [],
        invalid: %{"count" => 0},
        events: [],
        cursor: "cursor"
      },
      attrs
    )
  end
end
