defmodule Babs.Citizens.Citizen.ConfigTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Citizen.Config

  test "loads a citizen TOML config and resolves environment interpolation" do
    root = tmp_root()
    File.mkdir_p!(Path.join(root, "citizens"))
    File.mkdir_p!(Path.join(root, "workspaces/tester"))
    System.put_env("BABS_TEST_TOKEN", "secret-token")

    path = Path.join(root, "citizens/citizen-tester.toml")

    File.write!(path, """
    id = "BAB-CIT-9999"
    slug = "tester"
    display_name = "Tester"
    cli = "/bin/zsh"
    cli_args = ["-f"]
    cwd = "workspaces/tester"
    description = "Test citizen"

    [env]
    BABS_TEST_TOKEN = "${BABS_TEST_TOKEN}"
    """)

    assert {:ok, config} = Config.load_file(path, root: root)
    assert config.id == "BAB-CIT-9999"
    assert config.slug == "tester"
    assert config.cli_args == ["-f"]
    assert config.env == %{"BABS_TEST_TOKEN" => "secret-token"}
    assert config.cwd == Path.join(root, "workspaces/tester")
  after
    System.delete_env("BABS_TEST_TOKEN")
  end

  test "rejects invalid slugs" do
    refute Config.valid_slug?("Bad")
    refute Config.valid_slug?("../bad")
    assert Config.valid_slug?("clare")
  end

  test "load_slug reads the conventional citizen file path" do
    root = tmp_root()
    File.mkdir_p!(Path.join(root, "citizens"))

    File.write!(Path.join(root, "citizens/citizen-reader.toml"), """
    id = "BAB-CIT-9998"
    slug = "reader"
    display_name = "Reader"
    cli = "/bin/zsh"
    cwd = "workspaces/reader"
    """)

    assert {:ok, config} = Config.load_slug("reader", root: root)
    assert config.path == Path.join(root, "citizens/citizen-reader.toml")
    assert config.cwd == Path.join(root, "workspaces/reader")
  end

  test "reports missing required keys and missing environment interpolation" do
    root = tmp_root()
    File.mkdir_p!(Path.join(root, "citizens"))
    missing_required = Path.join(root, "citizens/citizen-bad.toml")

    File.write!(missing_required, """
    id = "BAB-CIT-BAD"
    slug = "bad"
    cli = "/bin/zsh"
    """)

    assert {:error, {:missing_required_keys, missing}} =
             Config.load_file(missing_required, root: root)

    assert "display_name" in missing
    assert "cwd" in missing

    missing_env = Path.join(root, "citizens/citizen-env.toml")

    File.write!(missing_env, """
    id = "BAB-CIT-ENV"
    slug = "env"
    display_name = "Env"
    cli = "/bin/zsh"
    cwd = "workspaces/env"

    [env]
    TOKEN = "${BABS_DOES_NOT_EXIST}"
    """)

    assert {:error, {"TOKEN", {:missing_env, "BABS_DOES_NOT_EXIST"}}} =
             Config.load_file(missing_env, root: root)
  end

  test "rejects malformed cli_args before runner construction" do
    root = tmp_root()
    File.mkdir_p!(Path.join(root, "citizens"))

    string_args = Path.join(root, "citizens/citizen-string-args.toml")

    File.write!(string_args, """
    id = "BAB-CIT-ARGS"
    slug = "args"
    display_name = "Args"
    cli = "/bin/zsh"
    cli_args = "-f"
    cwd = "workspaces/args"
    """)

    assert {:error, {:invalid_cli_args, "-f"}} =
             Config.load_file(string_args, root: root)

    mixed_args = Path.join(root, "citizens/citizen-mixed-args.toml")

    File.write!(mixed_args, """
    id = "BAB-CIT-MIXED"
    slug = "mixed"
    display_name = "Mixed"
    cli = "/bin/zsh"
    cli_args = ["-f", 1]
    cwd = "workspaces/mixed"
    """)

    assert {:error, {:invalid_cli_args, ["-f", 1]}} =
             Config.load_file(mixed_args, root: root)
  end

  test "reports workspace directory creation failures" do
    root = tmp_root()
    File.mkdir_p!(Path.join(root, "citizens"))
    File.write!(Path.join(root, "blocked"), "not a directory")

    path = Path.join(root, "citizens/citizen-blocked.toml")

    File.write!(path, """
    id = "BAB-CIT-BLOCKED"
    slug = "blocked"
    display_name = "Blocked"
    cli = "/bin/zsh"
    cwd = "blocked/workspace"
    """)

    assert {:error, {:cwd_mkdir_failed, failed_path, reason}} =
             Config.load_file(path, root: root)

    assert failed_path == Path.join(root, "blocked/workspace")
    assert reason in [:enotdir, :eexist, :eacces]
  end

  test "list_configs returns loaded configs and preserves decode errors" do
    root = tmp_root()
    File.mkdir_p!(Path.join(root, "citizens"))

    File.write!(Path.join(root, "citizens/citizen-good.toml"), """
    id = "BAB-CIT-GOOD"
    slug = "good"
    display_name = "Good"
    cli = "/bin/zsh"
    cwd = "workspaces/good"
    """)

    File.write!(Path.join(root, "citizens/citizen-bad.toml"), "not toml ===")

    results = Config.list_configs(root: root)

    assert Enum.any?(results, &match?({:ok, %{slug: "good"}}, &1))
    assert Enum.any?(results, &match?({:error, {:toml_decode_failed, _path, _reason}}, &1))
  end

  test "load_file reports file errors" do
    assert {:error, {:toml_decode_failed, _path, reason}} =
             Config.load_file(Path.join(tmp_root(), "missing.toml"))

    assert reason =~ ":enoent"
  end

  defp tmp_root do
    Path.join(System.tmp_dir!(), "babs-config-test-#{System.unique_integer([:positive])}")
  end
end
