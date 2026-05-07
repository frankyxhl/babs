defmodule Babs.Citizens.Citizen.TomlWriter do
  @moduledoc """
  Writes the flat Citizen TOML shape used by Phase 1/3 configs.
  """

  alias Babs.Citizens.CitizenConfig

  @spec write(CitizenConfig.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def write(%CitizenConfig{} = config, opts \\ []) do
    root = root(opts)
    config_dir = config_dir(opts)
    dir = Path.join(root, config_dir)
    final_path = Path.join(dir, "citizen-#{config.slug}.toml")
    toml_cwd = Keyword.get(opts, :toml_cwd, config.cwd)

    with :ok <- mkdir_config_dir(dir),
         :ok <- cleanup_stale_temp_files(dir, config.slug, opts),
         :ok <- ensure_missing(final_path),
         {:ok, temp_path} <- write_temp_file(dir, config, toml_cwd),
         :ok <- ensure_missing(final_path),
         :ok <- install_temp_file(temp_path, final_path, opts) do
      {:ok, final_path}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp root(opts) do
    opts
    |> Keyword.get(:root, Application.get_env(:babs_citizens, :root, File.cwd!()))
    |> Path.expand()
  end

  defp config_dir(opts) do
    Keyword.get(opts, :config_dir, Application.get_env(:babs_citizens, :config_dir, "citizens"))
  end

  defp mkdir_config_dir(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, {:toml_config_dir_failed, dir, reason}}
    end
  end

  defp cleanup_stale_temp_files(dir, slug, opts) do
    prefix = ".citizen-#{slug}."

    list_dir = Keyword.get(opts, :list_dir, &File.ls/1)

    case list_dir.(dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&(String.starts_with?(&1, prefix) and String.ends_with?(&1, ".toml.tmp")))
        |> Enum.map(&Path.join(dir, &1))
        |> Enum.reduce_while(:ok, fn path, :ok ->
          case File.rm(path) do
            :ok -> {:cont, :ok}
            {:error, :enoent} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, {:toml_temp_cleanup_failed, path, reason}}}
          end
        end)

      {:error, reason} ->
        {:error, {:toml_temp_cleanup_failed, dir, reason}}
    end
  end

  defp ensure_missing(path) do
    if File.exists?(path) do
      {:error, {:toml_already_exists, path}}
    else
      :ok
    end
  end

  defp write_temp_file(dir, config, toml_cwd) do
    unique = System.unique_integer([:positive, :monotonic])
    temp_path = Path.join(dir, ".citizen-#{config.slug}.#{unique}.toml.tmp")

    case File.write(temp_path, content(config, toml_cwd)) do
      :ok -> {:ok, temp_path}
      {:error, reason} -> {:error, {:toml_write_failed, temp_path, reason}}
    end
  end

  defp install_temp_file(temp_path, final_path, opts) do
    before_install = Keyword.get(opts, :before_install, fn _final_path -> :ok end)

    with :ok <- before_install.(final_path) do
      case File.ln(temp_path, final_path) do
        :ok ->
          File.rm(temp_path)
          :ok

        {:error, :eexist} ->
          File.rm(temp_path)
          {:error, {:toml_already_exists, final_path}}

        {:error, reason} ->
          {:error, {:toml_install_failed, temp_path, final_path, reason}}
      end
    end
  end

  defp content(config, toml_cwd) do
    [
      line("id", config.id),
      line("slug", config.slug),
      line("display_name", config.display_name),
      maybe_line("description", config.description),
      line("cli", config.cli),
      "cli_args = #{array(config.cli_args || [])}",
      line("launch_profile", config.launch_profile || "safe_interactive"),
      line("cwd", toml_cwd),
      env_table(config.env || %{}),
      role_value(config.role)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp maybe_line(_key, nil), do: nil

  defp maybe_line(key, value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: line(key, value)
  end

  defp line(key, value), do: "#{key} = #{basic_string(value)}"

  defp array(values) when is_list(values) do
    values
    |> Enum.map(&basic_string/1)
    |> Enum.join(", ")
    |> then(&"[#{&1}]")
  end

  defp env_table(env) when map_size(env) == 0, do: nil

  defp env_table(env) do
    rows =
      env
      |> Enum.sort()
      |> Enum.map(fn {key, value} -> "#{key} = #{basic_string(value)}" end)

    Enum.join(["[env]" | rows], "\n")
  end

  defp role_value(nil), do: nil
  defp role_value(value) when is_binary(value), do: line("role", value)

  defp role_value(%{"name" => name} = role) do
    rows = ["name = #{basic_string(name)}"]

    rows =
      case Map.fetch(role, "skills") do
        {:ok, skills} -> rows ++ ["skills = #{array(skills)}"]
        :error -> rows
      end

    Enum.join(["[role]" | rows], "\n")
  end

  defp basic_string(value) when is_binary(value) do
    escaped =
      value
      |> String.to_charlist()
      |> Enum.map(&escape_char/1)

    [?", escaped, ?"]
  end

  defp escape_char(?"), do: "\\\""
  defp escape_char(?\\), do: "\\\\"
  defp escape_char(?\b), do: "\\b"
  defp escape_char(?\t), do: "\\t"
  defp escape_char(?\n), do: "\\n"
  defp escape_char(?\f), do: "\\f"
  defp escape_char(?\r), do: "\\r"

  defp escape_char(char) when char < 0x20 do
    "\\u" <> String.pad_leading(Integer.to_string(char, 16), 4, "0")
  end

  defp escape_char(char), do: char
end
