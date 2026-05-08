defmodule Babs.Citizens.RolesTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Roles

  test "normalizes nil and empty values to an empty role list" do
    assert Roles.normalize(nil) == {:ok, []}
    assert Roles.normalize([]) == {:ok, []}
    assert Roles.legacy_first_role([]) == nil
  end

  test "normalizes string roles into canonical maps" do
    assert Roles.normalize("Developer") ==
             {:ok, [%{"name" => "developer", "skills" => []}]}

    assert Roles.normalize("copilot_cli") ==
             {:ok, [%{"name" => "copilot-cli", "skills" => []}]}
  end

  test "normalizes maps, atom keys, skills, and duplicate roles" do
    input = [
      %{"name" => "Developer", "skills" => ["Elixir", "Phoenix"]},
      %{name: "developer", skills: ["phoenix", "Code Review"]},
      %{name: "Inspector", skills: []}
    ]

    assert Roles.normalize(input) ==
             {:ok,
              [
                %{"name" => "developer", "skills" => ["elixir", "phoenix", "code-review"]},
                %{"name" => "inspector", "skills" => []}
              ]}
  end

  test "builds a legacy first-role value for migration compatibility" do
    assert {:ok, roles} =
             Roles.normalize([
               %{"name" => "Developer", "skills" => ["Elixir"]},
               "inspector"
             ])

    assert Roles.legacy_first_role(roles) == %{"name" => "developer", "skills" => ["elixir"]}
  end

  test "rejects invalid role and skill shapes" do
    assert Roles.normalize("bad/role") == {:error, {:invalid_role_name, "bad/role"}}

    assert Roles.normalize(%{"name" => "developer", "skills" => ["ok", 1]}) ==
             {:error, {:invalid_skill, 1}}

    assert Roles.normalize(%{"skills" => ["elixir"]}) ==
             {:error, {:missing_role_name, %{"skills" => ["elixir"]}}}
  end
end
