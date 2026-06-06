defmodule BabsWeb.KitchenSinkLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint BabsWeb.Endpoint

  test "renders light-theme kitchen sink with ticket rail and messaging preview" do
    {:ok, view, html} = live(build_conn(), "/dev/kitchen-sink?socket_token=token-1")

    assert html =~ ~s(data-testid="kitchen-sink")
    assert html =~ ~s(data-theme="light")
    assert html =~ ~s(href="/css/app.css")
    assert html =~ "Kitchen Sink"
    assert html =~ ~s(href="/tickets?socket_token=token-1")
    assert html =~ ~s(href="/citizens?socket_token=token-1")
    assert html =~ ~s(data-testid="ticket-state-rail")
    assert html =~ "in progress"
    assert html =~ "Assignees"
    assert html =~ "Delivery"
    assert html =~ ~s(data-testid="ticket-chat-preview")
    assert html =~ "Ticket Chat"
    assert html =~ "Legacy Comment"
    assert html =~ ~s(data-testid="git-diff-preview")
    assert html =~ ~s(data-testid="git-diff-component")
    assert html =~ "issue/100-git-diff-liveview"
    assert html =~ "terminal-in-light-shell"
    assert html =~ ~s(data-testid="tabs-preview")
    assert html =~ ~s(data-testid="table-preview")
    assert html =~ ~s(data-testid="empty-state-preview")
    assert html =~ ~s(data-testid="modal-preview")
    assert html =~ ~s(data-icon="send")
    assert html =~ ~s(data-icon="maximize")

    html =
      view
      |> element(~s(button[data-testid="theme-dark"]))
      |> render_click()

    assert html =~ ~s(data-theme="dark")

    html =
      view
      |> element(~s(button[data-testid="theme-light"]))
      |> render_click()

    assert html =~ ~s(data-theme="light")
  end
end
