defmodule Babs.Citizens.LifecycleStatusTest do
  use Babs.Citizens.RepoCase, async: false

  alias Babs.Citizens.{Catalog, ImportedHardline, Lifecycle, Repo, Runner}
  alias Babs.Citizens.Hardline.Pane

  test "start_registered_citizen loads SQLite config, starts, and marks running" do
    record =
      insert_citizen!(%{
        slug: "registered-start-#{System.unique_integer([:positive])}",
        status: "failed",
        last_error: "previous failure"
      })

    on_exit(fn -> Lifecycle.stop_citizen(record.slug) end)

    assert {:ok, pid} = Lifecycle.start_registered_citizen(record.slug)
    assert is_pid(pid)
    assert {:ok, ^pid} = Lifecycle.lookup(record.slug)

    running = Repo.get!(CitizenRecord, record.id)
    assert running.status == "running"
    assert running.last_error == nil
    assert running.cwd == record.cwd
    assert running.cli == record.cli
    assert running.cli_args == record.cli_args
    assert running.env == record.env
  end

  test "start_registered_citizen returns not_found for missing SQLite rows" do
    assert {:error, :not_found} = Lifecycle.start_registered_citizen("missing-registered")
  end

  test "start_registered_citizen marks failures with redacted last_error" do
    record =
      insert_citizen!(%{
        slug: "registered-start-failure",
        env: %{"SECRET_TOKEN" => "do-not-log"},
        status: "stopped"
      })

    with_tmux_binary("/definitely/missing/babs-tmux", fn ->
      assert {:error, {:tmux_executable_not_found, _path}} =
               Lifecycle.start_registered_citizen(record.slug)
    end)

    failed = Repo.get!(CitizenRecord, record.id)
    assert failed.status == "failed"
    assert failed.last_error =~ "tmux_executable_not_found"
    refute failed.last_error =~ "do-not-log"
  end

  test "restart_registered_citizen is stop plus start using the same SQLite row" do
    record =
      insert_citizen!(%{
        slug: "registered-restart-#{System.unique_integer([:positive])}",
        status: "running"
      })

    session = Runner.session_name(record.slug)
    on_exit(fn -> Lifecycle.stop_citizen(record.slug) end)

    assert {:ok, first_pid} = Lifecycle.start_registered_citizen(record.slug)
    assert {:ok, ^first_pid} = Lifecycle.lookup(record.slug)

    before_marker = "BABS_RESTART_BEFORE_#{System.unique_integer([:positive])}"
    Pane.inject(record.slug, "printf '#{before_marker}\\n'\n")
    wait_for_capture!(session, before_marker)

    assert {:ok, restarted_pid} = Lifecycle.restart_registered_citizen(record.slug)
    assert is_pid(restarted_pid)
    assert restarted_pid != first_pid
    assert {:ok, ^restarted_pid} = Lifecycle.lookup(record.slug)

    after_marker = "BABS_RESTART_AFTER_#{System.unique_integer([:positive])}"
    Pane.inject(record.slug, "printf '#{after_marker}\\n'\n")
    wait_for_capture!(session, after_marker)

    running = Repo.get!(CitizenRecord, record.id)
    assert running.status == "running"
    assert running.last_error == nil
    assert running.cwd == record.cwd
    assert running.cli == record.cli
    assert running.cli_args == record.cli_args
    assert running.env == record.env
  end

  test "restart_registered_citizen aborts when stop fails and does not start over it" do
    record = insert_citizen!(%{slug: "restart-stop-failure", status: "running"})

    with_tmux_binary("/definitely/missing/babs-tmux", fn ->
      assert {:error, {:tmux_executable_not_found, _path}} =
               Lifecycle.restart_registered_citizen(record.slug,
                 start_config: fn _config ->
                   flunk("restart must not start after stop failure")
                 end
               )
    end)

    assert Repo.get!(CitizenRecord, record.id).status == "running"
  end

  test "same-slug registered lifecycle actions serialize while different slugs proceed" do
    insert_citizen!(%{slug: "lock-a", status: "stopped"})
    insert_citizen!(%{slug: "lock-b", status: "stopped"})

    parent = self()

    start = fn config ->
      send(parent, {:lifecycle_entered, config.slug, self()})

      if config.slug == "lock-a" do
        receive do
          :release -> {:ok, self()}
        after
          2_000 -> {:error, :timeout}
        end
      else
        {:ok, self()}
      end
    end

    task_a =
      Task.async(fn ->
        Lifecycle.start_registered_citizen("lock-a", start_config: start)
      end)

    assert_receive {:lifecycle_entered, "lock-a", pid_a}

    same_slug_task =
      Task.async(fn ->
        Lifecycle.start_registered_citizen("lock-a", start_config: start)
      end)

    different_slug_task =
      Task.async(fn ->
        Lifecycle.start_registered_citizen("lock-b", start_config: start)
      end)

    assert_receive {:lifecycle_entered, "lock-b", _pid_b}, 500
    assert {:ok, _pid} = Task.await(different_slug_task)
    refute_receive {:lifecycle_entered, "lock-a", _second_pid}, 100

    send(pid_a, :release)
    assert {:ok, _pid} = Task.await(task_a)
    assert_receive {:lifecycle_entered, "lock-a", pid_second}, 500
    send(pid_second, :release)
    assert {:ok, _pid} = Task.await(same_slug_task)
  end

  test "same-slug registered lifecycle actions can time out while waiting for lock" do
    insert_citizen!(%{slug: "lock-timeout", status: "stopped"})
    parent = self()

    start = fn config ->
      send(parent, {:lifecycle_entered, config.slug, self()})

      receive do
        :release -> {:ok, self()}
      after
        2_000 -> {:error, :timeout}
      end
    end

    task =
      Task.async(fn ->
        Lifecycle.start_registered_citizen("lock-timeout", start_config: start)
      end)

    assert_receive {:lifecycle_entered, "lock-timeout", pid}

    assert {:error, {:lifecycle_lock_timeout, "lock-timeout"}} =
             Lifecycle.start_registered_citizen("lock-timeout",
               start_config: fn _config ->
                 flunk("lifecycle should not start after lock timeout")
               end,
               lock_timeout_ms: 20
             )

    send(pid, :release)
    assert {:ok, _pid} = Task.await(task)
  end

  test "stop_citizen marks the SQLite row stopped when the session is already gone" do
    record = insert_citizen!(%{slug: "stop-missing-session", status: "running"})

    assert :ok = Lifecycle.stop_citizen(record.slug)
    assert Repo.get!(CitizenRecord, record.id).status == "stopped"
  end

  test "stop_citizen does not mark stopped when tmux cannot be invoked" do
    record = insert_citizen!(%{slug: "stop-missing-tmux", status: "running"})

    with_tmux_binary("/definitely/missing/babs-tmux", fn ->
      assert {:error, {:tmux_executable_not_found, _path}} = Lifecycle.stop_citizen(record.slug)
    end)

    assert Repo.get!(CitizenRecord, record.id).status == "running"
  end

  test "attach_imported_citizen persists external metadata and starts pane without Babs session" do
    record = insert_citizen!(%{slug: "attach-imported", status: "stopped"})
    parent = self()

    pane = imported_pane("operator-work:0.0", "%101")

    start_imported_pane = fn config, target, opts ->
      send(parent, {:start_imported, config.slug, target, Keyword.fetch!(opts, :attach_session)})
      {:ok, self()}
    end

    assert {:ok, _pid} =
             Lifecycle.attach_imported_citizen(record.slug, "operator-work:0.0",
               find_attachable_pane: fn "operator-work:0.0" -> {:ok, pane} end,
               target_exists?: fn "%101" -> true end,
               start_imported_pane: start_imported_pane
             )

    assert_receive {:start_imported, "attach-imported", "%101", "operator-work"}

    reloaded = Repo.get!(CitizenRecord, record.id)
    assert reloaded.status == "running"
    assert ImportedHardline.external?(reloaded)
    assert ImportedHardline.target(reloaded) == "operator-work:0.0"
    assert ImportedHardline.operational_target(reloaded) == "%101"
    refute Runner.tmux_session_alive?(Runner.session_name(record.slug))
  end

  test "attach_imported_citizen refuses to replace an active hardline" do
    record = insert_citizen!(%{slug: "active-import", status: "running"})
    {:ok, _value} = Registry.register(Babs.Citizens.PaneRegistry, record.slug, nil)

    assert {:error, :active_hardline_exists} =
             Lifecycle.attach_imported_citizen(record.slug, "operator-work:0.0",
               find_attachable_pane: fn _target ->
                 flunk("active hardline must block tmux inventory lookup")
               end
             )
  end

  test "stop_citizen detaches imported external hardline without killing tmux" do
    record =
      insert_citizen!(%{
        slug: "detach-imported",
        status: "running",
        metadata: imported_metadata("operator-work:0.0", "%101")
      })

    {:ok, _value} = Registry.register(Babs.Citizens.PaneRegistry, record.slug, nil)

    with_tmux_binary("/definitely/missing/babs-tmux", fn ->
      assert :ok = Lifecycle.stop_citizen(record.slug)
    end)

    assert Repo.get!(CitizenRecord, record.id).status == "stopped"
  end

  test "start_registered_citizen for missing imported target marks failed and never starts babs tmux" do
    record =
      insert_citizen!(%{
        slug: "missing-import-target",
        status: "running",
        metadata: imported_metadata("missing-session:0.0", "%404")
      })

    assert {:error, {:import_target_missing, "%404"}} =
             Lifecycle.start_registered_citizen(record.slug,
               target_exists?: fn "%404" -> false end,
               start_imported_pane: fn _config, _target ->
                 flunk("missing imported targets must not start a pane")
               end
             )

    failed = Repo.get!(CitizenRecord, record.id)
    assert failed.status == "failed"
    assert failed.last_error =~ "import_target_missing"
    refute Runner.tmux_session_alive?(Runner.session_name(record.slug))
  end

  test "start_config marks spawn failure in SQLite without leaking env values" do
    record =
      insert_citizen!(%{
        slug: "spawn-failure",
        env: %{"SECRET_TOKEN" => "do-not-log"},
        status: "running"
      })

    with_tmux_binary("/definitely/missing/babs-tmux", fn ->
      assert {:error, {:tmux_executable_not_found, _path}} =
               record
               |> Catalog.to_config()
               |> Lifecycle.start_config()
    end)

    failed = Repo.get!(CitizenRecord, record.id)
    assert failed.status == "failed"
    assert failed.last_error =~ "tmux_executable_not_found"
    refute failed.last_error =~ "do-not-log"
  end

  test "start_config success clears last_error and marks SQLite row running" do
    record =
      insert_citizen!(%{
        slug: "start-success-#{System.unique_integer([:positive])}",
        status: "failed",
        last_error: "previous failure"
      })

    on_exit(fn -> Lifecycle.stop_citizen(record.slug) end)

    assert {:ok, _pid} =
             record
             |> Catalog.to_config()
             |> Lifecycle.start_config()

    running = Repo.get!(CitizenRecord, record.id)
    assert running.status == "running"
    assert running.last_error == nil
  end

  defp with_tmux_binary(binary, fun) do
    original = Application.get_env(:babs_citizens, Babs.Citizens.Runner)
    Application.put_env(:babs_citizens, Babs.Citizens.Runner, tmux_binary: binary)

    try do
      fun.()
    after
      if original do
        Application.put_env(:babs_citizens, Babs.Citizens.Runner, original)
      else
        Application.delete_env(:babs_citizens, Babs.Citizens.Runner)
      end
    end
  end

  defp wait_for_capture!(session, marker) do
    deadline = System.monotonic_time(:millisecond) + 5_000
    do_wait_for_capture!(session, marker, deadline)
  end

  defp do_wait_for_capture!(session, marker, deadline) do
    cond do
      capture_contains?(session, marker) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("timed out waiting for #{marker} in #{session}")

      true ->
        Process.sleep(100)
        do_wait_for_capture!(session, marker, deadline)
    end
  end

  defp capture_contains?(session, marker) do
    case Runner.capture_pane(session) do
      {:ok, capture} -> String.contains?(capture, marker)
      {:error, _reason} -> false
    end
  end

  defp imported_pane(target, pane_id) do
    %{
      session_name: "operator-work",
      window_index: "0",
      window_name: "main",
      pane_index: "0",
      pane_id: pane_id,
      target: target,
      current_command: "zsh",
      current_path: System.tmp_dir!(),
      attached?: false
    }
  end

  defp imported_metadata(target, pane_id) do
    %{
      "hardline" => %{
        "ownership" => "external",
        "tmux" => %{
          "target" => target,
          "pane_id" => pane_id,
          "session_name" => "operator-work",
          "window_index" => "0",
          "pane_index" => "0"
        }
      }
    }
  end
end
