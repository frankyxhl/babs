defmodule Babs.Citizens.CatalogTest do
  use Babs.Citizens.RepoCase, async: false

  import ExUnit.CaptureLog

  alias Babs.Citizens.{Catalog, CitizenConfig}

  test "imports TOML configs into SQLite with resolved cwd and running status" do
    root = tmp_root!()
    write_citizen_toml!(root, "clare")

    workspace = Path.join(root, "workspaces/clare")
    refute File.exists?(workspace)

    assert %{records: [record], warnings: [], errors: []} =
             Catalog.import_configs(root: root, config_dir: "citizens")

    assert record.slug == "clare"
    assert record.status == "running"
    assert record.cwd == workspace
    assert File.dir?(workspace)
  end

  test "imports direct_cli TOML configs as stopped so bootstrap does not start tmux" do
    root = tmp_root!()

    write_citizen_toml!(root, "dylan", %{
      cli: "codex",
      cli_args: [],
      launch_profile: "trusted_autonomous",
      ticket_backend: "direct_cli"
    })

    assert %{records: [record], warnings: [], errors: []} =
             Catalog.import_configs(root: root, config_dir: "citizens")

    assert record.slug == "dylan"
    assert record.cli == "codex"
    assert record.ticket_backend == "direct_cli"
    assert record.status == "stopped"
  end

  test "upserts by slug and preserves SQLite id, cwd, status, and running spawn fields" do
    root = tmp_root!()

    write_citizen_toml!(root, "dylan", %{
      id: "BAB-CIT-DYLAN-A",
      display_name: "Dylan",
      cli: "/bin/zsh",
      cli_args: ["-f"],
      env: %{"OPENAI_API_KEY" => "old"},
      role: %{"name" => "coder"}
    })

    assert %{records: [initial], warnings: [], errors: []} =
             Catalog.import_configs(root: root, config_dir: "citizens")

    File.rm_rf!(initial.cwd)

    write_citizen_toml!(root, "dylan", %{
      id: "BAB-CIT-DYLAN-B",
      display_name: "Dylan Updated",
      description: "Updated metadata",
      cli: "/usr/bin/env",
      cli_args: ["bash"],
      launch_profile: "trusted_autonomous",
      cwd: "new-dylan",
      env: %{"OPENAI_API_KEY" => "new"},
      role: %{"name" => "reviewer", "skills" => ["elixir"]}
    })

    assert %{
             records: [updated],
             warnings: [{:id_mismatch, "dylan", "BAB-CIT-DYLAN-A", "BAB-CIT-DYLAN-B"}],
             errors: []
           } = Catalog.import_configs(root: root, config_dir: "citizens")

    assert updated.id == initial.id
    assert updated.cwd == initial.cwd
    assert updated.status == "running"
    assert updated.cli == "/bin/zsh"
    assert updated.cli_args == ["-f"]
    assert updated.launch_profile == "safe_interactive"
    assert updated.env == %{"OPENAI_API_KEY" => "old"}
    assert updated.display_name == "Dylan Updated"
    assert updated.description == "Updated metadata"
    assert updated.role == %{"name" => "reviewer", "skills" => ["elixir"]}
    refute File.exists?(initial.cwd)
    refute File.exists?(Path.join(root, "workspaces/new-dylan"))
  end

  test "stopped and failed rows can repair spawn fields during TOML re-import" do
    root = tmp_root!()

    write_citizen_toml!(root, "elena", %{cli: "/bin/zsh", env: %{"TOKEN" => "old"}})
    assert %{records: [initial]} = Catalog.import_configs(root: root, config_dir: "citizens")
    assert {:ok, stopped} = Catalog.mark_stopped(initial.slug)

    write_citizen_toml!(root, "elena", %{
      cli: "/usr/bin/env",
      cli_args: ["zsh"],
      launch_profile: "trusted_autonomous",
      env: %{"TOKEN" => "new"}
    })

    assert %{records: [updated], warnings: [], errors: []} =
             Catalog.import_configs(root: root, config_dir: "citizens")

    assert updated.id == stopped.id
    assert updated.status == "stopped"
    assert updated.cli == "/usr/bin/env"
    assert updated.cli_args == ["zsh"]
    assert updated.launch_profile == "trusted_autonomous"
    assert updated.env == %{"TOKEN" => "new"}

    assert {:ok, failed} = Catalog.mark_failed(updated.slug, "operator repair test")

    write_citizen_toml!(root, "elena", %{cli: "/bin/zsh", env: %{"TOKEN" => "newer"}})
    assert %{records: [repaired]} = Catalog.import_configs(root: root, config_dir: "citizens")

    assert repaired.id == failed.id
    assert repaired.status == "failed"
    assert repaired.cli == "/bin/zsh"
    assert repaired.env == %{"TOKEN" => "newer"}
  end

  test "to_config drops database-only fields and preserves spawn fields" do
    record =
      insert_citizen!(%{
        slug: "to-config",
        description: "SQLite runtime",
        cli_args: ["--continue"],
        launch_profile: "trusted_autonomous",
        env: %{"TOKEN" => "secret"},
        role: "copilot-tester",
        status: "failed",
        metadata: %{"internal" => true},
        last_error: "boom"
      })

    id = record.id

    assert %CitizenConfig{
             id: ^id,
             slug: "to-config",
             display_name: "Test Citizen",
             description: "SQLite runtime",
             cli: "/bin/zsh",
             cli_args: ["--continue"],
             launch_profile: "trusted_autonomous",
             cwd: cwd,
             env: %{"TOKEN" => "secret"},
             role: "copilot-tester",
             path: nil
           } = Catalog.to_config(record)

    assert cwd == record.cwd
  end

  test "insert_new inserts a UI-created record without mkdir, merge, or warnings tuple" do
    missing_cwd = Path.join(tmp_root!(), "missing-workspace")

    config = %CitizenConfig{
      id: "BAB-CIT-INSERT-NEW",
      slug: "insert-new",
      display_name: "Insert New",
      description: "UI-created",
      cli: "/bin/zsh",
      cli_args: ["-f"],
      launch_profile: "trusted_autonomous",
      cwd: missing_cwd,
      env: %{},
      role: nil
    }

    assert {:ok, record} = Catalog.insert_new(config)
    assert record.id == "BAB-CIT-INSERT-NEW"
    assert record.slug == "insert-new"
    assert record.status == "running"
    assert record.launch_profile == "trusted_autonomous"
    assert record.metadata == %{}
    assert record.is_mayor == false
    refute File.exists?(missing_cwd)

    assert {:error, %Ecto.Changeset{} = changeset} = Catalog.insert_new(config)
    assert %{slug: ["has already been taken"]} = errors_on(changeset)
  end

  test "list_configured_or_imported_citizens hides stale rows but keeps imported external sessions" do
    root = tmp_root!()
    write_citizen_toml!(root, "clare")

    insert_citizen!(%{slug: "clare", display_name: "Clare"})
    insert_citizen!(%{slug: "json", display_name: "Json", status: "stopped"})

    external = insert_citizen!(%{slug: "external", display_name: "External"})

    assert {:ok, _external} =
             Catalog.mark_imported_external(external, %{
               session_name: "operator-session",
               window_index: "0",
               pane_index: "0",
               pane_id: "%42"
             })

    slugs =
      Catalog.list_configured_or_imported_citizens(root: root, config_dir: "citizens")
      |> Enum.map(& &1.slug)

    assert slugs == ["clare", "external"]
  end

  test "imports do not log persisted env secret values" do
    root = tmp_root!()
    write_citizen_toml!(root, "secret-env", %{env: %{"SECRET_TOKEN" => "super-secret-value"}})

    log =
      capture_log(fn ->
        assert %{records: [_record], errors: []} =
                 Catalog.import_configs(root: root, config_dir: "citizens")
      end)

    refute log =~ "super-secret-value"
    refute log =~ "SECRET_TOKEN"
  end

  test "mark_failed redacts token and secret values from persisted last_error" do
    record = insert_citizen!(%{slug: "redacted-failure"})

    assert {:ok, failed} =
             Catalog.mark_failed(record.slug, %{
               :secret_token => "lower-secret",
               "api_token" => "string-secret",
               "plain" => "plain-detail"
             })

    refute failed.last_error =~ "lower-secret"
    refute failed.last_error =~ "string-secret"
    assert failed.last_error =~ "plain-detail"
    assert failed.last_error =~ "[REDACTED]"
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
