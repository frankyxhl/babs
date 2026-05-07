defmodule Babs.Citizens.DirectCli.Adapters.Common do
  @moduledoc false

  alias Babs.Citizens.DirectCli.{Command, Env, Redactor}

  def cli_name(%{cli: cli}) when is_binary(cli), do: cli |> Path.basename() |> String.downcase()
  def cli_name(_config), do: ""

  def command(config, provider, args, opts) do
    {:ok,
     %Command{
       provider: provider,
       args: args,
       cwd: config.cwd,
       env: Env.build(config, opts),
       timeout_ms: Keyword.get(opts, :timeout_ms, 120_000),
       output_limit: Keyword.get(opts, :output_limit, 65_536),
       provider_session_id: Keyword.get(opts, :provider_session_id),
       resume?: Keyword.get(opts, :resume?, false)
     }}
  end

  def decode_json_lines(text) when is_binary(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case Jason.decode(line) do
        {:ok, value} -> [value]
        {:error, _reason} -> []
      end
    end)
  end

  def decode_json_object(text) when is_binary(text) do
    case Jason.decode(String.trim(text)) do
      {:ok, value} -> [value]
      {:error, _reason} -> decode_json_lines(text)
    end
  end

  def find_session_id(values) do
    values
    |> List.wrap()
    |> Enum.find_value(&session_id_from_value/1)
  end

  def find_text(values) do
    values
    |> List.wrap()
    |> Enum.reverse()
    |> Enum.find_value(&text_from_value/1)
  end

  def clean_text(text, opts) when is_binary(text) do
    text
    |> Redactor.bound_output(Keyword.get(opts, :output_limit, 65_536))
    |> Redactor.redact_text(secret_names: Keyword.get(opts, :secret_names, []))
    |> String.trim()
  end

  defp session_id_from_value(%{} = value) do
    direct =
      value["session_id"] || value["sessionId"] || value["session"] || value["thread_id"] ||
        value["threadId"] || value["conversation_id"] || value["conversationId"]

    cond do
      is_binary(direct) and direct != "" ->
        direct

      is_map(value["data"]) ->
        session_id_from_value(value["data"])

      is_map(value["message"]) ->
        session_id_from_value(value["message"])

      true ->
        nil
    end
  end

  defp session_id_from_value(_value), do: nil

  defp text_from_value(%{} = value) do
    direct =
      value["result"] || value["content"] || value["text"] || value["last_message"] ||
        value["lastMessage"] || value["response"]

    cond do
      is_binary(direct) and direct != "" ->
        direct

      is_list(value["content"]) ->
        value["content"]
        |> Enum.find_value(&text_from_value/1)

      is_map(value["data"]) ->
        text_from_value(value["data"])

      is_map(value["message"]) ->
        text_from_value(value["message"])

      true ->
        nil
    end
  end

  defp text_from_value(_value), do: nil
end
