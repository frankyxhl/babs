defmodule BabsWeb.Layouts do
  @moduledoc false

  use Phoenix.Component

  def render("root.html", assigns), do: root(assigns)

  def root(assigns) do
    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <meta name="theme-color" content="#f6f8fa" />
        <meta name="apple-mobile-web-app-capable" content="yes" />
        <meta name="apple-mobile-web-app-title" content="Babs" />
        <link rel="manifest" href="/manifest.webmanifest" />
        <link rel="apple-touch-icon" sizes="180x180" href="/icons/babs-180.png" />
        <link phx-track-static rel="stylesheet" href="/css/app.css" />
        <title>Babs</title>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end
end
