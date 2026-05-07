defmodule Babs.Citizens.Tickets.TurnIds do
  @moduledoc """
  Sortable, log-safe ids for Ticket turns, messages, and delivery attempts.
  """

  @prefixes %{turn: "turn", message: "msg", attempt: "attempt"}
  @suffix_size 10

  @spec generate!(atom(), String.t() | DateTime.t(), keyword()) :: String.t()
  def generate!(kind, timestamp, opts \\ []) when is_atom(kind) do
    prefix = Map.fetch!(@prefixes, kind)
    "#{prefix}_#{stamp!(timestamp)}_#{suffix!(opts)}"
  end

  defp stamp!(%DateTime{} = timestamp), do: format_datetime(timestamp)

  defp stamp!(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _offset} -> format_datetime(datetime)
      {:error, reason} -> raise ArgumentError, "invalid ISO8601 timestamp: #{inspect(reason)}"
    end
  end

  defp format_datetime(datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> then(fn dt ->
      [
        dt.year,
        dt.month,
        dt.day,
        dt.hour,
        dt.minute,
        dt.second
      ]
      |> Enum.map_join(&pad2_or_4/1)
    end)
  end

  defp pad2_or_4(value) when value >= 1000, do: Integer.to_string(value)
  defp pad2_or_4(value), do: value |> Integer.to_string() |> String.pad_leading(2, "0")

  defp suffix!(opts) do
    suffix =
      case Keyword.get(opts, :suffix) do
        value when is_binary(value) ->
          value

        nil ->
          :crypto.strong_rand_bytes(8)
          |> Base.encode32(case: :lower, padding: false)
          |> binary_part(0, @suffix_size)
      end

    if suffix =~ ~r/\A[a-z0-9]{#{@suffix_size}}\z/ do
      suffix
    else
      raise ArgumentError, "invalid Ticket turn id suffix"
    end
  end
end
