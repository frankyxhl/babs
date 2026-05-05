defmodule BabsWeb.TerminalControllerTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  @endpoint BabsWeb.Endpoint

  test "root redirects to sentinel terminal" do
    conn = get(build_conn(), "/")

    assert conn.status == 302
    assert Plug.Conn.get_resp_header(conn, "location") == ["/citizens/sentinel"]
  end

  test "missing citizen returns a plain text 404" do
    conn = get(build_conn(), "/citizens/not-a-citizen")

    assert conn.status == 404
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    assert conn.resp_body == "citizen not found: not-a-citizen\n"
  end

  test "existing citizen renders the terminal LiveView shell" do
    slug = "controller-test-#{System.unique_integer([:positive])}"
    {:ok, _value} = Registry.register(Babs.Citizens.PaneRegistry, slug, nil)

    conn = get(build_conn(), "/citizens/#{slug}?socket_token=secret")

    assert conn.status == 200
    assert conn.resp_body =~ ~s(data-testid="terminal")
    assert conn.resp_body =~ ~s(data-slug="#{slug}")
    assert conn.resp_body =~ ~s(data-socket-token="secret")
    assert conn.resp_body =~ "/js/terminal_boot.js"
  end

  test "existing new citizen keeps /citizens/new terminal URL" do
    {:ok, _value} = Registry.register(Babs.Citizens.PaneRegistry, "new", nil)

    conn = get(build_conn(), "/citizens/new?socket_token=route-token")

    assert conn.status == 200
    assert conn.resp_body =~ ~s(data-testid="terminal")
    assert conn.resp_body =~ ~s(data-slug="new")
    assert conn.resp_body =~ ~s(data-socket-token="route-token")
    refute conn.resp_body =~ ~s(data-testid="new-citizen-form")
  end

  test "head returns citizen existence without rendering the terminal" do
    slug = "head-test-#{System.unique_integer([:positive])}"
    {:ok, _value} = Registry.register(Babs.Citizens.PaneRegistry, slug, nil)

    assert head(build_conn(), "/citizens/#{slug}").status == 200
    assert head(build_conn(), "/citizens/not-a-citizen").status == 404
  end
end
