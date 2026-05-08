defmodule Babs.Citizens.Tickets.MayorPlannerTest do
  use Babs.Citizens.RepoCase, async: false

  alias Babs.Citizens.Tickets.MayorPlanner
  alias Babs.Citizens.Tickets.Ticket

  setup do
    config_root = tmp_root!()
    previous_root = Application.get_env(:babs_citizens, :root)
    Application.put_env(:babs_citizens, :root, config_root)

    write_citizen_toml!(config_root, "flora")
    write_citizen_toml!(config_root, "clare")

    insert_citizen!(%{
      slug: "flora",
      display_name: "Flora",
      is_mayor: true,
      roles: ["mayor"],
      env: %{"API_TOKEN" => "must-not-leak"}
    })

    insert_citizen!(%{
      slug: "clare",
      display_name: "Clare",
      roles: ["developer"],
      description: "Developer on 100.64.1.2 with token secret-value"
    })

    on_exit(fn ->
      File.rm_rf!(config_root)

      if previous_root do
        Application.put_env(:babs_citizens, :root, previous_root)
      else
        Application.delete_env(:babs_citizens, :root)
      end
    end)

    {:ok, config_root: config_root}
  end

  test "prepares a side-effect-free Mayor request from mission metadata" do
    history = [
      %{
        "ts" => "2026-05-08T10:00:00Z",
        "event" => "comment",
        "by" => "user",
        "body" => "Please split this from /Users/operator/project."
      }
    ]

    assert {:ok, request} =
             MayorPlanner.prepare(ticket(), history: history, max_messages: 5)

    assert request.mayor.slug == "flora"
    assert request.policy["rules_refs"] == ["BAB-1503", "COR-1616"]
    assert request.prompt =~ "You are flora, a Babs Mayor Citizen."
    assert request.prompt =~ "Ticket: T-2026-05-08-016"
    assert request.prompt =~ "Rules refs:"
    assert request.prompt =~ "BAB-1503"
    assert request.prompt =~ "af read"
    assert request.prompt =~ ~s("proposal_id")

    refute request.prompt =~ "/Users/operator"
    refute request.prompt =~ "100.64.1.2"
    refute request.prompt =~ "secret-value"
    refute request.prompt =~ "must-not-leak"
  end

  test "rejects tickets without Mayor policy" do
    assert {:error, {:mayor_planner, :missing_policy}} =
             MayorPlanner.prepare(%{ticket() | metadata: %{}},
               lister: fn -> flunk("citizens should not be loaded without mayor policy") end
             )
  end

  test "returns selector errors without dispatching" do
    assert {:error, {:mayor_selector, {:missing_mayor, "missing"}}} =
             ticket()
             |> put_in([Access.key!(:metadata), "mayor", "mayor"], "missing")
             |> MayorPlanner.prepare()
  end

  test "parses Mayor replies with policy bounds and rejects violations" do
    policy = policy()

    valid_reply =
      proposal_payload()
      |> Jason.encode!()

    assert {:ok, proposal} = MayorPlanner.parse_reply(valid_reply, policy)
    assert [%{"assignee_role" => "developer"}] = proposal["children"]

    assert {:error, {:mayor_planner, {:invalid_proposal, {:mayor_proposal, :invalid_json}}}} =
             MayorPlanner.parse_reply("not json", policy)

    too_many_children =
      proposal_payload()
      |> Map.put("children", [
        %{"title" => "One", "body" => "Body", "assignee_role" => "developer"},
        %{"title" => "Two", "body" => "Body", "assignee_role" => "developer"}
      ])
      |> Jason.encode!()

    assert {:error,
            {:mayor_planner, {:invalid_proposal, {:mayor_proposal, {:too_many_children, 2}}}}} =
             MayorPlanner.parse_reply(too_many_children, %{policy | "max_children" => 1})

    disallowed_role =
      proposal_payload()
      |> put_in(["children", Access.at(0), "assignee_role"], "designer")
      |> Jason.encode!()

    assert {:error,
            {:mayor_planner,
             {:invalid_proposal,
              {:mayor_proposal, {:invalid_child, 0, {:disallowed_assignee_role, "designer"}}}}}} =
             MayorPlanner.parse_reply(disallowed_role, policy)

    assert {:error, {:mayor_planner, {:invalid_policy, "bad-policy"}}} =
             MayorPlanner.parse_reply(valid_reply, "bad-policy")
  end

  defp ticket do
    %Ticket{
      id: "T-2026-05-08-016",
      type: "mission",
      state: "open",
      assigner: "user",
      assignees: [],
      assignee_role: nil,
      inspector: "user",
      priority: "high",
      parent_ticket: nil,
      created_at: "2026-05-08T10:00:00Z",
      updated_at: "2026-05-08T10:01:00Z",
      metadata: %{"mayor" => policy()},
      title: "Build the next slice",
      body: "Plan work safely without embedding SOP bodies.",
      path: nil,
      warnings: []
    }
  end

  defp policy do
    %{
      "mode" => "propose",
      "mayor" => "flora",
      "rules_refs" => ["BAB-1503", "COR-1616"],
      "max_children" => 5,
      "allowed_roles" => ["developer", "inspector"],
      "require_human_approval" => true
    }
  end

  defp proposal_payload do
    %{
      "proposal_id" => "prop_phase_16_2",
      "root_ticket_id" => "T-2026-05-08-016",
      "summary" => "Split into one child.",
      "rules_refs_used" => ["BAB-1503"],
      "children" => [
        %{"title" => "Implement", "body" => "Build it.", "assignee_role" => "developer"}
      ],
      "risks" => [],
      "questions" => []
    }
  end
end
