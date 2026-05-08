defmodule Babs.Citizens.FederationControlGuardTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Federation.ControlGuard

  test "authorizes write peers and returns a remote actor" do
    assert {:ok, auth} = ControlGuard.authorize("workbench", "write", toml: toml())

    assert auth.peer_id == "workbench"
    assert auth.peer_name == "Workbench"
    assert auth.capability == "write"
    assert auth.actor == "remote:workbench"
  end

  test "denies read-only peers without leaking peer URLs" do
    assert {:error, error} = ControlGuard.authorize("viewer", "write", toml: toml())

    assert error.status == 403
    assert error.code == "remote_capability_forbidden"
    assert error.reason_code == "capability_forbidden"
    refute inspect(error) =~ "example"
  end

  test "applies per-citizen capability overrides to control actions" do
    assert {:ok, auth} =
             ControlGuard.authorize_citizen("workbench", "dylan", "control", toml: toml())

    assert auth.target_slug == "dylan"

    assert {:error, error} =
             ControlGuard.authorize_citizen("workbench", "clare", "control", toml: toml())

    assert error.status == 403
    assert error.code == "remote_capability_forbidden"
    assert error.target_slug == "clare"
  end

  test "requires a configured peer id" do
    assert {:error, missing} = ControlGuard.authorize(nil, "write", toml: toml())
    assert missing.status == 403
    assert missing.code == "missing_peer_id"

    assert {:error, unknown} = ControlGuard.authorize("unknown", "write", toml: toml())
    assert unknown.status == 403
    assert unknown.code == "remote_peer_forbidden"
  end

  defp toml do
    """
    [node]
    id = "local"
    name = "Local"

    [peers.workbench]
    name = "Workbench"
    url = "http://workbench.example"
    capabilities = ["control"]

    [peers.workbench.citizens.clare]
    capabilities = ["read"]

    [peers.viewer]
    name = "Viewer"
    url = "http://viewer.example"
    capabilities = ["read"]
    """
  end
end
