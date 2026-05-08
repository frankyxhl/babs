defmodule Babs.Citizens.ProviderRuntime.Contract do
  @moduledoc """
  Read-only provider/backend capability contract.

  This module intentionally describes current provider behavior without running
  provider commands. Execution migration happens in later Phase 13f slices.
  """

  @enforce_keys [
    :provider,
    :backend,
    :ownership,
    :status,
    :command,
    :cwd_policy,
    :env_policy,
    :launch_profiles,
    :input_modes,
    :resume,
    :session_id_parser,
    :reply_parser,
    :capabilities,
    :version_fingerprint,
    :timeouts,
    :output_limits,
    :diagnostics,
    :raw_artifact_refs,
    :interactive_attach
  ]
  defstruct @enforce_keys

  @owners ~w(babs external reserved)
  @statuses ~w(supported deferred unsupported)
  @backends ~w(direct_cli hardline lazy_tmux)
  @unsafe_artifact_ref_keys ~w(
    absolute_path api_key content credential credentials env environment host
    hostname ip ip_address output password path private_ip prompt raw_output
    reply secret stderr stdout text token
  )

  @type t :: %__MODULE__{}

  def new(attrs) when is_map(attrs) do
    with {:ok, attrs} <- normalize_attrs(attrs),
         :ok <- required(attrs),
         :ok <- enum(attrs, :ownership, @owners),
         :ok <- enum(attrs, :status, @statuses),
         :ok <- enum(attrs, :backend, @backends),
         :ok <- safe_artifact_refs(attrs.raw_artifact_refs) do
      {:ok, struct!(__MODULE__, attrs)}
    end
  end

  def new(_attrs), do: {:error, :invalid_contract}

  def new!(attrs) do
    case new(attrs) do
      {:ok, contract} ->
        contract

      {:error, reason} ->
        raise ArgumentError, "invalid provider runtime contract: #{inspect(reason)}"
    end
  end

  def to_map(%__MODULE__{} = contract) do
    contract
    |> Map.from_struct()
    |> stringify_map()
  end

  defp normalize_attrs(attrs) do
    Enum.reduce_while(attrs, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case atom_key(key) do
        {:ok, atom} ->
          {:cont, {:ok, Map.put(acc, atom, normalize_value(value))}}

        :error ->
          {:halt, {:error, {:unknown_field, key}}}
      end
    end)
  end

  defp atom_key(key) when is_atom(key) do
    if key in @enforce_keys, do: {:ok, key}, else: :error
  end

  defp atom_key(key) when is_binary(key) do
    case Enum.find(@enforce_keys, &(Atom.to_string(&1) == key)) do
      nil -> :error
      atom -> {:ok, atom}
    end
  end

  defp atom_key(_key), do: :error

  defp normalize_value(value) when is_map(value), do: stringify_map(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value

  defp stringify_map(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {string_key(key), stringify_value(value)} end)
    |> Map.new()
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(value) when is_list(value), do: Enum.map(value, &stringify_value/1)
  defp stringify_value(value), do: value

  defp string_key(key) when is_atom(key), do: Atom.to_string(key)
  defp string_key(key) when is_binary(key), do: key

  defp required(attrs) do
    missing =
      @enforce_keys
      |> Enum.reject(&Map.has_key?(attrs, &1))

    case missing do
      [] -> :ok
      fields -> {:error, {:missing_fields, fields}}
    end
  end

  defp enum(attrs, field, values) do
    value = Map.fetch!(attrs, field)

    if value in values do
      :ok
    else
      {:error, {:invalid_field, field, value}}
    end
  end

  defp safe_artifact_refs(values) when is_list(values) do
    Enum.find_value(values, :ok, fn value ->
      case unsafe_artifact_ref(value) do
        nil -> false
        unsafe -> {:error, {:unsafe_raw_artifact_ref, unsafe}}
      end
    end)
  end

  defp safe_artifact_refs(value), do: {:error, {:invalid_field, :raw_artifact_refs, value}}

  defp unsafe_artifact_ref(%{} = value) do
    if Enum.any?(Map.keys(value), &unsafe_artifact_ref_key?/1) do
      value
    else
      Enum.find_value(Map.values(value), &unsafe_artifact_ref/1)
    end
  end

  defp unsafe_artifact_ref(values) when is_list(values),
    do: Enum.find_value(values, &unsafe_artifact_ref/1)

  defp unsafe_artifact_ref(value) when is_binary(value), do: unsafe_artifact_ref_value(value)

  defp unsafe_artifact_ref(_value), do: nil

  defp unsafe_artifact_ref_key?(key) do
    normalized =
      key
      |> string_key()
      |> String.downcase()

    normalized in @unsafe_artifact_ref_keys or String.ends_with?(normalized, "_token") or
      String.ends_with?(normalized, "_secret")
  end

  defp unsafe_artifact_ref_value(value) do
    cond do
      String.match?(
        value,
        ~r{(^|[^A-Za-z0-9_.-])/(?:Users|home|var|tmp|etc|private|opt)(/|\b)\S*}
      ) ->
        value

      String.match?(value, ~r/\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/) ->
        value

      String.match?(value, ~r/\b172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}\b/) ->
        value

      String.match?(value, ~r/\b192\.168\.\d{1,3}\.\d{1,3}\b/) ->
        value

      String.match?(value, ~r/\b100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3}\b/) ->
        value

      true ->
        nil
    end
  end
end
