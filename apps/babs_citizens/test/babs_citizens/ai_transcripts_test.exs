defmodule Babs.Citizens.AiTranscriptsTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.AiTranscripts

  @since "2026-05-06T00:00:00Z"
  @ticket_id "T-2026-05-06-001"

  test "finds assistant reply after a Claude-style user Ticket prompt" do
    path = transcript_path()

    write_jsonl(path, [
      %{
        "timestamp" => @since,
        "type" => "user",
        "message" => %{"content" => "Babs Ticket #{@ticket_id}"}
      },
      %{
        "timestamp" => "2026-05-06T00:00:01Z",
        "type" => "assistant",
        "message" => %{"content" => [%{"type" => "text", "text" => "Done from Claude"}]}
      }
    ])

    assert {:ok, %{text: "Done from Claude", role: "assistant", path: ^path}} =
             AiTranscripts.find_reply_in_file(path, @ticket_id, @since)
  end

  test "finds assistant reply in Codex-style role/content records" do
    path = transcript_path()

    write_jsonl(path, [
      %{"ts" => @since, "role" => "user", "content" => "Please work on #{@ticket_id}"},
      %{
        "ts" => "2026-05-06T00:00:02Z",
        "role" => "assistant",
        "content" => [%{"type" => "output_text", "text" => "Done from Codex"}]
      }
    ])

    assert {:ok, %{text: "Done from Codex"}} =
             AiTranscripts.find_reply_in_file(path, @ticket_id, @since)
  end

  test "ignores malformed, stale, and unrelated records" do
    path = transcript_path()

    File.write!(path, "{not-json}\n")

    append_jsonl(path, [
      %{"timestamp" => "2026-05-05T23:59:59Z", "role" => "user", "content" => @ticket_id},
      %{"timestamp" => "2026-05-06T00:00:01Z", "role" => "assistant", "content" => "stale"},
      %{"timestamp" => "2026-05-06T00:00:02Z", "role" => "user", "content" => "other ticket"},
      %{"timestamp" => "2026-05-06T00:00:03Z", "role" => "assistant", "content" => "unrelated"}
    ])

    assert :pending = AiTranscripts.find_reply_in_file(path, @ticket_id, @since)
  end

  test "reports recognized AI CLIs without transcript support explicitly" do
    config = %{cli: "gh", cli_args: ["copilot"], cwd: System.tmp_dir!(), env: %{}}

    assert {:error, :unsupported_copilot_transcripts} =
             AiTranscripts.find_reply(config, @ticket_id, @since)
  end

  test "keeps supported AI CLIs pending before transcript files appear" do
    config = %{cli: "claude", cli_args: [], cwd: System.tmp_dir!(), env: %{}}

    assert :pending = AiTranscripts.find_reply(config, @ticket_id, @since, paths: [])
  end

  defp transcript_path do
    path =
      Path.join(System.tmp_dir!(), "ai-transcript-#{System.unique_integer([:positive])}.jsonl")

    on_exit(fn -> File.rm(path) end)
    path
  end

  defp write_jsonl(path, records) do
    File.write!(path, encode_jsonl(records))
  end

  defp append_jsonl(path, records) do
    File.write!(path, encode_jsonl(records), [:append])
  end

  defp encode_jsonl(records) do
    Enum.map_join(records, "\n", &Jason.encode!/1) <> "\n"
  end
end
