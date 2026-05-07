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

  test "finds marked assistant reply in real Codex response_item payload records" do
    path = transcript_path()

    write_jsonl(path, [
      %{
        "timestamp" => @since,
        "type" => "response_item",
        "payload" => %{
          "type" => "message",
          "role" => "user",
          "content" => [
            %{
              "type" => "input_text",
              "text" =>
                "Babs Ticket #{@ticket_id}: say hello\nBABS_REPLY #{@ticket_id}: your response"
            }
          ]
        }
      },
      %{
        "timestamp" => "2026-05-06T00:00:01Z",
        "type" => "response_item",
        "payload" => %{
          "type" => "message",
          "role" => "assistant",
          "content" => [%{"type" => "output_text", "text" => "I'll check this."}]
        }
      },
      %{
        "timestamp" => "2026-05-06T00:00:02Z",
        "type" => "response_item",
        "payload" => %{
          "type" => "message",
          "role" => "assistant",
          "content" => [
            %{"type" => "output_text", "text" => "BABS_REPLY #{@ticket_id}: hello from Dylan"}
          ]
        }
      }
    ])

    assert {:ok, %{text: "BABS_REPLY #{@ticket_id}: hello from Dylan"}} =
             AiTranscripts.find_reply_in_file(path, @ticket_id, @since)
  end

  test "waits for a marked reply when the prompt requested the reply marker" do
    path = transcript_path()

    write_jsonl(path, [
      %{
        "timestamp" => @since,
        "role" => "user",
        "content" => "Babs Ticket #{@ticket_id}\nBABS_REPLY #{@ticket_id}: your response"
      },
      %{
        "timestamp" => "2026-05-06T00:00:02Z",
        "role" => "assistant",
        "content" => "I'll work on this before giving the final answer."
      }
    ])

    assert :pending = AiTranscripts.find_reply_in_file(path, @ticket_id, @since)
  end

  test "finds marked assistant reply in Copilot CLI session events" do
    copilot_home =
      Path.join(System.tmp_dir!(), "copilot-home-#{System.unique_integer([:positive])}")

    events_path = Path.join([copilot_home, "session-state", "session-1", "events.jsonl"])
    File.mkdir_p!(Path.dirname(events_path))
    on_exit(fn -> File.rm_rf(copilot_home) end)

    write_jsonl(events_path, [
      %{
        "timestamp" => @since,
        "type" => "user.message",
        "data" => %{
          "content" =>
            "Babs Ticket #{@ticket_id}: say hello\nBABS_REPLY #{@ticket_id}: your response"
        }
      },
      %{
        "timestamp" => "2026-05-06T00:00:03Z",
        "type" => "assistant.message",
        "data" => %{"content" => "BABS_REPLY #{@ticket_id}: hello from Elena"}
      }
    ])

    config = %{
      cli: "gh",
      cli_args: ["copilot"],
      cwd: System.tmp_dir!(),
      env: %{"COPILOT_HOME" => copilot_home}
    }

    assert {:ok, %{text: "BABS_REPLY #{@ticket_id}: hello from Elena", path: ^events_path}} =
             AiTranscripts.find_reply(config, @ticket_id, @since)
  end

  test "finds marked assistant reply in direct Copilot CLI session events" do
    copilot_home =
      Path.join(System.tmp_dir!(), "direct-copilot-home-#{System.unique_integer([:positive])}")

    events_path = Path.join([copilot_home, "session-state", "session-1", "events.jsonl"])
    File.mkdir_p!(Path.dirname(events_path))
    on_exit(fn -> File.rm_rf(copilot_home) end)

    write_jsonl(events_path, [
      %{
        "timestamp" => @since,
        "type" => "user.message",
        "data" => %{
          "content" =>
            "Babs Ticket #{@ticket_id}: say hello\nBABS_REPLY #{@ticket_id}: your response"
        }
      },
      %{
        "timestamp" => "2026-05-06T00:00:03Z",
        "type" => "assistant.message",
        "data" => %{"content" => "BABS_REPLY #{@ticket_id}: hello from direct Elena"}
      }
    ])

    config = %{
      cli: "copilot",
      cli_args: [],
      cwd: System.tmp_dir!(),
      env: %{"COPILOT_HOME" => copilot_home}
    }

    assert {:ok, %{text: "BABS_REPLY #{@ticket_id}: hello from direct Elena", path: ^events_path}} =
             AiTranscripts.find_reply(config, @ticket_id, @since)
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
