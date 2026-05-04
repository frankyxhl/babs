defmodule Hardline.RunnerIntegrationTest do
  use ExUnit.Case, async: false

  @tag :integration
  test "attaches to a detached tmux session through erlexec PTY" do
    session = "babs-test-#{System.unique_integer([:positive])}"
    sentinel = "BABS_SENTINEL_#{System.unique_integer([:positive])}"

    on_exit(fn ->
      System.cmd("tmux", ["kill-session", "-t", session], stderr_to_stdout: true)
    end)

    assert :ok = Hardline.Runner.start_session(session, Hardline.Runner.default_shell_command())
    assert {:ok, attach} = Hardline.Runner.attach(session)

    assert :ok = Hardline.Runner.inject(attach, "printf '#{sentinel}\\n'\n")
    assert {:ok, output} = Hardline.Runner.collect_until(attach, sentinel, 3_000)

    assert output =~ sentinel
    assert Hardline.Runner.tmux_session_alive?(session)

    assert :ok = Hardline.Runner.resize(attach, 40, 120)

    assert :ok = Hardline.Runner.detach(attach)
    assert Hardline.Runner.tmux_session_alive?(session)
  end

  @tag :integration
  test "starts a short fleet and cleans it up" do
    prefix = "babs-test-short-#{System.unique_integer([:positive])}"
    command = Hardline.Runner.default_shell_command()

    on_exit(fn ->
      Hardline.Runner.stop_fleet(Hardline.Runner.fleet_specs(3, prefix: prefix, command: command))
    end)

    assert {:ok, fleet} = Hardline.Runner.start_fleet(3, prefix: prefix, command: command)
    assert Enum.all?(fleet, fn spec -> Hardline.Runner.tmux_session_alive?(spec.session) end)

    assert {:ok, attachments} = Hardline.Runner.attach_fleet(fleet)

    for attach <- attachments do
      sentinel = "BABS_FLEET_#{attach.session}"
      assert :ok = Hardline.Runner.inject(attach, "printf '#{sentinel}\\n'\n")
      assert {:ok, output} = Hardline.Runner.collect_until(attach, sentinel, 3_000)
      assert output =~ sentinel
    end

    assert :ok = Hardline.Runner.detach_fleet(attachments)
    assert Enum.all?(fleet, fn spec -> Hardline.Runner.tmux_session_alive?(spec.session) end)

    assert :ok = Hardline.Runner.stop_fleet(fleet)
    refute Enum.any?(fleet, fn spec -> Hardline.Runner.tmux_session_alive?(spec.session) end)
  end
end
