defmodule Babs.Knowledge do
  @moduledoc """
  Citizen-scoped markdown Knowledge Home CRUD.
  """

  alias Babs.Citizens.Knowledge.Config

  @temp_suffix ".babs.md.tmp"
  @stale_temp_age_ms 900_000

  @spec list(term(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def list(slug, opts \\ []) do
    with {:ok, guard_root, home} <- resolve_home(slug, opts),
         :ok <- reject_symlink_path(guard_root, home, ".", :list_knowledge) do
      list_home(slug, home, opts)
    end
  end

  @spec read(term(), term(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def read(slug, child_path, opts \\ []) do
    with {:ok, guard_root, path} <- resolve_markdown_path(slug, child_path, opts),
         :ok <- reject_symlink_path(guard_root, path, child_path) do
      case File.read(path) do
        {:ok, content} -> {:ok, content}
        {:error, :enoent} -> {:error, {:not_found, child_path}}
        {:error, reason} -> {:error, {:redacted_io_error, {:read_knowledge, reason}}}
      end
    end
  end

  @spec write(term(), term(), term(), keyword()) :: :ok | {:error, term()}
  def write(slug, child_path, content, opts \\ [])

  def write(_slug, _child_path, content, _opts) when not is_binary(content),
    do: {:error, {:invalid_content, :not_binary}}

  def write(slug, child_path, content, opts) do
    with {:ok, guard_root, path} <- resolve_markdown_path(slug, child_path, opts),
         :ok <- reject_symlink_path(guard_root, path, child_path),
         :ok <- mkdir_parent(path),
         # Re-check after mkdir_p because previously missing parents now exist.
         :ok <- reject_symlink_path(guard_root, path, child_path),
         :ok <- cleanup_stale_temp_files(path, opts),
         {:ok, temp_path} <- write_temp(path, content),
         :ok <- run_before_rename(opts, temp_path, path),
         :ok <- install_temp(temp_path, path) do
      :ok
    end
  end

  @spec delete(term(), term(), keyword()) :: :ok | {:error, term()}
  def delete(slug, child_path, opts \\ []) do
    with {:ok, guard_root, path} <- resolve_markdown_path(slug, child_path, opts),
         :ok <- reject_symlink_path(guard_root, path, child_path) do
      case File.rm(path) do
        :ok -> :ok
        {:error, :enoent} -> {:error, {:not_found, child_path}}
        {:error, reason} -> {:error, {:redacted_io_error, {:delete_knowledge, reason}}}
      end
    end
  end

  defp resolve_home(slug, opts) do
    case Config.resolve(slug, ".", opts) do
      {:ok, home} -> {:ok, symlink_guard_root(opts), home}
      {:error, reason} -> {:error, normalize_resolver_error(reason)}
    end
  end

  defp resolve_markdown_path(slug, child_path, opts) do
    with {:ok, path} <- resolve_child(slug, child_path, opts),
         :ok <- ensure_markdown_path(child_path),
         {:ok, _home} <- Config.citizen_home(slug, opts) do
      {:ok, symlink_guard_root(opts), path}
    end
  end

  defp symlink_guard_root(opts) do
    root = Config.root(opts)
    knowledge_root = Config.knowledge_root(opts)

    if inside_or_same?(knowledge_root, root), do: root, else: knowledge_root
  end

  defp inside_or_same?(path, root) do
    path = Path.expand(path)
    root = Path.expand(root)

    path == root or String.starts_with?(path, child_path_prefix(root))
  end

  defp child_path_prefix("/"), do: "/"
  defp child_path_prefix(root), do: root <> "/"

  defp resolve_child(slug, child_path, opts) do
    case Config.resolve(slug, child_path, opts) do
      {:ok, path} -> {:ok, path}
      {:error, reason} -> {:error, normalize_resolver_error(reason)}
    end
  end

  defp normalize_resolver_error({:invalid_relative_path, _value}),
    do: {:invalid_child_path, :not_string}

  defp normalize_resolver_error({:null_byte, _value}), do: {:invalid_child_path, :null_byte}
  defp normalize_resolver_error({:empty_relative_path, _value}), do: {:invalid_child_path, :empty}

  defp normalize_resolver_error({:non_relative_path, _value}),
    do: {:invalid_child_path, :non_relative}

  defp normalize_resolver_error({:path_traversal, _value}),
    do: {:invalid_child_path, :path_traversal}

  defp normalize_resolver_error({:path_escape, _value}), do: {:invalid_child_path, :path_escape}
  defp normalize_resolver_error({:invalid_slug, _slug} = reason), do: reason
  defp normalize_resolver_error(reason), do: reason

  defp ensure_markdown_path(child_path) when is_binary(child_path) do
    if String.ends_with?(child_path, ".md") do
      :ok
    else
      {:error, {:not_markdown, child_path}}
    end
  end

  defp list_home(slug, home, opts) do
    case File.ls(home) do
      {:ok, entries} ->
        entries
        |> Enum.sort()
        |> list_entries(slug, opts)

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, {:redacted_io_error, {:list_knowledge, reason}}}
    end
  end

  defp list_entries(entries, slug, opts) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, names} ->
      case list_entry(slug, entry, opts) do
        {:ok, nil} -> {:cont, {:ok, names}}
        {:ok, name} -> {:cont, {:ok, [name | names]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, names} -> {:ok, Enum.reverse(names)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp list_entry(slug, entry, opts) do
    if visible_markdown_entry?(entry) do
      case resolve_child(slug, entry, opts) do
        {:ok, path} -> inspect_list_entry(path, entry)
        {:error, _reason} -> {:ok, nil}
      end
    else
      {:ok, nil}
    end
  end

  defp visible_markdown_entry?(entry) do
    String.ends_with?(entry, ".md") and
      not (String.starts_with?(entry, ".") or String.starts_with?(entry, "~") or
             String.starts_with?(entry, "#") or String.ends_with?(entry, ".tmp") or
             String.ends_with?(entry, "~") or String.ends_with?(entry, "#"))
  end

  defp inspect_list_entry(path, entry) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular}} -> {:ok, entry}
      {:ok, _stat} -> {:ok, nil}
      {:error, :enoent} -> {:ok, nil}
      {:error, reason} -> {:error, {:redacted_io_error, {:list_knowledge, reason}}}
    end
  end

  defp reject_symlink_path(guard_root, path, child_path, operation \\ :inspect_knowledge_path) do
    guard_root
    |> path_chain(path)
    |> Enum.reduce_while(:ok, fn {component, current_path}, :ok ->
      case File.lstat(current_path) do
        {:ok, %File.Stat{type: :symlink}} ->
          {:halt, {:error, {:unsafe_symlink, %{path: child_path, component: component}}}}

        {:ok, _stat} ->
          {:cont, :ok}

        {:error, :enoent} ->
          {:halt, :ok}

        {:error, reason} ->
          {:halt, {:error, {:redacted_io_error, {operation, reason}}}}
      end
    end)
  end

  defp path_chain(guard_root, path) do
    guard_root = Path.expand(guard_root)
    path = Path.expand(path)

    case Path.relative_to(path, guard_root) do
      "." ->
        [{".", guard_root}]

      relative_path ->
        relative_path
        |> Path.split()
        |> Enum.scan([], fn segment, segments -> segments ++ [segment] end)
        |> Enum.map(fn segments -> {Path.join(segments), Path.join([guard_root | segments])} end)
        |> then(&[{".", guard_root} | &1])
    end
  end

  defp mkdir_parent(path) do
    case File.mkdir_p(Path.dirname(path)) do
      :ok -> :ok
      {:error, reason} -> {:error, {:redacted_io_error, {:mkdir_knowledge, reason}}}
    end
  end

  defp cleanup_stale_temp_files(path, opts) do
    dir = Path.dirname(path)
    temp_name_pattern = temp_name_pattern(Path.basename(path))
    stale_temp_age_ms = Keyword.get(opts, :stale_temp_age_ms, @stale_temp_age_ms)
    now_ms = System.system_time(:millisecond)

    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&Regex.match?(temp_name_pattern, &1))
        |> Enum.reduce_while(:ok, fn entry, :ok ->
          temp_path = Path.join(dir, entry)

          case stale_temp_file?(temp_path, stale_temp_age_ms, now_ms) do
            {:ok, true} -> remove_stale_temp_file(temp_path)
            {:ok, false} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      {:error, reason} ->
        {:error, {:redacted_io_error, {:cleanup_knowledge_temp, reason}}}
    end
  end

  defp temp_name_pattern(basename) do
    Regex.compile!("^\\.#{Regex.escape(basename)}\\.\\d+#{Regex.escape(@temp_suffix)}$")
  end

  defp stale_temp_file?(path, stale_temp_age_ms, now_ms) do
    case File.lstat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} ->
        {:ok, now_ms - mtime * 1_000 >= stale_temp_age_ms}

      {:error, :enoent} ->
        {:ok, false}

      {:error, reason} ->
        {:error, {:redacted_io_error, {:cleanup_knowledge_temp, reason}}}
    end
  end

  defp remove_stale_temp_file(path) do
    case File.rm(path) do
      :ok ->
        {:cont, :ok}

      {:error, :enoent} ->
        {:cont, :ok}

      {:error, reason} ->
        {:halt, {:error, {:redacted_io_error, {:cleanup_knowledge_temp, reason}}}}
    end
  end

  defp write_temp(final_path, content) do
    temp_path = temp_path(final_path)

    case File.write(temp_path, content) do
      :ok ->
        {:ok, temp_path}

      {:error, reason} ->
        File.rm(temp_path)
        {:error, {:redacted_io_error, {:write_knowledge_temp, reason}}}
    end
  end

  defp temp_path(final_path) do
    unique = System.unique_integer([:positive, :monotonic])
    Path.join(Path.dirname(final_path), ".#{Path.basename(final_path)}.#{unique}#{@temp_suffix}")
  end

  defp run_before_rename(opts, temp_path, final_path) do
    before_rename = Keyword.get(opts, :before_rename, fn _temp_path, _final_path -> :ok end)

    case before_rename.(temp_path, final_path) do
      :ok ->
        :ok

      {:error, reason} ->
        File.rm(temp_path)
        {:error, {:redacted_io_error, {:before_rename_knowledge, reason}}}

      other ->
        File.rm(temp_path)
        {:error, {:redacted_io_error, {:before_rename_knowledge, {:unexpected_return, other}}}}
    end
  end

  defp install_temp(temp_path, final_path) do
    case File.rename(temp_path, final_path) do
      :ok ->
        :ok

      {:error, reason} ->
        File.rm(temp_path)
        {:error, {:redacted_io_error, {:install_knowledge, reason}}}
    end
  end
end
