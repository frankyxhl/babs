defmodule Babs.Citizens.ReattachScannerTest do
  use ExUnit.Case, async: false

  alias Babs.Citizens.{CitizenConfig, ReattachScanner}

  test "plans reattach for existing Babs sessions and start for missing seed configs" do
    clare = config("clare")
    dylan = config("dylan")
    sentinel = config("sentinel")

    assert ReattachScanner.plan_actions(
             [{:ok, clare}, {:ok, dylan}, {:ok, sentinel}],
             ["babs-clare", "personal-shell"]
           ) == [
             {:reattach, clare},
             {:start, dylan},
             {:start, sentinel}
           ]
  end

  test "preserves config load errors in the scan plan" do
    dylan = config("dylan")

    assert ReattachScanner.plan_actions(
             [{:error, {:missing_env, "OPENAI_API_KEY"}}, {:ok, dylan}],
             []
           ) == [
             {:config_error, {:missing_env, "OPENAI_API_KEY"}},
             {:start, dylan}
           ]
  end

  test "plans each existing slug only once" do
    clare = config("clare")

    assert ReattachScanner.plan_actions(
             [{:ok, clare}],
             ["babs-clare", "babs-clare", "unmanaged-clare"]
           ) == [
             {:reattach, clare}
           ]
  end

  test "plans SQLite rows by status and existing tmux sessions" do
    clare = row("clare", status: "running")
    dylan = row("dylan", status: "running")
    elena = row("elena", status: "stopped")
    sentinel = row("sentinel", status: "failed")

    assert ReattachScanner.plan_rows(
             [clare, dylan, elena, sentinel],
             ["babs-clare", "personal-shell"]
           ) == [
             {:reattach, clare},
             {:start, dylan},
             {:skip, "elena", :stopped},
             {:skip, "sentinel", :failed}
           ]
  end

  test "plans missing cwd for running SQLite rows as a durable failure" do
    cwd = Path.join(tmp_root(), "missing-workspace")
    record = row("missing-cwd", status: "running", cwd: cwd)

    assert ReattachScanner.plan_rows([record], []) == [
             {:fail_missing_cwd, record, {:missing_cwd, cwd}}
           ]
  end

  test "plans reattach before missing cwd failure for running SQLite rows" do
    cwd = Path.join(tmp_root(), "missing-workspace")
    record = row("reattach-missing-cwd", status: "running", cwd: cwd)

    assert ReattachScanner.plan_rows([record], ["babs-reattach-missing-cwd"]) == [
             {:reattach, record}
           ]
  end

  test "plans unexpected raw SQLite status as skipped instead of starting" do
    record = row("unknown-status", status: "paused")

    assert ReattachScanner.plan_rows([record], []) == [
             {:skip, "unknown-status", :unknown_status}
           ]
  end

  test "scan starts configured citizens from a temporary config directory" do
    slug = "scan-test-#{System.unique_integer([:positive])}"
    root = tmp_root()
    File.mkdir_p!(Path.join(root, "citizens"))

    File.write!(Path.join(root, "citizens/citizen-#{slug}.toml"), """
    id = "BAB-CIT-SCAN"
    slug = "#{slug}"
    display_name = "Scan Test"
    cli = "/bin/zsh"
    cli_args = ["-f"]
    cwd = "#{slug}"
    """)

    on_exit(fn -> Babs.Citizens.Lifecycle.stop_citizen(slug) end)

    assert ReattachScanner.scan(root: root, config_dir: "citizens") == [{:ok, slug}]
  end

  test "scan reattaches an existing configured tmux session" do
    slug = "scan-reattach-#{System.unique_integer([:positive])}"
    root = tmp_root()
    File.mkdir_p!(Path.join(root, "citizens"))
    cwd = Path.join(root, "workspaces/#{slug}")

    File.write!(Path.join(root, "citizens/citizen-#{slug}.toml"), """
    id = "BAB-CIT-SCAN"
    slug = "#{slug}"
    display_name = "Scan Reattach"
    cli = "/bin/zsh"
    cli_args = ["-f"]
    cwd = "#{slug}"
    """)

    config = %Babs.Citizens.CitizenConfig{
      id: "BAB-CIT-SCAN",
      slug: slug,
      display_name: "Scan Reattach",
      cli: "/bin/zsh",
      cli_args: ["-f"],
      cwd: cwd,
      env: %{}
    }

    on_exit(fn -> Babs.Citizens.Lifecycle.stop_citizen(slug) end)

    assert :ok = Babs.Citizens.Runner.start_session(config)
    assert ReattachScanner.scan(root: root, config_dir: "citizens") == [{:ok, slug}]
  end

  test "scan reports config errors as events" do
    root = tmp_root()
    File.mkdir_p!(Path.join(root, "citizens"))
    File.write!(Path.join(root, "citizens/citizen-bad.toml"), "not toml ===")

    assert [{:error, :config, {:toml_decode_failed, _path, _reason}}] =
             ReattachScanner.scan(root: root, config_dir: "citizens")
  end

  test "scan reports missing tmux as a recoverable event" do
    root = tmp_root()
    File.mkdir_p!(Path.join(root, "citizens"))

    File.write!(Path.join(root, "citizens/citizen-no-tmux.toml"), """
    id = "BAB-CIT-NO-TMUX"
    slug = "no-tmux"
    display_name = "No Tmux"
    cli = "/bin/zsh"
    cwd = "no-tmux"
    """)

    with_tmux_binary("/definitely/missing/babs-tmux", fn ->
      assert [
               {:error, :tmux, {:tmux_executable_not_found, "/definitely/missing/babs-tmux"}}
             ] = ReattachScanner.scan(root: root, config_dir: "citizens")
    end)
  end

  defp row(slug, attrs) do
    cwd =
      Keyword.get_lazy(attrs, :cwd, fn ->
        cwd = Path.join(tmp_root(), slug)
        File.mkdir_p!(cwd)
        cwd
      end)

    %Babs.Citizens.CitizenRecord{
      id: "BAB-CIT-#{String.upcase(String.replace(slug, "-", "_"))}",
      slug: slug,
      display_name: String.capitalize(slug),
      cli: "/bin/zsh",
      cli_args: ["-f"],
      cwd: cwd,
      env: %{},
      status: Keyword.get(attrs, :status, "running"),
      metadata: %{}
    }
  end

  defp config(slug) do
    %CitizenConfig{
      id: "BAB-CIT-#{slug}",
      slug: slug,
      display_name: String.capitalize(slug),
      cli: "/bin/zsh",
      cli_args: ["-f"],
      cwd: "/tmp/babs-#{slug}",
      env: %{}
    }
  end

  defp tmp_root do
    root =
      Path.join(
        System.tmp_dir!(),
        "babs-reattach-scan-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    root
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
