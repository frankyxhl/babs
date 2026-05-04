defmodule Hardline.Web.IndexHtmlTest do
  use ExUnit.Case, async: true

  test "declares the Phase 0b full-window URL contract" do
    core = static_file("js/hardline_core.js")
    manager = static_file("js/hardline_manager.js")

    assert core =~ "export function parsePageMode(search)"
    assert core =~ "params.get(\"full\") === \"1\""
    assert core =~ "params.get(\"session\") || \"\""
    assert manager =~ "document.body.classList.add(\"full-mode\")"
    assert core =~ "export function fullUrl(currentHref, slug)"
    assert core =~ "url.searchParams.set(\"session\", slug)"
    assert core =~ "url.searchParams.set(\"full\", \"1\")"
  end

  test "keeps full-window mode browser-only and manager-launched" do
    html = index_html()
    manager = static_file("js/hardline_manager.js")

    assert html =~ "Open Full"
    assert html =~ "data-testid=\"open-full-button\""
    assert manager =~ "openImpl(fullUrl(win.location.href, slug), \"_blank\")"
    assert manager =~ "elements.openFull.disabled = !active.alive"
    assert manager =~ "openFullSession(active.slug)"
    refute html =~ "fullButton"
    refute html =~ "full-open"
  end

  test "offers shell presets with tmux default selected first and no command field" do
    html = index_html()
    manager = static_file("js/hardline_manager.js")
    core = static_file("js/hardline_core.js")

    assert html =~ "id=\"command-preset\""
    assert html =~ "data-testid=\"command-preset\""
    assert html =~ "<option value=\"\" selected>Default tmux shell</option>"
    assert html =~ "<option value=\"/bin/zsh -f\">zsh fast shell</option>"
    assert core =~ "export function selectedCommand(presetValue)"
    assert manager =~ "command: selectedCommand(elements.commandPreset.value)"
    refute html =~ "Custom command"
    refute html =~ "custom-command-label"
  end

  test "uses icons on commands and status dots for session state" do
    html = index_html()
    manager = static_file("js/hardline_manager.js")
    core = static_file("js/hardline_core.js")

    assert html =~ "lucide.min.js"
    assert manager =~ "win.lucide.createIcons()"
    assert html =~ "data-lucide=\"refresh-cw\""
    assert html =~ "data-lucide=\"plus\""
    assert html =~ "data-lucide=\"shuffle\""
    assert html =~ "data-lucide=\"external-link\""
    assert html =~ "data-lucide=\"square\""
    assert core =~ "className: `status-dot ${state}`"
    assert manager =~ "status.dataset.testid = `session-status-${session.slug}`"
    refute html =~ ">up<"
    refute html =~ ">down<"
  end

  test "drops stale active session after refresh removes it" do
    manager = static_file("js/hardline_manager.js")
    core = static_file("js/hardline_core.js")

    assert core =~ "export function nextActiveSession(sessions, active)"
    assert manager =~ "const nextActive = nextActiveSession(sessions, active);"
    assert manager =~ "clearActiveSession(fullModeMissingSessionMessage(active.slug))"
    assert manager =~ "function clearActiveSession(message)"
    assert manager =~ "channel.leave();"
    refute manager =~ "|| active"
  end

  test "prefills session slugs from fruit and character suggestions" do
    html = index_html()
    manager = static_file("js/hardline_manager.js")
    core = static_file("js/hardline_core.js")

    assert html =~ "id=\"slug-reroll\""
    assert html =~ "data-testid=\"slug-reroll-button\""
    assert html =~ "placeholder=\"mango-scout\""
    assert core =~ "export const slugFruits = ["
    assert core =~ "\"dragonfruit\""
    assert core =~ "export const slugCharacters = ["
    assert core =~ "\"scout\""
    assert core =~ "export function suggestSlug(sessions"
    assert manager =~ "function suggestSlugIfEmpty()"
    assert manager =~ "elements.slugReroll.addEventListener(\"click\""
  end

  test "provides full-window layout and error affordances" do
    html = index_html()
    manager = static_file("js/hardline_manager.js")
    core = static_file("js/hardline_core.js")

    assert html =~ "body.full-mode"
    assert html =~ "body.full-mode aside"
    assert html =~ "body.full-mode #terminal"
    assert html =~ "width: 100vw;"
    assert html =~ "height: 100vh;"
    assert html =~ "id=\"full-overlay\""
    assert html =~ "data-testid=\"full-overlay\""
    assert manager =~ "export function showFullError(elements, text)"
    assert core =~ "export function fullModeMissingSessionMessage(slug)"
    assert html =~ "Back to manager"
  end

  test "aborts pane channel connection after screen capture failure" do
    manager = static_file("js/hardline_manager.js")

    assert manager =~ "const message = `capture: ${error.message}`;"
    assert manager =~ "setSocketStatus(\"unavailable\");"
    assert manager =~ "showFullError(elements, `Session unavailable: ${session.slug}`);"
    assert manager =~ "return;"
    assert manager =~ "socket.channel(`pane:${session.slug}`, {})"
  end

  test "loads browser behavior through testable static modules" do
    html = index_html()

    assert html =~ ~s(<script type="module" src="/js/hardline_boot.js"></script>)
    refute html =~ "const elements = {"
    refute html =~ "function renderSessions()"
    assert static_file("js/hardline_core.js") =~ "export function suggestSlug"
    assert static_file("js/hardline_manager.js") =~ "export function createHardlineManager"
  end

  defp index_html do
    static_file("index.html")
  end

  defp static_file(path) do
    :hardline
    |> :code.priv_dir()
    |> Path.join("static/#{path}")
    |> File.read!()
  end
end
