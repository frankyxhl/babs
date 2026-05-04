defmodule Hardline.Web.PaneChannelTest do
  use ExUnit.Case, async: true

  alias Hardline.Web.PaneChannel

  test "rejects joins when no pane server is registered" do
    name = "missing-pane-#{System.unique_integer([:positive])}"

    assert {:error, %{reason: "not_found"}} =
             PaneChannel.join("pane:#{name}", %{}, %Phoenix.Socket{})
  end

  test "accepts joins for registered pane servers" do
    name = "existing-pane-#{System.unique_integer([:positive])}"
    {:ok, _value} = Registry.register(Hardline.Web.PaneRegistry, name, nil)

    assert {:ok, %Phoenix.Socket{assigns: %{pane_name: ^name}}} =
             PaneChannel.join("pane:#{name}", %{}, %Phoenix.Socket{})
  end
end
