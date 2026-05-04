defmodule Babs.Citizens.Hardline.PaneTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Hardline.Pane

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
end
