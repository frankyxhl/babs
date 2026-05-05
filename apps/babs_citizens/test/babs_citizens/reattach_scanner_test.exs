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
    cwd = "workspaces/#{slug}"
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
    cwd = "workspaces/#{slug}"
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
    Path.join(System.tmp_dir!(), "babs-reattach-scan-#{System.unique_integer([:positive])}")
  end
end
