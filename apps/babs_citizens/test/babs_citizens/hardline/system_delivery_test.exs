defmodule Babs.Citizens.Hardline.SystemDeliveryTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.CitizenConfig
  alias Babs.Citizens.Hardline.SystemDelivery

  defp ai_config do
    %CitizenConfig{
      id: "BAB-CIT-AI",
      slug: "clare",
      display_name: "Clare",
      cli: "claude",
      cli_args: [],
      cwd: System.tmp_dir!()
    }
  end

  defp shell_config do
    %CitizenConfig{
      id: "BAB-CIT-SHELL",
      slug: "sentinel",
      display_name: "Sentinel",
      cli: "/bin/zsh",
      cli_args: ["-f"],
      cwd: System.tmp_dir!()
    }
  end

  test "shell system delivery uses direct inject without adding Enter" do
    parent = self()

    ops = %{
      inject: fn %{os_pid: 1}, data ->
        send(parent, {:inject, data})
        :ok
      end
    }

    assert {:ok, "echo hi"} =
             SystemDelivery.deliver(shell_config(), %{os_pid: 1}, "echo hi", ops: ops)

    assert_receive {:inject, "echo hi"}
  end

  test "AI system delivery pastes, waits for receipt, sends Enter, and records submitted input" do
    parent = self()
    attach = %{session: "babs-clare"}
    prompt = "[Babs Ticket T-2026-05-06-001 assigned]\nBody"

    ops = %{
      paste_text: fn ^attach, data ->
        send(parent, {:paste, data})
        :ok
      end,
      capture_pane: fn ^attach -> {:ok, "screen\n#{prompt}\n"} end,
      send_enter: fn ^attach ->
        send(parent, :enter)
        :ok
      end,
      sleep: fn _ms -> :ok end
    }

    submitted = prompt <> "\r"
    assert {:ok, ^submitted} = SystemDelivery.deliver(ai_config(), attach, prompt, ops: ops)

    assert_receive {:paste, ^prompt}
    assert_receive :enter
  end

  test "AI system delivery retries Enter while pasted block remains editable" do
    parent = self()
    attach = %{session: "babs-clare"}
    prompt = "[Babs Ticket T-2026-05-06-002 assigned]\nBody"
    capture_calls = :atomics.new(1, [])

    ops = %{
      paste_text: fn ^attach, _data -> :ok end,
      capture_pane: fn ^attach ->
        case :atomics.add_get(capture_calls, 1, 1) do
          1 -> {:ok, prompt}
          2 -> {:ok, "[Pasted text - press ctrl+g to edit]"}
          _ -> {:ok, "submitted"}
        end
      end,
      send_enter: fn ^attach ->
        send(parent, :enter)
        :ok
      end,
      sleep: fn _ms -> :ok end
    }

    submitted = prompt <> "\r"

    assert {:ok, ^submitted} =
             SystemDelivery.deliver(ai_config(), attach, prompt, ops: ops, enter_retries: 2)

    assert_receive :enter
    assert_receive :enter
  end

  test "AI system delivery fails when receipt marker is never observed" do
    attach = %{session: "babs-clare"}
    prompt = "[Babs Ticket T-2026-05-06-003 assigned]\nBody"

    ops = %{
      paste_text: fn ^attach, _data -> :ok end,
      capture_pane: fn ^attach -> {:ok, "unrelated screen"} end,
      send_enter: fn ^attach -> :ok end,
      sleep: fn _ms -> :ok end
    }

    assert {:error, {:receipt_not_observed, "Babs Ticket T-2026-05-06-003"}, ^prompt} =
             SystemDelivery.deliver(ai_config(), attach, prompt,
               ops: ops,
               receipt_attempts: 2,
               receipt_interval_ms: 0
             )
  end
end
