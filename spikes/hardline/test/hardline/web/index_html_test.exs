defmodule Hardline.Web.IndexHtmlTest do
  use ExUnit.Case, async: true

  test "declares the Phase 0b full-window URL contract" do
    html = index_html()

    assert html =~ "const requestedFullMode = params.get(\"full\") === \"1\";"
    assert html =~ "const requestedSession = params.get(\"session\") || \"\";"
    assert html =~ "document.body.classList.add(\"full-mode\")"
    assert html =~ "function fullUrl(slug)"
    assert html =~ "url.searchParams.set(\"session\", slug)"
    assert html =~ "url.searchParams.set(\"full\", \"1\")"
  end

  test "keeps full-window mode browser-only and manager-launched" do
    html = index_html()

    assert html =~ "Open Full"
    assert html =~ "window.open(fullUrl(slug), \"_blank\")"
    assert html =~ "elements.openFull.disabled = !active.alive"
    assert html =~ "openFullSession(active.slug)"
    refute html =~ "fullButton"
    refute html =~ "full-open"
  end

  test "offers shell presets with tmux default selected first and no command field" do
    html = index_html()

    assert html =~ "id=\"command-preset\""
    assert html =~ "<option value=\"\" selected>Default tmux shell</option>"
    assert html =~ "<option value=\"/bin/zsh -f\">zsh fast shell</option>"
    assert html =~ "function selectedCommand()"
    assert html =~ "command: selectedCommand()"
    refute html =~ "Custom command"
    refute html =~ "custom-command-label"
  end

  test "uses icons on commands and status dots for session state" do
    html = index_html()

    assert html =~ "lucide.min.js"
    assert html =~ "window.lucide.createIcons()"
    assert html =~ "data-lucide=\"refresh-cw\""
    assert html =~ "data-lucide=\"plus\""
    assert html =~ "data-lucide=\"shuffle\""
    assert html =~ "data-lucide=\"external-link\""
    assert html =~ "data-lucide=\"square\""
    assert html =~ "className = `status-dot ${session.alive ? \"up\" : \"down\"}`"
    refute html =~ ">up<"
    refute html =~ ">down<"
  end

  test "prefills session slugs from fruit and character suggestions" do
    html = index_html()

    assert html =~ "id=\"slug-reroll\""
    assert html =~ "placeholder=\"mango-scout\""
    assert html =~ "const slugFruits = ["
    assert html =~ "\"dragonfruit\""
    assert html =~ "const slugCharacters = ["
    assert html =~ "\"scout\""
    assert html =~ "function suggestSlug()"
    assert html =~ "function suggestSlugIfEmpty()"
    assert html =~ "elements.slugReroll.addEventListener(\"click\""
  end

  test "provides full-window layout and error affordances" do
    html = index_html()

    assert html =~ "body.full-mode"
    assert html =~ "body.full-mode aside"
    assert html =~ "body.full-mode #terminal"
    assert html =~ "width: 100vw;"
    assert html =~ "height: 100vh;"
    assert html =~ "id=\"full-overlay\""
    assert html =~ "function showFullError(text)"
    assert html =~ "Session not found: ${slug}"
    assert html =~ "Back to manager"
  end

  defp index_html do
    :hardline
    |> :code.priv_dir()
    |> Path.join("static/index.html")
    |> File.read!()
  end
end
