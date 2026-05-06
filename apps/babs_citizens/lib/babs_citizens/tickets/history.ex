defmodule Babs.Citizens.Tickets.History do
  @moduledoc """
  Append-only JSONL history helpers for Tickets.
  """

  alias Babs.Citizens.Tickets.TicketMarkdown

  @required ~w(ts event by)
  @max_event_bytes 16_384

  @spec append(String.t(), String.t(), map()) :: :ok | {:error, term()}
  def append(root, id, event) when is_binary(root) and is_binary(id) and is_map(event) do
    with :ok <- validate_event(event),
         {:ok, line} <- encode_event(id, event),
         :ok <- ensure_history_dir(root, id) do
      case File.write(TicketMarkdown.history_path(root, id), line, [:append]) do
        :ok -> :ok
        {:error, reason} -> {:error, {:redacted_io_error, {:append_history, reason}}}
      end
    end
  end

  @spec read(String.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def read(root, id) do
    path = TicketMarkdown.history_path(root, id)

    with {:ok, content} <- read_file(id, path) do
      content
      |> String.split("\n", trim: true)
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, []}, fn {line, number}, {:ok, events} ->
        case Jason.decode(line) do
          {:ok, event} when is_map(event) ->
            case validate_event(event) do
              :ok ->
                {:cont, {:ok, [event | events]}}

              {:error, {:invalid_history_event, reason}} ->
                {:halt, {:error, {:invalid_history, {id, number, reason}}}}
            end

          _ ->
            {:halt, {:error, {:invalid_history, {id, number, :malformed_json}}}}
        end
      end)
      |> case do
        {:ok, events} -> {:ok, Enum.reverse(events)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp validate_event(event) do
    missing =
      Enum.reject(
        @required,
        &(is_binary(Map.get(event, &1)) and String.trim(Map.get(event, &1)) != "")
      )

    case missing do
      [] -> :ok
      _ -> {:error, {:invalid_history_event, {:missing_keys, missing}}}
    end
  end

  defp encode_event(id, event) do
    case Jason.encode(event) do
      {:ok, encoded} ->
        line = encoded <> "\n"

        if byte_size(line) > @max_event_bytes do
          {:error, {:history_event_too_large, id}}
        else
          {:ok, line}
        end

      {:error, _reason} ->
        {:error, {:invalid_history_event, :not_json_encodable}}
    end
  end

  defp ensure_history_dir(root, _id) do
    case File.mkdir_p(root) do
      :ok -> :ok
      {:error, reason} -> {:error, {:redacted_io_error, {:mkdir_history_root, reason}}}
    end
  end

  defp read_file(id, path) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, {:invalid_history, {id, 0, :missing_history}}}
      {:error, reason} -> {:error, {:redacted_io_error, {:read_history, reason}}}
    end
  end
end
