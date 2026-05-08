defmodule Babs.Citizens.Hardline.Transcript do
  @moduledoc """
  Append-only JSONL transcript for `Babs.Citizens.Hardline.Pane`.

  Every byte that flows through a Pane (PTY output, browser input) is
  recorded as one JSON line in `<cwd>/transcript.jsonl` so a future
  reader can replay or audit the session.

  Record shape:

      {
        "ts": "2026-05-05T12:34:56.789012Z",
        "slug": "clare",
        "direction": "output" | "input",
        "stream_id": 42,
        "seq": 1,
        "b64": "<base64 of raw bytes>"
      }
  """

  @filename "transcript.jsonl"
  @default_replay_tail_bytes 1_048_576

  @typedoc "JSONL record fields written to the transcript."
  @type record :: %{
          required(:slug) => String.t(),
          required(:direction) => :output | :input,
          required(:stream_id) => integer(),
          required(:seq) => non_neg_integer(),
          required(:payload) => binary(),
          optional(:timestamp) => DateTime.t()
        }

  @doc "Absolute path to the transcript file inside `cwd`."
  @spec path(Path.t()) :: Path.t()
  def path(cwd) when is_binary(cwd), do: Path.join(cwd, @filename)

  @doc """
  Open `cwd/transcript.jsonl` for append, creating `cwd` if missing.

  Returns the IO device on success.
  """
  @spec open(Path.t()) :: {:ok, File.io_device()} | {:error, term()}
  def open(cwd) when is_binary(cwd) do
    with :ok <- File.mkdir_p(cwd),
         {:ok, io} <- File.open(path(cwd), [:append, :binary]) do
      {:ok, io}
    end
  end

  @doc "Close a transcript IO device opened with `open/1`."
  @spec close(File.io_device() | nil) :: :ok
  def close(nil), do: :ok
  def close(io), do: File.close(io)

  @doc "Flush a transcript IO device so replay reads the latest buffered bytes."
  @spec flush(File.io_device() | nil) :: :ok | {:error, term()}
  def flush(nil), do: {:error, :no_transcript}

  def flush(io) do
    :file.sync(io)
  end

  @doc """
  Append one record to the open transcript IO device.
  """
  @spec append(File.io_device(), record()) :: :ok | {:error, term()}
  def append(io, %{} = record) do
    IO.binwrite(io, [encode(record), ?\n])
  end

  @doc """
  Replay output bytes from `cwd/transcript.jsonl`.

  Only records with `"direction": "output"` are replayed. Malformed JSONL rows,
  invalid base64 payloads, and incomplete final rows are ignored because this is
  a best-effort browser snapshot, not an audit reader. Replay reads a bounded
  tail of the transcript file so reconnect cost does not grow with the full
  append-only transcript.
  """
  @spec replay_output(Path.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def replay_output(cwd, opts \\ []) when is_binary(cwd) and is_list(opts) do
    with {:ok, info} <- replay_output_info(cwd, opts) do
      {:ok, info.output}
    end
  end

  @doc """
  Replay output bytes and return metadata for read-only API consumers.
  """
  @spec replay_output_info(Path.t(), keyword()) ::
          {:ok,
           %{
             output: binary(),
             truncated: boolean(),
             lines: pos_integer(),
             returned_lines: non_neg_integer()
           }}
          | {:error, term()}
  def replay_output_info(cwd, opts \\ []) when is_binary(cwd) and is_list(opts) do
    line_limit = Keyword.get(opts, :lines, 200)
    slug = Keyword.get(opts, :slug)
    tail_bytes = Keyword.get(opts, :tail_bytes, @default_replay_tail_bytes)

    with {:ok, line_limit} <- positive_line_limit(line_limit),
         {:ok, slug} <- valid_slug_filter(slug),
         {:ok, tail_bytes} <- positive_tail_bytes(tail_bytes),
         {:ok, contents, tail_truncated?} <- read_transcript_tail(path(cwd), tail_bytes) do
      raw_output =
        contents
        |> String.split("\n", trim: true)
        |> Enum.flat_map(&decode_output_payload(&1, slug))
        |> IO.iodata_to_binary()

      {output, line_truncated?, returned_lines} = newest_lines_info(raw_output, line_limit)

      {:ok,
       %{
         output: output,
         truncated: tail_truncated? or line_truncated?,
         lines: line_limit,
         returned_lines: returned_lines
       }}
    end
  end

  @doc """
  Encode a record as a single JSON line (no trailing newline).
  """
  @spec encode(record()) :: iodata()
  def encode(
        %{
          slug: slug,
          direction: direction,
          stream_id: stream_id,
          seq: seq,
          payload: payload
        } = record
      )
      when is_binary(slug) and is_integer(stream_id) and is_integer(seq) and is_binary(payload) do
    timestamp = Map.get(record, :timestamp) || DateTime.utc_now()

    JSON.encode!(%{
      "ts" => DateTime.to_iso8601(timestamp),
      "slug" => slug,
      "direction" => direction_to_string(direction),
      "stream_id" => stream_id,
      "seq" => seq,
      "b64" => Base.encode64(payload)
    })
  end

  defp direction_to_string(:output), do: "output"
  defp direction_to_string(:input), do: "input"

  defp read_transcript_tail(path, tail_bytes) do
    case File.stat(path) do
      {:ok, stat} ->
        with {:ok, io} <- File.open(path, [:read, :binary]) do
          try do
            with {:ok, contents} <- read_tail(io, stat.size, tail_bytes) do
              {:ok, contents, stat.size > tail_bytes}
            end
          after
            File.close(io)
          end
        else
          {:error, reason} -> {:error, {:file_error, path, reason}}
        end

      {:error, :enoent} ->
        {:ok, "", false}

      {:error, reason} ->
        {:error, {:file_error, path, reason}}
    end
  end

  defp read_tail(io, size, tail_bytes) do
    start = max(size - tail_bytes - 1, 0)
    bytes_to_read = size - start

    case :file.pread(io, start, bytes_to_read) do
      {:ok, contents} when start == 0 ->
        {:ok, contents}

      {:ok, contents} ->
        {:ok, drop_leading_partial_line(contents)}

      :eof ->
        {:ok, ""}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp drop_leading_partial_line(contents) do
    case :binary.split(contents, "\n") do
      [_partial, rest] -> rest
      [_partial] -> ""
    end
  end

  defp decode_output_payload(line, slug) do
    with {:ok, %{"direction" => "output", "b64" => b64} = record} when is_binary(b64) <-
           JSON.decode(line),
         true <- slug_matches?(record, slug),
         {:ok, payload} <- Base.decode64(b64) do
      [payload]
    else
      _ -> []
    end
  end

  defp slug_matches?(_record, nil), do: true
  defp slug_matches?(%{"slug" => slug}, slug), do: true
  defp slug_matches?(_record, _slug), do: false

  defp newest_lines_info(output, line_limit) do
    trailing_newline? = String.ends_with?(output, "\n")

    parts =
      output
      |> :binary.split("\n", [:global])
      |> trim_trailing_empty_line()

    selected = Enum.take(parts, -line_limit)

    {
      join_lines(selected, trailing_newline?),
      length(parts) > line_limit,
      length(selected)
    }
  end

  defp trim_trailing_empty_line(parts) do
    case Enum.reverse(parts) do
      ["" | rest] -> Enum.reverse(rest)
      _other -> parts
    end
  end

  defp join_lines([], _trailing_newline?), do: ""

  defp join_lines(parts, true), do: [Enum.intersperse(parts, "\n"), "\n"] |> IO.iodata_to_binary()
  defp join_lines(parts, false), do: Enum.join(parts, "\n")

  defp positive_line_limit(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive_line_limit(value), do: {:error, {:invalid_line_limit, value}}

  defp positive_tail_bytes(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive_tail_bytes(value), do: {:error, {:invalid_tail_bytes, value}}

  defp valid_slug_filter(nil), do: {:ok, nil}
  defp valid_slug_filter(value) when is_binary(value), do: {:ok, value}
  defp valid_slug_filter(value), do: {:error, {:invalid_slug_filter, value}}
end
