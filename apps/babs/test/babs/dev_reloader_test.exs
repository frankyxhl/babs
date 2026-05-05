defmodule Babs.DevReloaderTest do
  use ExUnit.Case, async: false

  alias Babs.DevReloader

  @repo_root Path.expand("../../../../", __DIR__)

  test "matches Elixir source changes under the watched citizens path" do
    watch_path = "/repo/apps/babs_citizens/lib"

    assert DevReloader.watched_elixir_file?(
             "/repo/apps/babs_citizens/lib/babs_citizens/hardline/pane.ex",
             [:modified],
             watch_path
           )

    refute DevReloader.watched_elixir_file?(
             "/repo/apps/babs/lib/babs_web/router.ex",
             [:modified],
             watch_path
           )

    refute DevReloader.watched_elixir_file?(
             "/repo/apps/babs_citizens/lib/babs_citizens/readme.md",
             [:modified],
             watch_path
           )
  end

  test "initializes as disabled when dev reloader config is off" do
    previous = Application.get_env(:babs, DevReloader)

    try do
      Application.put_env(:babs, DevReloader,
        enabled: false,
        root: "/repo",
        watch_path: "apps/babs_citizens/lib",
        debounce_ms: 123
      )

      assert {:ok, state} = DevReloader.init([])
      refute state.enabled?
      assert state.root == "/repo"
      assert state.watch_path == "/repo/apps/babs_citizens/lib"
      assert state.debounce_ms == 123
    after
      Application.put_env(:babs, DevReloader, previous)
    end
  end

  test "debounces matching file events and ignores unrelated watcher events" do
    watcher = make_ref()
    path = "/repo/apps/babs_citizens/lib/babs_citizens/hardline/pane.ex"

    state = %{
      watch_path: "/repo/apps/babs_citizens/lib",
      debounce_ms: 10_000,
      watcher: watcher,
      debounce_ref: nil
    }

    assert {:noreply, state} =
             DevReloader.handle_info({:file_event, watcher, {path, [:modified]}}, state)

    assert is_reference(state.debounce_ref)
    Process.cancel_timer(state.debounce_ref)

    assert {:noreply, ^state} =
             DevReloader.handle_info({:file_event, make_ref(), {path, [:modified]}}, state)

    assert {:noreply, stopped} = DevReloader.handle_info({:file_event, watcher, :stop}, state)
    assert stopped.watcher == nil
  end

  test "reload_after_debounce compiles and restarts the citizens app" do
    state = %{
      root: @repo_root,
      debounce_ref: make_ref()
    }

    assert {:noreply, next_state} = DevReloader.handle_info(:reload_after_debounce, state)
    assert next_state.debounce_ref == nil
  end
end
