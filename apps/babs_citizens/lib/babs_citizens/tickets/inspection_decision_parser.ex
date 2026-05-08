defmodule Babs.Citizens.Tickets.InspectionDecisionParser do
  @moduledoc """
  Parses structured Inspector Citizen decisions from captured replies.
  """

  @decisions ~w(approve reject needs_changes)
  @json_fence_regex ~r/```json\s*\n(.*?)\n[ \t]*```/ims

  @spec parse(String.t()) :: {:ok, map()} | {:error, term()}
  def parse(body) when is_binary(body) do
    body
    |> json_candidate()
    |> Jason.decode()
    |> case do
      {:ok, decoded} when is_map(decoded) -> normalize(decoded)
      {:ok, decoded} -> {:error, {:invalid_json_shape, decoded}}
      {:error, reason} -> {:error, {:unparseable, reason}}
    end
  end

  def parse(value), do: {:error, {:unparseable, value}}

  defp json_candidate(body) do
    case Regex.run(@json_fence_regex, body, capture: :all_but_first) do
      [json | _rest] -> String.trim(json)
      nil -> String.trim(body)
    end
  end

  defp normalize(decoded) do
    with {:ok, decision} <- decision(decoded["decision"]),
         {:ok, summary} <- summary(decoded["summary"]),
         {:ok, findings} <- findings(Map.get(decoded, "findings", [])) do
      {:ok, %{decision: decision, summary: summary, findings: findings}}
    end
  end

  defp decision(value) when is_binary(value) do
    decision = value |> String.trim() |> String.downcase()

    if decision in @decisions do
      {:ok, decision}
    else
      {:error, {:invalid_decision, value}}
    end
  end

  defp decision(value), do: {:error, {:invalid_decision, value}}

  defp summary(value) when is_binary(value) do
    summary = String.trim(value)

    if summary == "" do
      {:error, {:missing_summary, value}}
    else
      {:ok, summary}
    end
  end

  defp summary(value), do: {:error, {:missing_summary, value}}

  defp findings(values) when is_list(values) do
    if Enum.all?(values, &is_map/1) do
      {:ok, values}
    else
      {:error, {:invalid_findings, values}}
    end
  end

  defp findings(value), do: {:error, {:invalid_findings, value}}
end
