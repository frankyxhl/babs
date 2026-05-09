defmodule Babs.Citizens.DirectCli.Adapters.Copilot do
  @moduledoc """
  Direct adapter for GitHub Copilot CLI.
  """

  @behaviour Babs.Citizens.DirectCli.Adapter

  alias Babs.Citizens.DirectCli.Adapters.Common
  alias Babs.Citizens.ProviderRuntime.Result

  @ticket_id_regex ~r/^T-\d{4}-\d{2}-\d{2}-\d{3}$/i
  @reply_line_regex ~r/^\s*BABS_REPLY\s+(T-\d{4}-\d{2}-\d{2}-\d{3})\s*:\s*(.+?)\s*$/i
  @ticket_reply_regex ~r/BABS_REPLY\s+(T-\d{4}-\d{2}-\d{2}-\d{3})\s*:/i
  @planning_reply_regex ~r/^\s*(the user\b|the operator\b|i\s+(need|should)\b|let me\b|we need\b)/i

  @impl true
  def provider, do: "copilot"

  @impl true
  def supports?(config) do
    case {Common.cli_name(config), Map.get(config, :cli_args, []) || []} do
      {"copilot", _args} -> true
      {"gh", ["copilot" | _rest]} -> true
      _other -> false
    end
  end

  @impl true
  def start_command(config, prompt, opts \\ []) do
    Common.command(config, provider(), base_args(config, prompt, [], opts), opts)
  end

  @impl true
  def resume_command(config, provider_session_id, prompt, opts \\ []) do
    command_opts = Keyword.merge(opts, provider_session_id: provider_session_id, resume?: true)

    Common.command(
      config,
      provider(),
      base_args(config, prompt, ["--resume=#{provider_session_id}"], command_opts),
      command_opts
    )
  end

  @impl true
  def parse_result(%{stdout: stdout} = artifacts, opts \\ []) do
    values = Common.decode_json_lines(stdout)
    text = find_assistant_message_text(values) || Common.find_text(values)
    ticket_id = ticket_id_from_opts(opts)
    final_reply = if is_binary(text), do: extract_final_reply(text, ticket_id), else: nil
    session_id = Common.find_session_id(values) || artifacts[:provider_session_id]

    cond do
      not is_binary(text) or String.trim(text) == "" ->
        {:error, :no_assistant_reply}

      not is_binary(final_reply) ->
        {:error, :missing_babs_reply}

      true ->
        {:ok, direct_success(final_reply, session_id, opts)}
    end
  end

  defp base_args(%{cli: cli, cli_args: ["copilot" | _rest], cwd: cwd}, prompt, extra, opts)
       when is_binary(cli) do
    [cli, "copilot", "--"] ++ copilot_args(cwd, prompt, extra, opts)
  end

  defp base_args(%{cli: cli, cwd: cwd}, prompt, extra, opts),
    do: [cli] ++ copilot_args(cwd, prompt, extra, opts)

  defp copilot_args(cwd, prompt, extra, opts) do
    [
      "-p",
      copilot_prompt(prompt, opts),
      "--output-format",
      "json",
      "--stream",
      "off",
      "--allow-all",
      "--no-ask-user",
      "-C",
      cwd
    ] ++ extra
  end

  defp copilot_prompt(prompt, opts) do
    ticket_id = ticket_id_from_opts(opts) || last_ticket_id(prompt)

    if Keyword.get(opts, :resume?, false) do
      copilot_resume_prompt(prompt, ticket_id)
    else
      copilot_start_prompt(prompt, ticket_id)
    end
  end

  defp copilot_start_prompt(prompt, ticket_id) do
    required_reply =
      if ticket_id do
        "BABS_REPLY #{ticket_id}: <your answer>"
      else
        "BABS_REPLY <ticket_id>: <your answer>"
      end

    """
    You are running as a Babs Citizen through GitHub Copilot CLI non-interactive mode.
    Return exactly one final line and nothing else.
    Do not explain your reasoning, describe your plan, quote these instructions, or use markdown.
    The final line must start with:
    #{required_reply}

    Original Babs prompt:
    #{prompt}
    """
    |> String.trim()
  end

  defp copilot_resume_prompt(prompt, ticket_id) do
    required_reply =
      if ticket_id do
        "BABS_REPLY #{ticket_id}: <your answer>"
      else
        "BABS_REPLY <ticket_id>: <your answer>"
      end

    case latest_operator_message(prompt, ticket_id) do
      message when is_binary(message) and message != "" ->
        """
        #{message}

        Reply with exactly one line:
        #{required_reply}
        """

      _other ->
        """
        #{String.trim(prompt)}

        Reply with exactly one line:
        #{required_reply}
        """
    end
    |> String.trim()
  end

  defp latest_operator_message(prompt, ticket_id) when is_binary(prompt) do
    marker =
      case ticket_id do
        ticket_id when is_binary(ticket_id) ->
          "BABS_REPLY\\s+#{Regex.escape(ticket_id)}\\s*:"

        _other ->
          "BABS_REPLY\\s+"
      end

    regex =
      Regex.compile!(
        "Latest operator message:\\n(?<message>.*)\\n\\nReply[^\\n]*with:\\n#{marker}[^\\n]*\\s*\\z",
        "s"
      )

    case Regex.run(regex, prompt, capture: ["message"]) do
      [message] -> String.trim(message)
      _other -> nil
    end
  end

  defp find_assistant_message_text(values) do
    values
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{"type" => "assistant.message"} = value ->
        Common.find_text([value])

      %{"type" => "message", "role" => "assistant"} = value ->
        Common.find_text([value])

      %{"role" => "assistant"} = value ->
        Common.find_text([value])

      _other ->
        nil
    end)
  end

  defp extract_final_reply(text, expected_ticket_id) when is_binary(text) do
    marker_reply = extract_marker_reply(text, expected_ticket_id)

    cond do
      is_binary(marker_reply) ->
        marker_reply

      contains_reply_marker?(text) ->
        nil

      true ->
        extract_markerless_reply(text)
    end
  end

  defp extract_marker_reply(text, expected_ticket_id) do
    text
    |> String.split(~r/\R/)
    |> Enum.reverse()
    |> Enum.find_value(fn line ->
      case Regex.run(@reply_line_regex, line, capture: :all_but_first) do
        [ticket_id, reply] ->
          reply = String.trim(reply)

          if reply_ticket_id_matches?(ticket_id, expected_ticket_id) and
               not placeholder_reply?(reply) do
            reply
          end

        _other ->
          nil
      end
    end)
  end

  defp extract_markerless_reply(text) do
    text
    |> String.split(~r/\R/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [reply] ->
        if safe_markerless_reply?(reply), do: reply

      _other ->
        nil
    end
  end

  defp safe_markerless_reply?(reply) do
    not placeholder_reply?(reply) and
      not Regex.match?(@planning_reply_regex, reply)
  end

  defp contains_reply_marker?(text) do
    text
    |> String.upcase()
    |> String.contains?("BABS_REPLY")
  end

  defp last_ticket_id(prompt) when is_binary(prompt) do
    prompt
    |> then(&Regex.scan(@ticket_reply_regex, &1, capture: :all_but_first))
    |> List.last()
    |> case do
      [ticket_id] -> ticket_id
      _other -> nil
    end
  end

  defp ticket_id_from_opts(opts) do
    case Keyword.get(opts, :ticket_id) do
      ticket_id when is_binary(ticket_id) ->
        ticket_id = String.trim(ticket_id)
        if Regex.match?(@ticket_id_regex, ticket_id), do: ticket_id

      _other ->
        nil
    end
  end

  defp reply_ticket_id_matches?(_ticket_id, nil), do: true

  defp reply_ticket_id_matches?(ticket_id, expected_ticket_id),
    do: ticket_id == expected_ticket_id

  defp placeholder_reply?(reply) do
    reply
    |> String.trim()
    |> String.trim("`")
    |> String.trim()
    |> String.downcase()
    |> then(&(&1 in ["", "your response", "your response.", "<your answer>"]))
  end

  defp direct_success(text, session_id, opts) do
    Result.direct_success(provider(), Common.clean_text(text, opts),
      provider_session_id: session_id,
      capabilities: %{"direct" => true, "resume" => is_binary(session_id)}
    )
  end
end
