defmodule BabsWeb.GitDiffComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BabsWeb.GitDiffComponent

  test "renders branch status and per-file diff lines" do
    html =
      render_component(&GitDiffComponent.git_diff/1,
        branch: %{name: "issue/example", detached?: false, truncated?: false},
        status: %{
          text: " M lib/example.ex\n?? test/example_test.ex\n",
          clean?: false,
          truncated?: false
        },
        diff: %{text: sample_diff(), truncated?: false, base: nil}
      )

    assert html =~ ~s(data-testid="git-diff-component")
    assert html =~ ~s(data-testid="git-diff-branch")
    assert html =~ "issue/example"
    assert html =~ ~s(data-testid="git-diff-status")
    assert html =~ "changed"
    assert html =~ ~s(data-testid="git-diff-status-text")
    assert html =~ " M lib/example.ex"
    assert html =~ ~s(data-testid="git-diff-file-lib-example-ex")
    assert html =~ ~s(data-line-kind="addition")
    assert html =~ ~s(data-line-kind="deletion")
    assert html =~ ~s(data-line-kind="hunk")
    assert html =~ ">defmodule Example do</span>"
    assert html =~ "new line"
    assert html =~ "old line"
  end

  test "renders an empty diff without crashing" do
    html =
      render_component(&GitDiffComponent.git_diff/1,
        branch: %{name: "main", detached?: false, truncated?: false},
        status: %{text: "", clean?: true, truncated?: false},
        diff: %{text: "", truncated?: false, base: nil}
      )

    assert html =~ ~s(data-testid="git-diff-empty")
    assert html =~ "No changes"
    assert html =~ "clean"
  end

  test "renders tagged errors with friendly copy" do
    html =
      render_component(&GitDiffComponent.git_diff/1,
        error:
          {:not_git_repo, %{workspace: "/tmp/not-a-repo", output: "fatal", truncated?: false}}
      )

    assert html =~ ~s(data-testid="git-diff-error")
    assert html =~ "Workspace is not a git repository"
    assert html =~ "/tmp/not-a-repo is not a git repository."
  end

  test "renders the truncation marker from bounded git output" do
    html =
      render_component(&GitDiffComponent.git_diff/1,
        branch: %{name: "main", detached?: false, truncated?: false},
        status: %{text: " M README.md\n", clean?: false, truncated?: false},
        diff: %{
          text: """
          diff --git a/README.md b/README.md
          --- a/README.md
          +++ b/README.md
          @@ -1 +1,2 @@
          -old
          +new
          [TRUNCATED]
          """,
          truncated?: true,
          base: nil
        }
      )

    assert html =~ ~s(data-testid="git-diff-truncated")
    assert html =~ ~s(data-line-kind="truncated")
    assert html =~ "[TRUNCATED]"
  end

  test "renders quoted git paths from diff headers" do
    html =
      render_component(&GitDiffComponent.git_diff/1,
        branch: %{name: "main", detached?: false, truncated?: false},
        status: %{text: " M #{<<195, 169>>}.txt\n M path with spaces.txt\n", clean?: false},
        diff: %{text: quoted_path_diff(), truncated?: false, base: nil}
      )

    assert html =~ <<195, 169>> <> ".txt"
    assert html =~ "path with spaces.txt"
    refute html =~ "<strong>Workspace diff</strong>"
  end

  test "preserves trailing whitespace in the last rendered diff line" do
    html =
      render_component(&GitDiffComponent.git_diff/1,
        branch: %{name: "main", detached?: false, truncated?: false},
        status: %{text: " M value.txt\n", clean?: false},
        diff: %{text: trailing_space_diff(), truncated?: false, base: nil}
      )

    assert html =~ ">value   </span>"
  end

  defp sample_diff do
    """
    diff --git a/lib/example.ex b/lib/example.ex
    index 1111111..2222222 100644
    --- a/lib/example.ex
    +++ b/lib/example.ex
    @@ -1,3 +1,3 @@
     defmodule Example do
    -  old line
    +  new line
     end
    """
  end

  defp trailing_space_diff do
    [
      "diff --git a/value.txt b/value.txt",
      "--- a/value.txt",
      "+++ b/value.txt",
      "@@ -1 +1 @@",
      "-old",
      "+value   \n"
    ]
    |> Enum.join("\n")
  end

  defp quoted_path_diff do
    ~S"""
    diff --git "a/\303\251.txt" "b/\303\251.txt"
    index 1111111..2222222 100644
    --- "a/\303\251.txt"
    +++ "b/\303\251.txt"
    @@ -1 +1 @@
    -old
    +new
    diff --git "a/path with spaces.txt" "b/path with spaces.txt"
    index 3333333..4444444 100644
    --- "a/path with spaces.txt"
    +++ "b/path with spaces.txt"
    @@ -1 +1 @@
    -old
    +new
    """
  end
end
