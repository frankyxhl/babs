defmodule Babs.Citizens.ProviderSessionTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.ProviderSession

  test "validates safe provider session metadata" do
    changeset =
      ProviderSession.changeset(%ProviderSession{}, %{
        id: "ps_test",
        citizen_slug: "elena",
        ticket_id: "T-2026-05-07-001",
        provider: "copilot",
        backend: "direct_cli",
        provider_session_id: "session-123",
        capabilities: %{"direct" => true, "resume" => true},
        workspace_ref: "citizen:elena",
        status: "active",
        metadata: %{"shape" => "fixture"}
      })

    assert changeset.valid?
  end

  test "rejects unsupported provider, backend, status, maps, and absolute paths" do
    attrs = valid_attrs()

    refute ProviderSession.changeset(%ProviderSession{}, %{attrs | provider: "unknown"}).valid?
    refute ProviderSession.changeset(%ProviderSession{}, %{attrs | backend: "batch"}).valid?
    refute ProviderSession.changeset(%ProviderSession{}, %{attrs | status: "running"}).valid?
    refute ProviderSession.changeset(%ProviderSession{}, %{attrs | capabilities: []}).valid?

    refute ProviderSession.changeset(%ProviderSession{}, %{
             attrs
             | workspace_ref: "/Users/frank/work"
           }).valid?

    refute ProviderSession.changeset(%ProviderSession{}, %{attrs | last_error: "/tmp/raw/path"}).valid?
  end

  defp valid_attrs do
    %{
      id: "ps_test",
      citizen_slug: "clare",
      ticket_id: "T-2026-05-07-001",
      provider: "claude",
      backend: "direct_cli",
      workspace_ref: "citizen:clare",
      status: "active",
      last_error: nil,
      capabilities: %{},
      metadata: %{}
    }
  end
end
