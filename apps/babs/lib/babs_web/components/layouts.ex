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
        <title>Babs</title>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end
end
