defmodule BabsWeb.CitizenPath do
  @moduledoc """
  Centralized local URL generation for Citizen browser routes.
  """

  def index(socket_token \\ ""), do: with_query("/citizens", socket_token)

  def new(socket_token \\ ""), do: with_query("/citizens/new", socket_token)

  def attach(socket_token \\ ""), do: with_query("/citizens/attach", socket_token)

  def terminal(slug, socket_token \\ "", opts \\ []) when is_binary(slug) do
    params =
      []
      |> maybe_put_full(Keyword.get(opts, :full?, false))
      |> maybe_put_socket_token(socket_token)

    with_query("/citizens/#{slug}", params)
  end

  defp with_query(path, socket_token) when is_binary(socket_token) do
    with_query(path, maybe_put_socket_token([], socket_token))
  end

  defp with_query(path, []), do: path

  defp with_query(path, params) when is_list(params) do
    path <> "?" <> URI.encode_query(params)
  end

  defp with_query(path, _socket_token), do: path

  defp maybe_put_full(params, true), do: params ++ [{"full", "1"}]
  defp maybe_put_full(params, _full), do: params

  defp maybe_put_socket_token(params, socket_token) when is_binary(socket_token) do
    case String.trim(socket_token) do
      "" -> params
      token -> params ++ [{"socket_token", token}]
    end
  end

  defp maybe_put_socket_token(params, _socket_token), do: params
end
