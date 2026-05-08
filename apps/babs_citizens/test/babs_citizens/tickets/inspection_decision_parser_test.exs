defmodule Babs.Citizens.Tickets.InspectionDecisionParserTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.InspectionDecisionParser

  test "parses a fenced approve decision with extra prose" do
    body = """
    I checked the work.

    ```json
    {
      "decision": "approve",
      "summary": "The acceptance criteria are met.",
      "findings": []
    }
    ```
    """

    assert {:ok,
            %{
              decision: "approve",
              summary: "The acceptance criteria are met.",
              findings: []
            }} = InspectionDecisionParser.parse(body)
  end

  test "parses whole-body reject json" do
    body =
      Jason.encode!(%{
        "decision" => "reject",
        "summary" => "Docs are missing.",
        "findings" => [%{"title" => "Missing docs", "severity" => "P2"}]
      })

    assert {:ok, parsed} = InspectionDecisionParser.parse(body)
    assert parsed.decision == "reject"
    assert parsed.summary == "Docs are missing."
    assert parsed.findings == [%{"title" => "Missing docs", "severity" => "P2"}]
  end

  test "accepts needs_changes as a distinct decision" do
    body =
      Jason.encode!(%{
        "decision" => "needs_changes",
        "summary" => "Tests need one more case.",
        "findings" => []
      })

    assert {:ok, %{decision: "needs_changes"}} = InspectionDecisionParser.parse(body)
  end

  test "rejects malformed json" do
    assert {:error, {:unparseable, _reason}} = InspectionDecisionParser.parse("not json")
  end

  test "rejects missing summary" do
    body = Jason.encode!(%{"decision" => "approve", "findings" => []})

    assert {:error, {:missing_summary, _value}} = InspectionDecisionParser.parse(body)
  end

  test "rejects invalid findings" do
    body =
      Jason.encode!(%{
        "decision" => "approve",
        "summary" => "Looks fine.",
        "findings" => ["not a map"]
      })

    assert {:error, {:invalid_findings, ["not a map"]}} =
             InspectionDecisionParser.parse(body)
  end

  test "rejects unknown decisions" do
    body =
      Jason.encode!(%{
        "decision" => "maybe",
        "summary" => "Cannot decide.",
        "findings" => []
      })

    assert {:error, {:invalid_decision, "maybe"}} = InspectionDecisionParser.parse(body)
  end
end
