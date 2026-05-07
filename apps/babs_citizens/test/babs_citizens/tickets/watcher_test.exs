defmodule Babs.Citizens.Tickets.WatcherTest do
  use ExUnit.Case, async: false

  alias Babs.Citizens.Tickets.Watcher

  setup do
    root = tmp_root!()
    {:ok, _apps} = Application.ensure_all_started(:babs_citizens)
    Phoenix.PubSub.subscribe(Babs.Citizens.PubSub, Watcher.topic())

    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, root: root}
  end

  test "broadcasts debounced refresh when ticket markdown changes", %{root: root} do
    start_supervised!({Watcher, tickets_root: root, name: unique_name(), debounce_ms: 20})

    Process.sleep(80)
    path = Path.join(root, "T-2026-05-06-001.md")
    File.write!(path, "not frontmatter")

    assert_receive {:tickets_changed, %{root: ^root, paths: paths}}, 2_000
    assert path in paths
  end

  test "starts even when root is missing and begins watching after retry" do
    root = Path.join(tmp_root!(), "later")

    pid =
      start_supervised!(
        {Watcher, tickets_root: root, name: unique_name(), debounce_ms: 20, retry_ms: 20}
      )

    File.mkdir_p!(root)
    wait_until(fn -> :sys.get_state(pid).watcher != nil end)
    path = Path.join(root, "T-2026-05-06-002.history.jsonl")
    File.write!(path, "{}\n")

    watcher = :sys.get_state(pid).watcher
    send(pid, {:file_event, watcher, {path, [:created]}})

    paths = receive_ticket_change(root, path)
    assert path in paths
  end

  defp unique_name do
    :"watcher_#{System.unique_integer([:positive])}"
  end

  defp wait_until(fun) do
    deadline = System.monotonic_time(:millisecond) + 1_000
    wait_until(fun, deadline)
  end

  defp wait_until(fun, deadline) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("condition was not met before deadline")

      true ->
        Process.sleep(20)
        wait_until(fun, deadline)
    end
  end

  defp receive_ticket_change(root, path) do
    receive_ticket_change(root, path, System.monotonic_time(:millisecond) + 5_000)
  end

  defp receive_ticket_change(root, path, deadline) do
    receive do
      {:tickets_changed, %{root: ^root, paths: paths}} ->
        paths
    after
      40 ->
        if System.monotonic_time(:millisecond) <= deadline do
          File.touch!(path)
          receive_ticket_change(root, path, deadline)
        else
          flunk("ticket change was not received before deadline")
        end
    end
  end

  defp tmp_root! do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-ticket-watcher-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end
end
