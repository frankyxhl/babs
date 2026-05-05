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
         {:ok, io} <- File.open(path(cwd), [:append, :binary, {:delayed_write, 4096, 50}]) do
      {:ok, io}
    end
  end

  @doc "Close a transcript IO device opened with `open/1`."
  @spec close(File.io_device() | nil) :: :ok
  def close(nil), do: :ok
  def close(io), do: File.close(io)

  @doc """
  Append one record to the open transcript IO device.
  """
  @spec append(File.io_device(), record()) :: :ok | {:error, term()}
  def append(io, %{} = record) do
    IO.binwrite(io, [encode(record), ?\n])
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
end
