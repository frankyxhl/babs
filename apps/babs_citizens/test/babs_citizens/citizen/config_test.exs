defmodule Babs.Citizens.Citizen.ConfigTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

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
    cwd = "tester"
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
    cwd = "reader"
    """)

    assert {:ok, config} = Config.load_slug("reader", root: root)
    assert config.path == Path.join(root, "citizens/citizen-reader.toml")
    assert config.cwd == Path.join(root, "workspaces/reader")
  end

  test "custom workspace_root resolves relative cwd outside the application root" do
    root = tmp_root()
    workspace_root = Path.join(System.tmp_dir!(), "babs-workspace-root-#{unique()}")
    File.mkdir_p!(Path.join(root, "citizens"))

    File.write!(Path.join(root, "citizens/citizen-sentinel.toml"), """
    id = "BAB-CIT-SENTINEL"
    slug = "sentinel"
    display_name = "Sentinel"
    cli = "/bin/zsh"
    cwd = "sentinel"
    """)

    assert {:ok, config} =
             Config.load_slug("sentinel", root: root, workspace_root: workspace_root)

    assert config.path == Path.join(root, "citizens/citizen-sentinel.toml")
    assert config.cwd == Path.join(workspace_root, "sentinel")
    assert File.dir?(Path.join(workspace_root, "sentinel"))
    refute File.exists?(Path.join(root, "workspaces/sentinel"))
  end

  test "relative workspace_root values expand from root, not process cwd" do
    root = tmp_root()
    File.mkdir_p!(Path.join(root, "citizens"))

    path = Path.join(root, "citizens/citizen-relative.toml")

    File.write!(path, """
    id = "BAB-CIT-RELATIVE"
    slug = "relative"
    display_name = "Relative"
    cli = "/bin/zsh"
    cwd = "relative"
    """)

    assert {:ok, config} = Config.load_file(path, root: root, workspace_root: "state/workspaces")
    assert config.cwd == Path.join(root, "state/workspaces/relative")
  end

  test "app config workspace_root is used when no option override is supplied" do
    root = tmp_root()
    workspace_root = Path.join(System.tmp_dir!(), "babs-app-workspace-root-#{unique()}")
    original = Application.get_env(:babs_citizens, :workspace_root)

    try do
      Application.put_env(:babs_citizens, :workspace_root, workspace_root)
      File.mkdir_p!(Path.join(root, "citizens"))

      path = Path.join(root, "citizens/citizen-app-config.toml")

      File.write!(path, """
      id = "BAB-CIT-APP-CONFIG"
      slug = "app-config"
      display_name = "App Config"
      cli = "/bin/zsh"
      cwd = "app-config"
      """)

      assert {:ok, config} = Config.load_file(path, root: root)
      assert config.cwd == Path.join(workspace_root, "app-config")
    after
      if original do
        Application.put_env(:babs_citizens, :workspace_root, original)
      else
        Application.delete_env(:babs_citizens, :workspace_root)
      end
    end
  end

  test "invalid app config workspace_root falls back to default root with warning" do
    root = tmp_root()
    original = Application.get_env(:babs_citizens, :workspace_root)

    try do
      Application.put_env(:babs_citizens, :workspace_root, 123)
      File.mkdir_p!(Path.join(root, "citizens"))

      path = Path.join(root, "citizens/citizen-invalid-workspace-root.toml")

      File.write!(path, """
      id = "BAB-CIT-INVALID-WORKSPACE-ROOT"
      slug = "invalid-workspace-root"
      display_name = "Invalid Workspace Root"
      cli = "/bin/zsh"
      cwd = "invalid-workspace-root"
      """)

      log =
        capture_log(fn ->
          assert {:ok, config} = Config.load_file(path, root: root)
          assert config.cwd == Path.join(root, "workspaces/invalid-workspace-root")
        end)

      assert log =~ "workspace_root 123 is not a string"
    after
      if original do
        Application.put_env(:babs_citizens, :workspace_root, original)
      else
        Application.delete_env(:babs_citizens, :workspace_root)
      end
    end
  end

  test "absolute cwd bypasses workspace_root" do
    root = tmp_root()
    workspace_root = Path.join(System.tmp_dir!(), "babs-workspace-root-#{unique()}")
    absolute_cwd = Path.join(System.tmp_dir!(), "babs-absolute-cwd-#{unique()}")
    File.mkdir_p!(Path.join(root, "citizens"))

    path = Path.join(root, "citizens/citizen-absolute.toml")

    File.write!(path, """
    id = "BAB-CIT-ABSOLUTE"
    slug = "absolute"
    display_name = "Absolute"
    cli = "/bin/zsh"
    cwd = "#{absolute_cwd}"
    """)

    assert {:ok, config} = Config.load_file(path, root: root, workspace_root: workspace_root)
    assert config.cwd == absolute_cwd
    assert File.dir?(absolute_cwd)
    refute File.exists?(Path.join(workspace_root, "absolute"))
  end

  test "create_cwd false resolves cwd without creating the directory" do
    root = tmp_root()
    File.mkdir_p!(Path.join(root, "citizens"))

    path = Path.join(root, "citizens/citizen-no-create.toml")

    File.write!(path, """
    id = "BAB-CIT-NO-CREATE"
    slug = "no-create"
    display_name = "No Create"
    cli = "/bin/zsh"
    cwd = "no-create"
    """)

    assert {:ok, config} = Config.load_file(path, root: root, create_cwd: false)
    assert config.cwd == Path.join(root, "workspaces/no-create")
    refute File.exists?(config.cwd)
  end

  test "legacy workspaces-prefixed cwd values warn after workspace_root split" do
    root = tmp_root()
    File.mkdir_p!(Path.join(root, "citizens"))

    path = Path.join(root, "citizens/citizen-legacy.toml")

    File.write!(path, """
    id = "BAB-CIT-LEGACY"
    slug = "legacy"
    display_name = "Legacy"
    cli = "/bin/zsh"
    cwd = "workspaces/legacy"
    """)

    log =
      capture_log(fn ->
        assert {:ok, config} = Config.load_file(path, root: root)
        assert config.cwd == Path.join(root, "workspaces/workspaces/legacy")
      end)

    assert log =~ "uses legacy cwd"
    assert log =~ "workspaces/legacy"
  end

  test "legacy workspaces-prefixed cwd warning allows leading dot segment" do
    root = tmp_root()
    File.mkdir_p!(Path.join(root, "citizens"))

    path = Path.join(root, "citizens/citizen-legacy-dot.toml")

    File.write!(path, """
    id = "BAB-CIT-LEGACY-DOT"
    slug = "legacy-dot"
    display_name = "Legacy Dot"
    cli = "/bin/zsh"
    cwd = "./workspaces/legacy-dot"
    """)

    log =
      capture_log(fn ->
        assert {:ok, config} = Config.load_file(path, root: root)
        assert config.cwd == Path.join(root, "workspaces/workspaces/legacy-dot")
      end)

    assert log =~ "uses legacy cwd"
    assert log =~ "./workspaces/legacy-dot"
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
    cwd = "env"

    [env]
    TOKEN = "${BABS_DOES_NOT_EXIST}"
    """)

    assert {:error, {"TOKEN", {:missing_env, "BABS_DOES_NOT_EXIST"}}} =
             Config.load_file(missing_env, root: root)
  end

  test "reports unsupported env TOML values as validation errors" do
    root = tmp_root()
    File.mkdir_p!(Path.join(root, "citizens"))

    path = Path.join(root, "citizens/citizen-env-value.toml")

    File.write!(path, """
    id = "BAB-CIT-ENV-VALUE"
    slug = "env-value"
    display_name = "Env Value"
    cli = "/bin/zsh"
    cwd = "env-value"

    [env]
    GOOD_NUMBER = 1
    BAD_ARRAY = ["not", "a", "string"]
    """)

    assert {:error, {"BAD_ARRAY", {:invalid_env_value, ["not", "a", "string"]}}} =
             Config.load_file(path, root: root)
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
    cwd = "args"
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
    cwd = "mixed"
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
             Config.load_file(path, root: root, workspace_root: root)

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
    cwd = "good"
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
    root = Path.join(System.tmp_dir!(), "babs-config-test-#{System.unique_integer([:positive])}")
    File.rm_rf!(root)
    root
  end

  defp unique, do: System.unique_integer([:positive])
end
