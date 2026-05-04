defmodule Hardline.Web.ManagerTest do
  use ExUnit.Case, async: false

  alias Hardline.Runner
  alias Hardline.Web.Manager

  setup do
    prefix = "babs-hardline-test-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      prefix
      |> Runner.list_sessions()
      |> Enum.each(&Runner.kill_session/1)
    end)

    {:ok, prefix: prefix}
  end

  test "validates browser-facing slugs" do
    assert Manager.valid_slug?("demo")
    assert Manager.valid_slug?("demo-a1")
    refute Manager.valid_slug?("Demo")
    refute Manager.valid_slug?("demo_a")
    refute Manager.valid_slug?("-demo")
    refute Manager.valid_slug?("../demo")
  end

  test "creates, lists, refreshes, and stops managed sessions", %{prefix: prefix} do
    start_supervised!({Manager, prefix: prefix, command: Runner.default_shell_command()})

    assert {:ok, a} = Manager.create_session("demo-a")
    assert {:ok, b} = Manager.create_session("demo-b")

    assert a.session == "#{prefix}-demo-a"
    assert b.session == "#{prefix}-demo-b"
    assert Runner.tmux_session_alive?(a.session)
    assert Runner.tmux_session_alive?(b.session)

    assert {:ok, sessions} = Manager.list_sessions()
    assert Enum.map(sessions, & &1.slug) == ["demo-a", "demo-b"]

    before = by_slug(sessions, "demo-a")

    assert {:ok, sessions} = Manager.list_sessions()
    after_refresh = by_slug(sessions, "demo-a")

    assert before.session_id == after_refresh.session_id
    assert before.pane_pid == after_refresh.pane_pid

    assert :ok = Manager.stop_session("demo-a")
    refute Runner.tmux_session_alive?(a.session)
    assert Runner.tmux_session_alive?(b.session)
  end

  test "creates browser sessions with tmux default shell when command is blank", %{prefix: prefix} do
    start_supervised!({Manager, prefix: prefix, command: Runner.default_shell_command()})

    assert {:ok, session} = Manager.create_session("tmux-default", "")
    assert session.command == ""
    assert Runner.tmux_session_alive?(session.session)
  end

  test "defaults browser manager sessions to tmux default shell", %{prefix: prefix} do
    start_supervised!({Manager, prefix: prefix})

    assert {:ok, session} = Manager.create_session("tmux-default")
    assert session.command == ""
    assert Runner.tmux_session_alive?(session.session)
  end

  test "reattaches existing prefixed tmux sessions on startup", %{prefix: prefix} do
    session = Runner.managed_session_name("existing", prefix)
    assert :ok = Runner.start_session(session, Runner.default_shell_command())

    start_supervised!({Manager, prefix: prefix, command: Runner.default_shell_command()})

    assert {:ok, sessions} = Manager.list_sessions()
    assert [%{slug: "existing", session: ^session, alive: true}] = sessions
  end

  test "does not list or kill unmanaged tmux sessions", %{prefix: prefix} do
    unmanaged = "operator-hardline-test-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      Runner.kill_session(unmanaged)
    end)

    assert :ok = Runner.start_session(unmanaged, Runner.default_shell_command())
    start_supervised!({Manager, prefix: prefix, command: Runner.default_shell_command()})

    assert {:ok, []} = Manager.list_sessions()
    assert {:error, :invalid_slug} = Manager.stop_session("../#{unmanaged}")
    assert Runner.tmux_session_alive?(unmanaged)
  end

  test "recreates a slug whose tmux session died out of band", %{prefix: prefix} do
    start_supervised!({Manager, prefix: prefix, command: Runner.default_shell_command()})

    assert {:ok, first} = Manager.create_session("stale")
    assert :ok = Runner.kill_session(first.session)
    refute Runner.tmux_session_alive?(first.session)

    assert {:ok, second} = Manager.create_session("stale")
    assert second.session == first.session
    assert Runner.tmux_session_alive?(second.session)
  end

  test "stop removes manager state when tmux already died", %{prefix: prefix} do
    start_supervised!({Manager, prefix: prefix, command: Runner.default_shell_command()})

    assert {:ok, session} = Manager.create_session("gone")
    assert :ok = Runner.kill_session(session.session)
    refute Runner.tmux_session_alive?(session.session)

    assert :ok = Manager.stop_session("gone")
    assert {:ok, []} = Manager.list_sessions()
  end

  test "reattaches a live tmux session when its pane server dies", %{prefix: prefix} do
    start_supervised!({Manager, prefix: prefix, command: Runner.default_shell_command()})

    assert {:ok, first} = Manager.create_session("pane-died")
    [{pid, _value}] = Registry.lookup(Hardline.Web.PaneRegistry, "pane-died")

    DynamicSupervisor.terminate_child(Hardline.Web.PaneSupervisor, pid)
    refute Process.alive?(pid)

    assert {:ok, [reattached]} = Manager.list_sessions()
    assert reattached.slug == "pane-died"
    assert reattached.session == first.session
    assert Runner.tmux_session_alive?(first.session)

    [{next_pid, _value}] = Registry.lookup(Hardline.Web.PaneRegistry, "pane-died")
    assert Process.alive?(next_pid)
    assert next_pid != pid
  end

  defp by_slug(sessions, slug) do
    Enum.find(sessions, &(&1.slug == slug))
  end
end
