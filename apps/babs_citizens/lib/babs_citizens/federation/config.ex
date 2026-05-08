defmodule Babs.Citizens.Federation.Config do
  @moduledoc """
  Read-only local node and peer configuration for Phase 17 federation slices.
  """

  @slug_regex ~r/^[a-z][a-z0-9-]{0,47}$/
  @canonical_capabilities ~w(read write control)
  @capability_expansions %{
    "read" => ["read"],
    "write" => ["read", "write"],
    "control" => ["read", "write", "control"]
  }

  defmodule Node do
    @moduledoc false
    defstruct id: "local", name: "Local Babs", public_url: nil, capabilities: ["read"]
  end

  defmodule Peer do
    @moduledoc false
    defstruct [:id, :name, :url, capabilities: [], citizens: %{}]
  end

  defstruct node: nil, peers: []

  @doc """
  Load federation config.

  `:toml` and `:path` opts are test/explicit override hooks. When neither is
  present, the loader reads the app env / `BABS_FEDERATION_CONFIG`; if no path is
  configured, safe local defaults are returned.
  """
  def load(opts \\ []) when is_list(opts) do
    with {:ok, raw} <- load_raw(opts) do
      from_raw(raw)
    end
  end

  defp load_raw(opts) do
    cond do
      Keyword.has_key?(opts, :toml) ->
        decode_toml(Keyword.fetch!(opts, :toml))

      Keyword.has_key?(opts, :path) ->
        load_path(Keyword.fetch!(opts, :path))

      path = configured_path() ->
        load_path(path)

      true ->
        {:ok, default_raw()}
    end
  end

  defp configured_path do
    app_path = Application.get_env(:babs_citizens, :federation_config_path)

    cond do
      present_string?(app_path) ->
        String.trim(app_path)

      present_string?(System.get_env("BABS_FEDERATION_CONFIG")) ->
        System.get_env("BABS_FEDERATION_CONFIG") |> String.trim()

      true ->
        nil
    end
  end

  defp load_path(nil), do: {:ok, default_raw()}

  defp load_path(path) when is_binary(path) do
    case File.read(path) do
      {:ok, toml} -> decode_toml(toml)
      {:error, reason} -> {:error, {:config_error, {:read_failed, reason}}}
    end
  end

  defp load_path(_path), do: {:error, {:config_error, {:invalid_path, :not_string}}}

  defp decode_toml(toml) when is_binary(toml) do
    case Toml.decode(toml, keys: :strings) do
      {:ok, raw} -> {:ok, raw}
      {:error, reason} -> {:error, {:config_error, {:toml_decode_failed, redact_reason(reason)}}}
    end
  end

  defp decode_toml(_toml), do: {:error, {:config_error, {:toml_decode_failed, :not_string}}}

  defp from_raw(raw) when is_map(raw) do
    with {:ok, node} <- parse_node(Map.get(raw, "node", %{})),
         {:ok, peers} <- parse_peers(Map.get(raw, "peers", %{})) do
      {:ok, %__MODULE__{node: node, peers: peers}}
    end
  end

  defp from_raw(_raw), do: {:error, {:config_error, {:invalid_table, "root"}}}

  defp parse_node(raw) when is_map(raw) do
    with {:ok, id} <- string_field(raw, "id", "node.id", default: "local"),
         :ok <- validate_slug(id, "node.id"),
         {:ok, name} <- string_field(raw, "name", "node.name", default: "Local Babs"),
         :ok <- validate_name(name, "node.name"),
         {:ok, public_url} <- optional_url(Map.get(raw, "public_url"), "node.public_url") do
      {:ok, %Node{id: id, name: name, public_url: public_url, capabilities: ["read"]}}
    end
  end

  defp parse_node(_raw), do: {:error, {:config_error, {:invalid_table, "node"}}}

  defp parse_peers(raw) when raw in [%{}, nil], do: {:ok, []}

  defp parse_peers(raw) when is_map(raw) do
    raw
    |> Enum.sort_by(fn {id, _peer} -> id end)
    |> Enum.reduce_while({:ok, []}, fn {id, peer_raw}, {:ok, peers} ->
      case parse_peer(id, peer_raw) do
        {:ok, peer} -> {:cont, {:ok, peers ++ [peer]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp parse_peers(_raw), do: {:error, {:config_error, {:invalid_table, "peers"}}}

  defp parse_peer(id, raw) when is_binary(id) and is_map(raw) do
    peer_path = "peers.#{id}"

    with :ok <- validate_slug(id, peer_path),
         {:ok, name} <- string_field(raw, "name", "#{peer_path}.name"),
         :ok <- validate_name(name, "#{peer_path}.name"),
         {:ok, url} <- required_url(Map.get(raw, "url"), "#{peer_path}.url"),
         {:ok, capabilities} <-
           capabilities(Map.get(raw, "capabilities"), "#{peer_path}.capabilities"),
         {:ok, citizens} <- parse_citizen_overrides(id, Map.get(raw, "citizens", %{})) do
      {:ok,
       %Peer{
         id: id,
         name: name,
         url: url,
         capabilities: capabilities,
         citizens: citizens
       }}
    end
  end

  defp parse_peer(id, _raw), do: {:error, {:config_error, {:invalid_table, "peers.#{id}"}}}

  defp parse_citizen_overrides(_peer_id, raw) when raw in [%{}, nil], do: {:ok, %{}}

  defp parse_citizen_overrides(peer_id, raw) when is_map(raw) do
    raw
    |> Enum.sort_by(fn {slug, _override} -> slug end)
    |> Enum.reduce_while({:ok, %{}}, fn {slug, override_raw}, {:ok, acc} ->
      path = "peers.#{peer_id}.citizens.#{slug}"

      with :ok <- validate_slug(slug, path),
           {:ok, override_raw} <- require_table(override_raw, path),
           {:ok, caps} <-
             capabilities(Map.get(override_raw, "capabilities"), "#{path}.capabilities") do
        {:cont, {:ok, Map.put(acc, slug, caps)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp parse_citizen_overrides(peer_id, _raw),
    do: {:error, {:config_error, {:invalid_table, "peers.#{peer_id}.citizens"}}}

  defp require_table(value, _path) when is_map(value), do: {:ok, value}
  defp require_table(_value, path), do: {:error, {:config_error, {:invalid_table, path}}}

  defp string_field(raw, key, path, opts \\ []) do
    case Map.fetch(raw, key) do
      {:ok, value} when is_binary(value) ->
        value = String.trim(value)

        if value == "" do
          {:error, {:config_error, {:blank, path}}}
        else
          {:ok, value}
        end

      {:ok, _value} ->
        {:error, {:config_error, {:invalid_string, path}}}

      :error ->
        case Keyword.fetch(opts, :default) do
          {:ok, default} -> {:ok, default}
          :error -> {:error, {:config_error, {:missing_required, path}}}
        end
    end
  end

  defp validate_slug(value, path) do
    if Regex.match?(@slug_regex, value) do
      :ok
    else
      {:error, {:config_error, {:invalid_id, path, value}}}
    end
  end

  defp validate_name(value, path) do
    cond do
      String.trim(value) == "" -> {:error, {:config_error, {:blank, path}}}
      String.length(value) > 80 -> {:error, {:config_error, {:too_long, path}}}
      true -> :ok
    end
  end

  defp optional_url(nil, _path), do: {:ok, nil}
  defp optional_url("", _path), do: {:ok, nil}

  defp optional_url(value, path) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      {:ok, nil}
    else
      validate_url(value, path)
    end
  end

  defp optional_url(_value, path),
    do: {:error, {:config_error, {:invalid_url, path, :not_string}}}

  defp required_url(value, path) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      {:error, {:config_error, {:missing_required, path}}}
    else
      validate_url(value, path)
    end
  end

  defp required_url(nil, path), do: {:error, {:config_error, {:missing_required, path}}}

  defp required_url(_value, path),
    do: {:error, {:config_error, {:invalid_url, path, :not_string}}}

  defp validate_url(value, path) do
    uri = URI.parse(value)

    if uri.scheme in ["http", "https"] and present_string?(uri.host) do
      {:ok, value}
    else
      {:error, {:config_error, {:invalid_url, path, value}}}
    end
  end

  defp capabilities(nil, path), do: {:error, {:config_error, {:missing_required, path}}}

  defp capabilities(values, path) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn
      value, {:ok, acc} when is_binary(value) ->
        value = String.trim(value)

        case Map.fetch(@capability_expansions, value) do
          {:ok, expanded} -> {:cont, {:ok, acc ++ expanded}}
          :error -> {:halt, {:error, {:config_error, {:invalid_capability, path, value}}}}
        end

      _value, _acc ->
        {:halt, {:error, {:config_error, {:invalid_capability, path, :not_string}}}}
    end)
    |> case do
      {:ok, expanded} ->
        {:ok, Enum.filter(@canonical_capabilities, &(&1 in expanded))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp capabilities(_value, path), do: {:error, {:config_error, {:invalid_capabilities, path}}}

  defp default_raw do
    %{
      "node" => %{"id" => "local", "name" => "Local Babs", "public_url" => ""},
      "peers" => %{}
    }
  end

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp redact_reason(reason) when is_binary(reason), do: String.slice(reason, 0, 300)
  defp redact_reason(reason), do: reason
end
