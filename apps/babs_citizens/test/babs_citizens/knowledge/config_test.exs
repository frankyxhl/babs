defmodule Babs.Citizens.Knowledge.ConfigTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Babs.Citizens.Knowledge.Config

  setup do
    old_root = Application.get_env(:babs_citizens, :root)
    old_workspace_root = Application.get_env(:babs_citizens, :workspace_root)
    old_knowledge_root = Application.get_env(:babs_citizens, :knowledge_root)

    on_exit(fn ->
      restore_env(:root, old_root)
      restore_env(:workspace_root, old_workspace_root)
      restore_env(:knowledge_root, old_knowledge_root)
    end)

    :ok
  end

  test "defaults Citizen knowledge homes under workspace_root without creating directories" do
    root = tmp_root()
    Application.put_env(:babs_citizens, :root, root)

    home = Path.join(root, "workspaces/clare")

    assert Config.root() == root
    assert Config.workspace_root() == Path.join(root, "workspaces")
    assert Config.knowledge_root() == Path.join(root, "workspaces")
    assert Config.citizen_home("clare") == {:ok, home}
    assert Config.resolve("clare", "Readme.md") == {:ok, Path.join(home, "Readme.md")}
    assert Config.resolve("clare", ".") == {:ok, home}
    refute File.exists?(home)
  end

  test "knowledge_root overrides workspace_root from app env or explicit opts" do
    root = tmp_root()
    app_knowledge_root = Path.join(root, "knowledge")
    opt_knowledge_root = Path.join(root, "custom-knowledge")

    Application.put_env(:babs_citizens, :root, root)
    Application.put_env(:babs_citizens, :workspace_root, Path.join(root, "workspaces"))
    Application.put_env(:babs_citizens, :knowledge_root, app_knowledge_root)

    assert Config.knowledge_root() == app_knowledge_root
    assert Config.citizen_home("dylan") == {:ok, Path.join(app_knowledge_root, "dylan")}

    assert Config.citizen_home("dylan", knowledge_root: opt_knowledge_root) ==
             {:ok, Path.join(opt_knowledge_root, "dylan")}
  end

  test "relative roots expand from the configured Babs root" do
    root = tmp_root()

    assert Config.workspace_root(root: root, workspace_root: "state/workspaces") ==
             Path.join(root, "state/workspaces")

    assert Config.knowledge_root(root: root, knowledge_root: "state/knowledge") ==
             Path.join(root, "state/knowledge")

    assert Config.citizen_home("elena", root: root, knowledge_root: "state/knowledge") ==
             {:ok, Path.join(root, "state/knowledge/elena")}
  end

  test "blank knowledge_root falls back to workspace_root" do
    root = tmp_root()
    Application.put_env(:babs_citizens, :root, root)
    Application.put_env(:babs_citizens, :workspace_root, Path.join(root, "workspace-home"))
    Application.put_env(:babs_citizens, :knowledge_root, "   ")

    assert Config.knowledge_root() == Path.join(root, "workspace-home")
    assert Config.knowledge_root(knowledge_root: "") == Path.join(root, "workspace-home")
  end

  test "non-string roots warn and fall back to defaults" do
    root = tmp_root()
    Application.put_env(:babs_citizens, :root, root)
    Application.put_env(:babs_citizens, :workspace_root, Path.join(root, "workspaces"))
    Application.put_env(:babs_citizens, :knowledge_root, 123)

    log =
      capture_log(fn ->
        assert Config.knowledge_root() == Path.join(root, "workspaces")
      end)

    assert log =~ "knowledge_root 123 is not a string"
  end

  test "rejects invalid slugs" do
    root = tmp_root()

    assert Config.citizen_home("../bad", root: root) == {:error, {:invalid_slug, "../bad"}}
    assert Config.resolve("Bad", "Readme.md", root: root) == {:error, {:invalid_slug, "Bad"}}
  end

  test "rejects unsafe relative paths before returning a resolved path" do
    root = tmp_root()

    cases = [
      {42, {:invalid_relative_path, 42}},
      {"", {:empty_relative_path, ""}},
      {"   ", {:empty_relative_path, "   "}},
      {"/etc/passwd", {:non_relative_path, "/etc/passwd"}},
      {"~/notes.md", {:non_relative_path, "~/notes.md"}},
      {"~other/notes.md", {:non_relative_path, "~other/notes.md"}},
      {"../secret.md", {:path_traversal, "../secret.md"}},
      {"notes/../secret.md", {:path_traversal, "notes/../secret.md"}},
      {"notes/\0bad.md", {:null_byte, "notes/\0bad.md"}}
    ]

    for {relative_path, reason} <- cases do
      assert Config.resolve("clare", relative_path, root: root) == {:error, reason}
    end
  end

  test "normalizes dot path segments while keeping paths inside the Citizen home" do
    root = tmp_root()
    home = Path.join(root, "knowledge/sentinel")

    assert Config.resolve("sentinel", "./notes/./Readme.md",
             root: root,
             knowledge_root: "knowledge"
           ) == {:ok, Path.join(home, "notes/Readme.md")}
  end

  defp tmp_root do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-knowledge-config-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    root
  end

  defp restore_env(key, nil), do: Application.delete_env(:babs_citizens, key)
  defp restore_env(key, value), do: Application.put_env(:babs_citizens, key, value)
end
