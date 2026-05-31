defmodule BabsWeb.EndpointTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Phoenix.ConnTest

  @endpoint BabsWeb.Endpoint

  test "uses the citizens PubSub so Hardline.Pane broadcasts reach channels" do
    assert BabsWeb.Endpoint.config(:pubsub_server) == Babs.Citizens.PubSub
  end

  test "root layout exposes PWA metadata" do
    html = build_conn() |> get("/citizens") |> html_response(200)

    assert html =~ ~s(rel="manifest" href="/manifest.webmanifest")
    assert html =~ ~s(name="theme-color" content="#f6f8fa")
    assert html =~ ~s(name="apple-mobile-web-app-capable" content="yes")
    assert html =~ ~s(name="apple-mobile-web-app-title" content="Babs")
    assert html =~ ~s(rel="apple-touch-icon" sizes="180x180" href="/icons/babs-180.png")
  end

  test "serves the PWA manifest with installable icon metadata" do
    conn = build_conn() |> get("/manifest.webmanifest")

    assert response(conn, 200)
    assert content_type(conn) =~ "application/manifest+json"

    assert {:ok, manifest} = Jason.decode(conn.resp_body)
    assert manifest["name"] == "Babs"
    assert manifest["short_name"] == "Babs"
    assert manifest["start_url"] == "/"
    assert manifest["scope"] == "/"
    assert manifest["display"] == "standalone"
    assert manifest["background_color"] == "#f6f8fa"
    assert manifest["theme_color"] == "#f6f8fa"

    assert Enum.any?(manifest["icons"], &(&1["sizes"] == "192x192"))
    assert Enum.any?(manifest["icons"], &(&1["sizes"] == "512x512"))
    assert Enum.any?(manifest["icons"], &String.contains?(&1["purpose"], "maskable"))
  end

  test "serves the service worker with update-friendly cache headers" do
    conn = build_conn() |> get("/sw.js")

    assert response(conn, 200) =~ "babs-shell-v"
    assert content_type(conn) =~ "javascript"
    assert ["no-cache"] = get_resp_header(conn, "cache-control")
  end

  test "serves LiveDashboard when dashboard auth is disabled" do
    with_dashboard_auth([required?: false, token: nil], fn ->
      conn = build_conn() |> get("/dev/dashboard")
      assert redirected_to(conn) == "/dev/dashboard/home"

      conn = build_conn() |> get("/dev/dashboard/home")
      assert html_response(conn, 200) =~ "LiveDashboard"
    end)
  end

  test "rejects LiveDashboard without credentials when dashboard auth is required" do
    with_dashboard_auth([required?: true, token: "dashboard-secret"], fn ->
      conn = build_conn() |> get("/dev/dashboard")

      assert response(conn, 401) =~ "Unauthorized"
      assert ["Basic realm=\"babs-dashboard\""] = get_resp_header(conn, "www-authenticate")
    end)
  end

  test "serves LiveDashboard with basic auth using the socket token" do
    with_dashboard_auth([required?: true, token: "dashboard-secret"], fn ->
      conn =
        build_conn()
        |> put_req_header("authorization", "Basic " <> Base.encode64("babs:dashboard-secret"))
        |> get("/dev/dashboard")

      assert redirected_to(conn) == "/dev/dashboard/home"

      conn =
        build_conn()
        |> put_req_header("authorization", "Basic " <> Base.encode64("babs:dashboard-secret"))
        |> get("/dev/dashboard/home")

      assert html_response(conn, 200) =~ "LiveDashboard"
    end)
  end

  test "serves PWA icon assets" do
    for {path, content_type} <- [
          {"/icons/babs-180.png", "image/png"},
          {"/icons/babs-192.png", "image/png"},
          {"/icons/babs-512.png", "image/png"},
          {"/icons/babs-maskable.svg", "image/svg+xml"}
        ] do
      conn = build_conn() |> get(path)

      assert response(conn, 200)
      assert content_type(conn) =~ content_type
    end
  end

  defp content_type(conn) do
    conn
    |> get_resp_header("content-type")
    |> List.first("")
  end

  defp with_dashboard_auth(opts, fun) do
    old_dashboard_auth = Application.get_env(:babs, BabsWeb.LiveDashboardAuth)
    old_socket_auth = Application.get_env(:babs, BabsWeb.UserSocket)
    socket_auth = Keyword.put(old_socket_auth || [], :auth_token, Keyword.fetch!(opts, :token))

    Application.put_env(:babs, BabsWeb.LiveDashboardAuth,
      required?: Keyword.fetch!(opts, :required?)
    )

    Application.put_env(:babs, BabsWeb.UserSocket, socket_auth)

    try do
      fun.()
    after
      restore_env(:babs, BabsWeb.LiveDashboardAuth, old_dashboard_auth)
      restore_env(:babs, BabsWeb.UserSocket, old_socket_auth)
    end
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
