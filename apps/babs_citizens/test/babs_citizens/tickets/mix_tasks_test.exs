defmodule Babs.Citizens.Tickets.MixTasksTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  setup do
    old_tickets_root = Application.get_env(:babs_citizens, :tickets_root)
    old_ticket_runtime_opts = Application.get_env(:babs_citizens, :ticket_runtime_opts)
    root = tmp_root()
    Application.put_env(:babs_citizens, :tickets_root, root)

    on_exit(fn ->
      restore_env(:tickets_root, old_tickets_root)
      restore_env(:ticket_runtime_opts, old_ticket_runtime_opts)
      Mix.Task.clear()
    end)

    {:ok, root: root}
  end

  test "mix babs.ticket.new/list/show bridge creates and reads a ticket", %{root: root} do
    output =
      capture_io(fn ->
        Mix.Task.rerun("babs.ticket.new", [
          "--title",
          "CLI bridge",
          "--body",
          "Create through the temporary Mix bridge.",
          "--date",
          "2026-05-06",
          "--now",
          "2026-05-06T00:00:00Z"
        ])
      end)

    assert output =~ "T-2026-05-06-001"
    assert File.exists?(Path.join(root, "T-2026-05-06-001.md"))

    list_output = capture_io(fn -> Mix.Task.rerun("babs.ticket.list", []) end)
    assert list_output =~ "T-2026-05-06-001"
    assert list_output =~ "CLI bridge"

    show_output = capture_io(fn -> Mix.Task.rerun("babs.ticket.show", ["T-2026-05-06-001"]) end)
    assert show_output =~ "# CLI bridge"
    assert show_output =~ "Create through the temporary Mix bridge."

    comment_output =
      capture_io(fn ->
        Mix.Task.rerun("babs.ticket.comment", ["T-2026-05-06-001", "Stored through CLI"])
      end)

    assert comment_output =~ "T-2026-05-06-001 comment stored"
    assert comment_output =~ "no assignees to notify"

    option_like_comment_output =
      capture_io(fn ->
        Mix.Task.rerun("babs.ticket.comment", ["T-2026-05-06-001", "--by"])
      end)

    assert option_like_comment_output =~ "T-2026-05-06-001 comment stored"
    assert option_like_comment_output =~ "no assignees to notify"

    comment_events = comment_events(root, "T-2026-05-06-001")
    assert List.last(comment_events)["body"] == "--by"
    assert List.last(comment_events)["by"] == "user"

    leading_by_output =
      capture_io(fn ->
        Mix.Task.rerun("babs.ticket.comment", [
          "--by",
          "clare",
          "T-2026-05-06-001",
          "Leading author option."
        ])
      end)

    assert leading_by_output =~ "T-2026-05-06-001 comment stored"

    comment_events = comment_events(root, "T-2026-05-06-001")
    assert List.last(comment_events)["body"] == "Leading author option."
    assert List.last(comment_events)["by"] == "clare"
  end

  test "mix babs.ticket.assign/transition/reject/approve/unassign bridge mutates tickets", %{
    root: root
  } do
    parent = self()

    Application.put_env(:babs_citizens, :ticket_runtime_opts,
      citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
      pane_lookup: fn "clare" -> {:ok, self()} end,
      pane_injector: fn "clare", prompt ->
        send(parent, {:injected, prompt})
        :ok
      end
    )

    capture_io(fn ->
      Mix.Task.rerun("babs.ticket.new", [
        "--title",
        "CLI assign",
        "--body",
        "Assign through the temporary Mix bridge.",
        "--date",
        "2026-05-06",
        "--now",
        "2026-05-06T00:00:00Z"
      ])
    end)

    assign_output =
      capture_io(fn -> Mix.Task.rerun("babs.ticket.assign", ["T-2026-05-06-001", "clare"]) end)

    assert assign_output =~ "T-2026-05-06-001 assigned to clare"
    assert assign_output =~ "prompt injected"
    assert_receive {:injected, prompt}
    assert prompt =~ "Assign through the temporary Mix bridge."

    comment_output =
      capture_io(fn ->
        Mix.Task.rerun("babs.ticket.comment", [
          "T-2026-05-06-001",
          "CLI comment to Clare.",
          "--by",
          "clare"
        ])
      end)

    assert comment_output =~ "T-2026-05-06-001 comment stored"
    assert comment_output =~ "notified clare"
    assert_receive {:injected, comment_prompt}
    assert comment_prompt =~ "CLI comment to Clare."
    assert comment_prompt =~ "From: clare"

    transition_output =
      capture_io(fn ->
        Mix.Task.rerun("babs.ticket.transition", ["T-2026-05-06-001", "pending_approval"])
      end)

    assert transition_output =~ "T-2026-05-06-001 state pending_approval"

    rejected_output =
      capture_io(fn ->
        Mix.Task.rerun("babs.ticket.reject", ["T-2026-05-06-001", "Needs more detail."])
      end)

    assert rejected_output =~ "T-2026-05-06-001 rejected"
    assert rejected_output =~ "state in_progress"
    assert_receive {:injected, feedback_prompt}
    assert feedback_prompt =~ "Needs more detail."

    unassign_output =
      capture_io(fn -> Mix.Task.rerun("babs.ticket.unassign", ["T-2026-05-06-001", "clare"]) end)

    assert unassign_output =~ "T-2026-05-06-001 unassigned from clare"
    assert unassign_output =~ "state open"
    assert File.read!(Path.join(root, "T-2026-05-06-001.md")) =~ "assignees: []"

    capture_io(fn ->
      Mix.Task.rerun("babs.ticket.assign", ["T-2026-05-06-001", "clare"])
    end)

    capture_io(fn ->
      Mix.Task.rerun("babs.ticket.transition", ["T-2026-05-06-001", "pending_approval"])
    end)

    approve_output =
      capture_io(fn -> Mix.Task.rerun("babs.ticket.approve", ["T-2026-05-06-001"]) end)

    assert approve_output =~ "T-2026-05-06-001 approved"
    assert approve_output =~ "state closed"
  end

  defp tmp_root do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-ticket-mix-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end

  defp restore_env(key, nil), do: Application.delete_env(:babs_citizens, key)
  defp restore_env(key, value), do: Application.put_env(:babs_citizens, key, value)

  defp history_events(root, id) do
    root
    |> Path.join("#{id}.history.jsonl")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
  end

  defp comment_events(root, id) do
    root
    |> history_events(id)
    |> Enum.filter(&(&1["event"] == "comment"))
  end
end
