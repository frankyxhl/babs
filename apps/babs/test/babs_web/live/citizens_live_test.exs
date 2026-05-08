defmodule BabsWeb.CitizensLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Babs.Citizens.{Catalog, CitizenRecord, Repo}

  @endpoint BabsWeb.Endpoint

  setup do
    ensure_repo!()
    Repo.delete_all(CitizenRecord)
    previous = Application.get_env(:babs, BabsWeb.CitizensLive)
    previous_root = Application.get_env(:babs_citizens, :root)
    config_root = tmp_root!()
    Application.put_env(:babs_citizens, :root, config_root)

    on_exit(fn ->
      File.rm_rf!(config_root)

      if previous do
        Application.put_env(:babs, BabsWeb.CitizensLive, previous)
      else
        Application.delete_env(:babs, BabsWeb.CitizensLive)
      end

      if previous_root do
        Application.put_env(:babs_citizens, :root, previous_root)
      else
        Application.delete_env(:babs_citizens, :root)
      end
    end)
  end

  test "renders empty state with new citizen link" do
    {:ok, _view, html} = live(build_conn(), "/citizens")

    assert html =~ ~s(data-testid="citizens-index")
    assert html =~ ~s(data-testid="citizens-empty-state")
    assert html =~ ~s(href="/citizens/new")
  end

  test "skips remote peer fetch during disconnected render" do
    Application.put_env(:babs, BabsWeb.CitizensLive,
      remote_peer_provider: fn -> raise "remote peer provider should wait for connected mount" end
    )

    html = build_conn() |> get("/citizens") |> html_response(200)

    assert html =~ ~s(data-testid="citizens-index")
    refute html =~ ~s(data-testid="remote-peer-citizens")
  end

  test "renders one read-only remote peer and refreshes remote citizens" do
    {:ok, agent} =
      Agent.start_link(fn ->
        remote_peer(%{
          citizens: [
            %{
              "slug" => "remote-clare",
              "display_name" => "Remote Clare",
              "live_status" => "up"
            }
          ]
        })
      end)

    Application.put_env(:babs, BabsWeb.CitizensLive,
      remote_peer_provider: fn -> Agent.get(agent, & &1) end
    )

    {:ok, view, _html} = live(build_conn(), "/citizens")
    html = render_async(view, 1_000)

    assert html =~ ~s(data-testid="remote-peer-citizens")
    assert html =~ "Peer Node"
    assert html =~ "Read-only"
    assert html =~ "fresh"
    assert html =~ ~s(data-testid="remote-citizen-remote-clare")
    assert html =~ "Remote Clare"
    assert html =~ ~s(data-testid="remote-citizen-restart-remote-clare")
    assert disabled_button?(html, "remote-citizen-restart-remote-clare")
    refute html =~ ~s(data-testid="citizen-open-remote-clare")
    refute html =~ ~s(data-testid="citizen-full-remote-clare")

    Agent.update(agent, fn peer ->
      %{peer | citizens: [%{"slug" => "remote-dylan", "display_name" => "Remote Dylan"}]}
    end)

    send(view.pid, :refresh_remote_peer)
    html = render_async(view, 1_000)

    assert html =~ ~s(data-testid="remote-citizen-remote-dylan")
    assert html =~ "Remote Dylan"
    refute html =~ "Remote Clare"
  end

  test "control remote peer can restart remote citizens and respects read-only overrides" do
    parent = self()

    Application.put_env(:babs, BabsWeb.CitizensLive,
      remote_peer_provider: fn ->
        remote_peer(%{
          read_only?: false,
          capabilities: ["read", "write", "control"],
          citizen_capabilities: %{"remote-dylan" => ["read"]},
          citizens: [
            %{
              "slug" => "remote-clare",
              "display_name" => "Remote Clare",
              "live_status" => "up"
            },
            %{
              "slug" => "remote-dylan",
              "display_name" => "Remote Dylan",
              "live_status" => "up"
            }
          ]
        })
      end,
      remote_citizen_action: fn action, peer, slug ->
        send(parent, {:remote_citizen_action, action, peer.peer_id, slug})
        {:ok, %{"ok" => true}}
      end
    )

    {:ok, view, _html} = live(build_conn(), "/citizens")
    html = render_async(view, 1_000)

    assert html =~ "Control-enabled"
    assert html =~ ~s(data-testid="remote-citizen-restart-remote-clare")
    refute disabled_button?(html, "remote-citizen-restart-remote-clare")
    assert disabled_button?(html, "remote-citizen-restart-remote-dylan")

    view
    |> element(~s(button[data-testid="remote-citizen-restart-remote-clare"]))
    |> render_click()

    assert_receive {:remote_citizen_action, :restart, "peer-a", "remote-clare"}
    assert render(view) =~ "Remote restart sent"
  end

  test "remote restart failures show redacted failure feedback" do
    Application.put_env(:babs, BabsWeb.CitizensLive,
      remote_peer_provider: fn ->
        remote_peer(%{
          read_only?: false,
          capabilities: ["read", "write", "control"],
          citizens: [
            %{
              "slug" => "remote-clare",
              "display_name" => "Remote Clare",
              "live_status" => "up"
            }
          ]
        })
      end,
      remote_citizen_action: fn :restart, _peer, "remote-clare" -> {:error, :timeout} end
    )

    {:ok, view, _html} = live(build_conn(), "/citizens")
    html = render_async(view, 1_000)

    assert html =~ ~s(data-testid="remote-citizen-restart-remote-clare")

    view
    |> element(~s(button[data-testid="remote-citizen-restart-remote-clare"]))
    |> render_click()

    html = render(view)
    assert html =~ "Remote restart failed"
    refute html =~ "timeout"
  end

  test "renders sorted citizens, counts, statuses, labels, and token-preserving links" do
    workspace_root = Path.join(tmp_root!(), "workspaces")
    Application.put_env(:babs_citizens, :workspace_root, workspace_root)

    on_exit(fn -> Application.delete_env(:babs_citizens, :workspace_root) end)

    insert_configured_citizen!(%{
      slug: "clare",
      display_name: "Clare",
      cli: "claude",
      cwd: Path.join(workspace_root, "clare"),
      env: %{"SECRET_TOKEN" => "raw-secret-value"}
    })

    insert_configured_citizen!(%{
      slug: "dylan",
      display_name: "Dylan",
      cli: "gh",
      cli_args: ["copilot"],
      ticket_backend: "direct_cli",
      cwd: Path.join(workspace_root, "dylan")
    })

    insert_configured_citizen!(%{
      slug: "failed-one",
      display_name: "Failed One",
      status: "failed",
      last_error: "redacted boom"
    })

    insert_configured_citizen!(%{
      slug: "stopped-one",
      display_name: "Stopped One",
      status: "stopped"
    })

    ensure_pane_registered!("clare")

    {:ok, _view, html} = live(build_conn(), "/citizens?socket_token=socket-token")

    assert html =~ ~s(data-testid="citizens-count-total")
    assert html =~ "4"
    assert html =~ ~s(data-testid="citizens-count-up")
    assert html =~ ~s(data-testid="citizens-count-reattaching")
    assert html =~ ~s(data-testid="citizens-count-stopped")
    assert html =~ ~s(data-testid="citizens-count-failed")

    assert html =~ ~s(data-testid="citizen-row-clare")
    assert html =~ ~s(data-testid="citizen-status-clare")
    assert html =~ "up"
    assert html =~ "claude"
    assert html =~ ~s(data-testid="citizen-backend-clare")
    assert html =~ "Hardline"
    assert html =~ "workspaces/clare"
    assert html =~ ~s(data-testid="citizen-row-dylan")
    assert html =~ "copilot-cli"
    assert html =~ ~s(data-testid="citizen-backend-dylan")
    assert html =~ "Direct CLI"
    assert html =~ "reattaching"
    assert html =~ "stopped"
    assert html =~ "failed"
    assert html =~ "redacted boom"

    refute html =~ "raw-secret-value"
    refute html =~ "SECRET_TOKEN"

    assert ordered?(html, [
             ~s(data-testid="citizen-row-clare"),
             ~s(data-testid="citizen-row-dylan"),
             ~s(data-testid="citizen-row-failed-one"),
             ~s(data-testid="citizen-row-stopped-one")
           ])

    assert html =~ ~s(href="/citizens/new?socket_token=socket-token")
    assert html =~ ~s(href="/citizens/attach?socket_token=socket-token")
    assert html =~ ~s(href="/citizens/clare?socket_token=socket-token")
    assert html =~ ~s(href="/citizens/clare?full=1&amp;socket_token=socket-token")
    assert html =~ ~s(data-testid="citizen-stop-clare")
    assert html =~ ~s(data-testid="citizen-restart-clare")
    refute html =~ ~s(data-testid="citizen-start-clare")

    assert html =~ ~s(data-testid="citizen-start-dylan")
    assert html =~ ~s(data-testid="citizen-stop-dylan")
    refute html =~ ~s(data-testid="citizen-restart-dylan")

    assert html =~ ~s(data-testid="citizen-start-failed-one")
    assert html =~ ~s(data-testid="citizen-start-stopped-one")
    assert html =~ ~s(data-testid="citizen-open-dylan")
    assert html =~ ~s(data-testid="citizen-full-dylan")
    refute html =~ ~s(href="/citizens/dylan?socket_token=socket-token")
    refute html =~ ~s(href="/citizens/dylan?full=1&amp;socket_token=socket-token")
  end

  test "renders imported external-owned lifecycle badges and detach controls" do
    insert_citizen!(%{
      slug: "imported-one",
      display_name: "Imported One",
      status: "running",
      metadata: %{
        "hardline" => %{
          "ownership" => "external",
          "tmux" => %{
            "session_name" => "operator",
            "window_index" => "0",
            "pane_index" => "0",
            "pane_id" => "%101",
            "target" => "operator:0.0"
          }
        }
      }
    })

    ensure_pane_registered!("imported-one")

    {:ok, _view, html} = live(build_conn(), "/citizens")

    assert html =~ ~s(data-testid="citizen-ownership-imported-one")
    assert html =~ "Imported · External-owned"
    assert html =~ "operator:0.0"
    assert html =~ "Detach only · tmux stays running"
    assert html =~ ~s(data-testid="citizen-stop-imported-one")
    assert html =~ "Detach"
    assert html =~ ~s(data-testid="citizen-restart-imported-one")
    assert html =~ "Reattach"
  end

  test "renders normalized citizen role badges" do
    insert_configured_citizen!(%{
      slug: "multi-role",
      display_name: "Multi Role",
      roles: [
        %{"name" => "developer", "skills" => ["elixir", "phoenix"]},
        %{"name" => "inspector", "skills" => []}
      ]
    })

    {:ok, _view, html} = live(build_conn(), "/citizens")

    assert html =~ ~s(data-testid="citizen-roles-multi-role")
    assert html =~ ~s(data-testid="citizen-role-multi-role-0")
    assert html =~ "developer"
    assert html =~ "elixir, phoenix"
    assert html =~ ~s(data-testid="citizen-role-multi-role-1")
    assert html =~ "inspector"
  end

  test "hides stale SQLite-only citizens from the normal index" do
    insert_configured_citizen!(%{slug: "clare", display_name: "Clare"})
    insert_citizen!(%{slug: "json", display_name: "Json", status: "stopped"})

    {:ok, _view, html} = live(build_conn(), "/citizens")

    assert html =~ ~s(data-testid="citizen-row-clare")
    refute html =~ ~s(data-testid="citizen-row-json")
  end

  test "start control invokes lifecycle boundary and refreshes the row" do
    record = insert_configured_citizen!(%{slug: "start-me", status: "stopped"})
    parent = self()

    Application.put_env(:babs, BabsWeb.CitizensLive,
      lifecycle_action: fn :start, slug ->
        send(parent, {:lifecycle_action, :start, slug})
        Catalog.mark_running(slug)

        pane_pid =
          spawn(fn ->
            Registry.register(Babs.Citizens.PaneRegistry, slug, nil)
            send(parent, {:pane_registered, slug, self()})

            receive do
              :stop -> :ok
            end
          end)

        {:ok, pane_pid}
      end
    )

    {:ok, view, html} = live(build_conn(), "/citizens")
    assert html =~ ~s(data-testid="citizen-start-start-me")
    assert html =~ "stopped"

    view
    |> element(~s(button[data-testid="citizen-start-start-me"]))
    |> render_click()

    assert_receive {:lifecycle_action, :start, "start-me"}
    assert_receive {:pane_registered, "start-me", pane_pid}
    html = render_async(view, 1_000)
    assert Repo.get!(CitizenRecord, record.id).status == "running"

    assert html =~ "up"
    assert html =~ ~s(data-testid="citizen-stop-start-me")
    assert html =~ ~s(data-testid="citizen-restart-start-me")
    send(pane_pid, :stop)
  end

  test "stop control invokes lifecycle boundary and refreshes the row" do
    record = insert_configured_citizen!(%{slug: "stop-me", status: "running"})
    ensure_pane_registered!(record.slug)
    parent = self()

    Application.put_env(:babs, BabsWeb.CitizensLive,
      lifecycle_action: fn :stop, slug ->
        send(parent, {:lifecycle_action, :stop, slug})
        Catalog.mark_stopped(slug)
        :ok
      end
    )

    {:ok, view, html} = live(build_conn(), "/citizens")
    assert html =~ ~s(data-testid="citizen-stop-stop-me")
    assert html =~ "up"

    view
    |> element(~s(button[data-testid="citizen-stop-stop-me"]))
    |> render_click()

    assert_receive {:lifecycle_action, :stop, "stop-me"}
    html = render_async(view, 1_000)
    assert Repo.get!(CitizenRecord, record.id).status == "stopped"
    assert html =~ "Stopped stop-me"
    assert html =~ "stopped"
    assert html =~ ~s(data-testid="citizen-start-stop-me")
    refute html =~ ~s(href="/citizens/stop-me")
  end

  test "restart control reports redacted lifecycle errors" do
    insert_configured_citizen!(%{slug: "restart-error", status: "running"})
    ensure_pane_registered!("restart-error")

    Application.put_env(:babs, BabsWeb.CitizensLive,
      lifecycle_action: fn :restart, "restart-error" ->
        {:error, {:tmux_failed, "api_token=super-secret"}}
      end
    )

    {:ok, view, html} = live(build_conn(), "/citizens")
    assert html =~ ~s(data-testid="citizen-restart-restart-error")

    view
    |> element(~s(button[data-testid="citizen-restart-restart-error"]))
    |> render_click()

    html = render_async(view, 1_000)
    assert html =~ "Restart failed for restart-error"
    assert html =~ "[REDACTED]"
    refute html =~ "super-secret"
  end

  test "lifecycle controls disable sibling controls while a request is in flight" do
    record = insert_configured_citizen!(%{slug: "busy-one", status: "running"})
    ensure_pane_registered!(record.slug)
    parent = self()

    Application.put_env(:babs, BabsWeb.CitizensLive,
      lifecycle_action: fn :stop, slug ->
        send(parent, {:lifecycle_started, self(), :stop, slug})

        receive do
          :release_stop ->
            Catalog.mark_stopped(slug)
            :ok
        end
      end
    )

    {:ok, view, _html} = live(build_conn(), "/citizens")

    html =
      view
      |> element(~s(button[data-testid="citizen-stop-busy-one"]))
      |> render_click()

    assert_receive {:lifecycle_started, task_pid, :stop, "busy-one"}
    assert disabled_button?(html, "citizen-stop-busy-one")
    assert disabled_button?(html, "citizen-restart-busy-one")

    send(task_pid, :release_stop)
    html = render_async(view, 1_000)

    assert Repo.get!(CitizenRecord, record.id).status == "stopped"
    assert html =~ "Stopped busy-one"
    assert html =~ "stopped"
  end

  test "refresh tick reflects status changes" do
    record = insert_configured_citizen!(%{slug: "tick-one", status: "running"})

    {:ok, view, html} = live(build_conn(), "/citizens")
    assert html =~ "reattaching"

    ensure_pane_registered!(record.slug)
    send(view.pid, :refresh_citizens)

    assert render(view) =~ "up"
  end

  defp ensure_repo! do
    {:ok, _apps} = Application.ensure_all_started(:babs)

    Ecto.Migrator.with_repo(Babs.Citizens.Repo, fn repo ->
      Ecto.Migrator.run(repo, Application.app_dir(:babs_citizens, "priv/repo/migrations"), :up,
        all: true
      )
    end)
  end

  defp insert_citizen!(attrs) do
    attrs =
      Map.merge(
        %{
          id: "BAB-CIT-#{System.unique_integer([:positive])}",
          slug: "citizen-#{System.unique_integer([:positive])}",
          display_name: "Test Citizen",
          cwd: tmp_cwd!(),
          cli: "/bin/zsh",
          cli_args: ["-f"],
          env: %{},
          status: "running",
          metadata: %{},
          is_mayor: false
        },
        attrs
      )

    %CitizenRecord{}
    |> CitizenRecord.changeset(attrs)
    |> Repo.insert!()
  end

  defp insert_configured_citizen!(attrs) do
    record = insert_citizen!(attrs)
    write_citizen_toml!(record)
    record
  end

  defp write_citizen_toml!(%CitizenRecord{} = record) do
    root = Application.fetch_env!(:babs_citizens, :root)
    File.mkdir_p!(Path.join(root, "citizens"))

    path = Path.join(root, "citizens/citizen-#{record.slug}.toml")

    File.write!(path, """
    id = "#{record.id}"
    slug = "#{record.slug}"
    display_name = "#{record.display_name}"
    cli = "#{record.cli}"
    cli_args = #{inspect(record.cli_args || [])}
    launch_profile = "#{record.launch_profile || "safe_interactive"}"
    ticket_backend = "#{record.ticket_backend || "hardline"}"
    cwd = "#{record.cwd}"

    [env]
    """)

    path
  end

  defp tmp_root! do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-web-case-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end

  defp tmp_cwd! do
    cwd = Path.join(tmp_root!(), "workspace")
    File.mkdir_p!(cwd)
    cwd
  end

  defp ordered?(text, needles) do
    needles
    |> Enum.map(&(:binary.match(text, &1) |> elem(0)))
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [left, right] -> left < right end)
  end

  defp remote_peer(attrs) do
    Map.merge(
      %{
        peer_id: "peer-a",
        peer_name: "Peer Node",
        peer_url: "http://babs-peer.example:4000",
        status: :fresh,
        read_only?: true,
        capabilities: ["read"],
        citizen_capabilities: %{},
        fetched_at: ~U[2026-05-09 00:00:00Z],
        node: %{"id" => "peer-a", "name" => "Peer Node"},
        citizens: [],
        tickets: [],
        invalid: %{"count" => 0},
        events: [],
        cursor: "cursor"
      },
      attrs
    )
  end

  defp ensure_pane_registered!(slug) do
    case Registry.register(Babs.Citizens.PaneRegistry, slug, nil) do
      {:ok, _value} -> :ok
      {:error, {:already_registered, _pid}} -> :ok
    end
  end

  defp disabled_button?(html, testid) do
    pattern =
      Regex.compile!(
        "<button(?=[^>]*data-testid=\"#{Regex.escape(testid)}\")(?=[^>]*disabled)[^>]*>"
      )

    Regex.match?(pattern, html)
  end
end
