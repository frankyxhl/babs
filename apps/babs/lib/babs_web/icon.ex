defmodule BabsWeb.Icon do
  @moduledoc """
  Small inline icon helper for the current no-build frontend.
  """

  use Phoenix.Component

  attr :name, :string, required: true
  attr :class, :string, default: "icon"

  def icon(assigns) do
    ~H"""
    <svg
      class={@class}
      data-icon={@name}
      aria-hidden="true"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <%= for path <- paths(@name) do %>
        <path d={path}></path>
      <% end %>
    </svg>
    """
  end

  defp paths("arrow-left"), do: ["m12 19-7-7 7-7", "M19 12H5"]

  defp paths("external-link"),
    do: ["M15 3h6v6", "M10 14 21 3", "M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"]

  defp paths("file-text"),
    do: [
      "M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z",
      "M14 2v6h6",
      "M16 13H8",
      "M16 17H8",
      "M10 9H8"
    ]

  defp paths("folder-open"), do: ["M6 14 8 4h14l-2 10Z", "M2 8h4l2 4h14l-2 8H4Z"]

  defp paths("link"),
    do: [
      "M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71",
      "M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"
    ]

  defp paths("list"),
    do: ["M8 6h13", "M8 12h13", "M8 18h13", "M3 6h.01", "M3 12h.01", "M3 18h.01"]

  defp paths("message-square"),
    do: ["M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"]

  defp paths("maximize"),
    do: [
      "M8 3H5a2 2 0 0 0-2 2v3",
      "M21 8V5a2 2 0 0 0-2-2h-3",
      "M3 16v3a2 2 0 0 0 2 2h3",
      "M16 21h3a2 2 0 0 0 2-2v-3"
    ]

  defp paths("play"), do: ["m5 3 14 9-14 9V3Z"]
  defp paths("plus"), do: ["M5 12h14", "M12 5v14"]

  defp paths("ban"), do: ["M4.93 4.93 19.07 19.07", "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20"]

  defp paths("check"), do: ["M20 6 9 17l-5-5"]

  defp paths("clock"),
    do: [
      "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20",
      "M12 6v6l4 2"
    ]

  defp paths("refresh"),
    do: [
      "M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16",
      "M3 21v-5h5",
      "M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8",
      "M16 8h5V3"
    ]

  defp paths("rotate-cw"), do: ["M21 12a9 9 0 1 1-2.64-6.36", "M21 3v6h-6"]

  defp paths("send"), do: ["m22 2-7 20-4-9-9-4Z", "M22 2 11 13"]

  defp paths("route"),
    do: [
      "M2 9h6",
      "M16 15h6",
      "M8 9a4 4 0 0 1 4 4v0a4 4 0 0 0 4 4",
      "M8 9l3-3",
      "M8 9l3 3",
      "M16 15l-3-3",
      "M16 15l-3 3"
    ]

  defp paths("square"), do: ["M5 5h14v14H5z"]

  defp paths("tag"),
    do: [
      "M20.59 13.41 13.41 20.59a2 2 0 0 1-2.82 0L3 13V3h10l7.59 7.59a2 2 0 0 1 0 2.82",
      "M7 7h.01"
    ]

  defp paths("triangle-alert"),
    do: [
      "m21.73 18-8-14a2 2 0 0 0-3.46 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3",
      "M12 9v4",
      "M12 17h.01"
    ]

  defp paths("users"),
    do: [
      "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2",
      "M9 7a4 4 0 1 0 0.01 0",
      "M22 21v-2a4 4 0 0 0-3-3.87",
      "M16 3.13a4 4 0 0 1 0 7.75"
    ]

  defp paths("undo"), do: ["M9 14 4 9l5-5", "M4 9h10a6 6 0 0 1 0 12h-5"]

  defp paths("user-plus"),
    do: [
      "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2",
      "M9 7a4 4 0 1 0 0.01 0",
      "M19 8v6",
      "M22 11h-6"
    ]

  defp paths("x"), do: ["M18 6 6 18", "M6 6l12 12"]

  defp paths(_name), do: ["M12 5v14", "M5 12h14"]
end
