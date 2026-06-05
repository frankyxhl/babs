defmodule Babs.KnowledgeTest do
  use ExUnit.Case, async: true

  alias Babs.Knowledge

  test "list returns sorted visible root markdown names and omits hidden temp backup and symlink entries" do
    root = tmp_root()
    home = home(root, "clare")
    File.mkdir_p!(home)

    File.write!(Path.join(home, "B.md"), "b")
    File.write!(Path.join(home, "A.md"), "a")
    File.write!(Path.join(home, "notes.txt"), "txt")
    File.write!(Path.join(home, ".Hidden.md"), "hidden")
    File.write!(Path.join(home, "~Draft.md"), "backup")
    File.write!(Path.join(home, "Draft.md~"), "backup")
    File.write!(Path.join(home, "#Draft.md#"), "backup")
    File.write!(Path.join(home, "Draft.md.tmp"), "temp")
    File.write!(Path.join(home, "Upper.MD"), "upper")
    File.mkdir_p!(Path.join(home, "Directory.md"))

    outside = Path.join(root, "outside.md")
    File.write!(outside, "outside")
    File.ln_s!(outside, Path.join(home, "Linked.md"))

    assert Knowledge.list("clare", opts(root)) == {:ok, ["A.md", "B.md"]}
  end

  test "list returns empty for a missing Citizen home" do
    root = tmp_root()

    assert Knowledge.list("clare", opts(root)) == {:ok, []}
  end

  test "read write and delete round trip through nested markdown paths" do
    root = tmp_root()
    final_path = Path.join(home(root, "clare"), "notes/Readme.md")

    assert :ok = Knowledge.write("clare", "notes/Readme.md", "hello\n", opts(root))
    assert File.read!(final_path) == "hello\n"
    assert Knowledge.read("clare", "notes/Readme.md", opts(root)) == {:ok, "hello\n"}

    assert :ok = Knowledge.delete("clare", "notes/Readme.md", opts(root))
    refute File.exists?(final_path)

    assert Knowledge.read("clare", "notes/Readme.md", opts(root)) ==
             {:error, {:not_found, "notes/Readme.md"}}

    assert Knowledge.delete("clare", "notes/Readme.md", opts(root)) ==
             {:error, {:not_found, "notes/Readme.md"}}
  end

  test "write accepts empty markdown and rejects non-binary content" do
    root = tmp_root()

    assert :ok = Knowledge.write("clare", "Empty.md", "", opts(root))
    assert Knowledge.read("clare", "Empty.md", opts(root)) == {:ok, ""}

    assert Knowledge.write("clare", "Bad.md", 42, opts(root)) ==
             {:error, {:invalid_content, :not_binary}}
  end

  test "unsafe child paths are redacted and invalid slugs pass through" do
    root = tmp_root()
    absolute = Path.join(root, "secret.md")

    assert Knowledge.read("clare", "../secret.md", opts(root)) ==
             {:error, {:invalid_child_path, :path_traversal}}

    assert Knowledge.read("clare", "bad\0.md", opts(root)) ==
             {:error, {:invalid_child_path, :null_byte}}

    assert Knowledge.read("clare", 42, opts(root)) ==
             {:error, {:invalid_child_path, :not_string}}

    assert Knowledge.read("clare", "", opts(root)) == {:error, {:invalid_child_path, :empty}}

    absolute_result = Knowledge.read("clare", absolute, opts(root))
    assert absolute_result == {:error, {:invalid_child_path, :non_relative}}
    refute inspect(absolute_result) =~ root

    assert Knowledge.read("Bad", "Readme.md", opts(root)) == {:error, {:invalid_slug, "Bad"}}
  end

  test "non-markdown child paths are rejected after resolver validation" do
    root = tmp_root()

    assert Knowledge.read("clare", "Readme.txt", opts(root)) ==
             {:error, {:not_markdown, "Readme.txt"}}
  end

  test "rejects symlinked Citizen home before direct operations and list" do
    root = tmp_root()
    knowledge_root = Path.join(root, "knowledge")
    outside = Path.join(root, "outside")
    File.mkdir_p!(knowledge_root)
    File.mkdir_p!(outside)
    File.ln_s!(outside, Path.join(knowledge_root, "clare"))

    expected = {:error, {:unsafe_symlink, %{path: "Readme.md", component: "knowledge/clare"}}}

    assert Knowledge.read("clare", "Readme.md", opts(root)) == expected
    assert Knowledge.write("clare", "Readme.md", "new", opts(root)) == expected
    assert Knowledge.delete("clare", "Readme.md", opts(root)) == expected

    assert Knowledge.list("clare", opts(root)) ==
             {:error, {:unsafe_symlink, %{path: ".", component: "knowledge/clare"}}}
  end

  test "rejects symlinked knowledge root before write creates the Citizen home" do
    root = tmp_root()
    outside = Path.join(root, "outside")
    knowledge_root = Path.join(root, "knowledge")
    File.mkdir_p!(root)
    File.mkdir_p!(outside)
    File.ln_s!(outside, knowledge_root)

    expected = {:error, {:unsafe_symlink, %{path: "Readme.md", component: "knowledge"}}}

    assert Knowledge.read("clare", "Readme.md", opts(root)) == expected
    assert Knowledge.write("clare", "Readme.md", "new", opts(root)) == expected
    assert Knowledge.delete("clare", "Readme.md", opts(root)) == expected

    refute File.exists?(Path.join(outside, "clare/Readme.md"))

    assert Knowledge.list("clare", opts(root)) ==
             {:error, {:unsafe_symlink, %{path: ".", component: "knowledge"}}}
  end

  test "rejects symlinked configured root ancestry before the knowledge root" do
    root = tmp_root()
    outside = Path.join(root, "outside")
    File.mkdir_p!(root)
    File.mkdir_p!(outside)
    File.ln_s!(outside, Path.join(root, "state"))
    opts = [root: root, knowledge_root: "state/knowledge"]

    expected = {:error, {:unsafe_symlink, %{path: "Readme.md", component: "state"}}}

    assert Knowledge.read("clare", "Readme.md", opts) == expected
    assert Knowledge.write("clare", "Readme.md", "new", opts) == expected
    assert Knowledge.delete("clare", "Readme.md", opts) == expected

    refute File.exists?(Path.join(outside, "knowledge/clare/Readme.md"))

    assert Knowledge.list("clare", opts) ==
             {:error, {:unsafe_symlink, %{path: ".", component: "state"}}}
  end

  test "rejects symlinked absolute knowledge root outside the configured root" do
    base = tmp_root()
    root = Path.join(base, "root")
    knowledge_root = Path.join(base, "knowledge-link")
    outside = Path.join(base, "outside")
    File.mkdir_p!(Path.dirname(knowledge_root))
    File.mkdir_p!(outside)
    File.ln_s!(outside, knowledge_root)
    opts = [root: root, knowledge_root: knowledge_root]

    expected = {:error, {:unsafe_symlink, %{path: "Readme.md", component: "knowledge-link"}}}

    assert Knowledge.read("clare", "Readme.md", opts) == expected
    assert Knowledge.write("clare", "Readme.md", "new", opts) == expected
    assert Knowledge.delete("clare", "Readme.md", opts) == expected

    refute File.exists?(Path.join(outside, "clare/Readme.md"))

    assert Knowledge.list("clare", opts) ==
             {:error, {:unsafe_symlink, %{path: ".", component: "knowledge-link"}}}
  end

  test "rejects symlinked absolute knowledge root ancestry outside the configured root" do
    base = tmp_root()
    root = Path.join(base, "root")
    outside = Path.join(base, "outside")
    link = Path.join(base, "state-link")
    knowledge_root = Path.join(link, "knowledge")
    File.mkdir_p!(root)
    File.mkdir_p!(outside)
    File.ln_s!(outside, link)
    opts = [root: root, knowledge_root: knowledge_root]

    expected = {:error, {:unsafe_symlink, %{path: "Readme.md", component: "state-link"}}}

    assert Knowledge.read("clare", "Readme.md", opts) == expected
    assert Knowledge.write("clare", "Readme.md", "new", opts) == expected
    assert Knowledge.delete("clare", "Readme.md", opts) == expected

    refute File.exists?(Path.join(outside, "knowledge/clare/Readme.md"))

    assert Knowledge.list("clare", opts) ==
             {:error, {:unsafe_symlink, %{path: ".", component: "state-link"}}}
  end

  test "rejects symlinked intermediate directories and target files" do
    root = tmp_root()
    home = home(root, "clare")
    outside = Path.join(root, "outside")
    File.mkdir_p!(home)
    File.mkdir_p!(outside)
    File.ln_s!(outside, Path.join(home, "notes"))

    expected_dir =
      {:error, {:unsafe_symlink, %{path: "notes/Readme.md", component: "knowledge/clare/notes"}}}

    assert Knowledge.read("clare", "notes/Readme.md", opts(root)) == expected_dir
    assert Knowledge.write("clare", "notes/Readme.md", "new", opts(root)) == expected_dir
    assert Knowledge.delete("clare", "notes/Readme.md", opts(root)) == expected_dir

    target = Path.join(root, "target.md")
    File.write!(target, "outside")
    File.ln_s!(target, Path.join(home, "Link.md"))

    assert Knowledge.read("clare", "Link.md", opts(root)) ==
             {:error, {:unsafe_symlink, %{path: "Link.md", component: "knowledge/clare/Link.md"}}}

    assert Knowledge.write("clare", "Link.md", "new", opts(root)) ==
             {:error, {:unsafe_symlink, %{path: "Link.md", component: "knowledge/clare/Link.md"}}}

    assert Knowledge.delete("clare", "Link.md", opts(root)) ==
             {:error, {:unsafe_symlink, %{path: "Link.md", component: "knowledge/clare/Link.md"}}}
  end

  test "write removes stale temp files but keeps recent temp files" do
    root = tmp_root()
    home = home(root, "clare")
    File.mkdir_p!(home)

    stale = Path.join(home, ".Readme.md.123.babs.md.tmp")
    recent = Path.join(home, ".Readme.md.456.babs.md.tmp")
    File.write!(stale, "stale")
    File.write!(recent, "recent")

    assert :ok =
             Knowledge.write("clare", "Readme.md", "new", opts(root, stale_temp_age_ms: 0))

    refute File.exists?(stale)
    refute File.exists?(recent)
    assert File.read!(Path.join(home, "Readme.md")) == "new"

    File.write!(recent, "recent")

    assert :ok = Knowledge.write("clare", "Readme.md", "newer", opts(root))
    assert File.read!(recent) == "recent"
  end

  test "atomic write hook sees old final content and cleans temp files on success and hook failure" do
    root = tmp_root()
    final_path = Path.join(home(root, "clare"), "Readme.md")
    File.mkdir_p!(Path.dirname(final_path))
    File.write!(final_path, "old")
    parent = self()

    assert :ok =
             Knowledge.write(
               "clare",
               "Readme.md",
               "new",
               opts(root,
                 before_rename: fn temp_path, ^final_path ->
                   assert File.read!(final_path) == "old"
                   assert File.read!(temp_path) == "new"
                   send(parent, {:before_rename, temp_path})
                   :ok
                 end
               )
             )

    assert_receive {:before_rename, temp_path}
    assert File.read!(final_path) == "new"
    refute File.exists?(temp_path)

    assert {:error, {:redacted_io_error, {:before_rename_knowledge, :stop}}} =
             Knowledge.write(
               "clare",
               "Readme.md",
               "ignored",
               opts(root,
                 before_rename: fn temp_path, ^final_path ->
                   send(parent, {:failed_before_rename, temp_path})
                   {:error, :stop}
                 end
               )
             )

    assert_receive {:failed_before_rename, failed_temp_path}
    assert File.read!(final_path) == "new"
    refute File.exists?(failed_temp_path)

    assert {:error,
            {:redacted_io_error, {:before_rename_knowledge, {:unexpected_return, :unexpected}}}} =
             Knowledge.write(
               "clare",
               "Readme.md",
               "ignored",
               opts(root,
                 before_rename: fn temp_path, ^final_path ->
                   send(parent, {:unexpected_before_rename, temp_path})
                   :unexpected
                 end
               )
             )

    assert_receive {:unexpected_before_rename, unexpected_temp_path}
    assert File.read!(final_path) == "new"
    refute File.exists?(unexpected_temp_path)
  end

  test "write with if_exists error creates missing files and preserves existing files" do
    root = tmp_root()
    final_path = Path.join(home(root, "clare"), "Readme.md")

    assert :ok = Knowledge.write("clare", "Readme.md", "first\n", opts(root, if_exists: :error))
    assert File.read!(final_path) == "first\n"

    assert {:error, {:knowledge_file_exists, "Readme.md"}} =
             Knowledge.write("clare", "Readme.md", "second\n", opts(root, if_exists: :error))

    assert File.read!(final_path) == "first\n"
    refute Enum.any?(File.ls!(Path.dirname(final_path)), &String.ends_with?(&1, ".babs.md.tmp"))

    assert :ok = Knowledge.write("clare", "Readme.md", "replacement\n", opts(root))
    assert File.read!(final_path) == "replacement\n"
  end

  test "write with if_exists error does not call before_rename for existing files" do
    root = tmp_root()
    final_path = Path.join(home(root, "clare"), "Readme.md")
    File.mkdir_p!(Path.dirname(final_path))
    File.write!(final_path, "original\n")
    parent = self()

    assert {:error, {:knowledge_file_exists, "Readme.md"}} =
             Knowledge.write(
               "clare",
               "Readme.md",
               "ignored\n",
               opts(root,
                 if_exists: :error,
                 before_rename: fn _temp_path, ^final_path ->
                   send(parent, :before_rename_called)
                   :ok
                 end
               )
             )

    refute_receive :before_rename_called, 50
    assert File.read!(final_path) == "original\n"
  end

  test "write retries cross-runtime temp file collisions without truncating the in-flight temp" do
    root = tmp_root()
    home = home(root, "clare")
    final_path = Path.join(home, "Readme.md")
    File.mkdir_p!(home)

    colliding_temp = Path.join(home, ".Readme.md.collision.babs.md.tmp")
    File.write!(colliding_temp, "in-flight")

    {:ok, token_agent} = Agent.start_link(fn -> ["collision", "fresh"] end)

    token_fun = fn ->
      Agent.get_and_update(token_agent, fn
        [token | rest] -> {token, rest}
        [] -> flunk("temp token retried more times than expected")
      end)
    end

    assert :ok =
             Knowledge.write("clare", "Readme.md", "new", opts(root, temp_token_fun: token_fun))

    assert File.read!(final_path) == "new"
    assert File.read!(colliding_temp) == "in-flight"
    assert Agent.get(token_agent, & &1) == []
  end

  defp opts(root, extra \\ []) do
    [root: root, knowledge_root: "knowledge"] ++ extra
  end

  defp home(root, slug), do: Path.join(root, "knowledge/#{slug}")

  defp tmp_root do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-knowledge-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end
end
