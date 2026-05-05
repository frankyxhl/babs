defmodule Babs.Citizens.LifecycleStatusTest do
  use Babs.Citizens.RepoCase, async: false

  alias Babs.Citizens.{Catalog, Lifecycle, Repo}

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
end
