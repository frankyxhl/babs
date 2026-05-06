defmodule Babs.Citizens.Tickets.HistoryTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.History

  @id "T-2026-05-06-001"

  test "appends and reads JSONL history events" do
    root = tmp_root()

    assert :ok =
             History.append(root, @id, %{
               "ts" => "2026-05-06T00:00:00Z",
               "event" => "created",
               "by" => "user"
             })

    assert :ok =
             History.append(root, @id, %{
               "ts" => "2026-05-06T00:01:00Z",
               "event" => "comment",
               "by" => "clare",
               "body" => "Done"
             })

    assert {:ok, events} = History.read(root, @id)
    assert Enum.map(events, & &1["event"]) == ["created", "comment"]
  end

  test "requires ts event and by fields" do
    assert {:error, {:invalid_history_event, {:missing_keys, ["by"]}}} =
             History.append(tmp_root(), @id, %{
               "ts" => "2026-05-06T00:00:00Z",
               "event" => "created"
             })
  end

  test "rejects malformed JSONL rows on read" do
    root = tmp_root()
    File.write!(Path.join(root, "#{@id}.history.jsonl"), "{not-json}\n")

    assert {:error, {:invalid_history, {@id, 1, :malformed_json}}} = History.read(root, @id)
  end

  test "rejects oversized history events before append" do
    assert {:error, {:history_event_too_large, @id}} =
             History.append(tmp_root(), @id, %{
               "ts" => "2026-05-06T00:00:00Z",
               "event" => "comment",
               "by" => "clare",
               "body" => String.duplicate("x", 20_000)
             })
  end

  defp tmp_root do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-ticket-history-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end
end
