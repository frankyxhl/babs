defmodule Babs.Knowledge.WatcherTest do
  use ExUnit.Case, async: false

  alias Babs.Knowledge.Watcher

  setup do
    root = tmp_root!()
    {:ok, _apps} = Application.ensure_all_started(:babs_citizens)
    Phoenix.PubSub.subscribe(Babs.Citizens.PubSub, Watcher.topic())

    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, root: root}
  end

  test "uses the knowledge PubSub topic" do
    assert Watcher.topic() == "knowledge"
  end

  test "disabled watcher does not start FileSystem watcher or broadcast", %{root: root} do
    pid =
      start_supervised!({Watcher, knowledge_root: root, name: unique_name(), enabled?: false})

    assert :sys.get_state(pid).watcher == nil

    path = Path.join([root, "clare", "Readme.md"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "# Clare\n")

    refute_receive {:knowledge_changed, "clare", "Readme.md"}, 100
  end

  test "broadcasts debounced change when knowledge markdown changes", %{root: root} do
    File.mkdir_p!(Path.join(root, "clare"))
    pid = start_supervised!({Watcher, knowledge_root: root, name: unique_name(), debounce_ms: 20})
    wait_for_watcher(pid)

    path = Path.join([root, "clare", "Readme.md"])
    File.write!(path, "# Clare\n")

    receive_knowledge_change("clare", "Readme.md", path)
  end

  test "debounces duplicate manual events for the same knowledge file", %{root: root} do
    pid = start_supervised!({Watcher, knowledge_root: root, name: unique_name(), debounce_ms: 20})
    path = Path.join([root, "clare", "Readme.md"])
    File.mkdir_p!(Path.dirname(path))

    watcher = wait_for_watcher(pid)
    send(pid, {:file_event, watcher, {path, [:modified]}})
    send(pid, {:file_event, watcher, {path, [:modified]}})

    assert_receive {:knowledge_changed, "clare", "Readme.md"}, 1_000
    refute_receive {:knowledge_changed, "clare", "Readme.md"}, 80
  end

  test "broadcasts one event per changed tuple in a debounce window", %{root: root} do
    pid = start_supervised!({Watcher, knowledge_root: root, name: unique_name(), debounce_ms: 20})
    clare_path = Path.join([root, "clare", "Readme.md"])
    dylan_path = Path.join([root, "dylan", "notes", "plan.md"])
    File.mkdir_p!(Path.dirname(clare_path))
    File.mkdir_p!(Path.dirname(dylan_path))

    watcher = wait_for_watcher(pid)
    send(pid, {:file_event, watcher, {dylan_path, [:modified]}})
    send(pid, {:file_event, watcher, {clare_path, [:modified]}})

    assert_receive {:knowledge_changed, "clare", "Readme.md"}, 1_000
    assert_receive {:knowledge_changed, "dylan", "notes/plan.md"}, 1_000
  end

  test "starts when root is missing and begins watching after retry" do
    parent = tmp_root!()
    on_exit(fn -> File.rm_rf!(parent) end)
    root = Path.join(parent, "later")

    pid =
      start_supervised!(
        {Watcher, knowledge_root: root, name: unique_name(), debounce_ms: 20, retry_ms: 20}
      )

    File.mkdir_p!(Path.join(root, "elena"))
    wait_for_watcher(pid)

    path = Path.join([root, "elena", "Readme.md"])
    File.write!(path, "# Elena\n")

    watcher = :sys.get_state(pid).watcher
    send(pid, {:file_event, watcher, {path, [:created]}})

    assert_receive {:knowledge_changed, "elena", "Readme.md"}, 1_000
  end

  test "schedules retry after FileSystem stop event", %{root: root} do
    pid =
      start_supervised!(
        {Watcher, knowledge_root: root, name: unique_name(), debounce_ms: 20, retry_ms: 1_000}
      )

    watcher = wait_for_watcher(pid)
    send(pid, {:file_event, watcher, :stop})

    wait_until(fn ->
      state = :sys.get_state(pid)

      if state.watcher == nil and state.retry_ref != nil do
        true
      else
        false
      end
    end)
  end

  test "ignores root directory slug directory outside root and artifact paths", %{root: root} do
    pid = start_supervised!({Watcher, knowledge_root: root, name: unique_name(), debounce_ms: 20})
    File.mkdir_p!(Path.join(root, "clare"))
    outside_root = tmp_root!()
    on_exit(fn -> File.rm_rf!(outside_root) end)

    watcher = wait_for_watcher(pid)

    ignored_paths = [
      root,
      Path.join(root, "clare"),
      Path.join([outside_root, "clare", "Readme.md"]),
      Path.join([root, "INVALID-SLUG", "Readme.md"]),
      Path.join([root, "clare", "notes.txt"]),
      Path.join([root, "clare", ".hidden.md"]),
      Path.join([root, "clare", ".drafts", "plan.md"]),
      Path.join([root, "clare", "#plan.md#"]),
      Path.join([root, "clare", ".Readme.md.1.babs.md.tmp"])
    ]

    Enum.each(ignored_paths, fn path ->
      File.mkdir_p!(Path.dirname(path))
      send(pid, {:file_event, watcher, {path, [:modified]}})
    end)

    refute_receive {:knowledge_changed, _slug, _name}, 100
  end

  test "accepts all configured FileSystem event types", %{root: root} do
    pid = start_supervised!({Watcher, knowledge_root: root, name: unique_name(), debounce_ms: 20})
    watcher = wait_for_watcher(pid)

    events = [
      {:created, "Readme.md"},
      {:modified, "notes/modified.md"},
      {:renamed, "notes/renamed.md"},
      {:deleted, "notes/deleted.md"},
      {:removed, "notes/removed.md"},
      {:moved_to, "notes/moved-to.md"},
      {:moved_from, "notes/moved-from.md"}
    ]

    Enum.each(events, fn {event, name} ->
      path = Path.join([root, "clare", name])
      File.mkdir_p!(Path.dirname(path))
      send(pid, {:file_event, watcher, {path, [event]}})
    end)

    Enum.each(events, fn {_event, name} ->
      assert_receive {:knowledge_changed, "clare", ^name}, 1_000
    end)
  end

  test "broadcasts Linux inotify atomic-save moved_to events", %{root: root} do
    pid = start_supervised!({Watcher, knowledge_root: root, name: unique_name(), debounce_ms: 20})
    watcher = wait_for_watcher(pid)

    path = Path.join([root, "clare", "Readme.md"])
    File.mkdir_p!(Path.dirname(path))
    send(pid, {:file_event, watcher, {path, [:moved_to]}})

    assert_receive {:knowledge_changed, "clare", "Readme.md"}, 1_000
  end

  test "normalizes macOS private tmp aliases before checking root containment" do
    root = Path.join("/tmp", "babs-knowledge-watcher-#{System.unique_integer([:positive])}")
    File.rm_rf!(root)
    File.mkdir_p!(Path.join(root, "clare"))
    on_exit(fn -> File.rm_rf!(root) end)

    pid = start_supervised!({Watcher, knowledge_root: root, name: unique_name(), debounce_ms: 20})
    watcher = wait_for_watcher(pid)

    path =
      [root, "clare", "Readme.md"]
      |> Path.join()
      |> String.replace_prefix("/tmp/", "/private/tmp/")

    send(pid, {:file_event, watcher, {path, [:modified]}})

    assert_receive {:knowledge_changed, "clare", "Readme.md"}, 1_000
  end

  defp unique_name do
    :"knowledge_watcher_#{System.unique_integer([:positive])}"
  end

  defp wait_for_watcher(pid) do
    wait_until(fn ->
      case :sys.get_state(pid).watcher do
        nil -> false
        watcher -> watcher
      end
    end)
  end

  defp wait_until(fun) do
    deadline = System.monotonic_time(:millisecond) + 1_000
    wait_until(fun, deadline)
  end

  defp wait_until(fun, deadline) do
    case fun.() do
      false ->
        if System.monotonic_time(:millisecond) > deadline do
          flunk("condition was not met before deadline")
        else
          Process.sleep(20)
          wait_until(fun, deadline)
        end

      value ->
        value
    end
  end

  defp receive_knowledge_change(slug, name, path) do
    receive_knowledge_change(slug, name, path, System.monotonic_time(:millisecond) + 5_000)
  end

  defp receive_knowledge_change(slug, name, path, deadline) do
    receive do
      {:knowledge_changed, ^slug, ^name} ->
        :ok
    after
      40 ->
        if System.monotonic_time(:millisecond) <= deadline do
          File.write!(path, "# Clare #{System.unique_integer([:positive])}\n")
          receive_knowledge_change(slug, name, path, deadline)
        else
          flunk("knowledge change was not received before deadline")
        end
    end
  end

  defp tmp_root! do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-knowledge-watcher-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end
end
