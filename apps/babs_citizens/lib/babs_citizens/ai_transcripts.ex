defmodule Babs.Citizens.AiTranscripts do
  @moduledoc """
  Read-only helpers for upstream AI CLI JSONL transcripts.
  """

  alias Babs.Citizens.Runner

  @type record :: %{role: String.t(), text: String.t(), ts: String.t() | nil, path: String.t()}

  @spec find_reply(Babs.Citizens.CitizenConfig.t(), String.t(), String.t(), keyword()) ::
          {:ok, record()} | :pending | {:error, term()}
  def find_reply(config, ticket_id, since, opts \\ []) do
    case Keyword.get_lazy(opts, :paths, fn -> discover_paths(config, since) end) do
      {:error, reason} ->
        {:error, reason}

      [] ->
        :pending

      paths ->
        paths
        |> Enum.sort_by(&mtime_unix/1, :desc)
        |> Enum.reduce_while(:pending, fn path, :pending ->
          case find_reply_in_file(path, ticket_id, since) do
            {:ok, record} -> {:halt, {:ok, record}}
            :pending -> {:cont, :pending}
            {:error, _reason} -> {:cont, :pending}
          end
        end)
    end
  end

  @spec find_reply_in_file(String.t(), String.t(), String.t()) ::
          {:ok, record()} | :pending | {:error, term()}
  def find_reply_in_file(path, ticket_id, since)
      when is_binary(path) and is_binary(ticket_id) and is_binary(since) do
    with {:ok, content} <- File.read(path) do
      since_dt = parse_ts(since)

      content
      |> String.split("\n", trim: true)
      |> Enum.reduce_while({:pending, false}, fn line, {:pending, seen_ticket?} ->
        case parse_line(line) do
          {:ok, %{role: role, text: text, ts: ts} = record} ->
            after_since? = after_or_unknown?(ts, since_dt)
            mentions_ticket? = String.contains?(text, ticket_id)

            cond do
              role in ["user", "system"] and mentions_ticket? and after_since? ->
                {:cont, {:pending, true}}

              role == "assistant" and seen_ticket? and after_since? and String.trim(text) != "" ->
                {:halt, {:ok, Map.put(record, :path, path)}}

              role == "assistant" and mentions_ticket? and after_since? and
                  String.trim(text) != "" ->
                {:halt, {:ok, Map.put(record, :path, path)}}

              true ->
                {:cont, {:pending, seen_ticket?}}
            end

          :ignore ->
            {:cont, {:pending, seen_ticket?}}
        end
      end)
      |> case do
        {:ok, record} -> {:ok, record}
        {:pending, _seen?} -> :pending
      end
    end
  end

  @spec parse_line(String.t()) ::
          {:ok, %{role: String.t(), text: String.t(), ts: String.t() | nil}} | :ignore
  def parse_line(line) when is_binary(line) do
    with {:ok, data} when is_map(data) <- Jason.decode(line),
         {:ok, role} <- role(data),
         text when is_binary(text) and text != "" <- text(data) do
      {:ok, %{role: role, text: text, ts: timestamp(data)}}
    else
      _ -> :ignore
    end
  end

  defp discover_paths(config, since) do
    explicit = explicit_paths(config)

    source_paths =
      cond do
        explicit != [] ->
          explicit

        Runner.ai_cli?(config) ->
          cli_paths(config)

        true ->
          []
      end

    case source_paths do
      {:error, _reason} = error ->
        error

      paths ->
        since_dt = parse_ts(since)

        Enum.filter(paths, fn path ->
          File.regular?(path) and after_or_unknown?(mtime_iso(path), since_dt)
        end)
    end
  end

  defp explicit_paths(config) do
    env = Map.get(config, :env) || %{}

    env
    |> Map.get("BABS_AI_TRANSCRIPT_PATHS", Map.get(env, "BABS_AI_TRANSCRIPT_PATH", ""))
    |> String.split(":", trim: true)
    |> Enum.flat_map(&Path.wildcard(Path.expand(&1)))
  end

  defp cli_paths(%{cli: cli} = config) do
    cli_args = Map.get(config, :cli_args, [])
    cwd = Map.get(config, :cwd, File.cwd!())

    cli_name = cli |> Path.basename() |> String.downcase()

    case {cli_name, cli_args} do
      {"claude", _args} ->
        Path.wildcard(
          Path.join([home(), ".claude", "projects", claude_project(cwd), "**", "*.jsonl"])
        )

      {"codex", _args} ->
        Path.wildcard(Path.join([home(), ".codex", "sessions", "**", "*.jsonl"]))

      {"gh", ["copilot" | _rest]} ->
        {:error, :unsupported_copilot_transcripts}

      _other ->
        []
    end
  end

  defp cli_paths(_config), do: []

  defp claude_project(cwd) do
    cwd
    |> Path.expand()
    |> String.replace("/", "-")
  end

  defp role(data) do
    candidates = [
      data["role"],
      data["type"],
      get_in(data, ["message", "role"]),
      get_in(data, ["message", "type"])
    ]

    case Enum.find(candidates, &(&1 in ["assistant", "user", "system"])) do
      nil -> :error
      role -> {:ok, role}
    end
  end

  defp text(data) do
    [
      data["content"],
      data["text"],
      data["message"],
      get_in(data, ["message", "content"]),
      get_in(data, ["message", "text"])
    ]
    |> Enum.map(&extract_text/1)
    |> Enum.find("", &(&1 != ""))
  end

  defp extract_text(value) when is_binary(value), do: value

  defp extract_text(%{"content" => value}), do: extract_text(value)
  defp extract_text(%{"text" => value}), do: extract_text(value)

  defp extract_text(values) when is_list(values) do
    values
    |> Enum.map(&extract_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp extract_text(_value), do: ""

  defp timestamp(data) do
    data["timestamp"] || data["ts"] || data["created_at"] ||
      get_in(data, ["message", "timestamp"])
  end

  defp parse_ts(nil), do: nil

  defp parse_ts(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp after_or_unknown?(_value, nil), do: true
  defp after_or_unknown?(nil, _since), do: true

  defp after_or_unknown?(value, since) when is_binary(value) do
    case parse_ts(value) do
      nil -> true
      dt -> DateTime.compare(dt, since) in [:gt, :eq]
    end
  end

  defp after_or_unknown?(%DateTime{} = value, since),
    do: DateTime.compare(value, since) in [:gt, :eq]

  defp mtime_unix(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} -> mtime
      _ -> 0
    end
  end

  defp mtime_iso(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} -> DateTime.from_unix!(mtime) |> DateTime.to_iso8601()
      _ -> nil
    end
  end

  defp home, do: System.user_home!()
end
