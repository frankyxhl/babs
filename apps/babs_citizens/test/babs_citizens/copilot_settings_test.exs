defmodule Babs.Citizens.CopilotSettingsTest do
  use ExUnit.Case, async: false

  alias Babs.Citizens.CopilotSettings

  test "trust_folder creates settings and adds the expanded workspace path" do
    home = tmp_dir("copilot-home")
    cwd = Path.join(home, "workspace")

    assert :ok = CopilotSettings.trust_folder(cwd, home: home)

    config_path = Path.join(home, "config.json")
    settings = decode_jsonc_file(config_path)

    assert settings["trustedFolders"] == [Path.expand(cwd)]
    assert config_path |> File.read!() |> String.starts_with?("// User settings belong")
  end

  test "trust_folder preserves existing config and avoids duplicate trusted folders" do
    home = tmp_dir("copilot-home-existing")
    cwd = Path.join(home, "workspace")
    settings_path = Path.join(home, "config.json")
    File.mkdir_p!(home)

    File.write!(
      settings_path,
      """
      // User settings belong in settings.json.
      // This file is managed automatically.
      {
        "theme": "dark",
        "trustedFolders": ["/already/trusted", "#{Path.expand(cwd)}"]
      }
      """
    )

    assert :ok = CopilotSettings.trust_folder(cwd, home: home)

    settings = decode_jsonc_file(settings_path)

    assert settings["theme"] == "dark"
    assert settings["trustedFolders"] == ["/already/trusted", Path.expand(cwd)]
    assert settings_path |> File.read!() |> String.starts_with?("// User settings belong")
  end

  test "trust_folder refuses to overwrite malformed config" do
    home = tmp_dir("copilot-home-malformed")
    settings_path = Path.join(home, "config.json")
    File.mkdir_p!(home)
    File.write!(settings_path, "{not-json}\n")

    assert {:error, {:copilot_settings_decode_failed, ^settings_path, _reason}} =
             CopilotSettings.trust_folder(Path.join(home, "workspace"), home: home)

    assert File.read!(settings_path) == "{not-json}\n"
  end

  test "trust_folder refuses invalid trustedFolders shape" do
    home = tmp_dir("copilot-home-invalid")
    settings_path = Path.join(home, "config.json")
    File.mkdir_p!(home)
    File.write!(settings_path, Jason.encode!(%{"trustedFolders" => "not-a-list"}))

    assert {:error, {:copilot_trusted_folders_invalid, ^settings_path}} =
             CopilotSettings.trust_folder(Path.join(home, "workspace"), home: home)
  end

  defp tmp_dir(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
  end

  defp decode_jsonc_file(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: false)
    |> Enum.reject(fn line -> line |> String.trim_leading() |> String.starts_with?("//") end)
    |> Enum.join("\n")
    |> Jason.decode!()
  end
end
