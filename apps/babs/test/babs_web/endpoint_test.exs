defmodule BabsWeb.EndpointTest do
  use ExUnit.Case, async: true

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
end
