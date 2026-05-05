defmodule Babs.Citizens.Citizen.Config do
  @moduledoc """
  Loads Phase 1 `citizens/citizen-<slug>.toml` files.
  """

  alias Babs.Citizens.CitizenConfig

  @slug_regex ~r/^[a-z][a-z0-9-]{0,47}$/
  @required ~w(id slug display_name cli cwd)

  def load_slug(slug, opts \\ []) when is_binary(slug) do
    root = Keyword.get(opts, :root, Application.get_env(:babs_citizens, :root, File.cwd!()))

    config_dir =
      Keyword.get(opts, :config_dir, Application.get_env(:babs_citizens, :config_dir, "citizens"))

    root
    |> Path.join(config_dir)
    |> Path.join("citizen-#{slug}.toml")
    |> load_file(opts)
  end

  def load_file(path, opts \\ []) when is_binary(path) do
    root = Keyword.get(opts, :root, Application.get_env(:babs_citizens, :root, File.cwd!()))

    with {:ok, raw} <- decode_file(path),
         :ok <- validate_required(raw),
         :ok <- validate_slug(raw["slug"]),
         {:ok, cli_args} <- validate_cli_args(Map.get(raw, "cli_args", [])),
         {:ok, env} <- resolve_env(Map.get(raw, "env", %{})),
         {:ok, cwd} <- resolve_cwd(root, raw["cwd"]) do
      {:ok,
       %CitizenConfig{
         id: raw["id"],
         slug: raw["slug"],
         display_name: raw["display_name"],
         cli: raw["cli"],
         cli_args: cli_args,
         cwd: cwd,
         description: Map.get(raw, "description"),
         env: env,
         role: Map.get(raw, "role"),
         path: path
       }}
    end
  end

  def list_configs(opts \\ []) do
    root = Keyword.get(opts, :root, Application.get_env(:babs_citizens, :root, File.cwd!()))

    config_dir =
      Keyword.get(opts, :config_dir, Application.get_env(:babs_citizens, :config_dir, "citizens"))

    dir = Path.join(root, config_dir)

    dir
    |> Path.join("citizen-*.toml")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&load_file(&1, Keyword.put(opts, :root, root)))
  end

  def valid_slug?(slug) when is_binary(slug), do: Regex.match?(@slug_regex, slug)
  def valid_slug?(_slug), do: false

  defp decode_file(path) do
    case Toml.decode_file(path) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, {:toml_decode_failed, path, reason}}
    end
  rescue
    error in File.Error -> {:error, {:file_error, path, error.reason}}
  end

  defp validate_required(raw) do
    missing = Enum.reject(@required, &present?(Map.get(raw, &1)))

    case missing do
      [] -> :ok
      _ -> {:error, {:missing_required_keys, missing}}
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp validate_slug(slug) do
    if valid_slug?(slug), do: :ok, else: {:error, {:invalid_slug, slug}}
  end

  defp validate_cli_args(args) when is_list(args) do
    if Enum.all?(args, &is_binary/1) do
      {:ok, args}
    else
      {:error, {:invalid_cli_args, args}}
    end
  end

  defp validate_cli_args(args), do: {:error, {:invalid_cli_args, args}}

  defp resolve_cwd(root, cwd) do
    path = Path.expand(cwd, root)

    case File.mkdir_p(path) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, {:cwd_mkdir_failed, path, reason}}
    end
  end

  defp resolve_env(env) when is_map(env) do
    Enum.reduce_while(env, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case resolve_env_value(value) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:error, reason} -> {:halt, {:error, {key, reason}}}
      end
    end)
  end

  defp resolve_env(_env), do: {:error, :invalid_env_table}

  defp resolve_env_value("${" <> rest) do
    with true <- String.ends_with?(rest, "}"),
         name <- String.trim_trailing(rest, "}"),
         value when is_binary(value) <- System.get_env(name) do
      {:ok, value}
    else
      false -> {:ok, "${" <> rest}
      nil -> {:error, {:missing_env, String.trim_trailing(rest, "}")}}
    end
  end

  defp resolve_env_value(value) when is_binary(value), do: {:ok, value}

  defp resolve_env_value(value) when is_integer(value) or is_float(value) or is_boolean(value),
    do: {:ok, to_string(value)}

  defp resolve_env_value(value), do: {:error, {:invalid_env_value, value}}
end
