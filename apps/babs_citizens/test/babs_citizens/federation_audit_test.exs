defmodule Babs.Citizens.FederationAuditTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Federation.Audit
  alias Babs.Citizens.Federation.ControlGuard

  @now ~U[2026-05-09 01:00:00Z]

  setup do
    root = tmp_root!()

    on_exit(fn -> File.rm_rf!(root) end)

    %{root: root}
  end

  test "appends redacted success records under the runtime var area", %{root: root} do
    assert {:ok, auth} =
             ControlGuard.authorize("workbench", "control",
               toml: """
               [node]
               id = "local"
               name = "Local"

               [peers.workbench]
               name = "Workbench"
               url = "http://workbench.example"
               capabilities = ["control"]
               """
             )

    assert :ok =
             Audit.success(
               auth,
               %{
                 action: "citizen.inject",
                 target_type: "citizen",
                 target_id: "clare",
                 result: "ok",
                 data: "must not be logged"
               },
               root: root,
               now: @now
             )

    [record] = records!(root)

    assert record == %{
             "ts" => "2026-05-09T01:00:00Z",
             "peer_id" => "workbench",
             "action" => "citizen.inject",
             "target_type" => "citizen",
             "target_id" => "clare",
             "result" => "ok",
             "capability" => "control"
           }
  end

  test "appends denied records without raw request payloads", %{root: root} do
    assert :ok =
             Audit.denied(
               %{
                 peer_id: "viewer",
                 action: "ticket.comment",
                 target_type: "ticket",
                 target_id: "T-2026-05-09-001",
                 reason_code: "capability_forbidden",
                 body: "must not be logged"
               },
               root: root,
               now: @now
             )

    [record] = records!(root)

    assert record == %{
             "ts" => "2026-05-09T01:00:00Z",
             "peer_id" => "viewer",
             "action" => "ticket.comment",
             "target_type" => "ticket",
             "target_id" => "T-2026-05-09-001",
             "result" => "denied",
             "reason_code" => "capability_forbidden"
           }
  end

  defp records!(root) do
    root
    |> Path.join("var/federation_audit.jsonl")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
  end

  defp tmp_root! do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-federation-audit-test-#{System.system_time(:nanosecond)}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end
end
