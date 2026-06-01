defmodule BabsWeb.TerminalControllerTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  @endpoint BabsWeb.Endpoint

  setup do
    previous = Application.get_env(:babs, BabsWeb.TerminalLive)

    Application.put_env(:babs, BabsWeb.TerminalLive, status_snapshot_provider: fn -> [] end)

    on_exit(fn ->
      if previous do
        Application.put_env(:babs, BabsWeb.TerminalLive, previous)
      else
        Application.delete_env(:babs, BabsWeb.TerminalLive)
      end
    end)

    :ok
  end

  test "root redirects to citizens index" do
    conn = get(build_conn(), "/")

    assert conn.status == 302
    assert Plug.Conn.get_resp_header(conn, "location") == ["/citizens"]
  end

  test "root redirect preserves socket token" do
    conn = get(build_conn(), "/?socket_token=route-token")

    assert conn.status == 302
    assert Plug.Conn.get_resp_header(conn, "location") == ["/citizens?socket_token=route-token"]
  end

  test "root redirect ignores malformed nested socket token" do
    conn = get(build_conn(), "/?socket_token[a]=route-token")

    assert conn.status == 302
    assert Plug.Conn.get_resp_header(conn, "location") == ["/citizens"]
  end

  test "citizens head route returns index existence without rendering" do
    assert head(build_conn(), "/citizens").status == 200
  end

  test "kitchen sink route can be disabled by config" do
    previous = Application.get_env(:babs, :kitchen_sink_enabled)
    Application.put_env(:babs, :kitchen_sink_enabled, false)

    try do
      conn = get(build_conn(), "/dev/kitchen-sink")

      assert conn.status == 404
      assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
      assert conn.resp_body == "not found"
    after
      if is_nil(previous) do
        Application.delete_env(:babs, :kitchen_sink_enabled)
      else
        Application.put_env(:babs, :kitchen_sink_enabled, previous)
      end
    end
  end

  test "kitchen sink route loads the generated app stylesheet" do
    previous = Application.get_env(:babs, :kitchen_sink_enabled)
    Application.put_env(:babs, :kitchen_sink_enabled, true)

    try do
      conn = get(build_conn(), "/dev/kitchen-sink")

      assert conn.status == 200
      assert conn.resp_body =~ ~s(data-testid="kitchen-sink")
      assert conn.resp_body =~ ~s(href="/css/app.css")
    after
      if is_nil(previous) do
        Application.delete_env(:babs, :kitchen_sink_enabled)
      else
        Application.put_env(:babs, :kitchen_sink_enabled, previous)
      end
    end
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

  test "existing citizen ignores malformed nested socket token" do
    slug = "controller-token-test-#{System.unique_integer([:positive])}"
    {:ok, _value} = Registry.register(Babs.Citizens.PaneRegistry, slug, nil)

    conn = get(build_conn(), "/citizens/#{slug}?socket_token[a]=secret")

    assert conn.status == 200
    assert conn.resp_body =~ ~s(data-testid="terminal")
    assert conn.resp_body =~ ~s(data-slug="#{slug}")
    assert conn.resp_body =~ ~s(data-socket-token="")
  end

  test "existing citizen can render pure full terminal mode" do
    slug = "controller-full-test-#{System.unique_integer([:positive])}"
    {:ok, _value} = Registry.register(Babs.Citizens.PaneRegistry, slug, nil)

    conn = get(build_conn(), "/citizens/#{slug}?socket_token=secret&full=1")

    assert conn.status == 200
    assert conn.resp_body =~ ~s(data-testid="terminal")
    assert conn.resp_body =~ ~s(data-slug="#{slug}")
    assert conn.resp_body =~ ~s(data-socket-token="secret")
    refute conn.resp_body =~ ~s(data-testid="terminal-chrome")
  end

  test "existing new citizen keeps /citizens/new terminal URL" do
    {:ok, _value} = Registry.register(Babs.Citizens.PaneRegistry, "new", nil)

    conn = get(build_conn(), "/citizens/new?socket_token=route-token")

    assert conn.status == 200
    assert conn.resp_body =~ ~s(data-testid="terminal")
    assert conn.resp_body =~ ~s(data-slug="new")
    assert conn.resp_body =~ ~s(data-socket-token="route-token")
    assert conn.resp_body =~ ~s(data-terminal-visible="true")
    refute conn.resp_body =~ ~s(data-home-visible="true")
    refute conn.resp_body =~ ~s(data-testid="new-citizen-form")
  end

  test "citizens attach route renders attach LiveView instead of slug terminal" do
    previous = Application.get_env(:babs, BabsWeb.AttachCitizenLive)

    Application.put_env(:babs, BabsWeb.AttachCitizenLive,
      citizen_provider: fn -> [] end,
      inventory_provider: fn _records -> [] end,
      lifecycle_lookup: fn _slug -> {:error, :not_found} end
    )

    try do
      conn = get(build_conn(), "/citizens/attach?socket_token=route-token")

      assert conn.status == 200
      assert conn.resp_body =~ ~s(data-testid="attach-citizen-page")
      assert conn.resp_body =~ ~s(href="/citizens?socket_token=route-token")
      refute conn.resp_body =~ ~s(data-testid="terminal")
      refute conn.resp_body =~ "citizen not found: attach"
    after
      if previous do
        Application.put_env(:babs, BabsWeb.AttachCitizenLive, previous)
      else
        Application.delete_env(:babs, BabsWeb.AttachCitizenLive)
      end
    end
  end

  test "head returns citizen existence without rendering the terminal" do
    slug = "head-test-#{System.unique_integer([:positive])}"
    {:ok, _value} = Registry.register(Babs.Citizens.PaneRegistry, slug, nil)

    assert head(build_conn(), "/citizens/#{slug}").status == 200
    assert head(build_conn(), "/citizens/not-a-citizen").status == 404
  end
end
