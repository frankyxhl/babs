defmodule BabsWeb.TerminalLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Babs.Knowledge.Watcher

  @endpoint BabsWeb.Endpoint

  setup do
    {:ok, _apps} = Application.ensure_all_started(:babs)
    previous = Application.get_env(:babs, BabsWeb.TerminalLive)
    previous_root = Application.get_env(:babs_citizens, :root)
    previous_workspace_root = Application.get_env(:babs_citizens, :workspace_root)
    previous_knowledge_root = Application.get_env(:babs_citizens, :knowledge_root)
    root = tmp_root!()
    workspace_root = Path.join(root, "workspaces")
    knowledge_root = Path.join(root, "knowledge")

    Application.put_env(:babs_citizens, :root, root)
    Application.put_env(:babs_citizens, :workspace_root, workspace_root)
    Application.put_env(:babs_citizens, :knowledge_root, knowledge_root)
    Application.put_env(:babs, BabsWeb.TerminalLive, status_snapshot_provider: fn -> [] end)

    on_exit(fn ->
      File.rm_rf!(root)

      if previous do
        Application.put_env(:babs, BabsWeb.TerminalLive, previous)
      else
        Application.delete_env(:babs, BabsWeb.TerminalLive)
      end

      restore_env(:root, previous_root)
      restore_env(:workspace_root, previous_workspace_root)
      restore_env(:knowledge_root, previous_knowledge_root)
    end)

    {:ok, root: root, knowledge_root: knowledge_root}
  end

  test "citizen route defaults to Home and renders sanitized Readme markdown", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-read")
    register_pane!(slug)
    write_knowledge!(knowledge_root, slug, "Readme.md", "# Citizen Home\n\nHello **Babs**.\n")
    write_knowledge!(knowledge_root, slug, "Plan.md", "# Plan\n\nShip it.\n")

    {:ok, _view, html} = live(build_conn(), "/citizens/#{slug}?socket_token=socket-token")

    assert html =~ ~s(data-testid="citizen-home")
    assert html =~ ~s(data-testid="citizen-page-tab-home")
    assert html =~ "Citizen Home"
    assert html =~ "<strong>Babs</strong>"
    assert html =~ ~s(data-testid="knowledge-file-Plan.md")
    assert html =~ ~s(data-testid="terminal")
    assert html =~ ~s(data-terminal-visible="false")
    assert html =~ ~s(href="/citizens/#{slug}?tab=terminal&amp;socket_token=socket-token")
  end

  test "terminal tab and full mode preserve existing terminal behavior", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-terminal")
    register_pane!(slug)
    write_knowledge!(knowledge_root, slug, "Readme.md", "# Home\n")

    {:ok, _view, html} = live(build_conn(), "/citizens/#{slug}?tab=terminal&socket_token=secret")

    assert html =~ ~s(data-testid="terminal")
    assert html =~ ~s(data-terminal-visible="true")
    assert html =~ ~s(data-testid="citizen-page-tab-terminal")
    assert html =~ ~s(data-testid="citizen-home")
    refute html =~ ~s(data-home-visible="true")

    conn = get(build_conn(), "/citizens/#{slug}?full=1&tab=home&file=Plan.md&socket_token=secret")

    assert conn.status == 200
    assert conn.resp_body =~ ~s(data-testid="terminal")
    refute conn.resp_body =~ ~s(data-testid="citizen-home")
    refute conn.resp_body =~ ~s(data-testid="citizen-page-tab-home")
  end

  test "terminal tab preserves terminal mode when switching citizen tabs", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-terminal-switch")
    other_slug = unique_slug("home-terminal-switch-other")
    register_pane!(slug)
    register_pane!(other_slug)
    write_knowledge!(knowledge_root, slug, "Readme.md", "# Home\n")

    Application.put_env(:babs, BabsWeb.TerminalLive,
      status_snapshot_provider: fn -> [tab(slug, :up), tab(other_slug, :up)] end
    )

    {:ok, _view, html} =
      live(build_conn(), "/citizens/#{slug}?tab=terminal&socket_token=socket-token")

    assert html =~
             ~s(href="/citizens/#{other_slug}?tab=terminal&amp;socket_token=socket-token")
  end

  test "home tab patches from terminal tab back to the default Home route", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-terminal-return")
    register_pane!(slug)
    write_knowledge!(knowledge_root, slug, "Readme.md", "# Home\n")

    {:ok, view, html} = live(build_conn(), "/citizens/#{slug}?tab=terminal")

    assert html =~ ~s(data-terminal-visible="true")

    html =
      view
      |> element(~s(a[data-testid="citizen-page-tab-home"]))
      |> render_click()

    assert_patch(view, "/citizens/#{slug}")
    assert html =~ ~s(data-page-tab="home")
    assert html =~ ~s(data-home-visible="true")
    assert html =~ ~s(data-terminal-visible="false")
    assert html =~ "Home"
  end

  test "clicking a knowledge file patches the URL and renders that file", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-file")
    register_pane!(slug)
    write_knowledge!(knowledge_root, slug, "Readme.md", "# Readme\n\nDefault file.\n")
    write_knowledge!(knowledge_root, slug, "Plan.md", "# Plan\n\nSelected file.\n")

    {:ok, view, _html} = live(build_conn(), "/citizens/#{slug}")

    html =
      view
      |> element(~s(a[data-testid="knowledge-file-Plan.md"]))
      |> render_click()

    assert_patch(view, "/citizens/#{slug}?file=Plan.md")
    assert html =~ "Selected file."
    refute html =~ "Default file."
    assert html =~ ~s(data-testid="terminal")
  end

  test "home sidebar lists notes and selecting a note renders it", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-note")
    register_pane!(slug)
    write_knowledge!(knowledge_root, slug, "Readme.md", "# Readme\n\nDefault file.\n")
    write_knowledge!(knowledge_root, slug, "notes/alpha.md", "# Alpha Note\n\nSelected note.\n")

    {:ok, view, html} = live(build_conn(), "/citizens/#{slug}")

    assert html =~ ~s(data-testid="knowledge-notes")
    assert html =~ ~s(data-testid="knowledge-file-notes/alpha.md")
    assert html =~ "alpha"

    html =
      view
      |> element(~s(a[data-testid="knowledge-file-notes/alpha.md"]))
      |> render_click()

    assert_patch(view, "/citizens/#{slug}?file=notes%2Falpha.md")
    assert html =~ "Selected note."
    refute html =~ "Default file."
  end

  test "home sidebar creates a new note with a slug name and selects it", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-note-create")
    register_pane!(slug)
    write_knowledge!(knowledge_root, slug, "Readme.md", "# Readme\n")

    {:ok, view, html} = live(build_conn(), "/citizens/#{slug}")

    assert html =~ ~s(data-testid="knowledge-note-create-form")

    html =
      view
      |> form(~s(form[data-testid="knowledge-note-create-form"]), note: %{name: "Bad Name"})
      |> render_submit()

    assert html =~ ~s(data-testid="knowledge-note-create-error")
    assert html =~ "Use a-z, 0-9, and hyphens."
    refute File.exists?(Path.join([knowledge_root, slug, "notes/Bad Name.md"]))

    html =
      view
      |> form(~s(form[data-testid="knowledge-note-create-form"]), note: %{name: "build-plan"})
      |> render_submit()

    assert_patch(view, "/citizens/#{slug}?file=notes%2Fbuild-plan.md")

    assert File.read!(Path.join([knowledge_root, slug, "notes/build-plan.md"])) ==
             "# build-plan\n\n"

    assert html =~ "Created notes/build-plan.md"
    assert html =~ ~s(data-testid="knowledge-file-notes/build-plan.md")
    assert html =~ "build-plan"
  end

  test "clicking Readme in the knowledge list patches back to the default Home URL", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-readme-link")
    register_pane!(slug)
    write_knowledge!(knowledge_root, slug, "Readme.md", "# Readme\n\nDefault file.\n")
    write_knowledge!(knowledge_root, slug, "Plan.md", "# Plan\n\nSelected file.\n")

    {:ok, view, html} = live(build_conn(), "/citizens/#{slug}?file=Plan.md")

    assert html =~ "Selected file."

    html =
      view
      |> element(~s(a[data-testid="knowledge-file-Readme.md"]))
      |> render_click()

    assert_patch(view, "/citizens/#{slug}")
    assert html =~ "Default file."
    refute html =~ "Selected file."
  end

  test "home edit mode saves raw markdown and re-renders the document", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-edit")
    register_pane!(slug)
    path = write_knowledge!(knowledge_root, slug, "Readme.md", "# Before\n\nOld body.\n")

    {:ok, view, html} = live(build_conn(), "/citizens/#{slug}")

    assert html =~ "Before"

    html =
      view
      |> element(~s(button[data-testid="knowledge-edit-button"]))
      |> render_click()

    assert html =~ ~s(data-testid="knowledge-edit-form")
    assert html =~ "Old body."

    html =
      view
      |> form(~s(form[data-testid="knowledge-edit-form"]),
        home: %{content: "# After\n\nSaved **markdown**.\n"}
      )
      |> render_submit()

    assert File.read!(path) == "# After\n\nSaved **markdown**.\n"
    assert html =~ "After"
    assert html =~ "<strong>markdown</strong>"
    assert html =~ "Saved Readme.md"
    refute html =~ ~s(data-testid="knowledge-edit-form")
  end

  test "home edit mode saves the selected knowledge file", %{knowledge_root: knowledge_root} do
    slug = unique_slug("home-edit-file")
    register_pane!(slug)
    readme_path = write_knowledge!(knowledge_root, slug, "Readme.md", "# Readme\n")
    plan_path = write_knowledge!(knowledge_root, slug, "Plan.md", "# Plan\n\nOriginal.\n")

    {:ok, view, html} = live(build_conn(), "/citizens/#{slug}?file=Plan.md")

    assert html =~ "Original."

    view
    |> element(~s(button[data-testid="knowledge-edit-button"]))
    |> render_click()

    html =
      view
      |> form(~s(form[data-testid="knowledge-edit-form"]),
        home: %{content: "# Plan\n\nUpdated selected file.\n"}
      )
      |> render_submit()

    assert File.read!(plan_path) == "# Plan\n\nUpdated selected file.\n"
    assert File.read!(readme_path) == "# Readme\n"
    assert html =~ "Updated selected file."
    refute html =~ "Original."
  end

  test "home edit validation reports and clears oversized content before save", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-edit-validate")
    register_pane!(slug)
    write_knowledge!(knowledge_root, slug, "Readme.md", "# Original\n")

    {:ok, view, _html} = live(build_conn(), "/citizens/#{slug}")

    view
    |> element(~s(button[data-testid="knowledge-edit-button"]))
    |> render_click()

    html =
      view
      |> form(~s(form[data-testid="knowledge-edit-form"]),
        home: %{content: String.duplicate("x", 300_000)}
      )
      |> render_change()

    assert html =~ ~s(data-testid="knowledge-edit-error")
    assert html =~ "Knowledge home must be 256 KiB or smaller."

    html =
      view
      |> form(~s(form[data-testid="knowledge-edit-form"]), home: %{content: "# Valid\n"})
      |> render_change()

    refute html =~ ~s(data-testid="knowledge-edit-error")
  end

  test "home edit mode allows blank saves and renders an explicit empty state", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-edit-blank")
    register_pane!(slug)
    path = write_knowledge!(knowledge_root, slug, "Readme.md", "# Before\n")

    {:ok, view, _html} = live(build_conn(), "/citizens/#{slug}")

    view
    |> element(~s(button[data-testid="knowledge-edit-button"]))
    |> render_click()

    html =
      view
      |> form(~s(form[data-testid="knowledge-edit-form"]), home: %{content: "  \n\n"})
      |> render_submit()

    assert File.read!(path) == "  \n\n"
    assert html =~ ~s(data-testid="knowledge-empty-state")
    assert html =~ "This file is empty."
  end

  test "home edit mode can be cancelled without writing and reloads external edits", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-edit-cancel")
    register_pane!(slug)
    path = write_knowledge!(knowledge_root, slug, "Readme.md", "# Original\n")

    {:ok, view, _html} = live(build_conn(), "/citizens/#{slug}")

    view
    |> element(~s(button[data-testid="knowledge-edit-button"]))
    |> render_click()

    File.write!(path, "# External\n")

    html =
      view
      |> element(~s(button[data-testid="knowledge-cancel-edit"]))
      |> render_click()

    assert File.read!(path) == "# External\n"
    assert html =~ "External"
    refute html =~ "Original"
    refute html =~ ~s(data-testid="knowledge-edit-form")
  end

  test "home edit mode creates missing Readme files", %{knowledge_root: knowledge_root} do
    slug = unique_slug("home-edit-create")
    register_pane!(slug)
    path = Path.join([knowledge_root, slug, "Readme.md"])

    refute File.exists?(path)

    {:ok, view, html} = live(build_conn(), "/citizens/#{slug}")

    assert html =~ "This file does not exist yet."

    view
    |> element(~s(button[data-testid="knowledge-edit-button"]))
    |> render_click()

    html =
      view
      |> form(~s(form[data-testid="knowledge-edit-form"]),
        home: %{content: "# Created\n\nNew file.\n"}
      )
      |> render_submit()

    assert File.read!(path) == "# Created\n\nNew file.\n"
    assert html =~ ~s(data-testid="knowledge-file-Readme.md")
    assert html =~ "Created"
    assert html =~ "New file."
  end

  test "home edit mode rejects oversized content without writing", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-edit-large")
    register_pane!(slug)
    path = write_knowledge!(knowledge_root, slug, "Readme.md", "# Original\n")

    {:ok, view, _html} = live(build_conn(), "/citizens/#{slug}")

    view
    |> element(~s(button[data-testid="knowledge-edit-button"]))
    |> render_click()

    html =
      view
      |> form(~s(form[data-testid="knowledge-edit-form"]),
        home: %{content: String.duplicate("x", 300_000)}
      )
      |> render_submit()

    assert File.read!(path) == "# Original\n"
    assert html =~ ~s(data-testid="knowledge-edit-error")
    assert html =~ ~s(data-testid="knowledge-edit-form")
    assert html =~ "Knowledge home must be 256 KiB or smaller."
  end

  test "home edit mode refuses to clobber external edits", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-edit-conflict")
    register_pane!(slug)
    path = write_knowledge!(knowledge_root, slug, "Readme.md", "# Base\n")

    {:ok, view, _html} = live(build_conn(), "/citizens/#{slug}")

    view
    |> element(~s(button[data-testid="knowledge-edit-button"]))
    |> render_click()

    File.write!(path, "# External\n")

    html =
      view
      |> form(~s(form[data-testid="knowledge-edit-form"]), home: %{content: "# Mine\n"})
      |> render_submit()

    assert File.read!(path) == "# External\n"
    assert html =~ ~s(data-testid="knowledge-edit-error")
    assert html =~ ~s(data-testid="knowledge-edit-form")
    assert html =~ "This file changed on disk. Reload before saving."
  end

  test "knowledge PubSub does not clobber an active Home edit", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-edit-refresh")
    register_pane!(slug)
    path = write_knowledge!(knowledge_root, slug, "Readme.md", "# Initial\n\nDraft source.\n")

    {:ok, view, _html} = live(build_conn(), "/citizens/#{slug}")

    html =
      view
      |> element(~s(button[data-testid="knowledge-edit-button"]))
      |> render_click()

    assert html =~ "Draft source."

    File.write!(path, "# External\n\nShould wait.\n")

    Phoenix.PubSub.broadcast(
      Babs.Citizens.PubSub,
      Watcher.topic(),
      {:knowledge_changed, slug, "Readme.md"}
    )

    html = render(view)

    assert html =~ ~s(data-testid="knowledge-edit-form")
    assert html =~ "Draft source."
    refute html =~ "Should wait."
  end

  test "missing Readme and empty knowledge list render friendly empty states" do
    slug = unique_slug("home-empty")
    register_pane!(slug)

    {:ok, _view, html} = live(build_conn(), "/citizens/#{slug}")

    assert html =~ ~s(data-testid="knowledge-empty-state")
    assert html =~ "This file does not exist yet."
    assert html =~ "No knowledge files yet."
    refute html =~ "{:not_found"
  end

  test "invalid manual file query falls back to Readme without leaking raw errors", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-invalid")
    register_pane!(slug)
    write_knowledge!(knowledge_root, slug, "Readme.md", "# Safe Readme\n")

    {:ok, _view, html} = live(build_conn(), "/citizens/#{slug}?file=../etc/passwd")

    assert html =~ "Safe Readme"
    refute html =~ "passwd"
    refute html =~ "path_traversal"
    refute html =~ "{:invalid_child_path"
  end

  test "knowledge render failures show friendly messages without raw tuples", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-render-error")
    register_pane!(slug)
    write_knowledge!(knowledge_root, slug, "Readme.md", <<255, 255, 255>>)

    {:ok, _view, html} = live(build_conn(), "/citizens/#{slug}")

    assert html =~ "Unable to render this knowledge file."
    refute html =~ "render_failed"
    refute html =~ "MDEx"
  end

  test "unsafe knowledge list failures show friendly messages without raw tuples", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-list-error")
    register_pane!(slug)
    target = Path.join(knowledge_root, "#{slug}-target")
    File.mkdir_p!(target)
    File.ln_s!(target, Path.join(knowledge_root, slug))

    {:ok, _view, html} = live(build_conn(), "/citizens/#{slug}")

    assert html =~ "Unable to read knowledge files."
    refute html =~ "unsafe_symlink"
    refute html =~ target
    refute html =~ ~s(data-testid="knowledge-edit-button")
  end

  test "knowledge PubSub refreshes matching Home state and ignores other slugs", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-refresh")
    other_slug = unique_slug("home-refresh-other")
    register_pane!(slug)
    write_knowledge!(knowledge_root, slug, "Readme.md", "# Initial\n")

    {:ok, view, html} = live(build_conn(), "/citizens/#{slug}")
    assert html =~ "Initial"

    write_knowledge!(knowledge_root, slug, "Readme.md", "# Ignored for now\n")

    Phoenix.PubSub.broadcast(
      Babs.Citizens.PubSub,
      Watcher.topic(),
      {:knowledge_changed, other_slug, "Readme.md"}
    )

    html = render(view)
    refute html =~ "Ignored for now"

    Phoenix.PubSub.broadcast(
      Babs.Citizens.PubSub,
      Watcher.topic(),
      {:knowledge_changed, slug, "Readme.md"}
    )

    assert render(view) =~ "Ignored for now"
  end

  test "knowledge PubSub does not reload Home content while Terminal tab is active", %{
    knowledge_root: knowledge_root
  } do
    slug = unique_slug("home-terminal-refresh")
    register_pane!(slug)
    write_knowledge!(knowledge_root, slug, "Readme.md", "# Initial\n")

    {:ok, view, html} = live(build_conn(), "/citizens/#{slug}")
    assert html =~ "Initial"

    view
    |> element(~s(a[data-testid="citizen-page-tab-terminal"]))
    |> render_click()

    assert_patch(view, "/citizens/#{slug}?tab=terminal")

    write_knowledge!(knowledge_root, slug, "Readme.md", "# Deferred\n")

    Phoenix.PubSub.broadcast(
      Babs.Citizens.PubSub,
      Watcher.topic(),
      {:knowledge_changed, slug, "Readme.md"}
    )

    html = render(view)
    assert html =~ "Initial"
    refute html =~ "Deferred"
  end

  test "lifecycle restart from terminal tab preserves the terminal tab" do
    parent = self()
    slug = unique_slug("home-restart")
    register_pane!(slug)

    Application.put_env(:babs, BabsWeb.TerminalLive,
      status_snapshot_provider: fn -> [tab(slug, :up)] end,
      lifecycle_action: fn :restart, ^slug ->
        send(parent, {:terminal_lifecycle_action, :restart, slug})
        {:ok, self()}
      end
    )

    {:ok, view, _html} =
      live(build_conn(), "/citizens/#{slug}?tab=terminal&socket_token=socket-token")

    view
    |> element(~s(button[data-testid="terminal-restart"]))
    |> render_click()

    assert_receive {:terminal_lifecycle_action, :restart, ^slug}
    assert_redirect(view, "/citizens/#{slug}?tab=terminal&socket_token=socket-token")
  end

  test "full mode renders the pure terminal shell and static browser modules" do
    html =
      %{
        slug: "sentinel",
        socket_token: "secret",
        full?: true,
        tabs: [tab("sentinel")],
        lifecycle_inflight: %{}
      }
      |> BabsWeb.TerminalLive.render()
      |> rendered_to_string()

    refute html =~ ~s(data-testid="terminal-chrome")
    refute html =~ ~s(data-testid="citizen-tab-sentinel")
    assert html =~ ~s(data-testid="connection-status")
    assert html =~ ~s(phx-update="ignore")
    assert html =~ ~s(data-state="connecting")
    assert html =~ ~s(data-testid="terminal")
    assert html =~ ~s(data-slug="sentinel")
    assert html =~ ~s(data-socket-token="secret")
    assert html =~ "/js/xterm.js"
    assert html =~ "/js/xterm-addon-fit.js"
    assert html =~ "/js/terminal_boot.js"
    refute html =~ "/js/live_boot.js"
    refute html =~ "allowedControls"
    refute html =~ ~s(data-testid="terminal-lifecycle-controls")
    refute html =~ ~s(data-testid="terminal-start")
    refute html =~ ~s(data-testid="terminal-stop")
    refute html =~ ~s(data-testid="terminal-restart")
  end

  test "default mode renders compact tab chrome and token-preserving links" do
    html =
      %{
        slug: "clare",
        socket_token: "socket-token",
        full?: false,
        lifecycle_inflight: %{},
        tabs: [
          tab("clare", :up),
          tab("dylan", :up),
          tab("failed-one", :failed),
          tab("reattaching-one", :reattaching),
          tab("stopped-one", :stopped)
        ]
      }
      |> BabsWeb.TerminalLive.render()
      |> rendered_to_string()

    assert html =~ ~s(data-testid="terminal-chrome")
    assert html =~ ~s(data-testid="citizens-link")
    assert html =~ ~s(href="/citizens?socket_token=socket-token")
    assert html =~ ~s(data-testid="citizen-tab-clare")
    assert html =~ ~s(data-testid="citizen-tab-dylan")
    assert html =~ ~s(href="/citizens/dylan?tab=terminal&amp;socket_token=socket-token")
    refute html =~ ~s(data-testid="citizen-tab-failed-one")
    refute html =~ ~s(data-testid="citizen-tab-reattaching-one")
    refute html =~ ~s(data-testid="citizen-tab-stopped-one")
    assert html =~ ~s(class="terminal-tab is-active status-up")
    assert html =~ ~s(data-testid="terminal-full-link")
    assert html =~ ~s(href="/citizens/clare?full=1&amp;socket_token=socket-token")
    assert html =~ ~s(data-testid="terminal-lifecycle-controls")
    assert html =~ ~s(data-testid="terminal-stop")
    assert html =~ ~s(data-testid="terminal-restart")
    refute html =~ ~s(data-testid="terminal-start")
    assert html =~ "calc(100vh - var(--terminal-chrome-height))"
    assert html =~ ~s(id="connection-status" phx-update="ignore")
    assert html =~ ~s(data-testid="terminal")
    assert html =~ "/js/live_boot.js"
  end

  test "single citizen default mode keeps stable chrome" do
    html =
      %{
        slug: "solo",
        socket_token: "",
        full?: false,
        tabs: [tab("solo", :up)],
        lifecycle_inflight: %{}
      }
      |> BabsWeb.TerminalLive.render()
      |> rendered_to_string()

    assert html =~ ~s(data-testid="terminal-chrome")
    assert html =~ ~s(data-testid="citizens-link")
    assert html =~ ~s(data-testid="citizen-tab-solo")
    assert html =~ ~s(data-testid="terminal-full-link")
    assert html =~ ~s(data-testid="terminal-stop")
    assert html =~ ~s(data-testid="terminal-restart")
  end

  test "default mode labels imported external-owned terminal controls as attach semantics" do
    html =
      %{
        slug: "imported-one",
        socket_token: "",
        full?: false,
        tabs: [
          tab("imported-one", :up)
          |> Map.merge(%{
            imported?: true,
            kill_authority?: false,
            detach_authority?: true,
            ownership_badge: "Imported · External-owned",
            lifecycle_reminder: "Detach only · tmux stays running",
            target_label: "operator:0.0"
          })
        ],
        lifecycle_inflight: %{}
      }
      |> BabsWeb.TerminalLive.render()
      |> rendered_to_string()

    assert html =~ ~s(data-testid="terminal-ownership-badge")
    assert html =~ "Imported · External-owned"
    assert html =~ ~s(data-testid="terminal-lifecycle-reminder")
    assert html =~ "Detach only · tmux stays running"
    assert html =~ ~s(data-testid="terminal-stop")
    assert html =~ "Detach"
    assert html =~ ~s(data-testid="terminal-restart")
    assert html =~ "Reattach"
    refute html =~ ">Stop</button>"
    refute html =~ ">Restart</button>"
  end

  test "default mode renders active citizen role badges and full mode hides role chrome" do
    role_tab =
      tab("clare", :up)
      |> Map.put(:roles, [
        %{"name" => "developer", "skills" => ["elixir"]},
        %{"name" => "inspector", "skills" => []}
      ])

    default_html =
      %{
        slug: "clare",
        socket_token: "",
        full?: false,
        tabs: [role_tab],
        lifecycle_inflight: %{}
      }
      |> BabsWeb.TerminalLive.render()
      |> rendered_to_string()

    assert default_html =~ ~s(data-testid="terminal-roles-clare")
    assert default_html =~ ~s(data-testid="terminal-role-clare-0")
    assert default_html =~ "developer"
    assert default_html =~ "elixir"
    assert default_html =~ ~s(data-testid="terminal-role-clare-1")
    assert default_html =~ "inspector"

    full_html =
      %{
        slug: "clare",
        socket_token: "",
        full?: true,
        tabs: [role_tab],
        lifecycle_inflight: %{}
      }
      |> BabsWeb.TerminalLive.render()
      |> rendered_to_string()

    refute full_html =~ ~s(data-testid="terminal-roles-clare")
    refute full_html =~ ~s(data-testid="terminal-role-clare-0")
  end

  test "default mode can label detach-only controls from capability fields" do
    html =
      %{
        slug: "imported-capability",
        socket_token: "",
        full?: false,
        tabs: [
          tab("imported-capability", :up)
          |> Map.merge(%{
            imported?: false,
            kill_authority?: false,
            detach_authority?: true,
            ownership_badge: "Imported · External-owned",
            lifecycle_reminder: "Detach only · tmux stays running"
          })
        ],
        lifecycle_inflight: %{}
      }
      |> BabsWeb.TerminalLive.render()
      |> rendered_to_string()

    assert html =~ ~s(data-testid="terminal-stop")
    assert html =~ "Detach"
    assert html =~ ~s(data-testid="terminal-restart")
    assert html =~ "Reattach"
    refute html =~ ">Stop</button>"
    refute html =~ ">Restart</button>"
  end

  test "active citizen tab preserves non-up status while other non-up tabs are hidden" do
    html =
      %{
        slug: "active-one",
        socket_token: "",
        full?: false,
        lifecycle_inflight: %{},
        tabs: [tab("active-one", :reattaching), tab("failed-one", :failed), tab("live-one", :up)]
      }
      |> BabsWeb.TerminalLive.render()
      |> rendered_to_string()

    assert html =~ ~s(data-testid="citizen-tab-active-one")
    assert html =~ ~s(class="terminal-tab is-active status-reattaching")
    assert html =~ ~s(data-testid="citizen-tab-live-one")
    assert html =~ ~s(data-testid="terminal-start")
    assert html =~ ~s(data-testid="terminal-stop")
    refute html =~ ~s(data-testid="terminal-restart")
    refute html =~ ~s(data-testid="citizen-tab-failed-one")
  end

  test "stop action invokes lifecycle boundary and redirects to citizens index" do
    parent = self()

    Application.put_env(:babs, BabsWeb.TerminalLive,
      status_snapshot_provider: fn -> [tab("clare", :up)] end,
      lifecycle_action: fn :stop, "clare" ->
        send(parent, {:terminal_lifecycle_action, :stop, "clare"})
        :ok
      end
    )

    register_pane!("clare")
    {:ok, view, _html} = live(build_conn(), "/citizens/clare?socket_token=socket-token")

    view
    |> element(~s(button[data-testid="terminal-stop"]))
    |> render_click()

    assert_receive {:terminal_lifecycle_action, :stop, "clare"}
    assert_redirect(view, "/citizens?socket_token=socket-token")
  end

  test "restart action invokes lifecycle boundary and redirects to a fresh terminal page" do
    parent = self()

    Application.put_env(:babs, BabsWeb.TerminalLive,
      status_snapshot_provider: fn -> [tab("clare", :up)] end,
      lifecycle_action: fn :restart, "clare" ->
        send(parent, {:terminal_lifecycle_action, :restart, "clare"})
        {:ok, self()}
      end
    )

    register_pane!("clare")
    {:ok, view, _html} = live(build_conn(), "/citizens/clare?socket_token=socket-token")

    view
    |> element(~s(button[data-testid="terminal-restart"]))
    |> render_click()

    assert_receive {:terminal_lifecycle_action, :restart, "clare"}
    assert_redirect(view, "/citizens/clare?socket_token=socket-token")
  end

  test "restart failure redirects to index instead of leaving stale terminal" do
    parent = self()

    Application.put_env(:babs, BabsWeb.TerminalLive,
      status_snapshot_provider: fn -> [tab("clare", :up)] end,
      lifecycle_action: fn :restart, "clare" ->
        send(parent, {:terminal_lifecycle_action, :restart, "clare"})
        {:error, {:tmux_failed, "api_token=super-secret"}}
      end
    )

    register_pane!("clare")
    {:ok, view, _html} = live(build_conn(), "/citizens/clare?socket_token=socket-token")

    view
    |> element(~s(button[data-testid="terminal-restart"]))
    |> render_click()

    assert_receive {:terminal_lifecycle_action, :restart, "clare"}
    assert_redirect(view, "/citizens?socket_token=socket-token")
  end

  test "start failure stays on terminal page with redacted error flash" do
    parent = self()

    Application.put_env(:babs, BabsWeb.TerminalLive,
      status_snapshot_provider: fn -> [tab("clare", :reattaching)] end,
      lifecycle_action: fn :start, "clare" ->
        send(parent, {:terminal_lifecycle_action, :start, "clare"})
        {:error, {:tmux_failed, "api_token=super-secret"}}
      end
    )

    register_pane!("clare")
    {:ok, view, _html} = live(build_conn(), "/citizens/clare?socket_token=socket-token")

    view
    |> element(~s(button[data-testid="terminal-start"]))
    |> render_click()

    assert_receive {:terminal_lifecycle_action, :start, "clare"}
    html = render_async(view, 1_000)
    assert html =~ ~s(data-testid="terminal")
    assert html =~ "Start failed for clare"
    assert html =~ "[REDACTED]"
    refute html =~ "super-secret"
  end

  test "terminal lifecycle controls disable siblings while a request is in flight" do
    parent = self()

    Application.put_env(:babs, BabsWeb.TerminalLive,
      status_snapshot_provider: fn -> [tab("clare", :up)] end,
      lifecycle_action: fn :restart, "clare" ->
        send(parent, {:terminal_lifecycle_started, self(), :restart, "clare"})

        receive do
          :release_restart -> {:ok, self()}
        end
      end
    )

    register_pane!("clare")
    {:ok, view, _html} = live(build_conn(), "/citizens/clare?socket_token=socket-token")

    html =
      view
      |> element(~s(button[data-testid="terminal-restart"]))
      |> render_click()

    assert_receive {:terminal_lifecycle_started, task_pid, :restart, "clare"}
    assert disabled_button?(html, "terminal-stop")
    assert disabled_button?(html, "terminal-restart")

    send(task_pid, :release_restart)

    assert_redirect(view, "/citizens/clare?socket_token=socket-token")
  end

  test "mount assigns the citizen slug, mode, and tabs" do
    Application.put_env(:babs, BabsWeb.TerminalLive,
      status_snapshot_provider: fn -> [tab("clare")] end
    )

    socket = %Phoenix.LiveView.Socket{}

    assert {:ok, socket} =
             BabsWeb.TerminalLive.mount(
               %{},
               %{"slug" => "clare", "socket_token" => "token", "full?" => true},
               socket
             )

    assert socket.assigns.slug == "clare"
    assert socket.assigns.socket_token == "token"
    assert socket.assigns.full? == true
    assert socket.assigns.lifecycle_inflight == %{}
    assert [%{slug: "clare"}] = socket.assigns.tabs
  end

  defp tab(slug, live_status \\ :up) do
    %{
      slug: slug,
      display_name: String.capitalize(slug),
      live_status: live_status,
      actions: actions(live_status),
      cli_label: "shell",
      cwd_label: "workspaces/#{slug}",
      last_error: nil,
      roles: []
    }
  end

  defp actions(:up), do: [:open, :full, :stop, :restart]
  defp actions(:reattaching), do: [:start, :stop]
  defp actions(:stopped), do: [:start]
  defp actions(:failed), do: [:start]

  defp write_knowledge!(knowledge_root, slug, name, content) do
    path = Path.join([knowledge_root, slug, name])
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, content)
    path
  end

  defp register_pane!(slug) do
    case Registry.register(Babs.Citizens.PaneRegistry, slug, nil) do
      {:ok, _pid} -> :ok
      {:error, {:already_registered, _pid}} -> :ok
    end
  end

  defp unique_slug(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  defp tmp_root! do
    root =
      Path.join(
        System.tmp_dir!(),
        "babs-terminal-live-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end

  defp restore_env(key, nil), do: Application.delete_env(:babs_citizens, key)
  defp restore_env(key, value), do: Application.put_env(:babs_citizens, key, value)

  defp disabled_button?(html, testid) do
    pattern =
      Regex.compile!(
        "<button(?=[^>]*data-testid=\"#{Regex.escape(testid)}\")(?=[^>]*disabled)[^>]*>"
      )

    Regex.match?(pattern, html)
  end
end
