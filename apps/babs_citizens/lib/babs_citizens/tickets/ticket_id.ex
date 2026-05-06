defmodule Babs.Citizens.Tickets.TicketId do
  @moduledoc """
  Parses, formats, allocates, and atomically claims Ticket ids.
  """

  @regex ~r/^T-(\d{4})-(\d{2})-(\d{2})-(\d{3})$/
  @max_sequence 999

  @spec parse(String.t()) ::
          {:ok, %{date: Date.t(), sequence: pos_integer()}} | {:error, {:invalid_id, term()}}
  def parse(id) when is_binary(id) do
    with [_, year, month, day, sequence] <- Regex.run(@regex, id),
         {year, ""} <- Integer.parse(year),
         {month, ""} <- Integer.parse(month),
         {day, ""} <- Integer.parse(day),
         {sequence, ""} <- Integer.parse(sequence),
         {:ok, date} <- Date.new(year, month, day) do
      {:ok, %{date: date, sequence: sequence}}
    else
      _ -> {:error, {:invalid_id, id}}
    end
  end

  def parse(value), do: {:error, {:invalid_id, value}}

  @spec validate(String.t()) :: :ok | {:error, {:invalid_id, term()}}
  def validate(id) do
    case parse(id) do
      {:ok, _parsed} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec format(Date.t(), pos_integer()) :: String.t()
  def format(%Date{} = date, sequence) when is_integer(sequence) and sequence > 0 do
    "T-#{Date.to_iso8601(date)}-#{String.pad_leading(to_string(sequence), 3, "0")}"
  end

  @spec local_date :: Date.t()
  def local_date do
    {{year, month, day}, _time} = :calendar.local_time()
    Date.new!(year, month, day)
  end

  @spec allocate(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def allocate(root, opts \\ []) do
    date = Keyword.get(opts, :date, local_date())
    next_sequence = max_sequence(root, date) + 1

    if next_sequence > @max_sequence do
      {:error, {:sequence_exhausted, date}}
    else
      {:ok, format(date, next_sequence)}
    end
  end

  @spec claim_next(String.t(), keyword()) :: {:ok, String.t(), String.t()} | {:error, term()}
  def claim_next(root, opts \\ []) do
    date = Keyword.get(opts, :date, local_date())

    case File.mkdir_p(root) do
      :ok -> claim_from(root, date, max_sequence(root, date) + 1)
      {:error, reason} -> {:error, {:redacted_io_error, {:mkdir_tickets_root, reason}}}
    end
  end

  defp claim_from(_root, date, sequence) when sequence > @max_sequence do
    {:error, {:sequence_exhausted, date}}
  end

  defp claim_from(root, date, sequence) do
    id = format(date, sequence)
    path = Path.join(root, "#{id}.md")

    case File.open(path, [:write, :exclusive]) do
      {:ok, io} ->
        File.close(io)
        {:ok, id, path}

      {:error, :eexist} ->
        claim_from(root, date, sequence + 1)

      {:error, reason} ->
        {:error, {:redacted_io_error, {:claim_ticket_id, reason}}}
    end
  end

  defp max_sequence(root, date) do
    root
    |> Path.join("T-#{Date.to_iso8601(date)}-*.md")
    |> Path.wildcard()
    |> Enum.map(&Path.basename(&1, ".md"))
    |> Enum.flat_map(fn id ->
      case parse(id) do
        {:ok, %{date: ^date, sequence: sequence}} -> [sequence]
        _ -> []
      end
    end)
    |> Enum.max(fn -> 0 end)
  end
end
