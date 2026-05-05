defmodule BabsWeb.TerminalLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  test "renders the terminal shell and static browser modules" do
    html =
      %{slug: "sentinel"}
      |> BabsWeb.TerminalLive.render()
      |> rendered_to_string()

    assert html =~ ~s(data-testid="connection-status")
    assert html =~ ~s(data-state="connecting")
    assert html =~ ~s(data-testid="terminal")
    assert html =~ ~s(data-slug="sentinel")
    assert html =~ "/js/xterm.js"
    assert html =~ "/js/xterm-addon-fit.js"
    assert html =~ "/js/terminal_boot.js"
    refute html =~ "allowedControls"
  end

  test "mount assigns the citizen slug" do
    socket = %Phoenix.LiveView.Socket{}

    assert {:ok, socket} = BabsWeb.TerminalLive.mount(%{}, %{"slug" => "clare"}, socket)
    assert socket.assigns.slug == "clare"
  end
end
