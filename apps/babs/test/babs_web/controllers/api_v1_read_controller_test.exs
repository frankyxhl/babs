defmodule BabsWeb.Api.V1.ReadControllerTest do
  use Babs.Citizens.RepoCase, async: false

  import Phoenix.ConnTest

  alias Babs.Citizens.Hardline.Transcript
  alias Babs.Citizens.Tickets.Api, as: TicketApi

  @endpoint BabsWeb.Endpoint

  setup do
    root = tmp_root!()
    workspace_root = Path.join(root, "workspaces")
    tickets_root = Path.join(root, "tickets")
    File.mkdir_p!(workspace_root)
    File.mkdir_p!(tickets_root)

    previous_root = Application.get_env(:babs_citizens, :root)
    previous_workspace_root = Application.get_env(:babs_citizens, :workspace_root)
    previous_tickets_root = Application.get_env(:babs_citizens, :tickets_root)
    previous_federation_config_path = Application.get_env(:babs_citizens, :federation_config_path)

    Application.put_env(:babs_citizens, :root, root)
    Application.put_env(:babs_citizens, :workspace_root, workspace_root)
    Application.put_env(:babs_citizens, :tickets_root, tickets_root)
    Application.delete_env(:babs_citizens, :federation_config_path)

    on_exit(fn ->
      restore_env(:root, previous_root)
      restore_env(:workspace_root, previous_workspace_root)
      restore_env(:tickets_root, previous_tickets_root)
      restore_env(:federation_config_path, previous_federation_config_path)
      File.rm_rf!(root)
    end)

    %{root: root, workspace_root: workspace_root, tickets_root: tickets_root}
  end

  test "GET /api/v1/node returns local identity and configured peers", %{root: root} do
    config_path = Path.join(root, "federation.toml")

    File.write!(config_path, """
    [node]
    id = "node-local"
    name = "Local Babs"
    public_url = ""

    [peers.workbench]
    name = "Workbench Babs"
    url = "http://babs-workbench.example:4000"
    capabilities = ["control"]
    """)

    Application.put_env(:babs_citizens, :federation_config_path, config_path)

    conn = get(build_conn(), "/api/v1/node")
    body = json_body(conn)

    assert conn.status == 200

    assert body["node"] == %{
             "id" => "node-local",
             "name" => "Local Babs",
             "public_url" => nil,
             "capabilities" => ["read"],
             "api_version" => "v1"
           }

    assert body["peers"] == [
             %{
               "id" => "workbench",
               "name" => "Workbench Babs",
               "url" => "http://babs-workbench.example:4000",
               "capabilities" => ["read", "write", "control"],
               "citizens" => %{}
             }
           ]
  end

  test "config errors return a JSON 503 without a node envelope", %{root: root} do
    Application.put_env(:babs_citizens, :federation_config_path, Path.join(root, "missing.toml"))

    conn = get(build_conn(), "/api/v1/node")
    body = json_body(conn)

    assert conn.status == 503
    assert body["error"]["code"] == "config_error"
    refute Map.has_key?(body, "node")
  end

  test "citizen list and detail use the path-safe allowlisted projection", %{
    workspace_root: workspace_root
  } do
    cwd = Path.join(workspace_root, "clare")
    File.mkdir_p!(cwd)

    insert_citizen!(%{
      id: "BAB-CIT-00000000-0000-0000-0000-000000000001",
      slug: "clare",
      display_name: "Clare",
      cwd: cwd,
      cli: "claude",
      cli_args: [],
      roles: ["developer"],
      metadata: %{
        "hardline" => %{
          "ownership" => "external",
          "tmux" => %{"target" => "private-target:0.0"}
        }
      },
      last_error: "private failure at #{cwd}"
    })

    {:ok, _value} = Registry.register(Babs.Citizens.PaneRegistry, "clare", nil)

    conn = get(build_conn(), "/api/v1/citizens")
    body = json_body(conn)
    [citizen] = body["citizens"]

    assert body["node"] == %{"id" => "local", "name" => "Local Babs"}
    assert citizen["slug"] == "clare"
    assert citizen["roles"] == ["developer"]
    assert citizen["live_status"] == "up"
    assert citizen["visual_state"] == "idle"
    assert citizen["actions"] == ["open", "full", "stop", "restart"]
    assert citizen["cwd_label"] == "workspaces/clare"
    assert citizen["interactive_attach"] == true
    assert citizen["kill_authority"] == false
    assert citizen["detach_authority"] == true
    assert citizen["ownership"] == "external"

    assert Enum.sort(Map.keys(citizen)) ==
             Enum.sort([
               "actions",
               "cli_label",
               "cwd_label",
               "detach_authority",
               "display_name",
               "durable_status",
               "id",
               "imported",
               "interactive_attach",
               "kill_authority",
               "lifecycle_reminder",
               "live_status",
               "ownership",
               "ownership_badge",
               "provider_runtime",
               "provider_runtime_capabilities",
               "roles",
               "slug",
               "ticket_backend",
               "ticket_backend_label",
               "visual_state"
             ])

    refute inspect(body) =~ cwd
    refute inspect(body) =~ "last_error"
    refute inspect(body) =~ "private-target"
    refute inspect(body) =~ "target_label"

    detail = get(build_conn(), "/api/v1/citizens/clare") |> json_body()
    assert detail["citizen"] == citizen
  end

  test "citizen transcript returns bounded output metadata without cwd paths", %{
    workspace_root: workspace_root
  } do
    cwd = Path.join(workspace_root, "dylan")
    File.mkdir_p!(cwd)

    insert_citizen!(%{
      slug: "dylan",
      display_name: "Dylan",
      cwd: cwd,
      cli: "codex",
      cli_args: [],
      roles: ["developer"]
    })

    {:ok, io} = Transcript.open(cwd)

    :ok =
      Transcript.append(io, %{
        slug: "dylan",
        direction: :input,
        stream_id: 1,
        seq: 1,
        payload: "hidden input\n"
      })

    :ok =
      Transcript.append(io, %{
        slug: "dylan",
        direction: :output,
        stream_id: 1,
        seq: 2,
        payload: "one\ntwo\nthree\n"
      })

    :ok = Transcript.close(io)

    conn = get(build_conn(), "/api/v1/citizens/dylan/transcript?lines=2&tail_bytes=1024")
    body = json_body(conn)

    assert conn.status == 200
    assert body["citizen_slug"] == "dylan"

    assert body["transcript"] == %{
             "output" => "two\nthree\n",
             "truncated" => true,
             "lines" => 2,
             "returned_lines" => 2
           }

    refute inspect(body) =~ cwd
    refute inspect(body) =~ "hidden input"
  end

  test "invalid transcript params return a stable JSON error" do
    conn = get(build_conn(), "/api/v1/citizens/clare/transcript?lines=0")
    body = json_body(conn)

    assert conn.status == 400
    assert body["error"]["code"] == "invalid_params"
  end

  test "ticket list and detail expose read-only path-safe projections", %{
    tickets_root: tickets_root
  } do
    assert {:ok, ticket} =
             TicketApi.create_ticket(
               %{
                 title: "Federation API",
                 body: "Expose read-only Ticket data.",
                 assignee_role: "developer",
                 metadata: %{"phase" => "17.1"}
               },
               tickets_root: tickets_root,
               date: ~D[2026-05-09],
               now: "2026-05-09T00:00:00Z"
             )

    conn = get(build_conn(), "/api/v1/tickets")
    body = json_body(conn)
    [summary] = body["tickets"]

    assert conn.status == 200
    assert body["invalid"] == %{"count" => 0}

    assert summary == %{
             "id" => ticket.id,
             "type" => "assignment",
             "state" => "open",
             "assigner" => "user",
             "assignees" => [],
             "assignee_role" => "developer",
             "inspector" => "user",
             "priority" => "normal",
             "parent_ticket" => nil,
             "created_at" => "2026-05-09T00:00:00Z",
             "updated_at" => "2026-05-09T00:00:00Z",
             "metadata" => %{"phase" => "17.1"},
             "title" => "Federation API"
           }

    refute inspect(body) =~ tickets_root
    refute Map.has_key?(summary, "path")
    refute Map.has_key?(summary, "warnings")

    detail = get(build_conn(), "/api/v1/tickets/#{ticket.id}") |> json_body()

    assert detail["ticket"]["body"] == "Expose read-only Ticket data."
    assert [%{"event" => "created"}] = detail["ticket"]["history"]
    refute inspect(detail) =~ tickets_root
    refute Map.has_key?(detail["ticket"], "path")
    refute Map.has_key?(detail["ticket"], "warnings")
  end

  test "unknown citizen and ticket resources return JSON 404s" do
    assert %{"error" => %{"code" => "not_found"}} =
             get(build_conn(), "/api/v1/citizens/missing") |> json_body()

    ticket_conn = get(build_conn(), "/api/v1/tickets/T-2026-05-09-999")
    assert ticket_conn.status == 404
    assert json_body(ticket_conn)["error"]["code"] == "not_found"
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  defp restore_env(key, nil), do: Application.delete_env(:babs_citizens, key)
  defp restore_env(key, value), do: Application.put_env(:babs_citizens, key, value)
end
