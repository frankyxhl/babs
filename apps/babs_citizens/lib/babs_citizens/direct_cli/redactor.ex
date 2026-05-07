defmodule Babs.Citizens.DirectCli.Redactor do
  @moduledoc """
  Redaction and output bounding for direct CLI execution artifacts.
  """

  @default_limit 65_536
  @sensitive_key_value ~r/("[a-z0-9_]*(?:secret|token|key|password)[a-z0-9_]*"|\b[a-z0-9_]*(?:secret|token|key|password)[a-z0-9_]*\b)(\s*(?:=>|:)\s*)("[^"]*"|[^\s,\]}]+)/i
  @sensitive_assignment ~r/\b([a-z0-9_]*(?:secret|token|key|password)[a-z0-9_]*=)([^\s,\]}]+)/i
  @private_ip ~r/\b(?:10|100)\.\d{1,3}\.\d{1,3}\.\d{1,3}\b|\b192\.168\.\d{1,3}\.\d{1,3}\b|\b172\.(?:1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3}\b/
  @local_path ~r{/(?:Users|home|workspace|tmp|var|private|Volumes)/[^\s\]'",<>)]+}

  def bound_output(value, limit \\ @default_limit)

  def bound_output(value, limit) when is_binary(value) and byte_size(value) > limit do
    binary_part(value, 0, limit) <> "\n[TRUNCATED]"
  end

  def bound_output(value, _limit) when is_binary(value), do: value

  def bound_output(values, limit) when is_list(values) do
    values
    |> Enum.map(&to_string/1)
    |> Enum.join("")
    |> bound_output(limit)
  end

  def bound_output(value, limit), do: value |> inspect() |> bound_output(limit)

  def redact_text(value, opts \\ []) do
    secret_names = Keyword.get(opts, :secret_names, [])
    secret_values = Keyword.get(opts, :secret_values, [])

    value
    |> to_string()
    |> String.replace(@sensitive_key_value, "\\1\\2[REDACTED]")
    |> String.replace(@sensitive_assignment, "\\1[REDACTED]")
    |> String.replace(@private_ip, "[REDACTED_IP]")
    |> String.replace(@local_path, "[REDACTED_PATH]")
    |> redact_named_secrets(secret_names)
    |> redact_secret_values(secret_values)
  end

  def redact_artifacts(%{} = artifacts, opts \\ []) do
    artifacts
    |> Map.update(:stdout, "", &redact_text(bound_output(&1), opts))
    |> Map.update(:stderr, "", &redact_text(bound_output(&1), opts))
  end

  defp redact_named_secrets(value, secret_names) do
    Enum.reduce(secret_names, value, fn name, acc ->
      String.replace(
        acc,
        ~r/\b#{Regex.escape(to_string(name))}=([^\s,\]}]+)/,
        "#{name}=[REDACTED]"
      )
    end)
  end

  defp redact_secret_values(value, secret_values) do
    secret_values
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.uniq()
    |> Enum.sort_by(&byte_size/1, :desc)
    |> Enum.reduce(value, fn secret, acc -> String.replace(acc, secret, "[REDACTED]") end)
  end
end
