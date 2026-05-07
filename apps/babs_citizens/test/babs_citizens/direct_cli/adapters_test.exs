defmodule Babs.Citizens.DirectCli.AdaptersTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.CitizenConfig
  alias Babs.Citizens.DirectCli.Adapters
  alias Babs.Citizens.DirectCli.Adapters.{Claude, Codex, Copilot, Fake}

  test "resolves supported provider adapters from citizen cli config" do
    assert {:ok, Claude} = Adapters.resolve(config("claude"))
    assert {:ok, Codex} = Adapters.resolve(config("codex"))
    assert {:ok, Copilot} = Adapters.resolve(config("copilot"))
    assert {:ok, Fake} = Adapters.resolve(config("babs-fake-ai"))
    assert {:error, {:unsupported_direct_cli, "zsh"}} = Adapters.resolve(config("/bin/zsh"))
  end

  test "claude command uses print json and explicit session id" do
    cfg = config("claude")

    assert {:ok, command} =
             Claude.start_command(cfg, "hello",
               provider_session_id: "00000000-0000-0000-0000-000000000001"
             )

    assert command.provider == "claude"

    assert command.args == [
             "claude",
             "--print",
             "--output-format",
             "json",
             "--session-id",
             "00000000-0000-0000-0000-000000000001",
             "hello"
           ]

    assert {:ok, resumed} = Claude.resume_command(cfg, "session-1", "again")

    assert resumed.args == [
             "claude",
             "--print",
             "--output-format",
             "json",
             "--resume",
             "session-1",
             "again"
           ]
  end

  test "claude command generates session id when runner has none stored" do
    cfg = config("claude")

    assert {:ok, command} = Claude.start_command(cfg, "hello", provider_session_id: nil)

    assert [
             "claude",
             "--print",
             "--output-format",
             "json",
             "--session-id",
             session_id,
             "hello"
           ] = command.args

    assert {:ok, _uuid} = Ecto.UUID.cast(session_id)
    assert command.provider_session_id == session_id
  end

  test "claude command preserves citizen cli args before direct flags" do
    cfg = %{config("claude") | cli_args: ["--model", "sonnet"]}

    assert {:ok, command} =
             Claude.start_command(cfg, "hello",
               provider_session_id: "00000000-0000-0000-0000-000000000001"
             )

    assert command.args == [
             "claude",
             "--model",
             "sonnet",
             "--print",
             "--output-format",
             "json",
             "--session-id",
             "00000000-0000-0000-0000-000000000001",
             "hello"
           ]

    assert {:ok, resumed} = Claude.resume_command(cfg, "session-1", "again")

    assert resumed.args == [
             "claude",
             "--model",
             "sonnet",
             "--print",
             "--output-format",
             "json",
             "--resume",
             "session-1",
             "again"
           ]
  end

  test "claude parses json result and redacts paths" do
    stdout =
      Jason.encode!(%{"session_id" => "session-1", "result" => "done at /Users/alice/secret"})

    assert {:ok, result} = Claude.parse_result(%{stdout: stdout, stderr: ""})
    assert result.provider_session_id == "session-1"
    assert result.text == "done at [REDACTED_PATH]"
    assert result.capabilities["resume"]
  end

  test "codex command and jsonl parser discover thread id" do
    cfg = config("codex")
    assert {:ok, command} = Codex.start_command(cfg, "hello")

    assert command.args == [
             "codex",
             "exec",
             "--json",
             "--cd",
             cfg.cwd,
             "--dangerously-bypass-approvals-and-sandbox",
             "hello"
           ]

    stdout =
      [
        %{"type" => "session.created", "thread_id" => "codex-thread"},
        %{"type" => "message", "content" => "codex reply"}
      ]
      |> Enum.map(&Jason.encode!/1)
      |> Enum.join("\n")

    assert {:ok, result} = Codex.parse_result(%{stdout: stdout, stderr: ""})
    assert result.provider_session_id == "codex-thread"
    assert result.text == "codex reply"

    assert {:ok, resumed} = Codex.resume_command(cfg, "codex-thread", "again")

    assert resumed.args == [
             "codex",
             "exec",
             "resume",
             "--json",
             "--dangerously-bypass-approvals-and-sandbox",
             "codex-thread",
             "again"
           ]
  end

  test "codex parser handles nested documented jsonl message text" do
    stdout =
      [
        %{"type" => "session.created", "thread_id" => "codex-thread"},
        %{
          "type" => "response.output_item.done",
          "params" => %{
            "item" => %{
              "type" => "message",
              "role" => "assistant",
              "text" => "codex nested reply"
            }
          }
        }
      ]
      |> Enum.map(&Jason.encode!/1)
      |> Enum.join("\n")

    assert {:ok, result} = Codex.parse_result(%{stdout: stdout, stderr: ""})
    assert result.provider_session_id == "codex-thread"
    assert result.text == "codex nested reply"
  end

  test "codex parser joins streaming jsonl deltas when no final text is present" do
    stdout =
      [
        %{"type" => "session.created", "thread_id" => "codex-thread"},
        %{"type" => "response.output_text.delta", "params" => %{"delta" => "codex "}},
        %{"type" => "response.output_text.delta", "params" => %{"delta" => "stream reply"}}
      ]
      |> Enum.map(&Jason.encode!/1)
      |> Enum.join("\n")

    assert {:ok, result} = Codex.parse_result(%{stdout: stdout, stderr: ""})
    assert result.provider_session_id == "codex-thread"
    assert result.text == "codex stream reply"
  end

  test "copilot command and jsonl parser handle session id" do
    cfg = config("copilot")
    assert {:ok, command} = Copilot.start_command(cfg, "hello")

    assert command.args == [
             "copilot",
             "-p",
             "hello",
             "--output-format",
             "json",
             "--stream",
             "off",
             "--allow-all",
             "--no-ask-user",
             "-C",
             cfg.cwd
           ]

    stdout =
      [
        %{"type" => "session", "sessionId" => "copilot-session"},
        %{"type" => "assistant.message", "data" => %{"content" => "copilot reply"}}
      ]
      |> Enum.map(&Jason.encode!/1)
      |> Enum.join("\n")

    assert {:ok, result} = Copilot.parse_result(%{stdout: stdout, stderr: ""})
    assert result.provider_session_id == "copilot-session"
    assert result.text == "copilot reply"
  end

  test "fake adapter is deterministic for BDD fixtures" do
    cfg = config("babs-fake-ai")
    assert {:ok, command} = Fake.start_command(cfg, "hello", provider_session_id: "fake-session")
    assert command.args == ["babs-fake-ai", "--session", "fake-session", "--reply", "hello"]

    stdout = Jason.encode!(%{"session_id" => "fake-session", "content" => "fake reply"})
    assert {:ok, result} = Fake.parse_result(%{stdout: stdout, stderr: ""})
    assert result.text == "fake reply"
    assert result.provider_session_id == "fake-session"
  end

  defp config(cli) do
    %CitizenConfig{
      id: "BAB-CIT-TEST",
      slug: "tester",
      display_name: "Tester",
      cli: cli,
      cli_args: [],
      launch_profile: "trusted_autonomous",
      ticket_backend: "direct_cli",
      cwd: "/workspace/tester",
      env: %{}
    }
  end
end
