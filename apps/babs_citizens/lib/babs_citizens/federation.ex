defmodule Babs.Citizens.Federation do
  @moduledoc """
  Read facade for local-node federation state.
  """

  alias Babs.Citizens.Federation.Config

  def config(opts \\ []) do
    Config.load(opts)
  end

  def node_info(opts \\ []) do
    with {:ok, config} <- config(opts) do
      {:ok,
       %{
         "node" => node_map(config.node),
         "peers" => Enum.map(config.peers, &peer_map/1)
       }}
    end
  end

  def node_summary(opts \\ []) do
    with {:ok, %{"node" => node}} <- node_info(opts) do
      {:ok, Map.take(node, ["id", "name"])}
    end
  end

  defp node_map(node) do
    %{
      "id" => node.id,
      "name" => node.name,
      "public_url" => node.public_url,
      "capabilities" => node.capabilities,
      "api_version" => "v1"
    }
  end

  defp peer_map(peer) do
    %{
      "id" => peer.id,
      "name" => peer.name,
      "url" => peer.url,
      "capabilities" => peer.capabilities,
      "citizens" => citizen_overrides(peer.citizens)
    }
  end

  defp citizen_overrides(citizens) do
    citizens
    |> Enum.sort_by(fn {slug, _capabilities} -> slug end)
    |> Map.new(fn {slug, capabilities} -> {slug, %{"capabilities" => capabilities}} end)
  end
end
