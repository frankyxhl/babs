defmodule Babs.Citizens.Hardline.TranscriptTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Hardline.Transcript

  setup do
    cwd = Path.join(System.tmp_dir!(), "babs-transcript-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(cwd) end)
    %{cwd: cwd}
  end

  test "path/1 returns transcript.jsonl inside cwd", %{cwd: cwd} do
    assert Transcript.path(cwd) == Path.join(cwd, "transcript.jsonl")
  end

  test "open/1 creates the cwd if missing and returns an io device", %{cwd: cwd} do
    refute File.dir?(cwd)
    assert {:ok, io} = Transcript.open(cwd)
    assert File.dir?(cwd)
    assert is_pid(io) or is_port(io)
    assert :ok = Transcript.close(io)
  end

  test "encode/1 emits a single JSON line with the documented fields", %{cwd: _cwd} do
    timestamp = ~U[2026-05-05 12:34:56.789012Z]

    line =
      Transcript.encode(%{
        slug: "clare",
        direction: :output,
        stream_id: 42,
        seq: 7,
        payload: <<1, 2, 3, "hi">>,
        timestamp: timestamp
      })
      |> IO.iodata_to_binary()

    refute String.contains?(line, "\n")

    assert {:ok, decoded} = JSON.decode(line)

    assert decoded == %{
             "ts" => "2026-05-05T12:34:56.789012Z",
             "slug" => "clare",
             "direction" => "output",
             "stream_id" => 42,
             "seq" => 7,
             "b64" => Base.encode64(<<1, 2, 3, "hi">>)
           }
  end

  test "encode/1 stamps a current timestamp when none is supplied" do
    before = DateTime.utc_now()

    line =
      Transcript.encode(%{
        slug: "clare",
        direction: :input,
        stream_id: 1,
        seq: 1,
        payload: "x"
      })
      |> IO.iodata_to_binary()

    assert {:ok, %{"ts" => ts, "direction" => "input"}} = JSON.decode(line)
    assert {:ok, parsed, 0} = DateTime.from_iso8601(ts)
    assert DateTime.compare(parsed, before) in [:gt, :eq]
  end

  test "append/2 writes a JSON line per call, preserving order across records", %{cwd: cwd} do
    {:ok, io} = Transcript.open(cwd)

    base = %{slug: "clare", stream_id: 9, payload: "hi"}

    for {direction, seq} <- [{:output, 1}, {:input, 2}, {:output, 3}] do
      :ok =
        Transcript.append(io, Map.merge(base, %{direction: direction, seq: seq}))
    end

    Transcript.close(io)

    lines =
      Transcript.path(cwd)
      |> File.read!()
      |> String.split("\n", trim: true)

    assert length(lines) == 3
    decoded = Enum.map(lines, fn l -> JSON.decode!(l) end)
    assert Enum.map(decoded, & &1["seq"]) == [1, 2, 3]
    assert Enum.map(decoded, & &1["direction"]) == ["output", "input", "output"]
    assert Enum.all?(decoded, &(&1["b64"] == Base.encode64("hi")))
  end

  test "append/2 round-trips arbitrary binary payloads via base64", %{cwd: cwd} do
    {:ok, io} = Transcript.open(cwd)

    raw = <<0, 27, 91, 51, 49, 109, "hello", 0xFF, 0xFE>>

    :ok =
      Transcript.append(io, %{
        slug: "clare",
        direction: :output,
        stream_id: 1,
        seq: 1,
        payload: raw
      })

    Transcript.close(io)

    [line] =
      Transcript.path(cwd)
      |> File.read!()
      |> String.split("\n", trim: true)

    decoded = JSON.decode!(line)
    assert Base.decode64!(decoded["b64"]) == raw
  end

  test "append/2 across two open/close cycles appends rather than truncating", %{cwd: cwd} do
    for seq <- 1..2 do
      {:ok, io} = Transcript.open(cwd)

      :ok =
        Transcript.append(io, %{
          slug: "clare",
          direction: :output,
          stream_id: 1,
          seq: seq,
          payload: "x"
        })

      Transcript.close(io)
    end

    lines =
      Transcript.path(cwd)
      |> File.read!()
      |> String.split("\n", trim: true)

    assert Enum.map(lines, &JSON.decode!(&1)["seq"]) == [1, 2]
  end
end
