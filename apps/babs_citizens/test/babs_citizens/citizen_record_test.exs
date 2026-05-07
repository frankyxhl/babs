defmodule Babs.Citizens.CitizenRecordTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.CitizenRecord

  test "validates and applies a complete citizen record" do
    changeset =
      CitizenRecord.changeset(%CitizenRecord{}, %{
        id: "BAB-CIT-0001",
        slug: "clare",
        display_name: "Clare",
        description: "Claude Code seed citizen",
        cwd: "/tmp/babs/clare",
        cli: "claude",
        cli_args: ["--continue"],
        launch_profile: "trusted_autonomous",
        ticket_backend: "direct_cli",
        env: %{"ANTHROPIC_API_KEY" => "secret"},
        role: %{"name" => "developer", "skills" => ["elixir", "phoenix"]},
        status: "running",
        metadata: %{"seed" => true},
        is_mayor: false
      })

    assert changeset.valid?

    record = Ecto.Changeset.apply_changes(changeset)
    assert record.cli_args == ["--continue"]
    assert record.launch_profile == "trusted_autonomous"
    assert record.ticket_backend == "direct_cli"
    assert record.env == %{"ANTHROPIC_API_KEY" => "secret"}
    assert record.role == %{"name" => "developer", "skills" => ["elixir", "phoenix"]}
    assert record.metadata == %{"seed" => true}
  end

  test "defaults list and map fields to spawn-safe empty values" do
    record = %CitizenRecord{}

    assert record.cli_args == []
    assert record.launch_profile == "safe_interactive"
    assert record.ticket_backend == "hardline"
    assert record.env == %{}
    assert record.metadata == %{}
    refute record.is_mayor
  end

  test "rejects invalid slug, status, cli_args, env, metadata, and role shapes" do
    attrs = valid_attrs()

    refute_valid(%{attrs | slug: "Bad"})
    refute_valid(%{attrs | status: "paused"})
    refute_valid(%{attrs | cli_args: ["-f", 1]})
    refute_valid(%{attrs | launch_profile: "trust-me"})
    refute_valid(%{attrs | ticket_backend: "batch"})
    refute_valid(%{attrs | env: ["TOKEN"]})
    refute_valid(%{attrs | metadata: ["seed"]})
    refute_valid(%{attrs | role: %{"name" => "developer", "skills" => ["ok", 1]}})
  end

  test "accepts nil, string, and BAB-1112 map role values" do
    assert_valid_role(nil)
    assert_valid_role("copilot-tester")
    assert_valid_role(%{"name" => "developer"})
    assert_valid_role(%{"name" => "developer", "skills" => ["elixir"]})
  end

  test "generates string ids compatible with the BAB-CIT namespace" do
    assert <<"BAB-CIT-", uuid::binary-size(36)>> = CitizenRecord.generate_id()
    assert {:ok, _uuid} = Ecto.UUID.cast(uuid)
  end

  defp assert_valid_role(role) do
    assert CitizenRecord.changeset(%CitizenRecord{}, %{valid_attrs() | role: role}).valid?
  end

  defp refute_valid(attrs) do
    refute CitizenRecord.changeset(%CitizenRecord{}, attrs).valid?
  end

  defp valid_attrs do
    %{
      id: "BAB-CIT-TEST",
      slug: "test-citizen",
      display_name: "Test Citizen",
      cwd: "/tmp/babs/test-citizen",
      cli: "/bin/zsh",
      cli_args: ["-f"],
      launch_profile: "safe_interactive",
      ticket_backend: "hardline",
      env: %{},
      role: nil,
      status: "running",
      metadata: %{},
      is_mayor: false
    }
  end
end
