defmodule Babs.Citizens.ReattachScannerTest do
  use ExUnit.Case, async: true

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
end
