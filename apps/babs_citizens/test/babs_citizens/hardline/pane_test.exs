defmodule Babs.Citizens.Hardline.PaneTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Hardline.Pane
  alias Babs.Citizens.CitizenConfig

  test "chunks PubSub payloads to the configured maximum size" do
    payload = :binary.copy("a", 9)

    assert Pane.chunk_bytes(payload, 4) == ["aaaa", "aaaa", "a"]
  end

  test "defaults chunking to the BAB-1106 4 KB ceiling" do
    payload = :binary.copy("x", 4097)
    chunks = Pane.chunk_bytes(payload)

    assert Enum.map(chunks, &byte_size/1) == [4096, 1]
  end

  test "rejects non-positive chunk sizes" do
    assert_raise ArgumentError, fn -> Pane.chunk_bytes("abc", 0) end
  end

  test "stdout handler tolerates pre-transcript hot-reload state" do
    slug = "legacy-pane-#{System.unique_integer([:positive])}"
    stream_id = 123

    Phoenix.PubSub.subscribe(Babs.Citizens.PubSub, "pane:#{slug}")

    state = %{
      attach: %{os_pid: 456},
      config: %CitizenConfig{
        id: "BAB-CIT-LEGACY",
        slug: slug,
        display_name: "Legacy Pane",
        cli: "/bin/zsh",
        cwd: System.tmp_dir!()
      },
      seq: 0,
      stream_id: stream_id
    }

    assert {:noreply, %{seq: 1}} = Pane.handle_info({:stdout, 456, "legacy"}, state)
    assert_receive {:pane_bytes, ^stream_id, 1, "legacy"}
  end
end
