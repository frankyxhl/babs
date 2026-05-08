defmodule BabsWeb.Api.V1.ControlControllerTest do
  use Babs.Citizens.RepoCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

  alias Babs.Citizens.Federation.Audit
  alias Babs.Citizens.Tickets.Api, as: TicketApi
  alias Babs.Citizens.Tickets.History
  alias BabsWeb.Api.V1.ControlController

  @endpoint BabsWeb.Endpoint

  setup do
    root = tmp_root!()
    workspace_root = Path.join(root, "workspaces")
    tickets_root = Path.join(root, "tickets")
    File.mkdir_p!(workspace_root)
    File.mkdir_p!(tickets_root)

    config_path = Path.join(root, "federation.toml")

    File.write!(config_path, """
    [node]
    id = "local"
    name = "Local"

    [peers.workbench]
    name = "Workbench"
    url = "http://workbench.example"
    capabilities = ["control"]

    [peers.workbench.citizens.readonly-clare]
    capabilities = ["read"]

    [peers.viewer]
    name = "Viewer"
    url = "http://viewer.example"
    capabilities = ["read"]
    """)

    previous_root = Application.get_env(:babs_citizens, :root)
    previous_workspace_root = Application.get_env(:babs_citizens, :workspace_root)
    previous_tickets_root = Application.get_env(:babs_citizens, :tickets_root)
    previous_federation_config_path = Application.get_env(:babs_citizens, :federation_config_path)
    previous_controller_config = Application.get_env(:babs, ControlController)

    Application.put_env(:babs_citizens, :root, root)
    Application.put_env(:babs_citizens, :workspace_root, workspace_root)
    Application.put_env(:babs_citizens, :tickets_root, tickets_root)
    Application.put_env(:babs_citizens, :federation_config_path, config_path)
    Application.delete_env(:babs, ControlController)

    on_exit(fn ->
      restore_env(:root, previous_root)
      restore_env(:workspace_root, previous_workspace_root)
      restore_env(:tickets_root, previous_tickets_root)
      restore_env(:federation_config_path, previous_federation_config_path)
      restore_app_env(:babs, ControlController, previous_controller_config)
      File.rm_rf!(root)
    end)

    %{root: root, tickets_root: tickets_root, workspace_root: workspace_root}
  end

  test "POST /api/v1/tickets/:id/comments appends a remote actor comment", %{
    tickets_root: tickets_root
  } do
    ticket = create_ticket!(tickets_root, "Remote comment", "Initial body.")

    conn =
      post_json("/api/v1/tickets/#{ticket.id}/comments", %{"body" => "Remote note."},
        peer_id: "workbench"
      )

    assert conn.status == 200
    assert json_body(conn)["ticket_id"] == ticket.id

    assert {:ok, history} = History.read(tickets_root, ticket.id)
    assert List.last(history)["event"] == "comment"
    assert List.last(history)["by"] == "remote:workbench"
    assert List.last(history)["body"] == "Remote note."
  end

  test "read-only peers are denied before ticket mutation", %{
    root: root,
    tickets_root: tickets_root
  } do
    ticket = create_ticket!(tickets_root, "Denied comment", "Initial body.")

    conn =
      post_json("/api/v1/tickets/#{ticket.id}/comments", %{"body" => "Should not land."},
        peer_id: "viewer"
      )

    assert conn.status == 403
    assert json_body(conn)["error"]["code"] == "remote_capability_forbidden"

    assert {:ok, history} = History.read(tickets_root, ticket.id)
    assert Enum.map(history, & &1["event"]) == ["created"]

    assert [denied] = audit_records!(root)
    assert denied["result"] == "denied"
    assert denied["peer_id"] == "viewer"
    assert denied["reason_code"] == "capability_forbidden"
    refute inspect(denied) =~ "Should not land"
  end

  test "requests without peer identity are rejected at the API boundary", %{
    root: root,
    tickets_root: tickets_root
  } do
    ticket = create_ticket!(tickets_root, "Missing peer", "Initial body.")

    conn =
      post_json_without_peer("/api/v1/tickets/#{ticket.id}/comments", %{
        "body" => "Should not land."
      })

    assert conn.status == 403
    assert json_body(conn)["error"]["code"] == "missing_peer_id"

    assert {:ok, history} = History.read(tickets_root, ticket.id)
    assert Enum.map(history, & &1["event"]) == ["created"]

    assert [denied] = audit_records!(root)
    assert denied["result"] == "denied"
    assert denied["reason_code"] == "missing_peer_id"
  end

  test "POST /api/v1/tickets/:id/transitions uses a server-owned remote transition event",
       %{tickets_root: tickets_root} do
    ticket =
      create_ticket!(tickets_root, "Remote transition", "Initial body.",
        state: "in_progress",
        assignees: ["clare"]
      )

    conn =
      post_json(
        "/api/v1/tickets/#{ticket.id}/transitions",
        %{"to" => "pending_approval", "event" => "approved"},
        peer_id: "workbench"
      )

    assert conn.status == 200
    assert json_body(conn)["state"] == "pending_approval"

    assert {:ok, history} = History.read(tickets_root, ticket.id)
    assert List.last(history)["event"] == "remote_transition"
    assert List.last(history)["by"] == "remote:workbench"
  end

  test "control peer can assign and unassign through local ticket APIs", %{
    tickets_root: tickets_root
  } do
    parent = self()

    Application.put_env(:babs, ControlController,
      ticket_api_opts: [
        citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
        pane_lookup: fn "clare" -> {:ok, parent} end,
        pane_injector: fn "clare", prompt ->
          send(parent, {:assignment_prompt, prompt})
          :ok
        end
      ]
    )

    ticket = create_ticket!(tickets_root, "Remote assignment", "Initial body.")

    assign =
      post_json("/api/v1/tickets/#{ticket.id}/assignments", %{"slug" => "clare"},
        peer_id: "workbench"
      )

    assert assign.status == 200
    assert json_body(assign)["assignees"] == ["clare"]
    assert_receive {:assignment_prompt, prompt}, 1_000
    assert prompt =~ "[Babs Ticket #{ticket.id} assigned]"

    unassign =
      delete_json("/api/v1/tickets/#{ticket.id}/assignments/clare", peer_id: "workbench")

    assert unassign.status == 200
    assert json_body(unassign)["assignees"] == []

    assert {:ok, history} = History.read(tickets_root, ticket.id)
    assert Enum.find(history, &(&1["event"] == "assigned"))["by"] == "remote:workbench"
    assert Enum.find(history, &(&1["event"] == "unassigned"))["by"] == "remote:workbench"
  end

  test "per-citizen read-only override denies control actions", %{tickets_root: tickets_root} do
    ticket = create_ticket!(tickets_root, "Denied assignment", "Initial body.")

    conn =
      post_json("/api/v1/tickets/#{ticket.id}/assignments", %{"slug" => "readonly-clare"},
        peer_id: "workbench"
      )

    assert conn.status == 403
    assert json_body(conn)["error"]["code"] == "remote_capability_forbidden"

    assert {:ok, %{ticket: current}} =
             TicketApi.show_ticket(ticket.id, tickets_root: tickets_root)

    assert current.state == "open"
    assert current.assignees == []
  end

  test "control peer can inject into a running citizen without appending a newline",
       %{root: root} do
    {:ok, _value} = Registry.register(Babs.Citizens.PaneRegistry, "clare", nil)

    conn =
      post_json("/api/v1/citizens/clare/injections", %{"data" => "hello"}, peer_id: "workbench")

    assert conn.status == 200
    assert json_body(conn)["citizen_slug"] == "clare"
    assert_receive {:"$gen_cast", {:inject, "hello", :manual}}, 1_000

    assert [success] = audit_records!(root)
    assert success["action"] == "citizen.inject"
    assert success["target_id"] == "clare"
    assert success["capability"] == "control"
    refute inspect(success) =~ "hello"
  end

  test "control peer can request citizen lifecycle actions", %{root: root} do
    parent = self()

    Application.put_env(:babs, ControlController,
      lifecycle_runner: fn action, slug ->
        send(parent, {:lifecycle, action, slug})
        :ok
      end
    )

    conn =
      post_json("/api/v1/citizens/clare/lifecycle", %{"action" => "restart"},
        peer_id: "workbench"
      )

    assert conn.status == 200
    assert json_body(conn)["action"] == "restart"
    assert_receive {:lifecycle, "restart", "clare"}, 1_000

    assert [success] = audit_records!(root)
    assert success["action"] == "citizen.lifecycle.restart"
    assert success["target_id"] == "clare"
  end

  test "invalid control bodies return typed JSON errors before local API calls" do
    conn =
      post_json("/api/v1/citizens/clare/injections", %{"data" => String.duplicate("x", 4097)},
        peer_id: "workbench"
      )

    assert conn.status == 400
    assert json_body(conn)["error"]["code"] == "invalid_params"
  end

  defp create_ticket!(tickets_root, title, body, attrs \\ []) do
    attrs = Enum.into(attrs, %{title: title, body: body})

    assert {:ok, ticket} =
             TicketApi.create_ticket(attrs,
               tickets_root: tickets_root,
               date: ~D[2026-05-09],
               now: "2026-05-09T00:00:00Z"
             )

    ticket
  end

  defp post_json(path, payload, opts), do: request_json(:post, path, payload, opts)
  defp delete_json(path, opts), do: request_json(:delete, path, nil, opts)

  defp post_json_without_peer(path, payload) do
    body = Jason.encode!(payload)

    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> post(path, body)
  end

  defp request_json(method, path, payload, opts) do
    body = if is_nil(payload), do: "", else: Jason.encode!(payload)

    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-babs-peer-id", Keyword.fetch!(opts, :peer_id))
    |> do_dispatch(method, path, body)
  end

  defp do_dispatch(conn, :post, path, body), do: post(conn, path, body)
  defp do_dispatch(conn, :delete, path, body), do: delete(conn, path, body)

  defp audit_records!(root) do
    path = Audit.path(root: root)

    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)
    else
      []
    end
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  defp restore_env(key, nil), do: Application.delete_env(:babs_citizens, key)
  defp restore_env(key, value), do: Application.put_env(:babs_citizens, key, value)

  defp restore_app_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_app_env(app, key, value), do: Application.put_env(app, key, value)
end
