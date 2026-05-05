defmodule BabsWeb.TerminalLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint BabsWeb.Endpoint

  setup do
    {:ok, _apps} = Application.ensure_all_started(:babs)
    previous = Application.get_env(:babs, BabsWeb.TerminalLive)

    on_exit(fn ->
      if previous do
        Application.put_env(:babs, BabsWeb.TerminalLive, previous)
      else
        Application.delete_env(:babs, BabsWeb.TerminalLive)
      end
    end)
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
    assert html =~ ~s(href="/citizens/dylan?socket_token=socket-token")
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

    {:ok, view, _html} =
      live_isolated(build_conn(), BabsWeb.TerminalLive,
        session: %{"slug" => "clare", "socket_token" => "socket-token"}
      )

    view
    |> element(~s(button[data-testid="terminal-stop"]))
    |> render_click()

    assert_receive {:terminal_lifecycle_action, :stop, "clare"}
    assert_redirect(view, "/citizens?socket_token=socket-token")
  end

  test "restart action invokes lifecycle boundary and keeps terminal shell rendered" do
    parent = self()

    Application.put_env(:babs, BabsWeb.TerminalLive,
      status_snapshot_provider: fn -> [tab("clare", :up)] end,
      lifecycle_action: fn :restart, "clare" ->
        send(parent, {:terminal_lifecycle_action, :restart, "clare"})
        {:ok, self()}
      end
    )

    {:ok, view, _html} =
      live_isolated(build_conn(), BabsWeb.TerminalLive,
        session: %{"slug" => "clare", "socket_token" => "socket-token"}
      )

    view
    |> element(~s(button[data-testid="terminal-restart"]))
    |> render_click()

    assert_receive {:terminal_lifecycle_action, :restart, "clare"}
    html = render_async(view, 1_000)
    assert html =~ ~s(data-testid="terminal")
    assert html =~ ~s(data-testid="terminal-restart")
    assert html =~ "Restarted clare"
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

    {:ok, view, _html} =
      live_isolated(build_conn(), BabsWeb.TerminalLive,
        session: %{"slug" => "clare", "socket_token" => "socket-token"}
      )

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

    {:ok, view, _html} =
      live_isolated(build_conn(), BabsWeb.TerminalLive,
        session: %{"slug" => "clare", "socket_token" => "socket-token"}
      )

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

    {:ok, view, _html} =
      live_isolated(build_conn(), BabsWeb.TerminalLive,
        session: %{"slug" => "clare", "socket_token" => "socket-token"}
      )

    html =
      view
      |> element(~s(button[data-testid="terminal-restart"]))
      |> render_click()

    assert_receive {:terminal_lifecycle_started, task_pid, :restart, "clare"}
    assert disabled_button?(html, "terminal-stop")
    assert disabled_button?(html, "terminal-restart")

    send(task_pid, :release_restart)
    html = render_async(view, 1_000)

    assert html =~ "Restarted clare"
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
      last_error: nil
    }
  end

  defp actions(:up), do: [:open, :full, :stop, :restart]
  defp actions(:reattaching), do: [:start, :stop]
  defp actions(:stopped), do: [:start]
  defp actions(:failed), do: [:start]

  defp disabled_button?(html, testid) do
    pattern =
      Regex.compile!(
        "<button(?=[^>]*data-testid=\"#{Regex.escape(testid)}\")(?=[^>]*disabled)[^>]*>"
      )

    Regex.match?(pattern, html)
  end
end
