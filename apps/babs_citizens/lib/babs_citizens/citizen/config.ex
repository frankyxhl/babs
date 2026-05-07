defmodule Babs.Citizens.Citizen.Config do
  @moduledoc """
  Loads Phase 1 `citizens/citizen-<slug>.toml` files.
  """

  require Logger

  alias Babs.Citizens.CitizenConfig

  @slug_regex ~r/^[a-z][a-z0-9-]{0,47}$/
  @required ~w(id slug display_name cli cwd)
  @launch_profiles ~w(safe_interactive trusted_autonomous)
  @ticket_backends ~w(hardline direct_cli lazy_tmux)

  def load_slug(slug, opts \\ []) when is_binary(slug) do
    root = root(opts)
    config_dir = config_dir(opts)

    root
    |> Path.join(config_dir)
    |> Path.join("citizen-#{slug}.toml")
    |> load_file(opts)
  end

  def load_file(path, opts \\ []) when is_binary(path) do
    root = root(opts)
    workspace_root = workspace_root(opts, root)
    create_cwd = Keyword.get(opts, :create_cwd, true)

    with {:ok, raw} <- decode_file(path),
         :ok <- validate_required(raw),
         :ok <- validate_slug(raw["slug"]),
         {:ok, cli_args} <- validate_cli_args(Map.get(raw, "cli_args", [])),
         {:ok, launch_profile} <- validate_launch_profile(Map.get(raw, "launch_profile")),
         {:ok, ticket_backend} <- validate_ticket_backend(Map.get(raw, "ticket_backend")),
         {:ok, env} <- resolve_env(Map.get(raw, "env", %{})),
         {:ok, cwd} <- resolve_cwd(workspace_root, raw["cwd"], create_cwd) do
      {:ok,
       %CitizenConfig{
         id: raw["id"],
         slug: raw["slug"],
         display_name: raw["display_name"],
         cli: raw["cli"],
         cli_args: cli_args,
         launch_profile: launch_profile,
         ticket_backend: ticket_backend,
         cwd: cwd,
         description: Map.get(raw, "description"),
         env: env,
         role: Map.get(raw, "role"),
         path: path
       }}
    end
  end

  def list_configs(opts \\ []) do
    root = root(opts)
    config_dir = config_dir(opts)

    dir = Path.join(root, config_dir)

    dir
    |> Path.join("citizen-*.toml")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&load_file(&1, Keyword.put(opts, :root, root)))
  end

  def valid_slug?(slug) when is_binary(slug), do: Regex.match?(@slug_regex, slug)
  def valid_slug?(_slug), do: false

  defp root(opts) do
    opts
    |> Keyword.get(:root, Application.get_env(:babs_citizens, :root, File.cwd!()))
    |> Path.expand()
  end

  defp config_dir(opts) do
    Keyword.get(opts, :config_dir, Application.get_env(:babs_citizens, :config_dir, "citizens"))
  end

  defp workspace_root(opts, root) do
    default = default_workspace_root(root)

    case Keyword.get(opts, :workspace_root, Application.get_env(:babs_citizens, :workspace_root)) do
      value when is_binary(value) ->
        value = String.trim(value)

        if value == "" do
          default
        else
          Path.expand(value, root)
        end

      nil ->
        default

      value ->
        Logger.warning(
          "Babs citizen workspace_root #{inspect(value)} is not a string; falling back to #{inspect(default)}"
        )

        default
    end
  end

  defp default_workspace_root(root), do: Path.join(root, "workspaces")

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

  defp validate_launch_profile(nil), do: {:ok, "safe_interactive"}

  defp validate_launch_profile(profile) when profile in @launch_profiles, do: {:ok, profile}

  defp validate_launch_profile(profile), do: {:error, {:invalid_launch_profile, profile}}

  defp validate_ticket_backend(nil), do: {:ok, "hardline"}

  defp validate_ticket_backend(backend) when backend in @ticket_backends, do: {:ok, backend}

  defp validate_ticket_backend(backend), do: {:error, {:invalid_ticket_backend, backend}}

  defp resolve_cwd(workspace_root, cwd, create_cwd) do
    maybe_warn_legacy_cwd(cwd)
    path = Path.expand(cwd, workspace_root)

    if create_cwd do
      case File.mkdir_p(path) do
        :ok -> {:ok, path}
        {:error, reason} -> {:error, {:cwd_mkdir_failed, path, reason}}
      end
    else
      {:ok, path}
    end
  end

  defp maybe_warn_legacy_cwd(cwd) when is_binary(cwd) do
    unless Path.type(cwd) == :absolute do
      normalized =
        cwd
        |> Path.split()
        |> Enum.drop_while(&(&1 == "."))

      if List.first(normalized) == "workspaces" do
        Logger.warning(
          "Babs citizen config uses legacy cwd #{inspect(cwd)}; Phase 2a resolves relative cwd values under workspace_root, so migrate seed-style configs to cwd = \"<slug>\" or use an absolute cwd for compatibility"
        )
      end
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
