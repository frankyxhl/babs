defmodule Babs.Citizens.Tickets.MayorPolicyTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.MayorPolicy

  test "preserves metadata when mayor policy is missing" do
    metadata = %{"source" => "test"}

    assert {:ok, ^metadata} = MayorPolicy.normalize_metadata(metadata)
    assert :missing = MayorPolicy.from_metadata(metadata)
  end

  test "normalizes propose metadata deterministically" do
    metadata = %{
      source: "test",
      mayor: %{
        mode: "propose",
        mayor: "flora",
        rules_refs: [" BAB-1503 ", "COR-1616", "BAB-1503"],
        max_children: 5,
        allowed_roles: ["Developer", "inspector", "Developer"],
        require_human_approval: true
      }
    }

    assert {:ok, normalized} = MayorPolicy.normalize_metadata(metadata)

    assert normalized == %{
             "source" => "test",
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

  test "rejects malformed mayor policies with nested reasons" do
    cases = [
      {%{"mode" => "auto"}, {:invalid_mode, "auto"}},
      {%{"mode" => "propose", "mayor" => "BadSlug", "require_human_approval" => true},
       {:invalid_mayor_slug, "BadSlug"}},
      {%{"mode" => "propose", "rules_refs" => "BAB-1503", "require_human_approval" => true},
       {:invalid_rules_refs, "BAB-1503"}},
      {%{
         "mode" => "propose",
         "rules_refs" => Enum.map(1..11, &"BAB-#{1000 + &1}"),
         "require_human_approval" => true
       }, {:too_many_rules_refs, 11}},
      {%{"mode" => "propose", "max_children" => 0, "require_human_approval" => true},
       {:invalid_max_children, 0}},
      {%{
         "mode" => "propose",
         "allowed_roles" => Enum.map(1..11, &"role-#{&1}"),
         "require_human_approval" => true
       }, {:too_many_allowed_roles, 11}},
      {%{"mode" => "propose", "allowed_roles" => ["bad/role"], "require_human_approval" => true},
       {:invalid_role_name, "bad/role"}},
      {%{"mode" => "propose", "require_human_approval" => false},
       {:human_approval_required, false}}
    ]

    for {policy, reason} <- cases do
      assert {:error, {:mayor_policy, ^reason}} =
               MayorPolicy.normalize_metadata(%{"mayor" => policy})
    end
  end
end
