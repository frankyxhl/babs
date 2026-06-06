defmodule Babs.Citizens.Tickets.InjectorTest do
  use ExUnit.Case, async: true

  alias Babs.Knowledge
  alias Babs.Citizens.Tickets.Injector
  alias Babs.Citizens.Tickets.Ticket

  test "prompt includes ticket identity, path, assignee, and body" do
    prompt = Injector.prompt(ticket(), "clare")

    assert prompt =~ "You are clare, a Babs Citizen."
    assert prompt =~ "This message was delivered through the Babs Ticket/Billboard system."
    assert prompt =~ "[Babs Ticket T-2026-05-06-001 assigned]"
    assert prompt =~ "Title: Inject prompt"
    assert prompt =~ "State: in_progress"
    assert prompt =~ "Assignee: clare"
    assert prompt =~ "Path: /tmp/T-2026-05-06-001.md"
    assert prompt =~ "Ticket body for the citizen."
    assert prompt =~ "BABS_REPLY T-2026-05-06-001: your response"
    refute prompt =~ "replying through `bb ticket comment`"
    assert String.ends_with?(prompt, "\n")
  end

  test "feedback prompt includes rejection feedback for the assignee" do
    prompt = Injector.feedback_prompt(ticket(), "clare", "  Missing docs.  ")

    assert prompt =~ "You are clare, a Babs Citizen."
    assert prompt =~ "[Babs Ticket T-2026-05-06-001 rejected]"
    assert prompt =~ "State: in_progress"
    assert prompt =~ "Assignee: clare"
    assert prompt =~ "Feedback from user:\nMissing docs."
    assert prompt =~ "BABS_REPLY T-2026-05-06-001: your response"
    assert String.ends_with?(prompt, "\n")
  end

  test "comment prompt includes provenance and trimmed body for the assignee" do
    prompt = Injector.comment_prompt(ticket(), "clare", "dylan", "  Please review the branch.  ")

    assert prompt =~ "You are clare, a Babs Citizen."
    assert prompt =~ "[Babs Ticket T-2026-05-06-001 comment]"
    assert prompt =~ "State: in_progress"
    assert prompt =~ "Assignee: clare"
    assert prompt =~ "From: dylan"
    assert prompt =~ "Please review the branch."
    assert prompt =~ "BABS_REPLY T-2026-05-06-001: your response"
    assert String.ends_with?(prompt, "\n")
  end

  test "comment prompt can thread Knowledge resolver opts into standing context" do
    root = tmp_root()

    assert :ok =
             Knowledge.write(
               "clare",
               "Readme.md",
               "Prefer concise replies.\n",
               knowledge_opts(root)
             )

    prompt =
      Injector.comment_prompt(
        ticket(),
        "clare",
        "dylan",
        "  Please review the branch.  ",
        [],
        root: root,
        knowledge_root: "knowledge"
      )

    assert prompt =~ "Citizen standing context:"
    assert prompt =~ "[file: Readme.md]\nPrefer concise replies."
    assert prompt =~ "Ticket body for the citizen."
  end

  test "prepare validates the citizen exists" do
    assert {:error, {:unknown_citizen, "ghost"}} =
             Injector.prepare("ghost", citizen_fetcher: fn _slug -> nil end)
  end

  test "prepare auto-starts when no live pane is registered" do
    parent = self()

    lookup = fn
      "clare" ->
        receive do
          :started -> {:ok, self()}
        after
          0 -> {:error, :not_found}
        end
    end

    starter = fn "clare" ->
      send(parent, :starter_called)
      send(self(), :started)
      {:ok, self()}
    end

    assert :ok =
             Injector.prepare("clare",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: lookup,
               citizen_starter: starter
             )

    assert_received :starter_called
  end

  test "prepare returns redacted start failures" do
    assert {:error, {:citizen_start_failed, "clare", message}} =
             Injector.prepare("clare",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:error, :not_found} end,
               citizen_starter: fn "clare" -> {:error, %{api_token: "fixture-value"}} end
             )

    refute message =~ "fixture-value"
    assert message =~ "[REDACTED]"
  end

  test "prepare returns redacted pane lookup failures" do
    assert {:error, {:citizen_lookup_failed, "clare", message}} =
             Injector.prepare("clare",
               citizen_fetcher: fn "clare" -> %{slug: "clare"} end,
               pane_lookup: fn "clare" -> {:error, %{api_token: "fixture-value"}} end
             )

    refute message =~ "fixture-value"
    assert message =~ "[REDACTED]"
  end

  test "inject returns redacted injection failures" do
    assert {:error, {:ticket_injection_failed, "clare", message}} =
             Injector.inject("clare", "prompt",
               pane_lookup: fn "clare" -> {:ok, self()} end,
               pane_injector: fn "clare", "prompt" ->
                 {:error, %{api_token: "fixture-value"}}
               end
             )

    refute message =~ "fixture-value"
    assert message =~ "[REDACTED]"
  end

  test "inject returns redacted pane lookup failures" do
    assert {:error, {:citizen_lookup_failed, "clare", message}} =
             Injector.inject("clare", "prompt",
               pane_lookup: fn "clare" -> {:error, %{api_token: "fixture-value"}} end
             )

    refute message =~ "fixture-value"
    assert message =~ "[REDACTED]"
  end

  defp ticket do
    %Ticket{
      id: "T-2026-05-06-001",
      type: "assignment",
      state: "in_progress",
      assigner: "user",
      assignees: ["clare"],
      assignee_role: nil,
      inspector: "user",
      priority: "normal",
      parent_ticket: nil,
      created_at: "2026-05-06T00:00:00Z",
      updated_at: "2026-05-06T00:01:00Z",
      metadata: %{},
      title: "Inject prompt",
      body: "Ticket body for the citizen.",
      path: "/tmp/T-2026-05-06-001.md",
      warnings: []
    }
  end

  defp knowledge_opts(root), do: [root: root, knowledge_root: "knowledge"]

  defp tmp_root do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-injector-context-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end
end
