defmodule BabsWeb.TicketPath do
  @moduledoc """
  Centralized local URL generation for Ticket browser routes.
  """

  def index(socket_token \\ ""), do: with_query("/tickets", socket_token)

  def detail(id, socket_token \\ "") when is_binary(id) do
    with_query("/tickets/#{id}", socket_token)
  end

  defp with_query(path, socket_token) when is_binary(socket_token) do
    case String.trim(socket_token) do
      "" -> path
      token -> path <> "?" <> URI.encode_query(socket_token: token)
    end
  end

  defp with_query(path, _socket_token), do: path
end
