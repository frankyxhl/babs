defmodule Babs.Citizens.SqliteJsonTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.SqliteJson

  test "dumps and loads normalized JSON values" do
    assert {:ok, encoded} = SqliteJson.dump(%{role: %{name: "developer"}, skills: ["elixir"]})
    assert {:ok, decoded} = SqliteJson.load(encoded)

    assert decoded == %{
             "role" => %{"name" => "developer"},
             "skills" => ["elixir"]
           }
  end

  test "passes nil through as a nullable JSON value" do
    assert {:ok, nil} = SqliteJson.cast(nil)
    assert {:ok, nil} = SqliteJson.dump(nil)
    assert {:ok, nil} = SqliteJson.load(nil)
  end

  test "rejects non-json terms and malformed encoded values" do
    assert :error = SqliteJson.cast({:tuple, :is_not_json})
    assert :error = SqliteJson.dump(%{1 => "non-string key"})
    assert :error = SqliteJson.load("not-json")
    assert :error = SqliteJson.load(123)
  end
end
