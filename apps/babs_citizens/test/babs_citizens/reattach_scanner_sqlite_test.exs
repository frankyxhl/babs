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

  test "scan_rows reports tmux scan failures" do
    record = insert_citizen!(%{slug: "tmux-scan-error"})

    with_tmux_binary("/definitely/missing/babs-tmux", fn ->
      assert [
               {:error, :tmux, {:tmux_executable_not_found, "/definitely/missing/babs-tmux"}}
             ] = ReattachScanner.scan_rows([record])
    end)
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
