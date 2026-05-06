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
    assert comment_output =~ "live delivery is deferred until Phase 12"
  end

  test "mix babs.ticket.assign/transition/unassign bridge mutates a ticket", %{root: root} do
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

    transition_output =
      capture_io(fn ->
        Mix.Task.rerun("babs.ticket.transition", ["T-2026-05-06-001", "pending_approval"])
      end)

    assert transition_output =~ "T-2026-05-06-001 state pending_approval"

    rejected_output =
      capture_io(fn ->
        Mix.Task.rerun("babs.ticket.transition", [
          "T-2026-05-06-001",
          "in_progress",
          "rejected"
        ])
      end)

    assert rejected_output =~ "T-2026-05-06-001 state in_progress"

    unassign_output =
      capture_io(fn -> Mix.Task.rerun("babs.ticket.unassign", ["T-2026-05-06-001", "clare"]) end)

    assert unassign_output =~ "T-2026-05-06-001 unassigned from clare"
    assert unassign_output =~ "state open"
    assert File.read!(Path.join(root, "T-2026-05-06-001.md")) =~ "assignees: []"
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
end
