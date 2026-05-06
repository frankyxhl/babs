defmodule Babs.Citizens.ReattachScannerSqliteTest do
  use Babs.Citizens.RepoCase, async: false

  alias Babs.Citizens.{Lifecycle, ReattachScanner, Repo, Runner}

  test "scan_rows starts a SQLite-only running row without TOML" do
    record = insert_citizen!(%{slug: "sqlite-only-#{System.unique_integer([:positive])}"})
    session = Runner.session_name(record.slug)

    on_exit(fn -> Lifecycle.stop_citizen(record.slug) end)

    assert ReattachScanner.scan_rows([record]) == [{:ok, record.slug}]
    assert Runner.tmux_session_alive?(session)
  end

  test "scan_rows marks running rows with missing cwd as failed" do
    missing_cwd = Path.join(tmp_root!(), "missing-cwd")
    record = insert_citizen!(%{slug: "missing-cwd", cwd: missing_cwd, status: "running"})

    assert ReattachScanner.scan_rows([record]) == [
             {:error, "missing-cwd", {:missing_cwd, missing_cwd}}
           ]

    failed = Repo.get!(CitizenRecord, record.id)
    assert failed.status == "failed"
    assert failed.last_error =~ "missing_cwd"
    assert failed.last_error =~ missing_cwd
  end

  test "scan_rows reattaches a live running session before checking missing cwd" do
    slug = "reattach-missing-cwd-#{System.unique_integer([:positive])}"
    record = insert_citizen!(%{slug: slug, status: "running"})
    config = Babs.Citizens.Catalog.to_config(record)

    on_exit(fn -> Lifecycle.stop_citizen(slug) end)

    assert :ok = Runner.start_session(config)
    File.rm_rf!(record.cwd)

    assert ReattachScanner.scan_rows([record]) == [{:ok, slug}]

    running = Repo.get!(CitizenRecord, record.id)
    assert running.status == "running"
    assert is_nil(running.last_error)
  end

  test "scan_rows reports tmux scan failures" do
    record = insert_citizen!(%{slug: "tmux-scan-error"})

    with_tmux_binary("/definitely/missing/babs-tmux", fn ->
      assert [
               {:error, :tmux, {:tmux_executable_not_found, "/definitely/missing/babs-tmux"}}
             ] = ReattachScanner.scan_rows([record])
    end)
  end

  test "scan_rows reattaches imported external rows without babs session discovery" do
    record =
      insert_citizen!(%{
        slug: "imported-reattach",
        status: "running",
        metadata: imported_metadata("operator-work:0.0", "%101")
      })

    parent = self()

    assert ReattachScanner.scan_rows([record],
             target_exists?: fn "%101" -> true end,
             start_imported_pane: fn config, target, opts ->
               send(
                 parent,
                 {:reattach_imported, config.slug, target, Keyword.fetch!(opts, :attach_session)}
               )

               {:ok, self()}
             end
           ) == [{:ok, record.slug}]

    assert_receive {:reattach_imported, "imported-reattach", "%101", "operator-work"}
    assert Repo.get!(CitizenRecord, record.id).status == "running"
    refute Runner.tmux_session_alive?(Runner.session_name(record.slug))
  end

  test "scan_rows marks missing imported external targets failed without spawning babs session" do
    record =
      insert_citizen!(%{
        slug: "imported-missing",
        status: "running",
        metadata: imported_metadata("missing-work:0.0", "%404")
      })

    assert ReattachScanner.scan_rows([record], target_exists?: fn "%404" -> false end) ==
             [
               {:error, record.slug, {:import_target_missing, "%404"}}
             ]

    failed = Repo.get!(CitizenRecord, record.id)
    assert failed.status == "failed"
    assert failed.last_error =~ "import_target_missing"
    refute Runner.tmux_session_alive?(Runner.session_name(record.slug))
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
