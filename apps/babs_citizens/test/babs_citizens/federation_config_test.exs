defmodule Babs.Citizens.FederationConfigTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Federation.Config

  test "facade renders API node info and compact node summary" do
    toml = """
    [node]
    id = "node-local"
    name = "Local Babs"

    [peers.workbench]
    name = "Workbench Babs"
    url = "http://workbench.example"
    capabilities = ["write"]

    [peers.workbench.citizens.clare]
    capabilities = ["read"]
    """

    assert {:ok, info} = Babs.Citizens.Federation.node_info(toml: toml)
    assert info["node"]["capabilities"] == ["read"]

    assert info["peers"] == [
             %{
               "id" => "workbench",
               "name" => "Workbench Babs",
               "url" => "http://workbench.example",
               "capabilities" => ["read", "write"],
               "citizens" => %{"clare" => %{"capabilities" => ["read"]}}
             }
           ]

    assert {:ok, %{"id" => "node-local", "name" => "Local Babs"}} =
             Babs.Citizens.Federation.node_summary(toml: toml)
  end

  test "loads safe local defaults when no config path is supplied" do
    assert {:ok, config} = Config.load(path: nil)

    assert config.node.id == "local"
    assert config.node.name == "Local Babs"
    assert config.node.public_url == nil
    assert config.node.capabilities == ["read"]
    assert config.peers == []
  end

  test "normalizes node, peers, capability expansion, and citizen overrides" do
    toml = """
    [node]
    id = "node-local"
    name = "Local Babs"
    public_url = "http://babs-local.example:4000"

    [peers.workbench]
    name = "Workbench Babs"
    url = "https://babs-workbench.example"
    capabilities = ["control", "read"]

    [peers.workbench.citizens.dylan]
    capabilities = ["read"]
    """

    assert {:ok, config} = Config.load(toml: toml)

    assert config.node.id == "node-local"
    assert config.node.name == "Local Babs"
    assert config.node.public_url == "http://babs-local.example:4000"
    assert config.node.capabilities == ["read"]

    assert [peer] = config.peers
    assert peer.id == "workbench"
    assert peer.name == "Workbench Babs"
    assert peer.url == "https://babs-workbench.example"
    assert peer.capabilities == ["read", "write", "control"]
    assert peer.citizens == %{"dylan" => ["read"]}
  end

  test "renders peers in stable id order" do
    toml = """
    [node]
    id = "node-local"
    name = "Local Babs"

    [peers.zed]
    name = "Zed"
    url = "http://zed.example"
    capabilities = ["read"]

    [peers.alpha]
    name = "Alpha"
    url = "http://alpha.example"
    capabilities = ["write"]
    """

    assert {:ok, config} = Config.load(toml: toml)
    assert Enum.map(config.peers, & &1.id) == ["alpha", "zed"]
    assert hd(config.peers).capabilities == ["read", "write"]
  end

  test "rejects invalid ids, urls, and capabilities" do
    assert {:error, {:config_error, {:invalid_id, "node.id", "Node Local"}}} =
             Config.load(
               toml: """
               [node]
               id = "Node Local"
               name = "Local Babs"
               """
             )

    assert {:error, {:config_error, {:invalid_url, "peers.workbench.url", "ssh://host"}}} =
             Config.load(
               toml: """
               [node]
               id = "node-local"
               name = "Local Babs"

               [peers.workbench]
               name = "Workbench"
               url = "ssh://host"
               capabilities = ["read"]
               """
             )

    assert {:error,
            {:config_error, {:invalid_capability, "peers.workbench.capabilities", "admin"}}} =
             Config.load(
               toml: """
               [node]
               id = "node-local"
               name = "Local Babs"

               [peers.workbench]
               name = "Workbench"
               url = "http://workbench.example"
               capabilities = ["admin"]
               """
             )
  end

  test "rejects citizen overrides that are not inside a valid peer table" do
    assert {:error, {:config_error, {:missing_required, "peers.workbench.name"}}} =
             Config.load(
               toml: """
               [node]
               id = "node-local"
               name = "Local Babs"

               [peers.workbench.citizens.dylan]
               capabilities = ["read"]
               """
             )
  end

  test "returns an explicit config error for missing external files" do
    path = Path.join(System.tmp_dir!(), "babs-missing-federation-#{System.unique_integer()}.toml")

    assert {:error, {:config_error, {:read_failed, :enoent}}} = Config.load(path: path)
  end
end
