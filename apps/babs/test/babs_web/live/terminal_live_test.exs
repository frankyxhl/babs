defmodule BabsWeb.TerminalLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

  setup do
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
      %{slug: "sentinel", socket_token: "secret", full?: true, tabs: [tab("sentinel")]}
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
  end

  test "default mode renders compact tab chrome and token-preserving links" do
    html =
      %{
        slug: "clare",
        socket_token: "socket-token",
        full?: false,
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
    assert html =~ "calc(100vh - var(--terminal-chrome-height))"
    assert html =~ ~s(id="connection-status" phx-update="ignore")
    assert html =~ ~s(data-testid="terminal")
    assert html =~ "/js/live_boot.js"
  end

  test "single citizen default mode keeps stable chrome" do
    html =
      %{slug: "solo", socket_token: "", full?: false, tabs: [tab("solo", :up)]}
      |> BabsWeb.TerminalLive.render()
      |> rendered_to_string()

    assert html =~ ~s(data-testid="terminal-chrome")
    assert html =~ ~s(data-testid="citizens-link")
    assert html =~ ~s(data-testid="citizen-tab-solo")
    assert html =~ ~s(data-testid="terminal-full-link")
  end

  test "active citizen tab preserves non-up status while other non-up tabs are hidden" do
    html =
      %{
        slug: "active-one",
        socket_token: "",
        full?: false,
        tabs: [tab("active-one", :reattaching), tab("failed-one", :failed), tab("live-one", :up)]
      }
      |> BabsWeb.TerminalLive.render()
      |> rendered_to_string()

    assert html =~ ~s(data-testid="citizen-tab-active-one")
    assert html =~ ~s(class="terminal-tab is-active status-reattaching")
    assert html =~ ~s(data-testid="citizen-tab-live-one")
    refute html =~ ~s(data-testid="citizen-tab-failed-one")
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
    assert [%{slug: "clare"}] = socket.assigns.tabs
  end

  defp tab(slug, live_status \\ :up) do
    %{
      slug: slug,
      display_name: String.capitalize(slug),
      live_status: live_status,
      cli_label: "shell",
      cwd_label: "workspaces/#{slug}",
      last_error: nil
    }
  end
end
