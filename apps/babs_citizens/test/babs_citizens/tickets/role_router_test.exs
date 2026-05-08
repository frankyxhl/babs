defmodule Babs.Citizens.Tickets.RoleRouterTest do
  use Babs.Citizens.RepoCase, async: false

  alias Babs.Citizens.ExecutionLock
  alias Babs.Citizens.Tickets.History
  alias Babs.Citizens.Tickets.RoleRouter
  alias Babs.Citizens.Tickets.Ticket

  setup do
    config_root = tmp_root!()
    tickets_root = tmp_root!()
    previous_root = Application.get_env(:babs_citizens, :root)
    Application.put_env(:babs_citizens, :root, config_root)

    on_exit(fn ->
      File.rm_rf!(config_root)
      File.rm_rf!(tickets_root)

      if previous_root do
        Application.put_env(:babs_citizens, :root, previous_root)
      else
        Application.delete_env(:babs_citizens, :root)
      end
    end)

    {:ok, config_root: config_root, tickets_root: tickets_root}
  end

  test "matches a citizen when the requested role is not first", %{
    config_root: config_root,
    tickets_root: tickets_root
  } do
    write_citizen_toml!(config_root, "clare")

    insert_citizen!(%{
      slug: "clare",
      display_name: "Clare",
      roles: [
        %{"name" => "inspector", "skills" => []},
        %{"name" => "developer", "skills" => ["elixir"]}
      ]
    })

    assert {:ok, %{slug: "clare", role: "developer"}} =
             RoleRouter.resolve(ticket(assignee_role: "Developer"), tickets_root: tickets_root)
  end

  test "excludes stale sqlite-only failed and busy citizens", %{
    config_root: config_root,
    tickets_root: tickets_root
  } do
    write_citizen_toml!(config_root, "busy")
    write_citizen_toml!(config_root, "ready")
    write_citizen_toml!(config_root, "failed")

    for attrs <- [
          %{slug: "stale", roles: ["developer"]},
          %{slug: "busy", roles: ["developer"]},
          %{slug: "failed", status: "failed", roles: ["developer"]},
          %{slug: "ready", roles: ["developer"]}
        ] do
      insert_citizen!(attrs)
    end

    ExecutionLock.with_lock("busy", fn ->
      assert {:ok, %{slug: "ready"}} =
               RoleRouter.resolve(ticket(assignee_role: "developer"), tickets_root: tickets_root)
    end)
  end

  test "uses role-routed history before slug fallback", %{
    config_root: config_root,
    tickets_root: tickets_root
  } do
    for slug <- ["clare", "dylan"] do
      write_citizen_toml!(config_root, slug)
      insert_citizen!(%{slug: slug, roles: ["developer"]})
    end

    assert {:ok, %{slug: "clare"}} =
             RoleRouter.resolve(ticket(assignee_role: "developer"), tickets_root: tickets_root)

    assert :ok =
             History.append(tickets_root, "T-2026-05-08-001", %{
               "ts" => "2026-05-08T00:00:00Z",
               "event" => "assigned",
               "by" => "user",
               "ticket_id" => "T-2026-05-08-001",
               "to" => ["clare"],
               "via_role" => "developer"
             })

    assert {:ok, %{slug: "dylan"}} =
             RoleRouter.resolve(ticket(assignee_role: "developer"), tickets_root: tickets_root)
  end

  test "returns clear errors for missing role and missing candidates", %{
    tickets_root: tickets_root
  } do
    assert {:error, {:missing_assignee_role, "T-2026-05-08-001"}} =
             RoleRouter.resolve(ticket(assignee_role: nil), tickets_root: tickets_root)

    assert {:error, {:no_role_candidate, "developer"}} =
             RoleRouter.resolve(ticket(assignee_role: "developer"), tickets_root: tickets_root)
  end

  defp ticket(attrs) do
    attrs = Keyword.merge([assignee_role: "developer", assignees: []], attrs)

    %Ticket{
      id: "T-2026-05-08-001",
      type: "assignment",
      state: "open",
      assigner: "user",
      assignees: Keyword.fetch!(attrs, :assignees),
      assignee_role: Keyword.fetch!(attrs, :assignee_role),
      inspector: "user",
      priority: "normal",
      parent_ticket: nil,
      created_at: "2026-05-08T00:00:00Z",
      updated_at: "2026-05-08T00:00:00Z",
      metadata: %{},
      title: "Role ticket",
      body: "Route by role."
    }
  end
end
