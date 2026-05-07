defmodule Babs.Citizens.StatusSnapshotTest do
  use Babs.Citizens.RepoCase, async: false

  alias Babs.Citizens.StatusSnapshot

  test "maps running citizens with live panes to up and idle" do
    record = insert_citizen!(%{slug: "live-up", status: "running"})
    {:ok, _value} = Registry.register(Babs.Citizens.PaneRegistry, record.slug, nil)

    [snapshot] = StatusSnapshot.list(include_stale?: true)

    assert snapshot.slug == "live-up"
    assert snapshot.live_status == :up
    assert snapshot.visual_state == :idle
  end

  test "maps running citizens without live panes to reattaching and waiting" do
    insert_citizen!(%{slug: "reattaching", status: "running"})

    [snapshot] = StatusSnapshot.list(include_stale?: true)

    assert snapshot.slug == "reattaching"
    assert snapshot.live_status == :reattaching
    assert snapshot.visual_state == :waiting
  end

  test "maps stopped and failed durable states without requiring live lookup" do
    insert_citizen!(%{slug: "stopped-one", status: "stopped"})
    insert_citizen!(%{slug: "failed-one", status: "failed", last_error: "redacted boom"})

    snapshots =
      StatusSnapshot.list(include_stale?: true)
      |> Map.new(&{&1.slug, &1})

    assert snapshots["stopped-one"].live_status == :stopped
    assert snapshots["stopped-one"].visual_state == :paused
    assert snapshots["failed-one"].live_status == :failed
    assert snapshots["failed-one"].visual_state == :dead
    assert snapshots["failed-one"].last_error == "redacted boom"
  end

  test "exposes lifecycle actions by live status" do
    up = insert_citizen!(%{slug: "up-one", status: "running"})
    insert_citizen!(%{slug: "reattaching-one", status: "running"})
    insert_citizen!(%{slug: "stopped-one", status: "stopped"})
    insert_citizen!(%{slug: "failed-one", status: "failed"})
    {:ok, _value} = Registry.register(Babs.Citizens.PaneRegistry, up.slug, nil)

    snapshots =
      StatusSnapshot.list(include_stale?: true)
      |> Map.new(&{&1.slug, &1.actions})

    assert snapshots["up-one"] == [:open, :full, :stop, :restart]
    assert snapshots["reattaching-one"] == [:start, :stop]
    assert snapshots["stopped-one"] == [:start]
    assert snapshots["failed-one"] == [:start]
  end

  test "exposes imported external ownership labels" do
    insert_citizen!(%{
      slug: "imported-one",
      status: "running",
      metadata: %{
        "hardline" => %{
          "ownership" => "external",
          "tmux" => %{
            "target" => "operator-work:0.0",
            "pane_id" => "%101",
            "session_name" => "operator-work",
            "window_index" => "0",
            "pane_index" => "0"
          }
        }
      }
    })

    [snapshot] = StatusSnapshot.list()

    assert snapshot.imported?
    assert snapshot.ownership == "external"
    assert snapshot.ownership_badge == "Imported · External-owned"
    assert snapshot.lifecycle_reminder == "Detach only · tmux stays running"
    assert snapshot.target_label == "operator-work:0.0"
  end

  test "does not expose env values in display snapshots" do
    insert_citizen!(%{
      slug: "secret-env",
      env: %{"SECRET_TOKEN" => "raw-secret-value"},
      status: "running"
    })

    [snapshot] = StatusSnapshot.list(include_stale?: true)

    refute Map.has_key?(snapshot, :env)
    refute inspect(snapshot) =~ "raw-secret-value"
    refute inspect(snapshot) =~ "SECRET_TOKEN"
  end

  test "exposes safe ticket backend labels for display" do
    insert_citizen!(%{slug: "hardline-one", ticket_backend: "hardline"})
    insert_citizen!(%{slug: "direct-one", ticket_backend: "direct_cli"})

    snapshots =
      StatusSnapshot.list(include_stale?: true)
      |> Map.new(&{&1.slug, &1})

    assert snapshots["hardline-one"].ticket_backend == "hardline"
    assert snapshots["hardline-one"].ticket_backend_label == "Hardline"
    assert snapshots["direct-one"].ticket_backend == "direct_cli"
    assert snapshots["direct-one"].ticket_backend_label == "Direct CLI"
  end

  test "labels known CLI presets and custom commands" do
    insert_citizen!(%{slug: "shell-one", cli: "/bin/zsh", cli_args: ["-f"]})
    insert_citizen!(%{slug: "claude-one", cli: "claude", cli_args: []})
    insert_citizen!(%{slug: "codex-one", cli: "codex", cli_args: []})
    insert_citizen!(%{slug: "droid-one", cli: "droid", cli_args: []})
    insert_citizen!(%{slug: "pi-one", cli: "pi", cli_args: []})
    insert_citizen!(%{slug: "copilot-one", cli: "gh", cli_args: ["copilot"]})
    insert_citizen!(%{slug: "custom-one", cli: "/opt/homebrew/bin/fish", cli_args: ["-l"]})

    labels =
      StatusSnapshot.list(include_stale?: true)
      |> Map.new(&{&1.slug, &1.cli_label})

    assert labels["shell-one"] == "shell"
    assert labels["claude-one"] == "claude"
    assert labels["codex-one"] == "codex"
    assert labels["droid-one"] == "droid"
    assert labels["pi-one"] == "pi"
    assert labels["copilot-one"] == "copilot-cli"
    assert labels["custom-one"] == "fish (custom)"
  end

  test "compacts cwd labels under workspace root and external paths" do
    root = tmp_root!()
    workspace_root = Path.join(root, "workspaces")
    in_workspace = Path.join(workspace_root, "clare")
    external = Path.join(tmp_root!(), "external/project")
    File.mkdir_p!(in_workspace)
    File.mkdir_p!(external)

    insert_citizen!(%{slug: "clare", cwd: in_workspace})
    insert_citizen!(%{slug: "external", cwd: external})

    snapshots =
      StatusSnapshot.list(workspace_root: workspace_root, include_stale?: true)
      |> Map.new(&{&1.slug, &1})

    assert snapshots["clare"].cwd_label == "workspaces/clare"
    assert snapshots["clare"].cwd == in_workspace
    assert snapshots["external"].cwd_label == ".../project"
    assert snapshots["external"].cwd == external
  end

  test "normal list hides stale SQLite-only rows but keeps configured and imported Citizens" do
    root = tmp_root!()
    write_citizen_toml!(root, "clare")

    insert_citizen!(%{slug: "clare", display_name: "Clare"})
    insert_citizen!(%{slug: "json", display_name: "Json", status: "stopped"})

    insert_citizen!(%{
      slug: "external",
      display_name: "External",
      metadata: %{"hardline" => %{"ownership" => "external"}}
    })

    slugs =
      StatusSnapshot.list(root: root, config_dir: "citizens")
      |> Enum.map(& &1.slug)

    assert slugs == ["clare", "external"]

    raw_slugs =
      StatusSnapshot.list(root: root, config_dir: "citizens", include_stale?: true)
      |> Enum.map(& &1.slug)

    assert raw_slugs == ["clare", "external", "json"]
  end
end
