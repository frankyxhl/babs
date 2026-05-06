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
  end
end
