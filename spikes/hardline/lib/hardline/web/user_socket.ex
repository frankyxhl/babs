defmodule Hardline.Web.UserSocket do
  @moduledoc false

  use Phoenix.Socket

  channel("pane:*", Hardline.Web.PaneChannel)

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
