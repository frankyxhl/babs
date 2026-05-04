defmodule Hardline.Observer do
  @moduledoc """
  Formats Phase 0 observer events for append-only logs.
  """

  def format_event(event, metadata) when is_atom(event) and is_map(metadata) do
    fields =
      metadata
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, value} -> "#{key}=#{format_value(value)}" end)

    (["ts=#{DateTime.utc_now() |> DateTime.to_iso8601()}", "event=#{event}"] ++ fields)
    |> Enum.join(" ")
    |> Kernel.<>("\n")
  end

  def append_event(path, event, metadata) when is_binary(path) do
    File.write!(path, format_event(event, metadata), [:append])
  end

  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value), do: to_string(value)
end
