defmodule BabsWeb.UserSocketTest do
  use ExUnit.Case, async: false

  alias BabsWeb.UserSocket

  setup do
    original = Application.get_env(:babs, UserSocket)

    on_exit(fn ->
      if original do
        Application.put_env(:babs, UserSocket, original)
      else
        Application.delete_env(:babs, UserSocket)
      end
    end)
  end

  test "allows socket connections when no auth token is configured" do
    Application.put_env(:babs, UserSocket, auth_token: nil)

    assert {:ok, %Phoenix.Socket{}} = UserSocket.connect(%{}, %Phoenix.Socket{}, %{})
  end

  test "requires the configured socket auth token" do
    Application.put_env(:babs, UserSocket, auth_token: "secret")

    assert {:ok, %Phoenix.Socket{}} =
             UserSocket.connect(%{"token" => "secret"}, %Phoenix.Socket{}, %{})

    assert :error = UserSocket.connect(%{}, %Phoenix.Socket{}, %{})
    assert :error = UserSocket.connect(%{"token" => "wrong"}, %Phoenix.Socket{}, %{})
  end
end
