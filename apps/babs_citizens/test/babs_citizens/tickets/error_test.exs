defmodule Babs.Citizens.Tickets.ErrorTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.Error

  test "renders redacted IO errors without host paths or raw reasons" do
    message = Error.message({:redacted_io_error, {:read_ticket, {:eacces, "/private/path"}}})

    assert message == "Ticket IO failed during read_ticket"
    refute message =~ "/private/path"
    refute message =~ "eacces"
  end

  test "renders stable typed ticket errors" do
    assert Error.message({:not_found, "T-2026-05-06-001"}) ==
             "Ticket T-2026-05-06-001 was not found"

    assert Error.message({:write_conflict, "T-2026-05-06-001"}) =~
             "changed while Babs was writing"

    assert Error.message({:invalid_transition, "pending_approval", "open"}) ==
             "Invalid Ticket transition: pending_approval -> open"

    assert Error.message({:invalid_slug, ""}) == "Invalid Citizen slug: \"\""
    assert Error.message({:unknown_citizen, "ghost"}) == "Unknown Citizen: ghost"

    assert Error.message({:citizen_start_failed, "clare", "raw credential value"}) ==
             "Citizen clare could not be started"

    assert Error.message({:citizen_lookup_failed, "clare", "raw credential value"}) ==
             "Citizen clare pane lookup failed"

    assert Error.message({:ticket_injection_failed, "clare", "raw credential value"}) ==
             "Ticket prompt could not be injected into clare"
  end
end
