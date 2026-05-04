defmodule Babs.Citizens.Citizen.ConfigTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Citizen.Config

  test "loads a citizen TOML config and resolves environment interpolation" do
    root = tmp_root()
    File.mkdir_p!(Path.join(root, "citizens"))
    File.mkdir_p!(Path.join(root, "workspaces/tester"))
    System.put_env("BABS_TEST_TOKEN", "secret-token")

    path = Path.join(root, "citizens/citizen-tester.toml")

    File.write!(path, """
    id = "BAB-CIT-9999"
    slug = "tester"
    display_name = "Tester"
    cli = "/bin/zsh"
    cli_args = ["-f"]
    cwd = "workspaces/tester"
    description = "Test citizen"

    [env]
    BABS_TEST_TOKEN = "${BABS_TEST_TOKEN}"
    """)

    assert {:ok, config} = Config.load_file(path, root: root)
    assert config.id == "BAB-CIT-9999"
    assert config.slug == "tester"
    assert config.cli_args == ["-f"]
    assert config.env == %{"BABS_TEST_TOKEN" => "secret-token"}
    assert config.cwd == Path.join(root, "workspaces/tester")
  after
    System.delete_env("BABS_TEST_TOKEN")
  end

  test "rejects invalid slugs" do
    refute Config.valid_slug?("Bad")
    refute Config.valid_slug?("../bad")
    assert Config.valid_slug?("clare")
  end

  defp tmp_root do
    Path.join(System.tmp_dir!(), "babs-config-test-#{System.unique_integer([:positive])}")
  end
end
