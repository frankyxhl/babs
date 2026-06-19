defmodule Babs.Citizens.Tickets.ReplyCapture do
  @moduledoc """
  Captures matched AI CLI replies into Ticket history.

  Capture polling is best effort. If this GenServer restarts, in-flight capture
  turns are intentionally lost rather than replayed from stale delivery state.
  """

  use GenServer

  alias Babs.Citizens.AiTranscripts
  alias Babs.Citizens.{Catalog, CitizenRecord, Runner}
  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.History

  @interval_ms 5_000
  @window_ms 30 * 60 * 1_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def track(turn, opts \\ []) when is_map(turn) do
    if enabled?() do
      case GenServer.whereis(__MODULE__) do
        nil -> :unavailable
        _pid -> GenServer.cast(__MODULE__, {:track, normalize_turn(turn, opts)})
      end
    else
      :disabled
    end
  end

  def enabled? do
    env_enabled? =
      case System.get_env("BABS_AI_REPLY_CAPTURE") do
        nil -> true
        value when value in ["0", "false", "FALSE", "off", "OFF"] -> false
        _value -> true
      end

    env_enabled? and Application.get_env(:babs_citizens, :ai_reply_capture_enabled, true)
  end

  def capture_once(turn, opts \\ []) when is_map(turn) do
    turn = normalize_turn(turn, opts)

    with true <- Keyword.get(opts, :enabled, enabled?()),
         {:ok, config} <- citizen_config(turn, opts),
         true <- Runner.ai_cli?(config) do
      adapter = Keyword.get(opts, :adapter, AiTranscripts)

      case adapter.find_reply(config, turn.ticket_id, turn.started_at, opts) do
        {:ok, %{text: body}} ->
          append_captured_comment(turn, clean_captured_body(turn.ticket_id, body), opts)

        :pending ->
          :pending

        {:error, reason} ->
          append_advisory(turn, "ai_reply_capture_unavailable", reason, opts)
          {:unavailable, reason}
      end
    else
      false -> :disabled
      {:error, reason} -> {:ignored, reason}
    end
  end

  @impl true
  def init(opts) do
    {:ok, %{turns: %{}, interval_ms: Keyword.get(opts, :interval_ms, @interval_ms)}}
  end

  @impl true
  def handle_cast({:track, turn}, state) do
    key = key(turn)
    state = put_in(state, [:turns, key], turn)
    Process.send_after(self(), {:poll, key}, 0)
    {:noreply, state}
  end

  @impl true
  def handle_info({:poll, key}, state) do
    case Map.fetch(state.turns, key) do
      {:ok, turn} ->
        handle_poll(key, turn, state)

      :error ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  defp handle_poll(key, turn, state) do
    cond do
      expired?(turn) ->
        _ignored = append_advisory(turn, "ai_reply_capture_expired", :window_expired, [])
        {:noreply, update_in(state.turns, &Map.delete(&1, key))}

      true ->
        case capture_once(turn, enabled: true) do
          {:captured, _body} ->
            {:noreply, update_in(state.turns, &Map.delete(&1, key))}

          {:duplicate, _body} ->
            {:noreply, update_in(state.turns, &Map.delete(&1, key))}

          :pending ->
            Process.send_after(self(), {:poll, key}, state.interval_ms)
            {:noreply, state}

          _done ->
            {:noreply, update_in(state.turns, &Map.delete(&1, key))}
        end
    end
  end

  defp append_captured_comment(turn, body, opts) do
    normalized = normalize_body(body)

    if duplicate_comment?(turn.root, turn.ticket_id, turn.slug, normalized) do
      {:duplicate, body}
    else
      attrs =
        %{
          body: String.trim(body),
          by: turn.slug,
          turn_id: turn.turn_id,
          attempt_id: turn.attempt_id
        }
        |> maybe_put_auto_reply(Map.get(turn, :auto_reply))
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      case Api.comment_ticket(
             turn.ticket_id,
             attrs,
             Keyword.merge(opts,
               tickets_root: turn.root,
               notify_assignees: false
             )
           ) do
        {:ok, _result} -> {:captured, body}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp maybe_put_auto_reply(attrs, true), do: Map.put(attrs, :auto_reply, true)
  defp maybe_put_auto_reply(attrs, _other), do: attrs

  defp append_advisory(turn, event, reason, _opts) do
    History.append(turn.root, turn.ticket_id, %{
      "ts" => DateTime.utc_now(:second) |> DateTime.to_iso8601(),
      "event" => event,
      "by" => "system",
      "ticket_id" => turn.ticket_id,
      "citizen" => turn.slug,
      "reason" => inspect(reason)
    })
  end

  defp duplicate_comment?(root, ticket_id, slug, normalized) do
    case History.read(root, ticket_id) do
      {:ok, history} ->
        Enum.any?(history, fn
          %{"event" => "comment", "by" => ^slug, "body" => body} ->
            normalize_body(body) == normalized

          _event ->
            false
        end)

      {:error, _reason} ->
        false
    end
  end

  defp citizen_config(turn, opts) do
    cond do
      Keyword.has_key?(opts, :citizen_config) ->
        {:ok, Keyword.fetch!(opts, :citizen_config)}

      fetcher = Keyword.get(opts, :citizen_config_fetcher) ->
        fetch_config_with(fn -> fetcher.(turn.slug) end)

      true ->
        fetch_config_with(fn -> Catalog.get_by_slug(turn.slug) end)
    end
  end

  defp fetch_config_with(fun) when is_function(fun, 0) do
    fun.()
    |> normalize_config_result()
  rescue
    error -> {:error, {:catalog_unavailable, Exception.message(error)}}
  catch
    :exit, reason -> {:error, {:catalog_unavailable, reason}}
  end

  defp normalize_config_result({:ok, config}), do: {:ok, config}
  defp normalize_config_result({:error, reason}), do: {:error, reason}
  defp normalize_config_result(%CitizenRecord{} = record), do: {:ok, Catalog.to_config(record)}
  defp normalize_config_result(nil), do: {:error, :citizen_not_found}
  defp normalize_config_result(config), do: {:ok, config}

  defp normalize_turn(turn, opts) do
    started_at =
      Map.get(turn, :started_at) ||
        DateTime.utc_now(:second) |> DateTime.to_iso8601()

    %{
      root: Map.fetch!(turn, :root),
      ticket_id: Map.fetch!(turn, :ticket_id),
      slug: Map.fetch!(turn, :slug),
      turn_id: Map.get(turn, :turn_id),
      attempt_id: Map.get(turn, :attempt_id),
      auto_reply: Map.get(turn, :auto_reply),
      started_at: started_at,
      window_ms: Map.get(turn, :window_ms, Keyword.get(opts, :window_ms, @window_ms))
    }
  end

  defp expired?(turn) do
    with {:ok, started_at, _offset} <- DateTime.from_iso8601(turn.started_at),
         {:ok, expires_at} <-
           DateTime.from_unix(
             DateTime.to_unix(started_at, :millisecond) + turn.window_ms,
             :millisecond
           ) do
      DateTime.compare(DateTime.utc_now(), expires_at) == :gt
    else
      _ -> false
    end
  end

  defp key(turn),
    do: {turn.root, turn.ticket_id, turn.slug, turn.started_at, turn.turn_id, turn.attempt_id}

  defp normalize_body(body) do
    body
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp clean_captured_body(ticket_id, body) do
    body
    |> String.trim()
    |> String.replace(~r/^BABS_REPLY\s+#{Regex.escape(ticket_id)}:\s*/i, "")
    |> String.trim()
  end
end
