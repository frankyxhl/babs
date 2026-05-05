defmodule BabsWeb.PaneChannelTest do
  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  @endpoint BabsWeb.Endpoint
  alias BabsWeb.PaneChannel

  test "rejects joins when no pane is registered" do
    slug = "missing-#{System.unique_integer([:positive])}"

    assert {:error, %{reason: "not_found"}} =
             PaneChannel.join("pane:#{slug}", %{}, %Phoenix.Socket{})
  end

  test "pushes pane bytes broadcast by Hardline.Pane on the citizens PubSub" do
    slug = "existing-#{System.unique_integer([:positive])}"
    {:ok, _value} = Registry.register(Babs.Citizens.PaneRegistry, slug, nil)

    {:ok, _reply, _socket} =
      BabsWeb.UserSocket
      |> socket(nil, %{})
      |> subscribe_and_join(PaneChannel, "pane:#{slug}")

    Phoenix.PubSub.broadcast(
      Babs.Citizens.PubSub,
      "pane:#{slug}",
      {:pane_bytes, 123, 456, "hello"}
    )

    assert_push "output", %{
      "stream_id" => 123,
      "seq" => 456,
      "base64" => encoded
    }

    assert Base.decode64!(encoded) == "hello"
  end

  test "allows only the Phase 1 restricted keyboard set" do
    assert PaneChannel.allowed_input?("printf 'ok'\\n")
    assert PaneChannel.allowed_input?("\r")
    assert PaneChannel.allowed_input?("\t")
    assert PaneChannel.allowed_input?(<<3>>)
    assert PaneChannel.allowed_input?(<<4>>)
    assert PaneChannel.allowed_input?(<<26>>)
    assert PaneChannel.allowed_input?("\e[A")
    assert PaneChannel.allowed_input?("\e[B")
    assert PaneChannel.allowed_input?("\e[C")
    assert PaneChannel.allowed_input?("\e[D")
    assert PaneChannel.allowed_input?(<<127>>)

    refute PaneChannel.allowed_input?(<<0>>)
    refute PaneChannel.allowed_input?("\e]52;c;clipboard\a")
    refute PaneChannel.allowed_input?(:binary.copy("x", 4097))
  end

  test "input and resize events tolerate invalid or unavailable panes" do
    socket = %Phoenix.Socket{assigns: %{slug: "missing-pane"}}

    assert {:noreply, ^socket} = PaneChannel.handle_in("input", %{"data" => "ok"}, socket)
    assert {:noreply, ^socket} = PaneChannel.handle_in("input", %{"data" => <<0>>}, socket)

    assert {:noreply, ^socket} =
             PaneChannel.handle_in("resize", %{"cols" => 120, "rows" => 30}, socket)

    assert {:noreply, ^socket} =
             PaneChannel.handle_in("resize", %{"cols" => 0, "rows" => 30}, socket)

    assert {:noreply, ^socket} =
             PaneChannel.handle_in("resize", %{"cols" => "120", "rows" => 30}, socket)
  end

  test "snapshot send is best effort when tmux capture fails" do
    socket = %Phoenix.Socket{assigns: %{slug: "missing-pane"}}

    assert {:noreply, ^socket} = PaneChannel.handle_info(:send_snapshot, socket)
  end
end
