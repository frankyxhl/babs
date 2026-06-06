defmodule Babs.GitTest do
  use ExUnit.Case, async: true

  alias Babs.Git

  test "reads branch status log and default working tree diff" do
    repo = committed_repo()

    assert {:ok, %{name: "main", detached?: false, truncated?: false}} = Git.branch(repo)
    assert {:ok, %{text: "", clean?: true, truncated?: false}} = Git.status(repo)
    assert {:ok, %{text: log, truncated?: false}} = Git.log(repo)
    assert log =~ "initial"

    File.write!(Path.join(repo, "README.md"), "hello\nchanged\n")

    assert {:ok, %{text: status, clean?: false, truncated?: false}} = Git.status(repo)
    assert status =~ " M README.md"

    assert {:ok, %{text: diff, base: nil, truncated?: false}} = Git.diff(repo)
    assert diff =~ "diff --git"
    assert diff =~ "+changed"
  end

  test "default HEAD diff includes staged new files" do
    repo = committed_repo()

    File.write!(Path.join(repo, "NEW.md"), "new content\n")
    git!(repo, ["add", "NEW.md"])

    assert {:ok, %{text: diff, base: nil, truncated?: false}} = Git.diff(repo)
    assert diff =~ "new file mode"
    assert diff =~ "+new content"
  end

  test "default HEAD diff includes untracked files" do
    repo = committed_repo()
    base = git!(repo, ["rev-parse", "HEAD"]) |> String.trim()

    File.write!(Path.join(repo, "UNTRACKED.md"), "untracked content\n")

    assert {:ok, %{text: status, clean?: false}} = Git.status(repo)
    assert status =~ "?? UNTRACKED.md"

    assert {:ok, %{text: default_diff, base: nil, truncated?: false}} = Git.diff(repo)
    assert default_diff =~ "diff --git a/UNTRACKED.md b/UNTRACKED.md"
    assert default_diff =~ "new file mode 100644"
    assert default_diff =~ "--- /dev/null"
    assert default_diff =~ "+++ b/UNTRACKED.md"
    assert default_diff =~ "+untracked content"

    assert {:ok, %{text: base_diff, base: ^base, truncated?: false}} = Git.diff(repo, base: base)
    assert base_diff =~ "diff --git a/UNTRACKED.md b/UNTRACKED.md"
    assert base_diff =~ "+untracked content"
  end

  test "unborn default diff includes staged initial files" do
    repo = empty_repo()

    File.write!(Path.join(repo, "FIRST.md"), "first content\n")
    git!(repo, ["add", "FIRST.md"])

    assert {:ok, %{text: diff, base: nil, truncated?: false}} = Git.diff(repo)
    assert diff =~ "new file mode"
    assert diff =~ "+first content"
  end

  test "unborn default diff includes untracked initial files" do
    repo = empty_repo()

    File.write!(Path.join(repo, "FIRST.md"), "first content\n")

    assert {:ok, %{text: diff, base: nil, truncated?: false}} = Git.diff(repo)
    assert diff =~ "diff --git a/FIRST.md b/FIRST.md"
    assert diff =~ "new file mode 100644"
    assert diff =~ "+first content"
  end

  test "supports explicit diff base" do
    repo = committed_repo()
    base = git!(repo, ["rev-parse", "HEAD"]) |> String.trim()

    File.write!(Path.join(repo, "README.md"), "hello\nfrom base\n")

    assert {:ok, %{text: diff, base: ^base, truncated?: false}} = Git.diff(repo, base: base)
    assert diff =~ "+from base"
  end

  test "diff disables repository textconv filters" do
    repo = committed_repo()
    marker = Path.join(repo, "textconv-ran")
    script = Path.join(repo, "textconv.sh")

    File.write!(script, "#!/bin/sh\nprintf ran > #{marker}\ncat \"$1\"\n")
    File.chmod!(script, 0o755)
    File.write!(Path.join(repo, ".gitattributes"), "*.dat diff=evil\n")
    File.write!(Path.join(repo, "asset.dat"), "before\n")
    git!(repo, ["add", ".gitattributes", "asset.dat"])
    git!(repo, ["commit", "-m", "add textconv fixture"])
    git!(repo, ["config", "diff.evil.textconv", script])

    File.write!(Path.join(repo, "asset.dat"), "after\n")

    assert {:ok, %{text: diff}} = Git.diff(repo)
    assert diff =~ "+after"
    refute File.exists?(marker)
  end

  test "read commands disable repository fsmonitor hooks" do
    repo = committed_repo()
    marker = Path.join(repo, "fsmonitor-ran")
    script = Path.join(repo, "fsmonitor.sh")

    File.write!(script, "#!/bin/sh\nprintf ran > #{marker}\nexit 0\n")
    File.chmod!(script, 0o755)

    git!(repo, ["-c", "core.fsmonitor=#{script}", "status", "--porcelain=v1"])
    assert File.exists?(marker)
    File.rm!(marker)

    git!(repo, ["config", "core.fsmonitor", script])
    File.write!(Path.join(repo, "README.md"), "changed\n")

    assert {:ok, %{clean?: false}} = Git.status(repo)
    assert {:ok, %{text: diff}} = Git.diff(repo)
    assert diff =~ "+changed"
    refute File.exists?(marker)
  end

  test "diff disables repository clean filters" do
    repo = committed_repo()
    marker = Path.join(repo, "clean-filter-ran")
    script = Path.join(repo, "clean-filter.sh")

    File.write!(script, "#!/bin/sh\nprintf ran > #{marker}\ncat\n")
    File.chmod!(script, 0o755)
    File.write!(Path.join(repo, ".gitattributes"), "*.dat filter=evil\n")
    File.write!(Path.join(repo, "asset.dat"), "before\n")
    git!(repo, ["add", ".gitattributes", "asset.dat"])
    git!(repo, ["commit", "-m", "add clean filter fixture"])
    git!(repo, ["config", "filter.evil.clean", script])

    File.write!(Path.join(repo, "asset.dat"), "after\n")

    git!(repo, ["diff", "--no-ext-diff", "--no-textconv", "HEAD", "--", "asset.dat"])
    assert File.exists?(marker)
    File.rm!(marker)

    assert {:ok, %{text: diff}} = Git.diff(repo)
    assert diff =~ "+after"
    refute File.exists?(marker)
  end

  test "returns tagged errors for invalid workspaces and non-repos" do
    root = tmp_root()

    assert Git.status(42) == {:error, {:invalid_workspace, :not_binary}}

    assert Git.status(Path.join(root, "missing")) ==
             {:error, {:invalid_workspace, :not_directory}}

    non_repo = Path.join(root, "not-a-repo")
    File.mkdir_p!(non_repo)

    assert {:error, {:not_git_repo, %{output: output, truncated?: false}}} = Git.status(non_repo)
    assert output =~ "not a git repository"
  end

  test "validates max_bytes max_count and base before running git" do
    repo = committed_repo()

    assert Git.status(repo, max_bytes: 1) == {:error, {:invalid_max_bytes, 1}}
    assert Git.log(repo, max_count: 0) == {:error, {:invalid_max_count, 0}}
    assert Git.log(repo, max_count: 101) == {:error, {:invalid_max_count, 101}}

    assert Git.diff(repo, base: "--output=/tmp/owned") ==
             {:error, {:invalid_base, :starts_with_dash}}

    assert Git.diff(repo, base: " ") == {:error, {:invalid_base, :blank}}
    assert Git.diff(repo, base: "HEAD\0bad") == {:error, {:invalid_base, :null_byte}}
    assert Git.diff(repo, base: 123) == {:error, {:invalid_base, :not_binary}}
  end

  test "returns bounded tagged git failures" do
    repo = committed_repo()

    assert {:error, {:git_failed, failure}} = Git.diff(repo, base: "refs/heads/does-not-exist")

    assert Enum.take(failure.args, 2) == ["-c", "core.fsmonitor=false"]

    assert Enum.take(failure.args, -5) == [
             "diff",
             "--no-ext-diff",
             "--no-textconv",
             "refs/heads/does-not-exist",
             "--"
           ]

    assert failure.exit_status > 0
    assert is_binary(failure.output)
    assert failure.output != ""
    assert failure.truncated? == false
  end

  test "bounds large diff output with a truncation marker inside max_bytes" do
    repo = committed_repo()

    File.write!(
      Path.join(repo, "README.md"),
      Enum.map_join(1..200, "\n", &"line #{&1}") <> "\n"
    )

    assert {:ok, %{text: diff, truncated?: true}} = Git.diff(repo, max_bytes: 80)
    assert String.ends_with?(diff, "\n[TRUNCATED]")
    assert byte_size(diff) <= 80
    assert String.valid?(diff)
  end

  test "normalizes invalid utf8 output without truncating" do
    repo = committed_repo()

    File.write!(Path.join(repo, "README.md"), <<"hello\n", 255, "\n">>)

    assert {:ok, %{text: diff, truncated?: false}} = Git.diff(repo, max_bytes: 4_096)
    assert String.valid?(diff)
    assert diff =~ "+?"
    assert :binary.match(diff, <<255>>) == :nomatch
  end

  test "handles unborn repositories without crashing" do
    repo = empty_repo()

    assert {:ok, %{name: "main", detached?: false, truncated?: false}} = Git.branch(repo)
    assert {:ok, %{text: "", truncated?: false}} = Git.log(repo)
    assert {:ok, %{text: "", base: nil, truncated?: false}} = Git.diff(repo)
  end

  test "reports detached HEAD as a short sha branch name" do
    repo = committed_repo()
    short_sha = git!(repo, ["rev-parse", "--short", "HEAD"]) |> String.trim()
    git!(repo, ["checkout", "--detach", "HEAD"])

    assert {:ok, %{name: ^short_sha, detached?: true, truncated?: false}} = Git.branch(repo)
  end

  defp committed_repo do
    repo = empty_repo()
    File.write!(Path.join(repo, "README.md"), "hello\n")
    git!(repo, ["add", "README.md"])
    git!(repo, ["commit", "-m", "initial"])
    repo
  end

  defp empty_repo do
    repo = tmp_root()
    git!(repo, ["init"])
    git!(repo, ["checkout", "-b", "main"])
    git!(repo, ["config", "user.email", "babs@example.test"])
    git!(repo, ["config", "user.name", "Babs Test"])
    repo
  end

  defp git!(repo, args) do
    case System.cmd("git", args, cd: repo, stderr_to_stdout: true) do
      {output, 0} ->
        output

      {output, status} ->
        flunk("git #{Enum.join(args, " ")} failed with #{status}: #{output}")
    end
  end

  defp tmp_root do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-git-test-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end
end
