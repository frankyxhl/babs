defmodule Babs.Citizens.BootstrapTest do
  use Babs.Citizens.RepoCase, async: false

  alias Babs.Citizens.{Bootstrap, Lifecycle, Repo, Runner}

  test "run_once imports TOML, then later respawns from SQLite after TOML is hidden" do
    root = tmp_root!()
    path = write_citizen_toml!(root, "bootstrap")
    session = Runner.session_name("bootstrap")

    on_exit(fn -> Lifecycle.stop_citizen("bootstrap") end)

    assert {:ok, %{import: %{records: [imported], errors: []}, scan: [{:ok, "bootstrap"}]}} =
             Bootstrap.run_once(root: root, config_dir: "citizens")

    assert imported.slug == "bootstrap"
    assert Runner.tmux_session_alive?(session)
    assert Repo.get!(CitizenRecord, imported.id).status == "running"

    assert :ok = Runner.kill_session(session)
    stop_pane_if_alive("bootstrap")
    File.rename!(path, path <> ".hidden")

    assert {:ok, %{import: %{records: [], errors: []}, scan: [{:ok, "bootstrap"}]}} =
             Bootstrap.run_once(root: root, config_dir: "citizens")

    assert Runner.tmux_session_alive?(session)
  end

  test "start_link stores one-shot bootstrap events" do
    slug = "bootstrap-gs-#{System.unique_integer([:positive])}"
    root = tmp_root!()
    write_citizen_toml!(root, slug)
    session = Runner.session_name(slug)

    on_exit(fn -> Lifecycle.stop_citizen(slug) end)

    start_supervised!({Bootstrap, [root: root, config_dir: "citizens"]})

    wait_until(fn ->
      case Bootstrap.events() do
        %{import: %{records: [_record], errors: []}, scan: [{:ok, ^slug}]} -> true
        _other -> false
      end
    end)

    assert Runner.tmux_session_alive?(session)
  end

  defp stop_pane_if_alive(slug) do
    case Lifecycle.lookup(slug) do
      {:ok, pid} -> DynamicSupervisor.terminate_child(Babs.Citizens.DynamicSupervisor, pid)
      {:error, :not_found} -> :ok
    end
  end

  defp wait_until(predicate) do
    deadline = System.monotonic_time(:millisecond) + 5_000
    do_wait_until(predicate, deadline)
  end

  defp do_wait_until(predicate, deadline) do
    cond do
      predicate.() ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("timed out waiting for bootstrap events")

      true ->
        Process.sleep(50)
        do_wait_until(predicate, deadline)
    end
  end
end
