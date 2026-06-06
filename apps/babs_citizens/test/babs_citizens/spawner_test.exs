defmodule Babs.Citizens.SpawnerTest do
  use Babs.Citizens.RepoCase, async: false

  alias Babs.Citizens.{Catalog, Repo, Spawner}
  alias Babs.Citizens.Citizen.TomlWriter

  test "validates input before TOML, SQLite, workspace, or lifecycle side effects" do
    root = tmp_root!()

    assert {:error, {:validation_failed, errors}} =
             Spawner.create_and_start(
               %{
                 "slug" => "new",
                 "display_name" => "",
                 "cli_preset" => "unknown",
                 "cwd" => "/absolute"
               },
               root: root,
               lifecycle_start: unexpected_lifecycle()
             )

    assert errors.slug == "is reserved"
    assert errors.display_name == "is required"
    assert errors.cli_preset == "is not supported"
    assert errors.cwd == "must be relative"
    refute File.exists?(Path.join(root, "citizens/citizen-new.toml"))
    assert Catalog.get_by_slug("new") == nil
  end

  test "rejects cwd path traversal before creating artifacts" do
    root = tmp_root!()
    escaped = Path.expand("../escaped", Path.join(root, "workspaces"))

    assert {:error, {:validation_failed, errors}} =
             Spawner.create_and_start(
               %{
                 "slug" => "traverse",
                 "display_name" => "Traverse",
                 "cli_preset" => "shell",
                 "cwd" => "../escaped"
               },
               root: root,
               lifecycle_start: unexpected_lifecycle()
             )

    assert errors.cwd == "must stay inside workspace root"
    refute File.exists?(Path.join(root, "citizens/citizen-traverse.toml"))
    refute File.exists?(escaped)
    assert Catalog.get_by_slug("traverse") == nil
  end

  test "rejects cwd that escapes workspace root through existing symlink" do
    root = tmp_root!()
    outside = Path.join(root, "outside")
    workspace_root = Path.join(root, "workspaces")
    File.mkdir_p!(outside)
    File.mkdir_p!(workspace_root)
    File.ln_s!(outside, Path.join(workspace_root, "link-out"))

    assert {:error, {:cwd_escapes_workspace, "link-out/escape"}} =
             Spawner.create_and_start(
               %{
                 "slug" => "symlink-cwd",
                 "display_name" => "Symlink Cwd",
                 "cli_preset" => "shell",
                 "cwd" => "link-out/escape"
               },
               root: root,
               lifecycle_start: unexpected_lifecycle()
             )

    refute File.exists?(Path.join(root, "citizens/citizen-symlink-cwd.toml"))
    refute File.exists?(Path.join(outside, "escape"))
    assert Catalog.get_by_slug("symlink-cwd") == nil
  end

  test "revalidates cwd after TOML write before creating workspace" do
    root = tmp_root!()
    outside = Path.join(root, "outside")
    workspace_root = Path.join(root, "workspaces")
    File.mkdir_p!(outside)
    File.mkdir_p!(workspace_root)

    writer = fn config, opts ->
      result = TomlWriter.write(config, opts)
      File.ln_s!(outside, Path.join(workspace_root, "late-link"))
      result
    end

    assert {:error, {:cwd_escapes_workspace, "late-link/escape"}} =
             Spawner.create_and_start(
               %{
                 "slug" => "late-symlink",
                 "display_name" => "Late Symlink",
                 "cli_preset" => "shell",
                 "cwd" => "late-link/escape"
               },
               root: root,
               toml_writer: writer,
               lifecycle_start: unexpected_lifecycle()
             )

    assert File.exists?(Path.join(root, "citizens/citizen-late-symlink.toml"))
    refute File.exists?(Path.join(outside, "escape"))
    assert Catalog.get_by_slug("late-symlink") == nil
  end

  test "accepts filesystem root as workspace root" do
    root = tmp_root!()

    assert {:ok, record} =
             Spawner.create_and_start(
               valid_params("root-workspace"),
               root: root,
               workspace_root: "/",
               mkdir: fn "/root-workspace" -> :ok end,
               readme_seeder: fn _config, _opts -> :ok end,
               lifecycle_start: fn _config -> {:ok, self()} end
             )

    assert record.cwd == "/root-workspace"
  end

  test "accepts atom-keyed params without converting untrusted key names to atoms" do
    root = tmp_root!()

    assert {:ok, record} =
             Spawner.create_and_start(
               %{
                 "unexpected-browser-key-#{System.unique_integer([:positive])}" => "ignored",
                 slug: "atom-keys",
                 display_name: "Atom Keys",
                 cli_preset: "shell",
                 cwd: "atom-keys"
               },
               root: root,
               lifecycle_start: fn _config -> {:ok, self()} end
             )

    assert record.slug == "atom-keys"
    assert File.dir?(Path.join(root, "workspaces/atom-keys"))
  end

  test "creates TOML, workspace, SQLite row, and starts lifecycle for shell preset" do
    root = tmp_root!()
    parent = self()

    assert {:ok, record} =
             Spawner.create_and_start(
               %{
                 "slug" => "spawn-ok",
                 "display_name" => "Spawn OK",
                 "description" => "Browser-created",
                 "cli_preset" => "shell",
                 "cwd" => ""
               },
               root: root,
               lifecycle_start: fn config ->
                 send(parent, {:lifecycle_started, config})
                 {:ok, self()}
               end
             )

    assert record.slug == "spawn-ok"
    assert record.display_name == "Spawn OK"
    assert record.description == "Browser-created"
    assert record.cwd == Path.join(root, "workspaces/spawn-ok")
    assert record.cli == "/bin/zsh"
    assert record.cli_args == ["-f"]
    assert record.ticket_backend == "hardline"
    assert record.status == "running"
    assert String.starts_with?(record.id, "BAB-CIT-")
    assert File.dir?(record.cwd)

    toml_path = Path.join(root, "citizens/citizen-spawn-ok.toml")
    assert File.exists?(toml_path)
    assert File.read!(toml_path) =~ ~s(cwd = "spawn-ok")
    assert File.read!(toml_path) =~ ~s(ticket_backend = "hardline")

    assert_receive {:lifecycle_started, config}
    assert config.path == toml_path
    assert config.cwd == record.cwd
  end

  test "seeds default Readme on spawn with display name slug and roles" do
    root = tmp_root!()

    assert {:ok, record} =
             Spawner.create_and_start(
               %{
                 "slug" => "readme-ok",
                 "display_name" => "Readme OK",
                 "cli_preset" => "shell",
                 "roles" => "Developer\nInspector"
               },
               root: root,
               lifecycle_start: fn _config -> {:ok, self()} end
             )

    content = File.read!(Path.join(record.cwd, "Readme.md"))

    assert content =~ "# Readme OK\n"
    assert content =~ "Slug: `readme-ok`"
    assert content =~ "Roles:\n\n- developer\n- inspector\n"
    assert content =~ "## Standing Context"
    assert String.ends_with?(content, "\n")
  end

  test "creates direct_cli citizen without starting lifecycle" do
    root = tmp_root!()

    assert {:ok, record} =
             Spawner.create_and_start(
               %{
                 "slug" => "direct-ok",
                 "display_name" => "Direct OK",
                 "description" => "Ticket-only direct Citizen",
                 "cli_preset" => "copilot-cli",
                 "ticket_backend" => "direct_cli",
                 "cwd" => ""
               },
               root: root,
               lifecycle_start: unexpected_lifecycle()
             )

    assert record.slug == "direct-ok"
    assert record.status == "stopped"
    assert record.ticket_backend == "direct_cli"
    assert record.cli == "copilot"
    assert File.dir?(record.cwd)

    toml = File.read!(Path.join(root, "citizens/citizen-direct-ok.toml"))
    assert toml =~ ~s(cli = "copilot")
    assert toml =~ ~s(ticket_backend = "direct_cli")

    assert File.read!(Path.join(record.cwd, "Readme.md")) =~ "Roles:\n\n- none\n"
  end

  test "creates citizen with browser role labels" do
    root = tmp_root!()
    parent = self()

    assert {:ok, record} =
             Spawner.create_and_start(
               %{
                 "slug" => "role-ok",
                 "display_name" => "Role OK",
                 "cli_preset" => "shell",
                 "roles" => "Developer\nInspector"
               },
               root: root,
               lifecycle_start: fn config ->
                 send(parent, {:lifecycle_started, config})
                 {:ok, self()}
               end
             )

    assert record.role == "developer"

    assert record.roles == [
             %{"name" => "developer", "skills" => []},
             %{"name" => "inspector", "skills" => []}
           ]

    toml = File.read!(Path.join(root, "citizens/citizen-role-ok.toml"))
    assert toml =~ ~s(role = "developer")
    assert toml =~ "[[roles]]"
    assert toml =~ ~s(name = "developer")
    assert toml =~ ~s(name = "inspector")

    assert_receive {:lifecycle_started, config}
    assert config.roles == record.roles
    assert config.role == "developer"
  end

  test "accepts atom-keyed pre-split role params" do
    root = tmp_root!()

    assert {:ok, record} =
             Spawner.create_and_start(
               %{
                 slug: "role-list",
                 display_name: "Role List",
                 cli_preset: "shell",
                 roles: ["Developer", "Inspector"]
               },
               root: root,
               lifecycle_start: fn _config -> {:ok, self()} end
             )

    assert record.roles == [
             %{"name" => "developer", "skills" => []},
             %{"name" => "inspector", "skills" => []}
           ]
  end

  test "rejects invalid role labels before creating artifacts" do
    root = tmp_root!()

    assert {:error, {:validation_failed, errors}} =
             Spawner.create_and_start(
               %{
                 "slug" => "bad-role",
                 "display_name" => "Bad Role",
                 "cli_preset" => "shell",
                 "roles" => "developer\nbad/role"
               },
               root: root,
               lifecycle_start: unexpected_lifecycle()
             )

    assert errors.roles == "must be valid role labels"
    refute File.exists?(Path.join(root, "citizens/citizen-bad-role.toml"))
    assert Catalog.get_by_slug("bad-role") == nil
  end

  test "rejects lazy_tmux from browser creation" do
    root = tmp_root!()

    assert {:error, {:validation_failed, errors}} =
             Spawner.create_and_start(
               %{
                 "slug" => "lazy-browser",
                 "display_name" => "Lazy Browser",
                 "cli_preset" => "copilot-cli",
                 "ticket_backend" => "lazy_tmux",
                 "cwd" => "lazy-browser"
               },
               root: root,
               lifecycle_start: unexpected_lifecycle()
             )

    assert errors.ticket_backend == "is not supported for browser creation"
    refute File.exists?(Path.join(root, "citizens/citizen-lazy-browser.toml"))
    assert Catalog.get_by_slug("lazy-browser") == nil
  end

  test "rejects direct_cli for presets without a direct adapter" do
    root = tmp_root!()

    assert {:error, {:validation_failed, errors}} =
             Spawner.create_and_start(
               %{
                 "slug" => "direct-shell",
                 "display_name" => "Direct Shell",
                 "cli_preset" => "shell",
                 "ticket_backend" => "direct_cli",
                 "cwd" => "direct-shell"
               },
               root: root,
               lifecycle_start: unexpected_lifecycle()
             )

    assert errors.ticket_backend == "requires a direct-capable CLI preset"
    refute File.exists?(Path.join(root, "citizens/citizen-direct-shell.toml"))
    assert Catalog.get_by_slug("direct-shell") == nil
  end

  test "copilot preset uses direct Copilot with trusted autonomous launch profile" do
    root = tmp_root!()
    parent = self()

    assert {:ok, record} =
             Spawner.create_and_start(
               %{
                 "slug" => "copilot-ok",
                 "display_name" => "Copilot OK",
                 "cli_preset" => "copilot-cli",
                 "cwd" => "copilot-ok"
               },
               root: root,
               lifecycle_start: fn config ->
                 send(parent, {:lifecycle_started, config})
                 {:ok, self()}
               end
             )

    assert record.cli == "copilot"
    assert record.cli_args == []
    assert record.launch_profile == "trusted_autonomous"
    assert record.ticket_backend == "hardline"

    toml = File.read!(Path.join(root, "citizens/citizen-copilot-ok.toml"))
    assert toml =~ ~s(cli = "copilot")
    assert toml =~ ~s(cli_args = [])
    assert toml =~ ~s(launch_profile = "trusted_autonomous")

    assert_receive {:lifecycle_started, config}
    assert config.launch_profile == "trusted_autonomous"
  end

  test "seeds Readme under configured knowledge root without writing into workspace" do
    root = tmp_root!()
    knowledge_root = Path.join(root, "knowledge-home")

    assert {:ok, record} =
             Spawner.create_and_start(valid_params("knowledge-root"),
               root: root,
               knowledge_root: knowledge_root,
               lifecycle_start: fn _config -> {:ok, self()} end
             )

    assert File.exists?(Path.join(knowledge_root, "knowledge-root/Readme.md"))
    refute File.exists?(Path.join(record.cwd, "Readme.md"))
  end

  test "does not overwrite an existing Readme in the knowledge home" do
    root = tmp_root!()
    readme_path = Path.join(root, "workspaces/no-clobber/Readme.md")
    File.mkdir_p!(Path.dirname(readme_path))
    File.write!(readme_path, "operator notes\n")

    assert {:ok, record} =
             Spawner.create_and_start(valid_params("no-clobber"),
               root: root,
               lifecycle_start: fn _config -> {:ok, self()} end
             )

    assert record.cwd == Path.dirname(readme_path)
    assert File.read!(readme_path) == "operator notes\n"
  end

  test "Readme seed failure preserves TOML and workspace without SQLite or lifecycle" do
    root = tmp_root!()
    parent = self()

    assert {:error, {:readme_seed_failed, :denied}} =
             Spawner.create_and_start(valid_params("seed-fail"),
               root: root,
               readme_seeder: fn config, _opts ->
                 send(parent, {:readme_seed_attempted, config.slug})
                 {:error, :denied}
               end,
               insert: fn _config, _opts -> flunk("SQLite insert should not be called") end,
               lifecycle_start: unexpected_lifecycle()
             )

    assert_receive {:readme_seed_attempted, "seed-fail"}
    assert File.exists?(Path.join(root, "citizens/citizen-seed-fail.toml"))
    assert File.dir?(Path.join(root, "workspaces/seed-fail"))
    assert Catalog.get_by_slug("seed-fail") == nil
  end

  test "duplicate TOML or SQLite slug blocks before lifecycle" do
    root = tmp_root!()
    File.mkdir_p!(Path.join(root, "citizens"))
    File.write!(Path.join(root, "citizens/citizen-dupe-toml.toml"), "already here\n")

    assert {:error, {:duplicate_toml, _path}} =
             Spawner.create_and_start(valid_params("dupe-toml"),
               root: root,
               lifecycle_start: unexpected_lifecycle()
             )

    insert_citizen!(%{slug: "dupe-sqlite"})

    assert {:error, {:duplicate_sqlite, "dupe-sqlite"}} =
             Spawner.create_and_start(valid_params("dupe-sqlite"),
               root: root,
               lifecycle_start: unexpected_lifecycle()
             )
  end

  test "TOML write failure does not create workspace or SQLite row" do
    root = tmp_root!()

    assert {:error, {:toml_write_failed, :denied}} =
             Spawner.create_and_start(valid_params("toml-fail"),
               root: root,
               toml_writer: fn _config, _opts -> {:error, {:toml_write_failed, :denied}} end,
               lifecycle_start: unexpected_lifecycle()
             )

    refute File.exists?(Path.join(root, "workspaces/toml-fail"))
    assert Catalog.get_by_slug("toml-fail") == nil
  end

  test "workspace mkdir failure preserves TOML and does not insert SQLite row" do
    root = tmp_root!()

    assert {:error, {:workspace_mkdir_failed, :eacces}} =
             Spawner.create_and_start(valid_params("mkdir-fail"),
               root: root,
               mkdir: fn _path -> {:error, :eacces} end,
               lifecycle_start: unexpected_lifecycle()
             )

    assert File.exists?(Path.join(root, "citizens/citizen-mkdir-fail.toml"))
    assert Catalog.get_by_slug("mkdir-fail") == nil
  end

  test "lifecycle failure leaves durable failed row with redacted last_error" do
    root = tmp_root!()

    assert {:error, {:lifecycle_start_failed, redacted}} =
             Spawner.create_and_start(valid_params("life-fail"),
               root: root,
               lifecycle_start: fn _config ->
                 {:error, {:tmux_failed, "api_token=super-secret"}}
               end
             )

    record = Catalog.get_by_slug("life-fail")
    assert record.status == "failed"
    assert record.last_error == redacted
    assert redacted =~ "[REDACTED]"
    refute redacted =~ "super-secret"
  end

  test "lifecycle exception leaves durable failed row with redacted last_error" do
    root = tmp_root!()

    assert {:error, {:lifecycle_start_failed, redacted}} =
             Spawner.create_and_start(valid_params("life-raise"),
               root: root,
               lifecycle_start: fn _config ->
                 raise "api_token=super-secret"
               end
             )

    record = Catalog.get_by_slug("life-raise")
    assert record.status == "failed"
    assert record.last_error == redacted
    assert redacted =~ "[REDACTED]"
    refute redacted =~ "super-secret"
  end

  test "lifecycle exit leaves durable failed row with redacted last_error" do
    root = tmp_root!()

    assert {:error, {:lifecycle_start_failed, redacted}} =
             Spawner.create_and_start(valid_params("life-exit"),
               root: root,
               lifecycle_start: fn _config ->
                 exit({:noproc, "api_token=exit-value"})
               end
             )

    record = Catalog.get_by_slug("life-exit")
    assert record.status == "failed"
    assert record.last_error == redacted
    assert redacted =~ "[REDACTED]"
    refute redacted =~ "exit-value"
  end

  test "same-slug creates serialize while different slugs proceed independently" do
    root = tmp_root!()
    parent = self()

    lifecycle = fn config ->
      send(parent, {:lifecycle_entered, config.slug, self()})

      if config.slug == "lock-a" do
        receive do
          :release -> {:ok, self()}
        after
          2_000 -> {:error, :timeout}
        end
      else
        {:ok, self()}
      end
    end

    task_a =
      Task.async(fn ->
        Spawner.create_and_start(valid_params("lock-a"), root: root, lifecycle_start: lifecycle)
      end)

    assert_receive {:lifecycle_entered, "lock-a", pid_a}

    same_slug_task =
      Task.async(fn ->
        Spawner.create_and_start(valid_params("lock-a"), root: root, lifecycle_start: lifecycle)
      end)

    different_slug_task =
      Task.async(fn ->
        Spawner.create_and_start(valid_params("lock-b"), root: root, lifecycle_start: lifecycle)
      end)

    assert_receive {:lifecycle_entered, "lock-b", _pid_b}, 500
    assert {:ok, %Babs.Citizens.CitizenRecord{slug: "lock-b"}} = Task.await(different_slug_task)
    refute_receive {:lifecycle_entered, "lock-a", _second_pid}, 100

    send(pid_a, :release)
    assert {:ok, %Babs.Citizens.CitizenRecord{slug: "lock-a"}} = Task.await(task_a)
    assert {:error, {:duplicate_toml, _path}} = Task.await(same_slug_task)

    assert Repo.aggregate(Babs.Citizens.CitizenRecord, :count, :id) == 2
  end

  test "same-slug lock returns timeout instead of waiting indefinitely" do
    root = tmp_root!()
    parent = self()

    lifecycle = fn config ->
      send(parent, {:lifecycle_entered, config.slug, self()})

      receive do
        :release -> {:ok, self()}
      after
        2_000 -> {:error, :timeout}
      end
    end

    task =
      Task.async(fn ->
        Spawner.create_and_start(valid_params("lock-timeout"),
          root: root,
          lifecycle_start: lifecycle
        )
      end)

    assert_receive {:lifecycle_entered, "lock-timeout", pid}

    assert {:error, {:spawn_lock_timeout, "lock-timeout"}} =
             Spawner.create_and_start(valid_params("lock-timeout"),
               root: root,
               lifecycle_start: unexpected_lifecycle(),
               lock_timeout_ms: 20
             )

    send(pid, :release)
    assert {:ok, %Babs.Citizens.CitizenRecord{slug: "lock-timeout"}} = Task.await(task)
  end

  defp valid_params(slug) do
    %{
      "slug" => slug,
      "display_name" => String.capitalize(slug),
      "cli_preset" => "shell",
      "cwd" => slug
    }
  end

  defp unexpected_lifecycle do
    fn _config -> flunk("lifecycle should not be called") end
  end
end
