defmodule Babs.Citizens.Tickets.MayorSelectorTest do
  use Babs.Citizens.RepoCase, async: false

  alias Babs.Citizens.ImportedHardline
  alias Babs.Citizens.Tickets.MayorSelector

  setup do
    config_root = tmp_root!()
    previous_root = Application.get_env(:babs_citizens, :root)
    Application.put_env(:babs_citizens, :root, config_root)

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

  test "selects a pinned eligible Mayor", %{config_root: config_root} do
    write_citizen_toml!(config_root, "flora")

    insert_citizen!(%{
      slug: "flora",
      display_name: "Flora",
      is_mayor: true,
      roles: ["Planner"]
    })

    assert {:ok, %{slug: "flora", selection: :pinned, role: "planner"}} =
             MayorSelector.select(policy("flora"))
  end

  test "selects the first eligible default Mayor by slug and skips external imports", %{
    config_root: config_root
  } do
    for slug <- ["zephyr", "flora", "alfred", "external"] do
      write_citizen_toml!(config_root, slug)
    end

    external_metadata =
      ImportedHardline.put_external(%{}, %{
        session_name: "external-work",
        window_index: "0",
        window_name: "main",
        pane_index: "1",
        pane_id: "%42",
        target: "external-work:0.1",
        current_command: "claude",
        current_path: "/tmp/project",
        attached?: false
      })

    insert_citizen!(%{slug: "zephyr", is_mayor: true, roles: ["mayor"]})
    insert_citizen!(%{slug: "flora", is_mayor: true, roles: ["planner"]})
    insert_citizen!(%{slug: "alfred", is_mayor: false, roles: ["mayor"]})

    insert_citizen!(%{
      slug: "external",
      is_mayor: true,
      roles: ["mayor"],
      metadata: external_metadata
    })

    assert {:ok, %{slug: "flora", selection: :default, role: "planner"}} =
             MayorSelector.select(policy(nil))
  end

  test "allows an explicitly pinned external-owned Mayor when eligible", %{
    config_root: config_root
  } do
    write_citizen_toml!(config_root, "external")

    metadata =
      ImportedHardline.put_external(%{}, %{
        session_name: "external-work",
        window_index: "0",
        pane_index: "1",
        pane_id: "%42",
        target: "external-work:0.1"
      })

    insert_citizen!(%{slug: "external", is_mayor: true, roles: ["mayor"], metadata: metadata})

    assert {:ok, %{slug: "external", selection: :pinned}} =
             MayorSelector.select(policy("external"))
  end

  test "rejects missing, failed, and ineligible pinned Mayors", %{config_root: config_root} do
    write_citizen_toml!(config_root, "failed")
    write_citizen_toml!(config_root, "not-mayor")
    write_citizen_toml!(config_root, "wrong-role")

    insert_citizen!(%{slug: "failed", is_mayor: true, roles: ["mayor"], status: "failed"})
    insert_citizen!(%{slug: "not-mayor", is_mayor: false, roles: ["mayor"]})
    insert_citizen!(%{slug: "wrong-role", is_mayor: true, roles: ["developer"]})

    assert {:error, {:mayor_selector, {:missing_mayor, "missing"}}} =
             MayorSelector.select(policy("missing"))

    assert {:error, {:mayor_selector, {:failed_mayor, "failed"}}} =
             MayorSelector.select(policy("failed"))

    assert {:error, {:mayor_selector, {:ineligible_mayor, "not-mayor", :not_marked_mayor}}} =
             MayorSelector.select(policy("not-mayor"))

    assert {:error, {:mayor_selector, {:ineligible_mayor, "wrong-role", :missing_mayor_role}}} =
             MayorSelector.select(policy("wrong-role"))
  end

  test "returns a stable error when no default Mayor is eligible", %{config_root: config_root} do
    write_citizen_toml!(config_root, "clare")
    insert_citizen!(%{slug: "clare", is_mayor: false, roles: ["developer"]})

    assert {:error, {:mayor_selector, :no_default_mayor}} =
             MayorSelector.select(policy(nil))
  end

  test "rejects non-map policies" do
    assert {:error, {:mayor_selector, {:invalid_policy, :not_map}}} =
             MayorSelector.select("not a policy")
  end

  defp policy(mayor) do
    %{
      "mode" => "propose",
      "mayor" => mayor,
      "rules_refs" => ["BAB-1503"],
      "max_children" => 5,
      "allowed_roles" => ["developer", "inspector"],
      "require_human_approval" => true
    }
  end
end
