defmodule Babs.Citizens.Federation.Audit do
  @moduledoc """
  Redacted JSONL audit records for remote federation write/control requests.

  Phase 17.4 keeps this intentionally simple: append-only, operator-scale JSONL
  under the runtime `var/` area. Rotation and stronger serialization are
  deferred protocol work.
  """

  alias Babs.Citizens.Federation.ControlGuard

  @audit_file "federation_audit.jsonl"

  @spec path(keyword()) :: String.t()
  def path(opts \\ []) do
    opts
    |> root()
    |> Path.join(Path.join("var", @audit_file))
  end

  @spec success(ControlGuard.Auth.t(), map(), keyword()) :: :ok | {:error, term()}
  def success(%ControlGuard.Auth{} = auth, attrs, opts \\ []) when is_map(attrs) do
    %{
      "ts" => timestamp(opts),
      "peer_id" => auth.peer_id,
      "action" => safe_string(Map.get(attrs, :action) || Map.get(attrs, "action")),
      "target_type" => safe_string(Map.get(attrs, :target_type) || Map.get(attrs, "target_type")),
      "target_id" => safe_string(Map.get(attrs, :target_id) || Map.get(attrs, "target_id")),
      "result" => safe_string(Map.get(attrs, :result) || Map.get(attrs, "result") || "ok"),
      "capability" => auth.capability
    }
    |> append(opts)
  end

  @spec denied(map(), keyword()) :: :ok | {:error, term()}
  def denied(attrs, opts \\ []) when is_map(attrs) do
    %{
      "ts" => timestamp(opts),
      "peer_id" => safe_optional(Map.get(attrs, :peer_id) || Map.get(attrs, "peer_id")),
      "action" => safe_string(Map.get(attrs, :action) || Map.get(attrs, "action")),
      "target_type" => safe_string(Map.get(attrs, :target_type) || Map.get(attrs, "target_type")),
      "target_id" => safe_string(Map.get(attrs, :target_id) || Map.get(attrs, "target_id")),
      "result" => "denied",
      "reason_code" =>
        safe_string(Map.get(attrs, :reason_code) || Map.get(attrs, "reason_code") || "denied")
    }
    |> append(opts)
  end

  defp append(record, opts) do
    audit_path = path(opts)

    with :ok <- File.mkdir_p(Path.dirname(audit_path)),
         {:ok, line} <- Jason.encode(record) do
      File.write(audit_path, line <> "\n", [:append])
    end
  end

  defp timestamp(opts) do
    opts
    |> Keyword.get_lazy(:now, fn -> DateTime.utc_now(:second) end)
    |> case do
      %DateTime{} = now -> DateTime.to_iso8601(now)
      now when is_binary(now) -> now
      _other -> DateTime.utc_now(:second) |> DateTime.to_iso8601()
    end
  end

  defp root(opts) do
    Keyword.get_lazy(opts, :root, fn ->
      Application.get_env(:babs_citizens, :root, File.cwd!())
    end)
  end

  defp safe_string(value) when is_binary(value), do: String.slice(value, 0, 128)
  defp safe_string(value) when is_atom(value), do: value |> Atom.to_string() |> safe_string()
  defp safe_string(value), do: value |> inspect() |> safe_string()

  defp safe_optional(nil), do: nil
  defp safe_optional(value), do: safe_string(value)
end
