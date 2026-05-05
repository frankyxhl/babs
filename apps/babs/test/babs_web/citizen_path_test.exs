defmodule BabsWeb.CitizenPathTest do
  use ExUnit.Case, async: true

  alias BabsWeb.CitizenPath

  test "builds index and new citizen URLs with optional socket token" do
    assert CitizenPath.index() == "/citizens"
    assert CitizenPath.index("socket token") == "/citizens?socket_token=socket+token"

    assert CitizenPath.new() == "/citizens/new"
    assert CitizenPath.new("socket token") == "/citizens/new?socket_token=socket+token"
    assert CitizenPath.index(%{"nested" => "token"}) == "/citizens"
    assert CitizenPath.new(%{"nested" => "token"}) == "/citizens/new"
  end

  test "builds terminal URLs with optional full mode and socket token" do
    assert CitizenPath.terminal("clare") == "/citizens/clare"

    assert CitizenPath.terminal("clare", "socket-token") ==
             "/citizens/clare?socket_token=socket-token"

    assert CitizenPath.terminal("clare", "", full?: true) == "/citizens/clare?full=1"

    assert CitizenPath.terminal("clare", "socket token", full?: true) ==
             "/citizens/clare?full=1&socket_token=socket+token"
  end
end
