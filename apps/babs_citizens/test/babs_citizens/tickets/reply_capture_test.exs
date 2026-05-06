defmodule Babs.Citizens.Tickets.ReplyCaptureTest do
  use ExUnit.Case, async: false

  alias Babs.Citizens.CitizenConfig
  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.History
  alias Babs.Citizens.Tickets.ReplyCapture

  setup do
    root = Path.join(System.tmp_dir!(), "reply-capture-#{System.unique_integer([:positive])}")
    File.rm_rf!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, ticket} =
      Api.create_ticket(%{title: "Capture", body: "Capture body"},
        tickets_root: root,
        now: "2026-05-06T00:00:00Z"
      )

    config = %CitizenConfig{
      id: "BAB-CIT-CLARE",
      slug: "clare",
      display_name: "Clare",
      cli: "claude",
      cli_args: [],
      cwd: root
    }

    %{root: root, ticket: ticket, config: config}
  end

  test "captures matched assistant reply as a durable comment", %{
    root: root,
    ticket: ticket,
    config: config
  } do
    transcript =
      transcript([
        %{
          "timestamp" => "2026-05-06T00:00:00Z",
          "role" => "user",
          "content" => "Babs Ticket #{ticket.id}"
        },
        %{
          "timestamp" => "2026-05-06T00:00:01Z",
          "role" => "assistant",
          "content" => "Captured reply"
        }
      ])

    assert {:captured, "Captured reply"} =
             ReplyCapture.capture_once(turn(root, ticket.id),
               citizen_config: config,
               paths: [transcript]
             )

    assert {:ok, history} = History.read(root, ticket.id)

    assert Enum.any?(
             history,
             &(&1["event"] == "comment" and &1["by"] == "clare" and &1["body"] == "Captured reply")
           )
  end

  test "does not duplicate an already captured reply", %{
    root: root,
    ticket: ticket,
    config: config
  } do
    transcript =
      transcript([
        %{"timestamp" => "2026-05-06T00:00:00Z", "role" => "user", "content" => ticket.id},
        %{"timestamp" => "2026-05-06T00:00:01Z", "role" => "assistant", "content" => "Same reply"}
      ])

    assert {:captured, "Same reply"} =
             ReplyCapture.capture_once(turn(root, ticket.id),
               citizen_config: config,
               paths: [transcript]
             )

    assert {:duplicate, "Same reply"} =
             ReplyCapture.capture_once(turn(root, ticket.id),
               citizen_config: config,
               paths: [transcript]
             )

    {:ok, history} = History.read(root, ticket.id)
    assert Enum.count(history, &(&1["event"] == "comment" and &1["body"] == "Same reply")) == 1
  end

  test "missing transcript files stay pending without a premature advisory", %{
    root: root,
    ticket: ticket,
    config: config
  } do
    assert :pending =
             ReplyCapture.capture_once(turn(root, ticket.id),
               citizen_config: config,
               paths: []
             )

    assert {:ok, history} = History.read(root, ticket.id)
    refute Enum.any?(history, &(&1["event"] == "ai_reply_capture_unavailable"))
    refute Enum.any?(history, &(&1["event"] == "comment"))
  end

  test "unsupported AI transcript providers record a non-comment advisory", %{
    root: root,
    ticket: ticket,
    config: config
  } do
    config = %{config | cli: "gh", cli_args: ["copilot"]}

    assert {:unavailable, :unsupported_copilot_transcripts} =
             ReplyCapture.capture_once(turn(root, ticket.id), citizen_config: config)

    assert {:ok, history} = History.read(root, ticket.id)

    assert Enum.any?(
             history,
             &(&1["event"] == "ai_reply_capture_unavailable" and
                 &1["reason"] == ":unsupported_copilot_transcripts")
           )

    refute Enum.any?(history, &(&1["event"] == "comment"))
  end

  test "ignores unexpected GenServer messages" do
    assert {:noreply, %{turns: %{}}} =
             ReplyCapture.handle_info(:unexpected, %{turns: %{}, interval_ms: 10})
  end

  test "capture can be disabled by option", %{root: root, ticket: ticket, config: config} do
    assert :disabled =
             ReplyCapture.capture_once(turn(root, ticket.id),
               citizen_config: config,
               enabled: false,
               paths: []
             )
  end

  defp turn(root, ticket_id) do
    %{root: root, ticket_id: ticket_id, slug: "clare", started_at: "2026-05-06T00:00:00Z"}
  end

  defp transcript(records) do
    path =
      Path.join(System.tmp_dir!(), "reply-transcript-#{System.unique_integer([:positive])}.jsonl")

    File.write!(path, Enum.map_join(records, "\n", &Jason.encode!/1) <> "\n")
    on_exit(fn -> File.rm(path) end)
    path
  end
end
