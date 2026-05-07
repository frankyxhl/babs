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

  test "captures marked transcript reply without storing the marker", %{
    root: root,
    ticket: ticket,
    config: config
  } do
    transcript =
      transcript([
        %{"timestamp" => "2026-05-06T00:00:00Z", "role" => "user", "content" => ticket.id},
        %{
          "timestamp" => "2026-05-06T00:00:01Z",
          "role" => "assistant",
          "content" => "BABS_REPLY #{ticket.id}: hello from transcript"
        }
      ])

    assert {:captured, "hello from transcript"} =
             ReplyCapture.capture_once(turn(root, ticket.id),
               citizen_config: config,
               paths: [transcript]
             )

    assert {:ok, history} = History.read(root, ticket.id)

    assert Enum.any?(
             history,
             &(&1["event"] == "comment" and &1["by"] == "clare" and
                 &1["body"] == "hello from transcript")
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

  test "missing Copilot transcript files stay pending without an advisory", %{
    root: root,
    ticket: ticket,
    config: config
  } do
    config = %{config | cli: "gh", cli_args: ["copilot"]}

    assert :pending =
             ReplyCapture.capture_once(turn(root, ticket.id), citizen_config: config, paths: [])

    assert {:ok, history} = History.read(root, ticket.id)

    refute Enum.any?(history, &(&1["event"] == "ai_reply_capture_unavailable"))
    refute Enum.any?(history, &(&1["event"] == "comment"))
  end

  test "captures direct Copilot transcript reply as Elena comment", %{
    root: root,
    ticket: ticket,
    config: config
  } do
    transcript =
      transcript([
        %{
          "timestamp" => "2026-05-06T00:00:00Z",
          "type" => "user.message",
          "data" => %{
            "content" => "Babs Ticket #{ticket.id}\nBABS_REPLY #{ticket.id}: your response"
          }
        },
        %{
          "timestamp" => "2026-05-06T00:00:01Z",
          "type" => "assistant.message",
          "data" => %{"content" => "BABS_REPLY #{ticket.id}: hello from Elena"}
        }
      ])

    config = %{
      config
      | slug: "elena",
        display_name: "Elena",
        cli: "copilot",
        cli_args: []
    }

    assert {:captured, "hello from Elena"} =
             ReplyCapture.capture_once(%{turn(root, ticket.id) | slug: "elena"},
               citizen_config: config,
               paths: [transcript]
             )

    assert {:ok, history} = History.read(root, ticket.id)

    assert Enum.any?(
             history,
             &(&1["event"] == "comment" and &1["by"] == "elena" and
                 &1["body"] == "hello from Elena")
           )
  end

  test "ignores unexpected GenServer messages" do
    assert {:noreply, %{turns: %{}}} =
             ReplyCapture.handle_info(:unexpected, %{turns: %{}, interval_ms: 10})
  end

  test "tracks same-second attempts separately by turn and attempt id", %{
    root: root,
    ticket: ticket
  } do
    first =
      turn(root, ticket.id)
      |> Map.put(:turn_id, "turn_20260506000000_first")
      |> Map.put(:attempt_id, "attempt_20260506000000_first")

    second =
      turn(root, ticket.id)
      |> Map.put(:turn_id, "turn_20260506000000_second")
      |> Map.put(:attempt_id, "attempt_20260506000000_second")

    assert {:noreply, state} =
             ReplyCapture.handle_cast({:track, first}, %{turns: %{}, interval_ms: 10})

    assert {:noreply, state} = ReplyCapture.handle_cast({:track, second}, state)

    assert map_size(state.turns) == 2

    assert Enum.sort(Enum.map(state.turns, fn {_key, turn} -> turn.turn_id end)) == [
             first.turn_id,
             second.turn_id
           ]

    assert Enum.sort(Enum.map(state.turns, fn {_key, turn} -> turn.attempt_id end)) == [
             first.attempt_id,
             second.attempt_id
           ]
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
