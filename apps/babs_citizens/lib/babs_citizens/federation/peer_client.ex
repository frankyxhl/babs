defmodule Babs.Citizens.Federation.PeerClient do
  @moduledoc """
  HTTP client for configured Babs peers.

  Read helpers build remote snapshots for federation UI. Mutating helpers send
  capability-gated operator requests to the receiving node.
  """

  alias Babs.Citizens.Federation.Config
  alias Babs.Citizens.Federation.HttpcClient

  @default_timeout_ms 1_500
  @default_freshness_ms 15_000

  def fetch_first_peer(opts \\ []) do
    case Config.load(opts) do
      {:ok, %{peers: []}} ->
        {:ok, nil}

      {:ok, %{peers: [peer | _rest]}} ->
        fetch_peer(peer, opts)

      {:error, {:config_error, reason}} ->
        {:ok, error_snapshot(:config_error, reason, opts)}
    end
  end

  def fetch_peer(peer, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now(:second) end)

    with {:ok, node} <- get_json(peer, "/api/v1/node", opts),
         {:ok, node} <- node_payload(node),
         {:ok, citizens} <- get_json(peer, "/api/v1/citizens", opts),
         {:ok, citizens} <- citizens_payload(citizens),
         {:ok, tickets} <- get_json(peer, "/api/v1/tickets", opts),
         {:ok, tickets, invalid} <- tickets_payload(tickets),
         {:ok, events} <- get_events(peer, opts),
         {:ok, events, cursor} <- events_payload(events) do
      {:ok,
       %{
         peer_id: peer.id,
         peer_name: peer.name,
         peer_url: peer.url,
         status: :fresh,
         read_only?: read_only?(peer),
         capabilities: peer.capabilities,
         citizen_capabilities: peer.citizens,
         fetched_at: now,
         node: node,
         citizens: citizens,
         tickets: tickets,
         invalid: invalid,
         events: events,
         cursor: cursor
       }}
    else
      {:error, reason} ->
        {:ok, fallback_snapshot(peer, reason, now, opts)}
    end
  end

  def comment_ticket(peer, id, body, opts \\ []) when is_binary(id) and is_binary(body) do
    post_json(peer, "/api/v1/tickets/#{path_segment(id)}/comments", %{"body" => body}, opts)
  end

  def transition_ticket(peer, id, to_state, opts \\ [])
      when is_binary(id) and is_binary(to_state) do
    post_json(
      peer,
      "/api/v1/tickets/#{path_segment(id)}/transitions",
      %{"to" => to_state},
      opts
    )
  end

  def assign_ticket(peer, id, slug, opts \\ [])
      when is_binary(id) and is_binary(slug) do
    post_json(
      peer,
      "/api/v1/tickets/#{path_segment(id)}/assignments",
      %{"slug" => slug},
      opts
    )
  end

  def unassign_ticket(peer, id, slug, opts \\ [])
      when is_binary(id) and is_binary(slug) do
    delete_json(
      peer,
      "/api/v1/tickets/#{path_segment(id)}/assignments/#{path_segment(slug)}",
      opts
    )
  end

  def inject_citizen(peer, slug, data, opts \\ []) when is_binary(slug) and is_binary(data) do
    post_json(
      peer,
      "/api/v1/citizens/#{path_segment(slug)}/injections",
      %{"data" => data},
      opts
    )
  end

  def lifecycle_citizen(peer, slug, action, opts \\ [])
      when is_binary(slug) and is_binary(action) do
    post_json(
      peer,
      "/api/v1/citizens/#{path_segment(slug)}/lifecycle",
      %{"action" => action},
      opts
    )
  end

  defp node_payload(%{"node" => node}) when is_map(node), do: {:ok, node}
  defp node_payload(_response), do: {:error, :invalid_node_response}

  defp citizens_payload(%{"citizens" => citizens}) when is_list(citizens), do: {:ok, citizens}
  defp citizens_payload(_response), do: {:error, :invalid_citizens_response}

  defp tickets_payload(%{"tickets" => tickets, "invalid" => invalid})
       when is_list(tickets) and is_map(invalid) do
    {:ok, tickets, invalid}
  end

  defp tickets_payload(_response), do: {:error, :invalid_tickets_response}

  defp events_payload(%{"events" => events, "cursor" => cursor})
       when is_list(events) and is_binary(cursor) do
    {:ok, events, cursor}
  end

  defp events_payload(_response), do: {:error, :invalid_events_response}

  def freshness_status(fetched_at, now, freshness_ms \\ @default_freshness_ms)

  def freshness_status(%DateTime{} = fetched_at, %DateTime{} = now, freshness_ms) do
    if DateTime.diff(now, fetched_at, :millisecond) <= freshness_ms do
      :fresh
    else
      :stale
    end
  end

  def freshness_status(_fetched_at, _now, _freshness_ms), do: :unreachable

  defp events_path(opts) do
    case Keyword.get(opts, :cursor) || previous_cursor(Keyword.get(opts, :previous_snapshot)) do
      cursor when is_binary(cursor) and cursor != "" ->
        "/api/v1/events?cursor=#{URI.encode_www_form(cursor)}"

      _cursor ->
        "/api/v1/events"
    end
  end

  defp get_events(peer, opts) do
    case get_json(peer, events_path(opts), opts) do
      {:error, {:http_status, 400, "invalid_cursor"}} -> get_json(peer, "/api/v1/events", opts)
      result -> result
    end
  end

  defp previous_cursor(previous) when is_map(previous) do
    Map.get(previous, :cursor) || Map.get(previous, "cursor")
  end

  defp previous_cursor(_previous), do: nil

  defp get_json(peer, path, opts) do
    url = peer_url(peer) |> String.trim_trailing("/") |> Kernel.<>(path)
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)

    with {:ok, %{status: status, body: body}} <-
           http_get(http_client(opts), url, timeout: timeout) do
      if status >= 200 and status < 300 do
        case Jason.decode(body) do
          {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
          {:ok, _decoded} -> {:error, :invalid_json_shape}
          {:error, _reason} -> {:error, :invalid_json}
        end
      else
        {:error, http_status_error(status, body)}
      end
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_http_response}
    end
  end

  defp post_json(peer, path, payload, opts) do
    with {:ok, body} <- Jason.encode(payload) do
      request_json(peer, :post, path, body, opts)
    end
  end

  defp delete_json(peer, path, opts) do
    request_json(peer, :delete, path, "", opts)
  end

  defp request_json(peer, method, path, body, opts) do
    url = peer_url(peer) |> String.trim_trailing("/") |> Kernel.<>(path)
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)

    with {:ok, headers} <- request_headers(opts),
         {:ok, %{status: status, body: response_body}} <-
           http_request(http_client(opts), method, url, headers, body, timeout: timeout) do
      if status >= 200 and status < 300 do
        case Jason.decode(response_body) do
          {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
          {:ok, _decoded} -> {:error, :invalid_json_shape}
          {:error, _reason} -> {:error, :invalid_json}
        end
      else
        {:error, http_status_error(status, response_body)}
      end
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_http_response}
    end
  end

  defp request_headers(opts) do
    case Config.load(opts) do
      {:ok, %{node: %{id: id}}} ->
        {:ok,
         [
           {"accept", "application/json"},
           {"content-type", "application/json"},
           {"x-babs-peer-id", id}
         ]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_status_error(status, body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"code" => code}}} when is_binary(code) ->
        {:http_status, status, code}

      _other ->
        {:http_status, status}
    end
  end

  defp http_client(opts) do
    Keyword.get(
      opts,
      :http_client,
      Application.get_env(:babs_citizens, :federation_http_client, HttpcClient)
    )
  end

  defp http_get(client, url, opts) when is_function(client, 2), do: client.(url, opts)
  defp http_get(client, url, opts) when is_atom(client), do: client.get(url, opts)

  defp http_request(client, method, url, headers, body, opts) when is_function(client, 5),
    do: client.(method, url, headers, body, opts)

  defp http_request(client, method, url, headers, body, opts) when is_atom(client),
    do: client.request(method, url, headers, body, opts)

  defp fallback_snapshot(peer, reason, now, opts) do
    previous = Keyword.get(opts, :previous_snapshot)

    if previous_peer_id(previous) == peer.id and Map.get(previous, :fetched_at) do
      status =
        previous
        |> Map.get(:fetched_at)
        |> freshness_status(now, Keyword.get(opts, :freshness_ms, @default_freshness_ms))

      previous
      |> Map.put(:status, status)
      |> Map.put(:error, redacted_error(reason))
    else
      unreachable_snapshot(peer, reason)
    end
  end

  defp previous_peer_id(previous) when is_map(previous) do
    Map.get(previous, :peer_id) || Map.get(previous, "peer_id")
  end

  defp previous_peer_id(_previous), do: nil

  defp unreachable_snapshot(peer, reason) do
    %{
      peer_id: peer.id,
      peer_name: peer.name,
      peer_url: peer.url,
      status: :unreachable,
      read_only?: read_only?(peer),
      capabilities: peer.capabilities,
      citizen_capabilities: peer.citizens,
      fetched_at: nil,
      node: %{"id" => peer.id, "name" => peer.name},
      citizens: [],
      tickets: [],
      invalid: %{"count" => 0},
      events: [],
      cursor: nil,
      error: redacted_error(reason)
    }
  end

  defp read_only?(peer) do
    not Enum.any?(peer.capabilities, &(&1 in ["write", "control"]))
  end

  defp path_segment(value), do: URI.encode(value, &URI.char_unreserved?/1)

  defp error_snapshot(status, reason, opts) do
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now(:second) end)

    %{
      peer_id: nil,
      peer_name: nil,
      peer_url: nil,
      status: status,
      read_only?: true,
      capabilities: [],
      citizen_capabilities: %{},
      fetched_at: now,
      node: %{},
      citizens: [],
      tickets: [],
      invalid: %{"count" => 0},
      events: [],
      cursor: nil,
      error: redacted_error(reason)
    }
  end

  defp redacted_error(reason) do
    reason
    |> inspect()
    |> String.slice(0, 200)
  end

  defp peer_url(peer) when is_map(peer) do
    Map.get(peer, :url) || Map.get(peer, :peer_url) || Map.get(peer, "url") ||
      Map.get(peer, "peer_url")
  end
end
