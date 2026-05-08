defmodule BabsWeb.Api.V1.EventFeed do
  @moduledoc false

  alias Babs.Citizens.{Federation, StatusSnapshot}
  alias Babs.Citizens.Tickets.{Api, Config}
  alias BabsWeb.Api.V1.Presenter

  @snapshot_keys ["node", "citizens", "tickets"]

  def build(opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now(:second) end)

    with {:ok, previous_hashes} <- decode_cursor(cursor),
         {:ok, info} <- Federation.node_info(),
         {:ok, snapshots} <- snapshots(info),
         hashes <- snapshot_hashes(snapshots),
         cursor <- encode_cursor(hashes) do
      {:ok,
       %{
         "node" => Presenter.node_summary(info),
         "cursor" => cursor,
         "events" => events(info, snapshots, hashes, previous_hashes, now)
       }}
    end
  end

  def encode_cursor(hashes) when is_map(hashes) do
    %{"v" => 1, "hashes" => Map.take(hashes, @snapshot_keys)}
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  def decode_cursor(cursor) when cursor in [nil, ""], do: {:ok, %{}}

  def decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, %{"v" => 1, "hashes" => hashes}} when is_map(hashes) <- Jason.decode(json),
         true <-
           Enum.all?(hashes, fn {key, value} -> key in @snapshot_keys and is_binary(value) end) do
      {:ok, Map.take(hashes, @snapshot_keys)}
    else
      _reason -> {:error, :invalid_cursor}
    end
  end

  def decode_cursor(_cursor), do: {:error, :invalid_cursor}

  defp snapshots(info) do
    with :ok <- ensure_ticket_root_readable(),
         {:ok, %{tickets: tickets, invalid: invalid}} <- Api.list_tickets() do
      {:ok,
       %{
         "node" => %{
           "node" => Map.take(info["node"], ["id", "name", "public_url"])
         },
         "citizens" => %{
           "citizens" =>
             StatusSnapshot.list(include_stale?: true)
             |> Enum.map(&Presenter.citizen_projection/1)
         },
         "tickets" => %{
           "tickets" => Enum.map(tickets, &Presenter.ticket_summary/1),
           "invalid" => %{"count" => length(invalid)}
         }
       }}
    end
  end

  defp ensure_ticket_root_readable do
    root = Config.tickets_root()

    case File.stat(root) do
      {:ok, %{type: :directory}} ->
        case File.ls(root) do
          {:ok, _entries} -> :ok
          {:error, reason} -> {:error, {:read_failed, reason}}
        end

      {:error, :enoent} ->
        :ok

      {:ok, _stat} ->
        {:error, {:read_failed, :not_directory}}

      {:error, reason} ->
        {:error, {:read_failed, reason}}
    end
  end

  defp snapshot_hashes(snapshots) do
    Map.new(@snapshot_keys, fn key -> {key, content_hash(Map.fetch!(snapshots, key))} end)
  end

  defp content_hash(payload) do
    :crypto.hash(:sha256, canonical_json(payload))
    |> Base.encode16(case: :lower)
  end

  defp events(info, snapshots, hashes, previous_hashes, now) do
    node_id = info["node"]["id"]
    occurred_at = DateTime.to_iso8601(now)

    @snapshot_keys
    |> Enum.filter(&(Map.get(previous_hashes, &1) != Map.fetch!(hashes, &1)))
    |> Enum.map(fn key ->
      %{
        "id" => "#{node_id}:#{key}:#{Map.fetch!(hashes, key)}",
        "type" => "#{key}.snapshot",
        "occurred_at" => occurred_at,
        "payload" => Map.fetch!(snapshots, key)
      }
    end)
  end

  defp canonical_json(value) when is_map(value) do
    entries =
      value
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, entry_value} ->
        [Jason.encode!(to_string(key)), ?:, canonical_json(entry_value)]
      end)

    [?{, Enum.intersperse(entries, ?,), ?}]
  end

  defp canonical_json(value) when is_list(value) do
    [?[, value |> Enum.map(&canonical_json/1) |> Enum.intersperse(?,), ?]]
  end

  defp canonical_json(value), do: Jason.encode!(value)
end
