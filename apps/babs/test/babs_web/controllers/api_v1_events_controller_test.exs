defmodule BabsWeb.Api.V1.EventsControllerTest do
  use Babs.Citizens.RepoCase, async: false

  import Phoenix.ConnTest

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

    %{workspace_root: workspace_root, tickets_root: tickets_root}
  end

  test "GET /api/v1/events returns initial node citizen and ticket snapshots", %{
    workspace_root: workspace_root,
    tickets_root: tickets_root
  } do
    cwd = Path.join(workspace_root, "clare")
    File.mkdir_p!(cwd)
    insert_citizen!(%{slug: "clare", display_name: "Clare", cwd: cwd, roles: ["developer"]})

    assert {:ok, ticket} =
             TicketApi.create_ticket(%{title: "Remote read", body: "Expose snapshot."},
               tickets_root: tickets_root,
               date: ~D[2026-05-09],
               now: "2026-05-09T00:00:00Z"
             )

    conn = get(build_conn(), "/api/v1/events")
    body = json_body(conn)

    assert conn.status == 200
    assert body["node"] == %{"id" => "local", "name" => "Local Babs"}
    assert is_binary(body["cursor"])

    assert Enum.map(body["events"], & &1["type"]) == [
             "node.snapshot",
             "citizens.snapshot",
             "tickets.snapshot"
           ]

    assert Enum.all?(body["events"], &String.starts_with?(&1["id"], "local:"))

    assert [%{"payload" => %{"citizens" => [citizen]}}] =
             Enum.filter(body["events"], &(&1["type"] == "citizens.snapshot"))

    assert citizen["slug"] == "clare"
    assert citizen["cwd_label"] == "workspaces/clare"

    assert [%{"payload" => %{"tickets" => [summary]}}] =
             Enum.filter(body["events"], &(&1["type"] == "tickets.snapshot"))

    assert summary["id"] == ticket.id
    refute inspect(body) =~ cwd
    refute inspect(body) =~ tickets_root
    refute inspect(body) =~ "last_error"
    refute inspect(body) =~ "path"
  end

  test "resupplying an unchanged cursor returns an empty event list and stable cursor" do
    first = get(build_conn(), "/api/v1/events") |> json_body()

    second =
      get(build_conn(), "/api/v1/events?cursor=#{URI.encode_www_form(first["cursor"])}")
      |> json_body()

    third =
      get(build_conn(), "/api/v1/events?cursor=#{URI.encode_www_form(second["cursor"])}")
      |> json_body()

    assert second["events"] == []
    assert third["events"] == []
    assert second["cursor"] == first["cursor"]
    assert third["cursor"] == second["cursor"]
  end

  test "changed tickets produce only a tickets snapshot for the previous cursor", %{
    tickets_root: tickets_root
  } do
    first = get(build_conn(), "/api/v1/events") |> json_body()

    assert {:ok, _ticket} =
             TicketApi.create_ticket(
               %{title: "New remote ticket", body: "Changed ticket snapshot."},
               tickets_root: tickets_root,
               date: ~D[2026-05-09],
               now: "2026-05-09T00:01:00Z"
             )

    body =
      get(build_conn(), "/api/v1/events?cursor=#{URI.encode_www_form(first["cursor"])}")
      |> json_body()

    assert Enum.map(body["events"], & &1["type"]) == ["tickets.snapshot"]
    assert [%{"title" => "New remote ticket"}] = hd(body["events"])["payload"]["tickets"]
  end

  test "invalid cursor returns a stable JSON error" do
    conn = get(build_conn(), "/api/v1/events?cursor=not-a-cursor")
    body = json_body(conn)

    assert conn.status == 400

    assert body == %{
             "error" => %{"code" => "invalid_cursor", "message" => "Event cursor is invalid"}
           }
  end

  test "GET /api/v1/events reports read_failed when the ticket root is not a directory", %{
    tickets_root: tickets_root
  } do
    File.rm_rf!(tickets_root)
    File.write!(tickets_root, "not a directory")

    conn = get(build_conn(), "/api/v1/events")
    body = json_body(conn)

    assert conn.status == 500

    assert body == %{
             "error" => %{"code" => "read_failed", "message" => "Events could not be read"}
           }
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  defp restore_env(key, nil), do: Application.delete_env(:babs_citizens, key)
  defp restore_env(key, value), do: Application.put_env(:babs_citizens, key, value)
end
