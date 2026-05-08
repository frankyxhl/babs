defmodule Babs.Citizens.Tickets.InspectorSelectorTest do
  use Babs.Citizens.RepoCase, async: false

  alias Babs.Citizens.ExecutionLock
  alias Babs.Citizens.Tickets.History
  alias Babs.Citizens.Tickets.InspectorSelector
  alias Babs.Citizens.Tickets.Ticket

  setup do
    config_root = tmp_root!()
    tickets_root = tmp_root!()

    on_exit(fn ->
      File.rm_rf!(config_root)
      File.rm_rf!(tickets_root)
    end)

    {:ok, config_root: config_root, tickets_root: tickets_root}
  end

  test "selects explicit citizens first in policy order", ctx do
    for slug <- ["clare", "dylan", "elena"] do
      write_citizen_toml!(ctx.config_root, slug)
      insert_citizen!(%{slug: slug, roles: ["inspector"]})
    end

    assert {:ok, result} =
             InspectorSelector.select(
               ticket(%{
                 "citizens" => ["dylan", "clare"],
                 "roles" => ["inspector"],
                 "max_inspectors" => 3
               }),
               root: ctx.config_root,
               tickets_root: ctx.tickets_root
             )

    assert Enum.map(result.inspectors, & &1.slug) == ["dylan", "clare", "elena"]
    assert Enum.map(result.inspectors, & &1.source) == [:explicit, :explicit, :role]
  end

  test "role candidates use all history files then least recent inspection then slug order",
       ctx do
    for slug <- ["clare", "dylan", "elena"] do
      write_citizen_toml!(ctx.config_root, slug)
      insert_citizen!(%{slug: slug, roles: ["inspector"]})
    end

    assert :ok =
             History.append(ctx.tickets_root, "T-2026-05-08-001", %{
               "ts" => "2026-05-08T00:00:00Z",
               "event" => "inspection_requested",
               "by" => "system",
               "ticket_id" => "T-2026-05-08-001",
               "inspection_id" => "insp_20260508000000_1",
               "policy" => %{},
               "inspectors" => ["clare"]
             })

    assert :ok =
             History.append(ctx.tickets_root, "T-2026-05-08-099", %{
               "ts" => "2026-05-08T00:10:00Z",
               "event" => "inspection_requested",
               "by" => "system",
               "ticket_id" => "T-2026-05-08-099",
               "inspection_id" => "insp_20260508001000_1",
               "policy" => %{},
               "inspectors" => ["dylan"]
             })

    assert {:ok, result} =
             InspectorSelector.select(
               ticket(%{"roles" => ["inspector"], "max_inspectors" => 3}),
               root: ctx.config_root,
               tickets_root: ctx.tickets_root
             )

    assert Enum.map(result.inspectors, & &1.slug) == ["elena", "clare", "dylan"]
  end

  test "self inspection flag applies to explicit and role candidates", ctx do
    for slug <- ["clare", "dylan"] do
      write_citizen_toml!(ctx.config_root, slug)
      insert_citizen!(%{slug: slug, roles: ["inspector"]})
    end

    self_ticket =
      ticket(
        %{
          "citizens" => ["clare"],
          "roles" => ["inspector"],
          "max_inspectors" => 2
        },
        assignees: ["clare"]
      )

    assert {:ok, result} =
             InspectorSelector.select(self_ticket,
               root: ctx.config_root,
               tickets_root: ctx.tickets_root
             )

    assert Enum.map(result.inspectors, & &1.slug) == ["dylan"]

    assert {:ok, result} =
             InspectorSelector.select(
               %{
                 self_ticket
                 | metadata:
                     put_in(self_ticket.metadata, ["inspection", "allow_self_inspection"], true)
               },
               root: ctx.config_root,
               tickets_root: ctx.tickets_root
             )

    assert Enum.map(result.inspectors, & &1.slug) == ["clare", "dylan"]
  end

  test "excludes failed stale busy and non-executable imported citizens", ctx do
    write_citizen_toml!(ctx.config_root, "busy")
    write_citizen_toml!(ctx.config_root, "failed")
    write_citizen_toml!(ctx.config_root, "ready")

    insert_citizen!(%{slug: "stale", roles: ["inspector"]})
    insert_citizen!(%{slug: "busy", roles: ["inspector"]})
    insert_citizen!(%{slug: "failed", roles: ["inspector"], status: "failed"})
    insert_citizen!(%{slug: "ready", roles: ["inspector"]})

    insert_citizen!(%{
      slug: "external-no-target",
      roles: ["inspector"],
      metadata: %{"hardline" => %{"ownership" => "external", "tmux" => %{}}}
    })

    ExecutionLock.with_lock("busy", fn ->
      assert {:ok, result} =
               InspectorSelector.select(
                 ticket(%{"roles" => ["inspector"], "max_inspectors" => 5}),
                 root: ctx.config_root,
                 tickets_root: ctx.tickets_root
               )

      assert Enum.map(result.inspectors, & &1.slug) == ["ready"]
    end)
  end

  test "returns clear human action error when no eligible inspector exists", ctx do
    write_citizen_toml!(ctx.config_root, "clare")
    insert_citizen!(%{slug: "clare", roles: ["inspector"], status: "failed"})

    assert {:error, {:inspection_requires_human, :no_eligible_inspectors}} =
             InspectorSelector.select(
               ticket(%{"roles" => ["inspector"]}),
               root: ctx.config_root,
               tickets_root: ctx.tickets_root
             )
  end

  test "keeps human inspection policy out of automatic selection", ctx do
    assert {:error, {:inspection_not_auto, "human"}} =
             InspectorSelector.select(
               ticket(%{"mode" => "human"}),
               root: ctx.config_root,
               tickets_root: ctx.tickets_root
             )
  end

  defp ticket(policy, attrs \\ []) do
    %Ticket{
      id: "T-2026-05-08-002",
      type: "assignment",
      state: Keyword.get(attrs, :state, "pending_approval"),
      assigner: "user",
      assignees: Keyword.get(attrs, :assignees, []),
      assignee_role: nil,
      inspector: "user",
      priority: "normal",
      parent_ticket: nil,
      created_at: "2026-05-08T00:00:00Z",
      updated_at: "2026-05-08T00:00:00Z",
      metadata: %{"inspection" => Map.merge(%{"mode" => "auto"}, policy)},
      title: "Inspection ticket",
      body: "Review the completed work."
    }
  end
end
