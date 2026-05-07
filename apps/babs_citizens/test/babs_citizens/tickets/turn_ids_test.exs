defmodule Babs.Citizens.Tickets.TurnIdsTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.TurnIds

  test "generates sortable ids with the documented prefix timestamp and suffix format" do
    assert TurnIds.generate!(:turn, "2026-05-07T01:02:03Z", suffix: "abc123def0") ==
             "turn_20260507010203_abc123def0"

    assert TurnIds.generate!(:message, "2026-05-07T01:02:03Z", suffix: "abc123def0") ==
             "msg_20260507010203_abc123def0"

    assert TurnIds.generate!(:attempt, "2026-05-07T01:02:03Z", suffix: "abc123def0") ==
             "attempt_20260507010203_abc123def0"
  end

  test "random ids use safe characters and sort by timestamp prefix" do
    early = TurnIds.generate!(:turn, "2026-05-07T01:02:03Z")
    later = TurnIds.generate!(:turn, "2026-05-07T01:02:04Z")

    assert early =~ ~r/\Aturn_20260507010203_[a-z0-9]{10}\z/
    assert later =~ ~r/\Aturn_20260507010204_[a-z0-9]{10}\z/
    assert early < later
  end
end
