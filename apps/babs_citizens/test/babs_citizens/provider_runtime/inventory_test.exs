defmodule Babs.Citizens.ProviderRuntime.InventoryTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.ImportedHardline
  alias Babs.Citizens.ProviderRuntime.{Contract, Inventory}

  test "lists current direct, hardline, imported, and reserved provider contracts" do
    keys =
      Inventory.all()
      |> Enum.map(&{&1.provider, &1.backend, &1.ownership})
      |> MapSet.new()

    assert MapSet.member?(keys, {"claude", "direct_cli", "babs"})
    assert MapSet.member?(keys, {"codex", "direct_cli", "babs"})
    assert MapSet.member?(keys, {"copilot", "direct_cli", "babs"})
    assert MapSet.member?(keys, {"fake", "direct_cli", "babs"})
    assert MapSet.member?(keys, {"ai_cli", "hardline", "babs"})
    assert MapSet.member?(keys, {"ai_cli", "hardline", "external"})
    assert MapSet.member?(keys, {"droid", "hardline", "reserved"})
    assert MapSet.member?(keys, {"pi", "hardline", "reserved"})
    assert MapSet.member?(keys, {"ai_cli", "lazy_tmux", "reserved"})
  end

  test "direct CLI rows expose resume, parser, limits, and no raw artifact refs" do
    assert {:ok, contract} = Inventory.get("codex", "direct_cli")
    map = Contract.to_map(contract)

    assert map["resume"]["supported"]
    assert map["session_id_parser"]["supported"]
    assert map["reply_parser"]["supported"]
    assert map["input_modes"] == ["argv_prompt"]
    assert map["output_limits"]["stdout_bytes"] == 65_536
    assert map["raw_artifact_refs"] == []
  end

  test "resolves direct CLI configs through existing adapter support rules" do
    assert {:ok, %{provider: "claude", backend: "direct_cli"}} =
             Inventory.for_config(%{cli: "claude", cli_args: [], ticket_backend: "direct_cli"})

    assert {:ok, %{provider: "claude", backend: "direct_cli"}} =
             Inventory.for_config(%{
               "cli" => "claude",
               "cli_args" => [],
               "ticket_backend" => "direct_cli"
             })

    assert {:ok, %{provider: "codex", backend: "direct_cli"}} =
             Inventory.for_config(%{cli: "codex", cli_args: [], ticket_backend: "direct_cli"})

    assert {:ok, %{provider: "copilot", backend: "direct_cli"}} =
             Inventory.for_config(%{
               cli: "gh",
               cli_args: ["copilot"],
               ticket_backend: "direct_cli"
             })

    assert {:ok, %{provider: "fake", backend: "direct_cli"}} =
             Inventory.for_config(%{
               cli: "babs-fake-ai",
               cli_args: [],
               ticket_backend: "direct_cli"
             })
  end

  test "distinguishes babs-owned hardline from imported external hardline" do
    assert {:ok, babs_owned} =
             Inventory.for_config(%{cli: "claude", ticket_backend: "hardline", metadata: %{}})

    imported_metadata =
      ImportedHardline.put_external(
        %{},
        %{session_name: "peer", window_index: "0", pane_index: "1", pane_id: "%42"}
      )

    assert {:ok, imported} =
             Inventory.for_config(%{
               cli: "claude",
               ticket_backend: "hardline",
               metadata: imported_metadata
             })

    assert babs_owned.provider == "ai_cli"
    assert babs_owned.ownership == "babs"
    assert babs_owned.capabilities["kill_authority"]

    assert imported.provider == "ai_cli"
    assert imported.ownership == "external"
    refute imported.capabilities["kill_authority"]
    assert imported.capabilities["detach_authority"]
  end

  test "returns structured errors for unknown rows and backends" do
    assert {:error, {:unknown_provider_runtime, "missing", "direct_cli", "babs"}} =
             Inventory.get("missing", "direct_cli")

    assert {:error, {:unsupported_ticket_backend, "unsupported"}} =
             Inventory.for_config(%{cli: "claude", ticket_backend: "unsupported"})
  end

  test "reserved provider rows are visible but not executable" do
    assert {:ok, droid} = Inventory.get("droid", "hardline", ownership: "reserved")
    assert droid.status == "deferred"
    refute droid.capabilities["execute"]

    assert {:ok, lazy_tmux} = Inventory.get("ai_cli", "lazy_tmux", ownership: "reserved")
    assert lazy_tmux.status == "deferred"
    refute lazy_tmux.capabilities["execute"]
  end

  test "capability_map returns public-safe string-keyed data for configs" do
    assert {:ok, map} =
             Inventory.capability_map(%{
               cli: "copilot",
               cli_args: [],
               ticket_backend: "direct_cli"
             })

    assert map["provider"] == "copilot"
    assert map["backend"] == "direct_cli"
    refute inspect(map) =~ "/Users/"
    refute inspect(map) =~ "/home/"
    refute inspect(map) =~ "/root/"
    refute inspect(map) =~ "private-network-address"
  end

  test "capability_map accepts an already-resolved contract" do
    assert {:ok, contract} = Inventory.get("ai_cli", "hardline")
    assert {:ok, map} = Inventory.capability_map(contract)

    assert map["provider"] == "ai_cli"
    assert map["backend"] == "hardline"
    assert map["interactive_attach"]["supported"]
  end
end
