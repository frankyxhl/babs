defmodule Hardline.Pane do
  @moduledoc """
  Pure helpers for the future erlexec-backed pane process.
  """

  @pubsub_chunk_size 4096

  def chunk_bytes(bytes, max_size \\ @pubsub_chunk_size)

  def chunk_bytes(_bytes, max_size) when not (is_integer(max_size) and max_size > 0) do
    raise ArgumentError, "max_size must be a positive integer"
  end

  def chunk_bytes(bytes, max_size) when is_binary(bytes) do
    do_chunk(bytes, max_size, [])
  end

  defp do_chunk("", _max_size, acc), do: Enum.reverse(acc)

  defp do_chunk(bytes, max_size, acc) do
    size = min(byte_size(bytes), max_size)
    chunk = binary_part(bytes, 0, size)
    rest = binary_part(bytes, size, byte_size(bytes) - size)

    do_chunk(rest, max_size, [chunk | acc])
  end
end
