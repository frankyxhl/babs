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

  test "flush/1 syncs an open transcript and rejects missing devices", %{cwd: cwd} do
    {:ok, io} = Transcript.open(cwd)

    assert :ok =
             Transcript.append(io, %{
               slug: "clare",
               direction: :output,
               stream_id: 1,
               seq: 1,
               payload: "flushed\n"
             })

    assert :ok = Transcript.flush(io)
    assert {:error, :no_transcript} = Transcript.flush(nil)
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

  test "replay_output/2 returns output bytes and ignores input records", %{cwd: cwd} do
    {:ok, io} = Transcript.open(cwd)

    :ok =
      Transcript.append(io, %{
        slug: "clare",
        direction: :input,
        stream_id: 1,
        seq: 1,
        payload: "printf 'hidden'\n"
      })

    :ok =
      Transcript.append(io, %{
        slug: "clare",
        direction: :output,
        stream_id: 1,
        seq: 2,
        payload: "visible\n"
      })

    Transcript.close(io)

    assert {:ok, "visible\n"} = Transcript.replay_output(cwd)
  end

  test "replay_output/2 filters output records by slug when requested", %{cwd: cwd} do
    {:ok, io} = Transcript.open(cwd)

    :ok =
      Transcript.append(io, %{
        slug: "dylan",
        direction: :output,
        stream_id: 1,
        seq: 1,
        payload: "other citizen\n"
      })

    :ok =
      Transcript.append(io, %{
        slug: "clare",
        direction: :output,
        stream_id: 1,
        seq: 2,
        payload: "active citizen\n"
      })

    Transcript.close(io)

    assert {:ok, "active citizen\n"} = Transcript.replay_output(cwd, slug: "clare")
  end

  test "replay_output/2 preserves legacy output replay when no slug is requested", %{cwd: cwd} do
    {:ok, io} = Transcript.open(cwd)

    for {slug, seq, payload} <- [{"dylan", 1, "one\n"}, {"clare", 2, "two\n"}] do
      :ok =
        Transcript.append(io, %{
          slug: slug,
          direction: :output,
          stream_id: 1,
          seq: seq,
          payload: payload
        })
    end

    Transcript.close(io)

    assert {:ok, "one\ntwo\n"} = Transcript.replay_output(cwd)
  end

  test "replay_output/2 skips malformed JSONL and invalid base64", %{cwd: cwd} do
    File.mkdir_p!(cwd)

    File.write!(Transcript.path(cwd), """
    not json
    {"direction":"output","b64":"%%%","slug":"clare","stream_id":1,"seq":1}
    #{IO.iodata_to_binary(Transcript.encode(%{slug: "clare", direction: :output, stream_id: 1, seq: 2, payload: "ok\n"}))}
    """)

    assert {:ok, "ok\n"} = Transcript.replay_output(cwd)
  end

  test "replay_output/2 round-trips arbitrary binary output payloads", %{cwd: cwd} do
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

    :ok = Transcript.close(io)

    assert {:ok, ^raw} = Transcript.replay_output(cwd)
  end

  test "replay_output/2 caps replay to newest output lines", %{cwd: cwd} do
    {:ok, io} = Transcript.open(cwd)

    :ok =
      Transcript.append(io, %{
        slug: "clare",
        direction: :output,
        stream_id: 1,
        seq: 1,
        payload: "one\ntwo\nthree\n"
      })

    Transcript.close(io)

    assert {:ok, "two\nthree\n"} = Transcript.replay_output(cwd, lines: 2)
  end

  test "replay_output/2 reads a bounded tail and skips truncated leading JSONL", %{cwd: cwd} do
    File.mkdir_p!(cwd)

    old_line =
      Transcript.encode(%{
        slug: "clare",
        direction: :output,
        stream_id: 1,
        seq: 1,
        payload: "old\n"
      })
      |> IO.iodata_to_binary()

    filler_line =
      Transcript.encode(%{
        slug: "clare",
        direction: :input,
        stream_id: 1,
        seq: 2,
        payload: String.duplicate("x", 256)
      })
      |> IO.iodata_to_binary()

    new_line =
      Transcript.encode(%{
        slug: "clare",
        direction: :output,
        stream_id: 1,
        seq: 3,
        payload: "new\n"
      })
      |> IO.iodata_to_binary()

    File.write!(Transcript.path(cwd), [old_line, "\n", filler_line, "\n", new_line, "\n"])

    assert {:ok, "new\n"} =
             Transcript.replay_output(cwd, tail_bytes: byte_size(new_line) + 12)
  end

  test "replay_output/2 returns an empty payload for missing transcripts", %{cwd: cwd} do
    assert {:ok, ""} = Transcript.replay_output(cwd)
  end
end
