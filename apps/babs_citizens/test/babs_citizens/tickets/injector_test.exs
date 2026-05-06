defmodule Babs.Citizens.Tickets.InjectorTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.Injector
  alias Babs.Citizens.Tickets.Ticket

  test "prompt includes ticket identity, path, assignee, and body" do
    prompt = Injector.prompt(ticket(), "clare")

    assert prompt =~ "[Babs Ticket T-2026-05-06-001 assigned]"
    assert prompt =~ "Title: Inject prompt"
    assert prompt =~ "State: in_progress"
    assert prompt =~ "Assignee: clare"
    assert prompt =~ "Path: /tmp/T-2026-05-06-001.md"
    assert prompt =~ "Ticket body for the citizen."
    assert String.ends_with?(prompt, "\n")
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
end
