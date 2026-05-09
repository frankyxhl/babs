defmodule Babs.Citizens.DirectCli.EnvRedactorTest do
  use ExUnit.Case, async: false

  alias Babs.Citizens.CitizenConfig
  alias Babs.Citizens.DirectCli.{Env, Redactor}

  test "builds bounded env from allowlist plus citizen env" do
    original_path = System.get_env("PATH")

    try do
      System.put_env("BABS_SHOULD_NOT_LEAK", "nope")
      System.put_env("PATH", "/bin")

      env = Env.build(config(%{"CUSTOM_TOKEN" => "secret"}), allowlist: ["PATH"])

      assert {"PATH", "/bin"} in env
      assert {"CUSTOM_TOKEN", "secret"} in env
      assert {"BABS_DIRECT_CLI", "1"} in env
      refute Enum.any?(env, &match?({"BABS_SHOULD_NOT_LEAK", _}, &1))
    after
      System.delete_env("BABS_SHOULD_NOT_LEAK")
      restore_env("PATH", original_path)
    end
  end

  test "redacts tokens paths and private ips while bounding output" do
    text = "api_token=secret path=/Users/alice/Projects/babs host=100.64.0.1"

    redacted = Redactor.redact_text(text)

    refute redacted =~ "secret"
    refute redacted =~ "/Users/alice"
    refute redacted =~ "100.64.0.1"
    assert redacted =~ "[REDACTED"

    assert Redactor.bound_output(String.duplicate("x", 12), 4) == "xxxx\n[TRUNCATED]"
  end

  test "redacts configured secret values even when printed without assignment names" do
    config = config(%{"OPENAI_API_KEY" => "sk-test-secret-value"})

    assert Env.secret_names(config) == ["OPENAI_API_KEY"]
    assert Env.secret_values(config) == ["sk-test-secret-value"]

    redacted =
      Redactor.redact_text("provider echoed sk-test-secret-value",
        secret_names: Env.secret_names(config),
        secret_values: Env.secret_values(config)
      )

    refute redacted =~ "sk-test-secret-value"
    assert redacted == "provider echoed [REDACTED]"
  end

  test "keeps redacted json key values parseable" do
    text =
      Jason.encode!(%{
        "type" => "assistant.message",
        "data" => %{
          "content" => "BABS_REPLY T-2026-05-09-003: /Users/alice/Projects/babs",
          "outputTokens" => 42
        }
      })

    redacted = Redactor.redact_text(text)

    assert {:ok, value} = Jason.decode(redacted)
    assert get_in(value, ["data", "outputTokens"]) == "[REDACTED]"
    assert get_in(value, ["data", "content"]) == "BABS_REPLY T-2026-05-09-003: [REDACTED_PATH]"
  end

  test "keeps unquoted assignment redaction shell-safe" do
    assert Redactor.redact_text("api_token=secret") == "api_token=[REDACTED]"
  end

  test "bounds output on a valid UTF-8 boundary" do
    text = "ab🙂cd"

    bounded = Redactor.bound_output(text, 5)

    assert bounded == "ab\n[TRUNCATED]"
    assert String.valid?(bounded)
  end

  defp config(env) do
    %CitizenConfig{
      id: "BAB-CIT-TEST",
      slug: "tester",
      display_name: "Tester",
      cli: "codex",
      cwd: "/workspace/tester",
      env: env
    }
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
