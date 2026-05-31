defmodule Babs.Knowledge.MarkdownTest do
  use ExUnit.Case, async: true

  alias Babs.Knowledge.Markdown

  test "parses string-keyed frontmatter and separates the body" do
    content = "---\ntitle: Clare Home\ntags: [ops, docs]\n:legacy: yes\n---\n# Hello\nBody\n"

    assert Markdown.parse(content) ==
             {:ok,
              {%{"title" => "Clare Home", "tags" => ["ops", "docs"], ":legacy" => "yes"},
               "# Hello\nBody\n"}}
  end

  test "missing frontmatter keeps the full body unchanged" do
    content = "\n---\ntitle: Not frontmatter\n---\nBody\n"

    assert Markdown.parse(content) == {:ok, {%{}, content}}
    assert Markdown.parse("") == {:ok, {%{}, ""}}
  end

  test "empty frontmatter supports adjacent fences and blank YAML" do
    assert Markdown.parse("---\n---\n") == {:ok, {%{}, ""}}
    assert Markdown.parse("---\n\n---\nBody") == {:ok, {%{}, "Body"}}
  end

  test "frontmatter fences support CRLF and trailing whitespace" do
    content = "---  \r\ntitle: CRLF\r\n---  \r\nBody\r\n"

    assert Markdown.parse(content) == {:ok, {%{"title" => "CRLF"}, "Body\r\n"}}
  end

  test "frontmatter fences must start at column zero" do
    content = "---\ntitle: Test\ndescription: |\n   ---\n   Body separator\n---\nBody\n"

    assert {:ok, {frontmatter, "Body\n"}} = Markdown.parse(content)
    assert frontmatter["title"] == "Test"
    assert frontmatter["description"] =~ "---\n"
    assert frontmatter["description"] =~ "Body separator"
  end

  test "rejects missing closing fence invalid YAML and non-map YAML" do
    assert Markdown.parse("---\ntitle: nope\nBody") ==
             {:error, {:invalid_frontmatter, :missing_closing_fence}}

    assert Markdown.parse("---\n" <> String.duplicate("x", 65_537)) ==
             {:error, {:invalid_frontmatter, :frontmatter_too_large}}

    assert {:error, {:invalid_frontmatter, {:yaml_decode_failed, _reason}}} =
             Markdown.parse("---\ntitle: [\n---\nBody")

    assert Markdown.parse("---\n- one\n---\nBody") ==
             {:error, {:invalid_frontmatter, :frontmatter_not_map}}
  end

  test "accepts frontmatter at the exact byte limit" do
    value = String.duplicate("x", 65_528)
    content = "---\ntitle: #{value}\n---\nBody"

    assert {:ok, {%{"title" => ^value}, "Body"}} = Markdown.parse(content)
  end

  test "rejects non-binary parse and render input" do
    assert Markdown.parse(42) == {:error, {:invalid_markdown, :not_string}}
    assert Markdown.render_body(42) == {:error, {:invalid_markdown, :not_string}}
  end

  test "renders combined frontmatter body and sanitized html" do
    content = "---\ntitle: Readme\n---\n**bold**"

    assert {:ok, %{frontmatter: %{"title" => "Readme"}, body: "**bold**", html: html}} =
             Markdown.render(content)

    assert html =~ "<strong>bold</strong>"

    assert Markdown.render("") == {:ok, %{frontmatter: %{}, body: "", html: ""}}
    assert Markdown.render(42) == {:error, {:invalid_markdown, :not_string}}
  end

  test "render propagates parse errors unchanged" do
    error = {:error, {:invalid_frontmatter, :frontmatter_not_map}}

    assert Markdown.parse("---\n- one\n---\nBody") == error
    assert Markdown.render("---\n- one\n---\nBody") == error
  end

  test "render propagates body render failures unchanged" do
    assert {:error, {:render_failed, %MDEx.DecodeError{}}} = Markdown.render_body(<<255>>)

    assert {:error, {:render_failed, %MDEx.DecodeError{}}} =
             Markdown.render("---\ntitle: Bad\n---\n" <> <<255>>)

    malformed = <<255, "  \n"::binary>>

    assert Markdown.parse(malformed) == {:ok, {%{}, malformed}}
    assert {:error, {:render_failed, %MDEx.DecodeError{}}} = Markdown.render(malformed)
  end

  test "renders empty and code block bodies" do
    assert Markdown.render_body("") == {:ok, ""}

    body = "```elixir\nIO.puts(\"hi\")\n```\n\n    indented\n"
    assert {:ok, html} = Markdown.render_body(body)

    assert html =~ "<pre"
    assert html =~ "<code"
    assert html =~ "IO"
    assert html =~ "puts"
    assert html =~ "indented"
  end

  test "renders selected commonmark extensions" do
    body = """
    ~~gone~~

    - [x] done

    | A |
    | - |
    | B |

    https://example.com
    """

    assert {:ok, html} = Markdown.render_body(body)

    assert html =~ "<del>gone</del>"
    assert html =~ "<table>"
    assert html =~ ~r/<li>\s*done<\/li>/
    refute html =~ "[x]"
    refute html =~ "<input"
    assert html =~ ~s(href="https://example.com")
  end

  test "sanitizes common raw html xss vectors" do
    body = ~s"""
    <script>alert(1)</script>
    <style>body { color: red }</style>
    <img src=x onerror="alert(2)">
    <svg onload="alert(3)"></svg>
    <a href="javascript:alert(4)">bad</a>
    <a href="JaVaScRiPt:alert(5)">mixed</a>
    <strong>safe</strong>
    <a href="https://example.com/safe">safe link</a>
    """

    assert {:ok, html} = Markdown.render_body(body)

    assert html =~ "<strong>safe</strong>"
    assert html =~ ~s(href="https://example.com/safe")
    refute html =~ "<script"
    refute html =~ "<style"
    refute html =~ "<svg"
    refute html =~ "onerror"
    refute html =~ "javascript"
    refute html =~ "JaVaScRiPt"
    refute html =~ "alert("
  end
end
