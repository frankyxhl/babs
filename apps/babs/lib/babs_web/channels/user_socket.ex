defmodule BabsWeb.UserSocket do
  @moduledoc false

  use Phoenix.Socket

  channel("pane:*", BabsWeb.PaneChannel)

  @impl true
  def connect(params, socket, _connect_info) do
    if authorized?(Map.get(params, "token")) do
      {:ok, socket}
    else
      :error
    end
  end

  @impl true
  def id(_socket), do: nil

  defp authorized?(token) do
    case auth_token() do
      nil -> true
      expected -> secure_equal?(token, expected)
    end
  end

  defp auth_token do
    :babs
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:auth_token)
    |> normalize_token()
  end

  defp normalize_token(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_token(_value), do: nil

  defp secure_equal?(token, expected)
       when is_binary(token) and byte_size(token) == byte_size(expected) do
    Plug.Crypto.secure_compare(token, expected)
  end

  defp secure_equal?(_token, _expected), do: false
end
