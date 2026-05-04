defmodule Mix.Tasks.Hardline.ValidateTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Hardline.Validate

  test "exit status is zero only for a complete pass" do
    assert Validate.exit_status(%{status: "PASS"}) == 0
    assert Validate.exit_status(%{status: "FAIL"}) == 1
    assert Validate.exit_status(%{status: "INCOMPLETE"}) == 1
  end
end
