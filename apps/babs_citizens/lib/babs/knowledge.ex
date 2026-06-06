defmodule Babs.Knowledge do
  @moduledoc """
  Citizen-scoped markdown Knowledge Home CRUD.
  """

  alias Babs.Citizens.Knowledge.Config

  @temp_suffix ".babs.md.tmp"
  @stale_temp_age_ms 900_000
  @temp_write_attempts 16

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
         {:ok, temp_path} <- write_temp(path, content, opts),
         :ok <- maybe_reject_existing_final(opts, temp_path, path, child_path),
         :ok <- run_before_rename(opts, temp_path, path),
         :ok <- install_temp(temp_path, path, child_path, opts) do
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

    if inside_or_same?(knowledge_root, root) do
      root
    else
      common_path_prefix(root, knowledge_root)
    end
  end

  defp common_path_prefix(left, right) do
    left
    |> Path.expand()
    |> Path.split()
    |> Enum.zip(Path.expand(right) |> Path.split())
    |> Enum.take_while(fn {left_segment, right_segment} -> left_segment == right_segment end)
    |> Enum.map(fn {segment, _segment} -> segment end)
    |> case do
      [] -> "."
      segments -> Path.join(segments)
    end
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
    with {:ok, chain} <- path_chain(guard_root, path, operation) do
      Enum.reduce_while(chain, :ok, fn {component, current_path}, :ok ->
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
  end

  defp path_chain(guard_root, path, operation) do
    guard_root = Path.expand(guard_root)
    path = Path.expand(path)

    case safe_relative_to(path, guard_root) do
      {:ok, "."} ->
        {:ok, [{".", guard_root}]}

      {:ok, relative_path} ->
        chain =
          relative_path
          |> Path.split()
          |> Enum.scan([], fn segment, segments -> segments ++ [segment] end)
          |> Enum.map(fn segments ->
            {Path.join(segments), Path.join([guard_root | segments])}
          end)
          |> then(&[{".", guard_root} | &1])

        {:ok, chain}

      :error ->
        {:error, {:redacted_io_error, {operation, :path_escape}}}
    end
  end

  defp safe_relative_to(path, guard_root) do
    relative_path = Path.relative_to(path, guard_root)

    cond do
      relative_path == "." ->
        {:ok, "."}

      Path.type(relative_path) == :relative and
          not Enum.any?(Path.split(relative_path), &(&1 == "..")) ->
        {:ok, relative_path}

      true ->
        :error
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
    Regex.compile!("^\\.#{Regex.escape(basename)}\\.[A-Za-z0-9_-]+#{Regex.escape(@temp_suffix)}$")
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

  defp write_temp(final_path, content, opts) do
    write_temp(final_path, content, opts, @temp_write_attempts)
  end

  defp write_temp(_final_path, _content, _opts, 0) do
    {:error, {:redacted_io_error, {:write_knowledge_temp, :eexist}}}
  end

  defp write_temp(final_path, content, opts, attempts_left) do
    temp_path = temp_path(final_path, opts)

    case File.open(temp_path, [:write, :exclusive, :binary], fn file ->
           IO.binwrite(file, content)
         end) do
      {:ok, :ok} ->
        {:ok, temp_path}

      {:ok, {:error, reason}} ->
        File.rm(temp_path)
        {:error, {:redacted_io_error, {:write_knowledge_temp, reason}}}

      {:error, :eexist} ->
        write_temp(final_path, content, opts, attempts_left - 1)

      {:error, reason} ->
        File.rm(temp_path)
        {:error, {:redacted_io_error, {:write_knowledge_temp, reason}}}
    end
  end

  defp temp_path(final_path, opts) do
    token = temp_token(opts)
    Path.join(Path.dirname(final_path), ".#{Path.basename(final_path)}.#{token}#{@temp_suffix}")
  end

  defp temp_token(opts) do
    case Keyword.get(opts, :temp_token_fun) do
      fun when is_function(fun, 0) -> sanitize_temp_token(fun.())
      _fun -> random_temp_token()
    end
  end

  defp sanitize_temp_token(token) when is_binary(token) do
    token
    |> String.replace(~r/[^A-Za-z0-9_-]/, "")
    |> case do
      "" -> random_temp_token()
      token -> token
    end
  end

  defp sanitize_temp_token(_token), do: random_temp_token()

  defp random_temp_token do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
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

  defp maybe_reject_existing_final(opts, temp_path, final_path, child_path) do
    if Keyword.get(opts, :if_exists) == :error do
      case File.lstat(final_path) do
        {:ok, _stat} ->
          File.rm(temp_path)
          {:error, {:knowledge_file_exists, child_path}}

        {:error, :enoent} ->
          :ok

        {:error, reason} ->
          File.rm(temp_path)
          {:error, {:redacted_io_error, {:inspect_knowledge, reason}}}
      end
    else
      :ok
    end
  end

  defp install_temp(temp_path, final_path, child_path, opts) do
    if Keyword.get(opts, :if_exists) == :error do
      install_temp_exclusive(temp_path, final_path, child_path)
    else
      install_temp_replace(temp_path, final_path)
    end
  end

  defp install_temp_replace(temp_path, final_path) do
    case File.rename(temp_path, final_path) do
      :ok ->
        :ok

      {:error, reason} ->
        File.rm(temp_path)
        {:error, {:redacted_io_error, {:install_knowledge, reason}}}
    end
  end

  defp install_temp_exclusive(temp_path, final_path, child_path) do
    case File.ln(temp_path, final_path) do
      :ok ->
        remove_installed_temp(temp_path)

      {:error, :eexist} ->
        File.rm(temp_path)
        {:error, {:knowledge_file_exists, child_path}}

      {:error, reason} ->
        File.rm(temp_path)
        {:error, {:redacted_io_error, {:install_knowledge, reason}}}
    end
  end

  defp remove_installed_temp(temp_path) do
    case File.rm(temp_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, {:redacted_io_error, {:cleanup_knowledge_temp, reason}}}
    end
  end
end
