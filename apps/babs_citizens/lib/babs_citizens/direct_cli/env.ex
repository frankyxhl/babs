defmodule Babs.Citizens.DirectCli.Env do
  @moduledoc """
  Builds a bounded direct CLI subprocess environment.
  """

  @base_allowlist ~w(HOME PATH LANG LC_ALL LC_CTYPE TERM USER LOGNAME SHELL)

  def build(config, opts \\ []) do
    root =
      :babs_citizens
      |> Application.get_env(:root, File.cwd!())
      |> Path.expand()

    allowlist = Keyword.get(opts, :allowlist, @base_allowlist)

    inherited =
      allowlist
      |> Enum.flat_map(fn key ->
        case System.get_env(key) do
          nil -> []
          value -> [{key, value}]
        end
      end)
      |> Map.new()

    inherited
    |> Map.merge(config.env || %{})
    |> Map.merge(babs_env(config, root))
    |> Enum.sort()
  end

  def secret_names(config) do
    (config.env || %{})
    |> Map.keys()
    |> Enum.filter(&secret_key?/1)
  end

  def secret_values(config) do
    (config.env || %{})
    |> Enum.filter(fn {key, value} -> secret_key?(key) and present?(value) end)
    |> Enum.map(fn {_key, value} -> to_string(value) end)
  end

  defp secret_key?(key), do: Regex.match?(~r/(secret|token|key|password)/i, to_string(key))
  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp babs_env(config, root) do
    env = %{
      "BABS_CITIZEN_SLUG" => config.slug,
      "BABS_ROOT" => root,
      "BABS_DIRECT_CLI" => "1"
    }

    case Application.get_env(:babs_citizens, :tickets_root) do
      value when is_binary(value) and value != "" ->
        Map.put(env, "BABS_TICKETS_ROOT", Path.expand(value, root))

      _value ->
        env
    end
  end
end
