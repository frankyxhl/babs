defmodule Babs.Citizens.Spawner do
  @moduledoc """
  Creates browser-submitted Citizens and starts their Hardline lifecycle.
  """

  alias Babs.Citizens.Citizen.TomlWriter
  alias Babs.Citizens.{Catalog, CitizenConfig, CitizenRecord, Lifecycle, TicketBackend}

  @reserved_slugs ~w(new edit index)
  @param_atoms %{
    "slug" => :slug,
    "display_name" => :display_name,
    "description" => :description,
    "cli_preset" => :cli_preset,
    "ticket_backend" => :ticket_backend,
    "cwd" => :cwd
  }
  @presets %{
    "shell" => {"/bin/zsh", ["-f"], "safe_interactive"},
    "claude" => {"claude", [], "trusted_autonomous"},
    "codex" => {"codex", [], "trusted_autonomous"},
    "droid" => {"droid", [], "trusted_autonomous"},
    "pi" => {"pi", [], "trusted_autonomous"},
    "copilot-cli" => {"copilot", [], "trusted_autonomous"}
  }
  @direct_cli_presets ~w(claude codex copilot-cli)

  def presets, do: Map.keys(@presets)

  def ticket_backend_options, do: TicketBackend.browser_create_options()

  def create_and_start(params, opts \\ []) when is_map(params) do
    with {:ok, attrs} <- validate(params) do
      with_slug_lock(attrs.slug, opts, fn -> create_and_start_locked(attrs, opts) end)
    end
  end

  defp create_and_start_locked(attrs, opts) do
    with {:ok, paths} <- resolve_paths(attrs.cwd, opts),
         toml_path = citizen_toml_path(attrs.slug, opts),
         :ok <- ensure_no_existing_artifacts(attrs.slug, toml_path),
         {:ok, config} <- build_config(attrs, paths.resolved_cwd, toml_path),
         {:ok, _path} <- write_toml(config, paths.toml_cwd, opts),
         :ok <- mkdir_workspace(paths, opts),
         {:ok, record} <- insert_record(config, opts),
         :ok <- maybe_start_lifecycle(config, opts) do
      {:ok, record}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate(params) do
    slug = param(params, "slug") |> normalize_slug()
    display_name = param(params, "display_name") |> trim_to_nil()
    description = param(params, "description") |> trim_to_nil()
    preset = param(params, "cli_preset") |> trim_to_nil()
    ticket_backend = param(params, "ticket_backend") |> trim_to_nil() || "hardline"
    cwd = param(params, "cwd") |> trim_to_nil()

    errors =
      %{}
      |> validate_slug(slug)
      |> validate_display_name(display_name)
      |> validate_preset(preset)
      |> validate_ticket_backend(ticket_backend, preset)
      |> validate_cwd(cwd)

    if map_size(errors) == 0 do
      {:ok,
       %{
         slug: slug,
         display_name: display_name,
         description: description,
         cli_preset: preset,
         ticket_backend: ticket_backend,
         cwd: cwd || slug
       }}
    else
      {:error, {:validation_failed, errors}}
    end
  end

  defp param(params, key) do
    Map.get(params, key) || Map.get(params, Map.fetch!(@param_atoms, key))
  end

  defp normalize_slug(value) when is_binary(value),
    do: value |> String.trim() |> String.downcase()

  defp normalize_slug(_value), do: nil

  defp trim_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trim_to_nil(_value), do: nil

  defp validate_slug(errors, nil), do: Map.put(errors, :slug, "is required")

  defp validate_slug(errors, slug) do
    cond do
      slug in @reserved_slugs ->
        Map.put(errors, :slug, "is reserved")

      Babs.Citizens.Citizen.Config.valid_slug?(slug) ->
        errors

      true ->
        Map.put(
          errors,
          :slug,
          "must start with a lowercase letter and contain only lowercase letters, numbers, and dashes"
        )
    end
  end

  defp validate_display_name(errors, nil), do: Map.put(errors, :display_name, "is required")
  defp validate_display_name(errors, _display_name), do: errors

  defp validate_preset(errors, nil), do: Map.put(errors, :cli_preset, "is required")

  defp validate_preset(errors, preset) do
    if Map.has_key?(@presets, preset),
      do: errors,
      else: Map.put(errors, :cli_preset, "is not supported")
  end

  defp validate_ticket_backend(errors, nil, _preset),
    do: Map.put(errors, :ticket_backend, "is required")

  defp validate_ticket_backend(errors, "direct_cli", preset)
       when preset not in @direct_cli_presets do
    Map.put(errors, :ticket_backend, "requires a direct-capable CLI preset")
  end

  defp validate_ticket_backend(errors, ticket_backend, _preset) do
    if TicketBackend.browser_creatable?(ticket_backend) do
      errors
    else
      Map.put(errors, :ticket_backend, "is not supported for browser creation")
    end
  end

  defp validate_cwd(errors, nil), do: errors

  defp validate_cwd(errors, cwd) do
    cond do
      Path.type(cwd) == :absolute ->
        Map.put(errors, :cwd, "must be relative")

      cwd_escapes_workspace?(cwd) ->
        Map.put(errors, :cwd, "must stay inside workspace root")

      true ->
        errors
    end
  end

  defp cwd_escapes_workspace?(cwd) do
    cwd
    |> Path.split()
    |> Enum.any?(&(&1 == ".."))
  end

  defp resolve_paths(relative_cwd, opts) do
    root = root(opts)
    workspace_root = workspace_root(opts, root)
    resolved_cwd = Path.expand(relative_cwd, workspace_root)

    if path_inside?(resolved_cwd, workspace_root) do
      {:ok,
       %{
         toml_cwd: relative_cwd,
         resolved_cwd: resolved_cwd,
         workspace_root: workspace_root
       }}
    else
      {:error, {:cwd_escapes_workspace, relative_cwd}}
    end
  end

  defp path_inside?(path, root) do
    with {:ok, expanded_path} <- realish_path(path),
         {:ok, expanded_root} <- realish_path(root) do
      inside_path?(expanded_path, expanded_root)
    else
      {:error, _reason} -> false
    end
  end

  defp inside_path?(expanded_path, "/"), do: String.starts_with?(expanded_path, "/")

  defp inside_path?(expanded_path, expanded_root) do
    expanded_path == expanded_root or String.starts_with?(expanded_path, expanded_root <> "/")
  end

  defp realish_path(path) do
    resolve_symlinks(Path.expand(path), 0)
  end

  defp resolve_symlinks(_path, hops) when hops > 32, do: {:error, :too_many_symlinks}

  defp resolve_symlinks(path, hops) do
    [root | segments] = Path.split(path)
    resolve_segments(root, segments, hops)
  end

  defp resolve_segments(current, [], _hops), do: {:ok, Path.expand(current)}

  defp resolve_segments(current, [segment | rest], hops) do
    next = Path.join(current, segment)

    case File.lstat(next) do
      {:ok, %File.Stat{type: :symlink}} ->
        with {:ok, target} <- File.read_link(next) do
          target_path = Path.expand(target, current)
          remaining = if rest == [], do: "", else: Path.join(rest)
          next_path = if remaining == "", do: target_path, else: Path.join(target_path, remaining)
          resolve_symlinks(next_path, hops + 1)
        end

      {:ok, _stat} ->
        resolve_segments(next, rest, hops)

      {:error, :enoent} ->
        {:ok, Path.expand(Path.join([next | rest]))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_config(attrs, resolved_cwd, toml_path) do
    {cli, cli_args, launch_profile} = Map.fetch!(@presets, attrs.cli_preset)

    {:ok,
     %CitizenConfig{
       id: CitizenRecord.generate_id(),
       slug: attrs.slug,
       display_name: attrs.display_name,
       description: attrs.description,
       cli: cli,
       cli_args: cli_args,
       launch_profile: launch_profile,
       ticket_backend: attrs.ticket_backend,
       cwd: resolved_cwd,
       env: %{},
       role: nil,
       path: toml_path
     }}
  end

  defp ensure_no_existing_artifacts(slug, toml_path) do
    cond do
      File.exists?(toml_path) ->
        {:error, {:duplicate_toml, toml_path}}

      Catalog.get_by_slug(slug) ->
        {:error, {:duplicate_sqlite, slug}}

      true ->
        :ok
    end
  end

  defp write_toml(config, toml_cwd, opts) do
    writer = Keyword.get(opts, :toml_writer, &TomlWriter.write/2)
    writer.(config, Keyword.put(opts, :toml_cwd, toml_cwd))
  end

  defp mkdir_workspace(paths, opts) do
    case Keyword.fetch(opts, :mkdir) do
      {:ok, mkdir} ->
        with :ok <- ensure_workspace_path_inside(paths),
             :ok <- run_mkdir(mkdir, paths.resolved_cwd),
             :ok <- ensure_workspace_path_inside(paths) do
          :ok
        end

      :error ->
        with :ok <- File.mkdir_p(paths.workspace_root),
             :ok <- mkdir_workspace_inside(paths),
             :ok <- ensure_workspace_path_inside(paths) do
          :ok
        else
          {:error, {:cwd_escapes_workspace, _relative_cwd}} = error -> error
          {:error, {:workspace_mkdir_failed, _reason}} = error -> error
          {:error, reason} -> {:error, {:workspace_mkdir_failed, reason}}
        end
    end
  end

  defp run_mkdir(mkdir, path) do
    case mkdir.(path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:workspace_mkdir_failed, reason}}
    end
  end

  defp mkdir_workspace_inside(paths) do
    paths.resolved_cwd
    |> relative_segments!(paths.workspace_root)
    |> mkdir_segments(paths.workspace_root, paths)
  end

  defp relative_segments!(path, "/") do
    path
    |> Path.expand()
    |> String.trim_leading("/")
    |> path_segments()
  end

  defp relative_segments!(path, root) do
    expanded_path = Path.expand(path)
    expanded_root = Path.expand(root)

    cond do
      expanded_path == expanded_root ->
        []

      String.starts_with?(expanded_path, expanded_root <> "/") ->
        expanded_path
        |> String.replace_prefix(expanded_root <> "/", "")
        |> path_segments()
    end
  end

  defp path_segments(""), do: []
  defp path_segments(path), do: Path.split(path)

  defp mkdir_segments([], _current, _paths), do: :ok

  defp mkdir_segments([segment | rest], current, paths) do
    next = Path.join(current, segment)
    next_paths = %{paths | resolved_cwd: next}

    with :ok <- ensure_workspace_path_inside(next_paths),
         :ok <- mkdir_segment(next, paths),
         :ok <- ensure_workspace_path_inside(next_paths) do
      mkdir_segments(rest, next, paths)
    end
  end

  defp mkdir_segment(path, paths) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :directory}} ->
        :ok

      {:ok, %File.Stat{type: :symlink}} ->
        {:error, {:cwd_escapes_workspace, paths.toml_cwd}}

      {:ok, _stat} ->
        {:error, {:workspace_mkdir_failed, :enotdir}}

      {:error, :enoent} ->
        case File.mkdir(path) do
          :ok -> :ok
          {:error, :eexist} -> mkdir_segment(path, paths)
          {:error, reason} -> {:error, {:workspace_mkdir_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:workspace_mkdir_failed, reason}}
    end
  end

  defp ensure_workspace_path_inside(paths) do
    if path_inside?(paths.resolved_cwd, paths.workspace_root) do
      :ok
    else
      {:error, {:cwd_escapes_workspace, paths.toml_cwd}}
    end
  end

  defp insert_record(config, opts) do
    insert = Keyword.get(opts, :insert, &Catalog.insert_new/2)

    case call_insert(insert, config, initial_status(config)) do
      {:ok, record} -> {:ok, record}
      {:error, reason} -> {:error, {:sqlite_insert_failed, reason}}
    end
  end

  defp call_insert(insert, config, initial_status) do
    case :erlang.fun_info(insert, :arity) do
      {:arity, 1} -> insert.(config)
      {:arity, 2} -> insert.(config, initial_status: initial_status)
    end
  end

  defp initial_status(%CitizenConfig{ticket_backend: "direct_cli"}), do: "stopped"
  defp initial_status(_config), do: "running"

  defp maybe_start_lifecycle(%CitizenConfig{ticket_backend: "direct_cli"}, _opts), do: :ok

  defp maybe_start_lifecycle(config, opts) do
    with {:ok, _pid} <- start_lifecycle(config, opts), do: :ok
  end

  defp start_lifecycle(config, opts) do
    start = Keyword.get(opts, :lifecycle_start, &Lifecycle.start_config/1)

    try do
      case start.(config) do
        {:ok, _pid} = ok ->
          ok

        {:error, reason} ->
          {:error,
           {:lifecycle_start_failed, ensure_redacted_lifecycle_error(config.slug, reason)}}
      end
    rescue
      error ->
        reason = {error.__struct__, Exception.message(error)}
        persist_lifecycle_failure(config, reason)
    catch
      kind, reason ->
        persist_lifecycle_failure(config, {kind, reason})
    end
  end

  defp persist_lifecycle_failure(config, reason) do
    case Catalog.mark_failed(config.slug, reason) do
      {:ok, failed} -> {:error, {:lifecycle_start_failed, failed.last_error}}
      {:error, _reason} -> {:error, {:lifecycle_start_failed, Catalog.redact_reason(reason)}}
    end
  end

  defp ensure_redacted_lifecycle_error(slug, reason) do
    case Catalog.get_by_slug(slug) do
      %CitizenRecord{last_error: last_error} when is_binary(last_error) and last_error != "" ->
        last_error

      %CitizenRecord{} ->
        case Catalog.mark_failed(slug, reason) do
          {:ok, failed} -> failed.last_error
          {:error, _reason} -> Catalog.redact_reason(reason)
        end

      nil ->
        Catalog.redact_reason(reason)
    end
  end

  defp with_slug_lock(slug, opts, fun) do
    case acquire_lock(slug, lock_deadline(opts)) do
      :ok ->
        try do
          fun.()
        after
          Registry.unregister(Babs.Citizens.SpawnerRegistry, slug)
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp acquire_lock(slug, deadline) do
    case Registry.register(Babs.Citizens.SpawnerRegistry, slug, nil) do
      {:ok, _pid} ->
        :ok

      {:error, {:already_registered, _pid}} ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, {:spawn_lock_timeout, slug}}
        else
          Process.sleep(10)
          acquire_lock(slug, deadline)
        end
    end
  end

  defp lock_deadline(opts) do
    timeout_ms = Keyword.get(opts, :lock_timeout_ms, 5_000)
    System.monotonic_time(:millisecond) + timeout_ms
  end

  defp citizen_toml_path(slug, opts) do
    root = root(opts)
    Path.join([root, config_dir(opts), "citizen-#{slug}.toml"])
  end

  defp root(opts) do
    opts
    |> Keyword.get(:root, Application.get_env(:babs_citizens, :root, File.cwd!()))
    |> Path.expand()
  end

  defp config_dir(opts) do
    Keyword.get(opts, :config_dir, Application.get_env(:babs_citizens, :config_dir, "citizens"))
  end

  defp workspace_root(opts, root) do
    case Keyword.get(opts, :workspace_root, Application.get_env(:babs_citizens, :workspace_root)) do
      value when is_binary(value) and value != "" -> Path.expand(value, root)
      _value -> Path.join(root, "workspaces")
    end
  end
end
