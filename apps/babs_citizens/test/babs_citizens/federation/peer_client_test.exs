defmodule Babs.Citizens.Federation.PeerClientTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Federation.PeerClient

  @now ~U[2026-05-09 00:00:00Z]

  test "fetches the first configured peer in sorted id order" do
    {:ok, calls} = Agent.start_link(fn -> [] end)

    http = fn url, _opts ->
      Agent.update(calls, &[url | &1])
      {:ok, %{status: 200, body: Jason.encode!(response_for(url))}}
    end

    assert {:ok, snapshot} =
             PeerClient.fetch_first_peer(
               toml: """
               [node]
               id = "local"
               name = "Local"

               [peers.zed]
               name = "Zed"
               url = "http://zed.example"
               capabilities = ["read"]

               [peers.alpha]
               name = "Alpha"
               url = "http://alpha.example"
               capabilities = ["write"]
               """,
               http_client: http,
               now: @now
             )

    assert snapshot.peer_id == "alpha"
    assert snapshot.peer_name == "Alpha"
    assert snapshot.status == :fresh
    assert snapshot.read_only?
    assert snapshot.capabilities == ["read", "write"]
    assert snapshot.node == %{"id" => "alpha", "name" => "Alpha"}
    assert [%{"slug" => "remote-clare"}] = snapshot.citizens
    assert [%{"id" => "T-2026-05-09-001"}] = snapshot.tickets
    assert snapshot.cursor == "cursor-1"

    assert calls
           |> Agent.get(&Enum.reverse/1)
           |> Enum.all?(&String.starts_with?(&1, "http://alpha.example/"))
  end

  test "returns nil when no peers are configured" do
    assert {:ok, nil} =
             PeerClient.fetch_first_peer(
               toml: """
               [node]
               id = "local"
               name = "Local"
               """
             )
  end

  test "uses the previous event cursor on refresh" do
    {:ok, calls} = Agent.start_link(fn -> [] end)

    previous = %{
      peer_id: "alpha",
      fetched_at: @now,
      cursor: "cursor-previous"
    }

    http = fn url, _opts ->
      Agent.update(calls, &[url | &1])
      {:ok, %{status: 200, body: Jason.encode!(response_for(url))}}
    end

    assert {:ok, snapshot} =
             PeerClient.fetch_first_peer(
               toml: peer_toml(),
               http_client: http,
               previous_snapshot: previous,
               now: @now
             )

    assert snapshot.cursor == "cursor-next"

    assert calls
           |> Agent.get(&Enum.reverse/1)
           |> List.last() == "http://alpha.example/api/v1/events?cursor=cursor-previous"
  end

  test "retries event feed without cursor when the previous cursor is rejected" do
    {:ok, calls} = Agent.start_link(fn -> [] end)

    previous = %{
      peer_id: "alpha",
      fetched_at: @now,
      cursor: "bad-cursor"
    }

    http = fn url, _opts ->
      Agent.update(calls, &[url | &1])

      case url do
        "http://alpha.example/api/v1/events?cursor=bad-cursor" ->
          {:ok,
           %{
             status: 400,
             body:
               Jason.encode!(%{
                 "error" => %{"code" => "invalid_cursor", "message" => "Event cursor is invalid"}
               })
           }}

        _url ->
          {:ok, %{status: 200, body: Jason.encode!(response_for(url))}}
      end
    end

    assert {:ok, snapshot} =
             PeerClient.fetch_first_peer(
               toml: peer_toml(),
               http_client: http,
               previous_snapshot: previous,
               now: @now
             )

    assert snapshot.status == :fresh
    assert snapshot.cursor == "cursor-1"

    assert calls
           |> Agent.get(&Enum.reverse/1)
           |> Enum.take(-2) == [
             "http://alpha.example/api/v1/events?cursor=bad-cursor",
             "http://alpha.example/api/v1/events"
           ]
  end

  test "unreachable and malformed peer responses return explicit status without crashing" do
    http_error = fn _url, _opts -> {:error, :econnrefused} end

    assert {:ok, unreachable} =
             PeerClient.fetch_first_peer(toml: peer_toml(), http_client: http_error, now: @now)

    assert unreachable.status == :unreachable
    assert unreachable.peer_id == "alpha"
    assert unreachable.error =~ "econnrefused"

    bad_json = fn _url, _opts -> {:ok, %{status: 200, body: "not json"}} end

    assert {:ok, malformed} =
             PeerClient.fetch_first_peer(toml: peer_toml(), http_client: bad_json, now: @now)

    assert malformed.status == :unreachable
  end

  test "missing peer response keys return explicit status without hiding remote state as empty" do
    missing_citizens = fn
      "http://alpha.example/api/v1/citizens", _opts ->
        {:ok, %{status: 200, body: Jason.encode!(%{})}}

      url, _opts ->
        {:ok, %{status: 200, body: Jason.encode!(response_for(url))}}
    end

    assert {:ok, malformed} =
             PeerClient.fetch_first_peer(
               toml: peer_toml(),
               http_client: missing_citizens,
               now: @now
             )

    assert malformed.status == :unreachable
    assert malformed.citizens == []
    assert malformed.error =~ "invalid_citizens_response"
  end

  test "failed fetch can fall back to a stale previous snapshot" do
    previous = %{
      peer_id: "alpha",
      peer_name: "Alpha",
      peer_url: "http://alpha.example",
      status: :fresh,
      read_only?: true,
      capabilities: ["read"],
      fetched_at: @now,
      node: %{"id" => "alpha", "name" => "Alpha"},
      citizens: [%{"slug" => "remote-clare"}],
      tickets: [%{"id" => "T-2026-05-09-001"}],
      invalid: %{"count" => 0},
      events: [],
      cursor: "cursor-1"
    }

    http_error = fn _url, _opts -> {:error, :timeout} end
    stale_now = DateTime.add(@now, 15_001, :millisecond)

    assert {:ok, snapshot} =
             PeerClient.fetch_first_peer(
               toml: peer_toml(),
               http_client: http_error,
               now: stale_now,
               previous_snapshot: previous
             )

    assert snapshot.status == :stale
    assert snapshot.citizens == previous.citizens
    assert snapshot.tickets == previous.tickets
    assert snapshot.error =~ "timeout"
  end

  test "freshness status treats the exact freshness window boundary as fresh" do
    fetched_at = ~U[2026-05-09 00:00:00Z]
    at_boundary = ~U[2026-05-09 00:00:15Z]
    after_boundary = ~U[2026-05-09 00:00:15.001Z]

    assert PeerClient.freshness_status(fetched_at, at_boundary, 15_000) == :fresh
    assert PeerClient.freshness_status(fetched_at, after_boundary, 15_000) == :stale
    assert PeerClient.freshness_status(nil, at_boundary, 15_000) == :unreachable
  end

  defp peer_toml do
    """
    [node]
    id = "local"
    name = "Local"

    [peers.alpha]
    name = "Alpha"
    url = "http://alpha.example"
    capabilities = ["read"]
    """
  end

  defp response_for("http://alpha.example/api/v1/node") do
    %{"node" => %{"id" => "alpha", "name" => "Alpha"}}
  end

  defp response_for("http://alpha.example/api/v1/citizens") do
    %{"citizens" => [%{"slug" => "remote-clare"}]}
  end

  defp response_for("http://alpha.example/api/v1/tickets") do
    %{"tickets" => [%{"id" => "T-2026-05-09-001"}], "invalid" => %{"count" => 0}}
  end

  defp response_for("http://alpha.example/api/v1/events") do
    %{"cursor" => "cursor-1", "events" => []}
  end

  defp response_for("http://alpha.example/api/v1/events?cursor=cursor-previous") do
    %{"cursor" => "cursor-next", "events" => []}
  end
end
