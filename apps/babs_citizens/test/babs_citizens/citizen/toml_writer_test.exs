defmodule Babs.Citizens.Citizen.TomlWriterTest do
  use ExUnit.Case, async: false

  alias Babs.Citizens.Citizen.Config
  alias Babs.Citizens.Citizen.TomlWriter
  alias Babs.Citizens.CitizenConfig

  test "writes readable TOML under configured config_dir and round-trips resolved cwd" do
    root = tmp_root()
    workspace_root = Path.join(root, "custom-workspaces")

    config = %CitizenConfig{
      id: "BAB-CIT-TOML",
      slug: "toml-writer",
      display_name: "Toml \"Writer\"",
      description: "Line one\\two\nLine two",
      cli: "/bin/zsh",
      cli_args: [],
      cwd: Path.join(workspace_root, "toml-cwd"),
      env: %{},
      role: nil
    }

    assert {:ok, path} =
             TomlWriter.write(config,
               root: root,
               config_dir: "custom-citizens",
               workspace_root: workspace_root,
               toml_cwd: "toml-cwd"
             )

    assert path == Path.join(root, "custom-citizens/citizen-toml-writer.toml")
    content = File.read!(path)
    assert content =~ ~s(display_name = "Toml \\"Writer\\"")
    assert content =~ ~s(description = "Line one\\\\two\\nLine two")
    assert content =~ "cli_args = []"
    refute content =~ "[env]"
    refute content =~ "role"

    assert {:ok, loaded} = Config.load_file(path, root: root, workspace_root: workspace_root)
    assert loaded.display_name == ~s(Toml "Writer")
    assert loaded.description == "Line one\\two\nLine two"
    assert loaded.cli_args == []
    assert loaded.cwd == Path.join(workspace_root, "toml-cwd")
  end

  test "removes stale temp files and refuses to overwrite an existing final TOML" do
    root = tmp_root()
    dir = Path.join(root, "citizens")
    File.mkdir_p!(dir)
    stale = Path.join(dir, ".citizen-existing.123.toml.tmp")
    File.write!(stale, "stale")

    config = %CitizenConfig{
      id: "BAB-CIT-EXISTING",
      slug: "existing",
      display_name: "Existing",
      cli: "/bin/zsh",
      cli_args: ["-f"],
      cwd: Path.join(root, "workspaces/existing"),
      env: %{}
    }

    assert {:ok, path} = TomlWriter.write(config, root: root, toml_cwd: "existing")
    refute File.exists?(stale)

    assert {:error, {:toml_already_exists, ^path}} =
             TomlWriter.write(config, root: root, toml_cwd: "existing")
  end

  test "does not overwrite a final TOML created immediately before install" do
    root = tmp_root()
    dir = Path.join(root, "citizens")
    final_path = Path.join(dir, "citizen-race.toml")

    config = %CitizenConfig{
      id: "BAB-CIT-RACE",
      slug: "race",
      display_name: "Race",
      cli: "/bin/zsh",
      cli_args: ["-f"],
      cwd: Path.join(root, "workspaces/race"),
      env: %{}
    }

    assert {:error, {:toml_already_exists, ^final_path}} =
             TomlWriter.write(config,
               root: root,
               toml_cwd: "race",
               before_install: fn ^final_path ->
                 File.write!(final_path, "external\n")
                 :ok
               end
             )

    assert File.read!(final_path) == "external\n"
    refute Enum.any?(File.ls!(dir), &String.ends_with?(&1, ".toml.tmp"))
  end

  test "returns typed error when temp cleanup cannot list config dir" do
    root = tmp_root()
    dir = Path.join(root, "citizens")

    config = %CitizenConfig{
      id: "BAB-CIT-LIST-FAIL",
      slug: "list-fail",
      display_name: "List Fail",
      cli: "/bin/zsh",
      cli_args: ["-f"],
      cwd: Path.join(root, "workspaces/list-fail"),
      env: %{}
    }

    assert {:error, {:toml_temp_cleanup_failed, ^dir, :eacces}} =
             TomlWriter.write(config,
               root: root,
               toml_cwd: "list-fail",
               list_dir: fn ^dir -> {:error, :eacces} end
             )

    refute File.exists?(Path.join(dir, "citizen-list-fail.toml"))
  end

  defp tmp_root do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-toml-writer-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end
end
