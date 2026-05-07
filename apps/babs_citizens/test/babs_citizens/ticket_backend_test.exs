defmodule Babs.Citizens.TicketBackendTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.TicketBackend

  test "browser creation only exposes hardline and direct CLI" do
    options = TicketBackend.browser_create_options()

    assert Enum.map(options, & &1.value) == ["hardline", "direct_cli"]
    assert Enum.map(options, & &1.label) == ["Hardline", "Direct CLI"]
    assert TicketBackend.browser_creatable?("hardline")
    assert TicketBackend.browser_creatable?("direct_cli")
    refute TicketBackend.browser_creatable?("lazy_tmux")
  end

  test "labels and assignment hints are stable for known backends" do
    assert TicketBackend.label("hardline") == "Hardline"
    assert TicketBackend.label("direct_cli") == "Direct CLI"
    assert TicketBackend.label("lazy_tmux") == "Lazy tmux"
    assert TicketBackend.label("unknown") == "Hardline"

    assert TicketBackend.assign_hint("hardline") == "starts tmux if stopped"
    assert TicketBackend.assign_hint("direct_cli") == "no tmux start"
    assert TicketBackend.assign_hint("lazy_tmux") == "opens tmux only when needed"
    assert TicketBackend.assign_hint("unknown") == "starts tmux if stopped"
  end
end
