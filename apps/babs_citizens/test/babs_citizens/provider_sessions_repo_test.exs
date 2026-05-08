defmodule Babs.Citizens.ProviderSessionsRepoTest do
  use Babs.Citizens.RepoCase, async: false

  alias Babs.Citizens.{ProviderSession, ProviderSessions, Repo}

  test "upserts one active session per citizen ticket provider backend" do
    assert {:ok, first} =
             ProviderSessions.upsert_active(%{
               citizen_slug: "elena",
               ticket_id: "T-2026-05-07-001",
               provider: "copilot",
               backend: "direct_cli",
               provider_session_id: "session-a",
               workspace_ref: "citizen:elena",
               capabilities: %{"direct" => true}
             })

    assert {:ok, second} =
             ProviderSessions.upsert_active(%{
               citizen_slug: "elena",
               ticket_id: "T-2026-05-07-001",
               provider: "copilot",
               backend: "direct_cli",
               provider_session_id: "session-b",
               workspace_ref: "citizen:elena",
               capabilities: %{"direct" => true, "resume" => true}
             })

    assert second.id == first.id
    assert second.provider_session_id == "session-b"
    assert Repo.aggregate(ProviderSession, :count, :id) == 1
  end

  test "partial unique index permits a new active session after close" do
    assert {:ok, first} = insert_session("session-a")
    assert {:ok, _closed} = ProviderSessions.close(first)
    assert {:ok, second} = insert_session("session-b")

    assert second.id != first.id
    assert Repo.aggregate(ProviderSession, :count, :id) == 2
  end

  test "redacts local paths before storing workspace refs and errors" do
    assert {:ok, session} =
             ProviderSessions.upsert_active(%{
               citizen_slug: "dylan",
               ticket_id: "T-2026-05-07-002",
               provider: "codex",
               backend: "direct_cli",
               workspace_ref: "/Users/alice/Projects/babs/workspaces/dylan"
             })

    assert session.workspace_ref == "citizen:dylan"

    assert {:ok, failed} =
             ProviderSessions.mark_failed(session, {:bad, "/tmp/raw", "api_token=secret"})

    refute failed.last_error =~ "/tmp/raw"
    refute failed.last_error =~ "secret"
    assert failed.last_error =~ "[REDACTED"
  end

  test "mark_failed can persist standardized diagnostic summaries" do
    assert {:ok, session} = insert_session("session-diagnostic")

    assert {:ok, failed} =
             ProviderSessions.mark_failed(
               session,
               {:exit_status, 2,
                %{
                  stdout: "raw stdout with sk-test-secret-value",
                  stderr: "raw stderr at /home/operator/work"
                }},
               secret_values: ["sk-test-secret-value"]
             )

    assert failed.status == "failed"
    assert failed.last_error == "provider exited with status 2"
    refute failed.last_error =~ "raw stdout"
    refute failed.last_error =~ "sk-test-secret-value"
    refute failed.last_error =~ "/home/operator"
  end

  test "mark_non_resumable uses standardized diagnostic summaries" do
    assert {:ok, session} = insert_session("session-non-resumable")

    assert {:ok, non_resumable} =
             ProviderSessions.mark_non_resumable(
               session,
               {:exit_status, 2, %{stdout: "raw stdout", stderr: "raw stderr"}}
             )

    assert non_resumable.status == "non_resumable"
    assert non_resumable.last_error == "provider exited with status 2"
    refute non_resumable.last_error =~ "raw stdout"
  end

  test "marks stale in-flight executions failed during boot cleanup" do
    assert {:ok, session} = insert_session("session-a")
    assert {:ok, _started} = ProviderSessions.mark_started(session, %{os_pid: 12_345})

    assert {1, nil} = ProviderSessions.mark_stale_in_flight_failed()

    reloaded = Repo.get!(ProviderSession, session.id)
    assert reloaded.status == "failed"
    assert reloaded.os_pid == nil
    assert reloaded.started_at == nil
  end

  defp insert_session(provider_session_id) do
    ProviderSessions.upsert_active(%{
      citizen_slug: "clare",
      ticket_id: "T-2026-05-07-001",
      provider: "claude",
      backend: "direct_cli",
      provider_session_id: provider_session_id,
      workspace_ref: "citizen:clare"
    })
  end
end
