defmodule Babs.Citizens.Tickets.InspectionPolicyTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.InspectionPolicy

  test "defaults missing inspection metadata to human policy without rewriting metadata" do
    metadata = %{"source" => "test"}

    assert {:ok, ^metadata} = InspectionPolicy.normalize_metadata(metadata)
    assert {:ok, policy} = InspectionPolicy.from_metadata(metadata)

    assert policy == %{
             "mode" => "human",
             "strategy" => "single",
             "roles" => ["inspector"],
             "citizens" => [],
             "quorum" => "all_pass",
             "max_inspectors" => 3,
             "allow_self_inspection" => false
           }
  end

  test "normalizes auto council policy deterministically" do
    metadata = %{
      "source" => "test",
      "inspection" => %{
        "mode" => "auto",
        "strategy" => "council",
        "roles" => ["Inspector", "reviewer", "Inspector"],
        "citizens" => ["clare", "dylan", "clare"],
        "quorum" => "all_pass",
        "max_inspectors" => 2,
        "allow_self_inspection" => true
      }
    }

    assert {:ok, normalized} = InspectionPolicy.normalize_metadata(metadata)

    assert normalized == %{
             "source" => "test",
             "inspection" => %{
               "mode" => "auto",
               "strategy" => "council",
               "roles" => ["inspector", "reviewer"],
               "citizens" => ["clare", "dylan"],
               "quorum" => "all_pass",
               "max_inspectors" => 2,
               "allow_self_inspection" => true
             }
           }
  end

  test "normalizes partial explicit human policy" do
    assert {:ok, %{"inspection" => policy}} =
             InspectionPolicy.normalize_metadata(%{"inspection" => %{"mode" => "human"}})

    assert policy["mode"] == "human"
    assert policy["roles"] == ["inspector"]
    assert policy["max_inspectors"] == 3
  end

  test "rejects malformed inspection policies with nested reasons" do
    cases = [
      {%{"mode" => "manual"}, {:invalid_mode, "manual"}},
      {%{"strategy" => "committee"}, {:invalid_strategy, "committee"}},
      {%{"quorum" => "majority"}, {:unsupported_quorum, "majority"}},
      {%{"roles" => ["bad/role"]}, {:invalid_role_name, "bad/role"}},
      {%{"citizens" => ["BadSlug"]}, {:invalid_citizen_slug, "BadSlug"}},
      {%{"roles" => Enum.map(1..11, &"role-#{&1}")}, {:too_many_roles, 11}},
      {%{"citizens" => Enum.map(1..11, &"citizen-#{&1}")}, {:too_many_citizens, 11}},
      {%{"max_inspectors" => 0}, {:invalid_max_inspectors, 0}},
      {%{"max_inspectors" => 11}, {:invalid_max_inspectors, 11}},
      {%{"max_inspectors" => "3"}, {:invalid_max_inspectors, "3"}},
      {%{"allow_self_inspection" => "yes"}, {:invalid_allow_self_inspection, "yes"}},
      {%{"mode" => "auto", "roles" => [], "citizens" => []}, :missing_inspection_candidates}
    ]

    for {policy, reason} <- cases do
      assert {:error, {:inspection_policy, ^reason}} =
               InspectionPolicy.normalize_metadata(%{"inspection" => policy})
    end
  end
end
