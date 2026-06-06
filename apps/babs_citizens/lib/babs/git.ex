defmodule Babs.Git do
  @moduledoc """
  Workspace-scoped git reader for operator review surfaces.

  Commands are executed without a shell and are constrained to the caller's
  workspace directory.
  """

  @default_max_bytes 65_536
  @default_max_count 20
  @max_count_range 1..100
  @truncation_marker "\n[TRUNCATED]"
  @min_max_bytes byte_size(@truncation_marker) + 1
  @git_config_overrides ["-c", "core.fsmonitor=false"]
  @untracked_files_args ["ls-files", "--others", "--exclude-standard", "-z"]

  @type bounded_text :: %{text: String.t(), truncated?: boolean()}
  @type status_result :: %{text: String.t(), clean?: boolean(), truncated?: boolean()}
  @type branch_result :: %{name: String.t(), detached?: boolean(), truncated?: boolean()}
  @type log_result :: %{text: String.t(), truncated?: boolean()}
  @type diff_result :: %{text: String.t(), truncated?: boolean(), base: String.t() | nil}
  @type git_failure :: %{
          args: [String.t()],
          exit_status: non_neg_integer(),
          output: String.t(),
          truncated?: boolean()
        }
  @type error ::
          {:invalid_workspace, :not_binary}
          | {:invalid_workspace, :not_directory}
          | {:git_executable_not_found, String.t()}
          | {:not_git_repo, %{output: String.t(), truncated?: boolean()}}
          | {:invalid_base, :blank | :null_byte | :starts_with_dash | :not_binary}
          | {:invalid_max_bytes, term()}
          | {:invalid_max_count, term()}
          | {:git_failed, git_failure()}

  @spec status(term(), keyword()) :: {:ok, status_result()} | {:error, error()}
  def status(workspace, opts \\ []) do
    with {:ok, workspace, max_bytes} <- context(workspace, opts) do
      case git_cmd(workspace, ["status", "--porcelain=v1"]) do
        {:ok, output} ->
          bounded = bound_text(output, max_bytes)

          {:ok,
           %{
             text: bounded.text,
             clean?: String.trim(output) == "",
             truncated?: bounded.truncated?
           }}

        {:error, {status, output, args}} ->
          {:error, {:git_failed, git_failure(args, status, output, max_bytes)}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec branch(term(), keyword()) :: {:ok, branch_result()} | {:error, error()}
  def branch(workspace, opts \\ []) do
    with {:ok, workspace, max_bytes} <- context(workspace, opts) do
      branch_name(workspace, max_bytes)
    end
  end

  @spec log(term(), keyword()) :: {:ok, log_result()} | {:error, error()}
  def log(workspace, opts \\ []) do
    with {:ok, max_count} <- max_count(opts),
         {:ok, workspace, max_bytes} <- context(workspace, opts) do
      if head?(workspace) do
        run_git(
          workspace,
          ["log", "--oneline", "--decorate", "-n", Integer.to_string(max_count)],
          max_bytes
        )
      else
        {:ok, %{text: "", truncated?: false}}
      end
    end
  end

  @spec diff(term(), keyword()) :: {:ok, diff_result()} | {:error, error()}
  def diff(workspace, opts \\ []) do
    with {:ok, base} <- diff_base(opts),
         {:ok, workspace, max_bytes} <- context(workspace, opts) do
      case run_diff(workspace, base, max_bytes) do
        {:ok, result} -> {:ok, Map.put(result, :base, base)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp context(workspace, opts) do
    with {:ok, workspace} <- validate_workspace(workspace),
         {:ok, max_bytes} <- max_bytes(opts),
         :ok <- ensure_git_available(),
         :ok <- ensure_git_repo(workspace, max_bytes) do
      {:ok, workspace, max_bytes}
    end
  end

  defp validate_workspace(workspace) when is_binary(workspace) do
    workspace = Path.expand(workspace)

    if File.dir?(workspace) do
      {:ok, workspace}
    else
      {:error, {:invalid_workspace, :not_directory}}
    end
  end

  defp validate_workspace(_workspace), do: {:error, {:invalid_workspace, :not_binary}}

  defp max_bytes(opts) do
    value = Keyword.get(opts, :max_bytes, @default_max_bytes)

    if is_integer(value) and value >= @min_max_bytes do
      {:ok, value}
    else
      {:error, {:invalid_max_bytes, value}}
    end
  end

  defp max_count(opts) do
    value = Keyword.get(opts, :max_count, @default_max_count)

    if is_integer(value) and value in @max_count_range do
      {:ok, value}
    else
      {:error, {:invalid_max_count, value}}
    end
  end

  defp diff_base(opts) do
    case Keyword.fetch(opts, :base) do
      :error ->
        {:ok, nil}

      {:ok, base} when is_binary(base) ->
        trimmed = String.trim(base)

        cond do
          String.contains?(base, <<0>>) -> {:error, {:invalid_base, :null_byte}}
          trimmed == "" -> {:error, {:invalid_base, :blank}}
          String.starts_with?(trimmed, "-") -> {:error, {:invalid_base, :starts_with_dash}}
          true -> {:ok, trimmed}
        end

      {:ok, _base} ->
        {:error, {:invalid_base, :not_binary}}
    end
  end

  defp ensure_git_available do
    if System.find_executable("git") do
      :ok
    else
      {:error, {:git_executable_not_found, "git"}}
    end
  end

  defp ensure_git_repo(workspace, max_bytes) do
    args = ["rev-parse", "--is-inside-work-tree"]

    case git_cmd(workspace, args) do
      {:ok, output} ->
        if String.trim(output) == "true" do
          :ok
        else
          {:error, {:not_git_repo, output_error(output, max_bytes)}}
        end

      {:error, {_status, output, _args}} ->
        {:error, {:not_git_repo, output_error(output, max_bytes)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp branch_name(workspace, max_bytes) do
    case run_git(workspace, ["symbolic-ref", "--quiet", "--short", "HEAD"], max_bytes) do
      {:ok, %{text: text, truncated?: truncated?}} ->
        {:ok, %{name: String.trim(text), detached?: false, truncated?: truncated?}}

      {:error, {:git_failed, _failure}} ->
        detached_or_unborn_branch(workspace, max_bytes)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp detached_or_unborn_branch(workspace, max_bytes) do
    if head?(workspace) do
      case run_git(workspace, ["rev-parse", "--short", "HEAD"], max_bytes) do
        {:ok, %{text: text, truncated?: truncated?}} ->
          {:ok, %{name: String.trim(text), detached?: true, truncated?: truncated?}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, %{name: "", detached?: false, truncated?: false}}
    end
  end

  defp head?(workspace) do
    case git_cmd(workspace, ["rev-parse", "--verify", "HEAD"]) do
      {:ok, _output} -> true
      _other -> false
    end
  end

  defp run_diff(workspace, base, max_bytes) when is_binary(base) do
    run_git_diff(workspace, ["diff", "--no-ext-diff", "--no-textconv", base, "--"], max_bytes)
  end

  defp run_diff(workspace, nil, max_bytes) do
    if head?(workspace) do
      run_git_diff(workspace, ["diff", "--no-ext-diff", "--no-textconv", "HEAD", "--"], max_bytes)
    else
      run_unborn_diff(workspace, max_bytes)
    end
  end

  defp run_unborn_diff(workspace, max_bytes) do
    with {:ok, cached} <-
           git_cmd(workspace, ["diff", "--no-ext-diff", "--no-textconv", "--cached", "--"]),
         {:ok, worktree} <- git_cmd(workspace, ["diff", "--no-ext-diff", "--no-textconv", "--"]),
         {:ok, untracked} <- untracked_diff(workspace, max_bytes) do
      {:ok, cached |> join_diff(worktree) |> join_diff(untracked) |> bound_text(max_bytes)}
    else
      {:error, {status, output, args}} ->
        {:error, {:git_failed, git_failure(args, status, output, max_bytes)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp join_diff("", right), do: right
  defp join_diff(left, ""), do: left
  defp join_diff(left, right), do: left <> "\n" <> right

  defp run_git_diff(workspace, args, max_bytes) do
    with {:ok, tracked} <- git_cmd(workspace, args),
         {:ok, untracked} <- untracked_diff(workspace, max_bytes) do
      {:ok, tracked |> join_diff(untracked) |> bound_text(max_bytes)}
    else
      {:error, {status, output, executed_args}} ->
        {:error, {:git_failed, git_failure(executed_args, status, output, max_bytes)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp untracked_diff(workspace, max_bytes) do
    case git_cmd(workspace, @untracked_files_args) do
      {:ok, ""} ->
        {:ok, ""}

      {:ok, output} ->
        output
        |> nul_split()
        |> Enum.reject(&(&1 == ""))
        |> Enum.reduce_while({:ok, [], 0}, fn relative_path, {:ok, acc, bytes} ->
          case untracked_file_diff(workspace, relative_path, max_bytes) do
            {:ok, ""} ->
              {:cont, {:ok, acc, bytes}}

            {:ok, diff} ->
              bytes = bytes + byte_size(diff) + join_separator_size(acc)

              if bytes > max_bytes do
                {:halt, {:ok, [diff | acc], bytes}}
              else
                {:cont, {:ok, [diff | acc], bytes}}
              end

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end)
        |> case do
          {:ok, diffs, _bytes} -> {:ok, diffs |> Enum.reverse() |> Enum.join("\n")}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp join_separator_size([]), do: 0
  defp join_separator_size(_acc), do: 1

  defp nul_split(value), do: :binary.split(value, <<0>>, [:global])

  defp untracked_file_diff(workspace, relative_path, max_bytes) do
    with {:ok, path} <- safe_workspace_path(workspace, relative_path, max_bytes),
         {:ok, stat} <- lstat_untracked(path, max_bytes) do
      case stat.type do
        :regular -> untracked_regular_file_diff(relative_path, path, max_bytes)
        :symlink -> untracked_symlink_diff(relative_path, path, max_bytes)
        _other -> {:ok, ""}
      end
    end
  end

  defp safe_workspace_path(workspace, relative_path, max_bytes) do
    workspace = Path.expand(workspace)
    path = Path.expand(relative_path, workspace)

    if path != workspace and String.starts_with?(path, child_path_prefix(workspace)) do
      {:ok, path}
    else
      {:error, {:git_failed, git_failure(@untracked_files_args, 1, "invalid path", max_bytes)}}
    end
  end

  defp child_path_prefix("/"), do: "/"
  defp child_path_prefix(path), do: path <> "/"

  defp lstat_untracked(path, max_bytes) do
    case File.lstat(path) do
      {:ok, stat} ->
        {:ok, stat}

      {:error, :enoent} ->
        {:ok, %{type: :missing}}

      {:error, reason} ->
        {:error, {:git_failed, git_failure(@untracked_files_args, 1, inspect(reason), max_bytes)}}
    end
  end

  defp untracked_regular_file_diff(relative_path, path, max_bytes) do
    case File.open(path, [:read, :binary], &IO.binread(&1, max_bytes + 1)) do
      {:ok, content} ->
        {:ok, new_file_diff(relative_path, "100644", content)}

      {:error, :enoent} ->
        {:ok, ""}

      {:error, reason} ->
        {:error, {:git_failed, git_failure(@untracked_files_args, 1, inspect(reason), max_bytes)}}
    end
  end

  defp untracked_symlink_diff(relative_path, path, max_bytes) do
    case File.read_link(path) do
      {:ok, target} ->
        {:ok, new_file_diff(relative_path, "120000", target)}

      {:error, :enoent} ->
        {:ok, ""}

      {:error, reason} ->
        {:error, {:git_failed, git_failure(@untracked_files_args, 1, inspect(reason), max_bytes)}}
    end
  end

  defp new_file_diff(relative_path, mode, content) do
    display_path = display_path(relative_path)
    lines = added_lines(content)

    [
      "diff --git a/#{display_path} b/#{display_path}\n",
      "new file mode #{mode}\n",
      "--- /dev/null\n",
      "+++ b/#{display_path}\n",
      "@@ -0,0 +1,#{length(lines)} @@\n",
      Enum.map(lines, &["+", &1, "\n"])
    ]
    |> IO.iodata_to_binary()
  end

  defp added_lines(content) do
    content
    |> normalize_text()
    |> String.split("\n", trim: false)
    |> case do
      [""] -> []
      lines -> drop_trailing_empty_line(lines)
    end
  end

  defp drop_trailing_empty_line(lines) do
    if List.last(lines) == "" do
      Enum.drop(lines, -1)
    else
      lines
    end
  end

  defp display_path(path) do
    path
    |> normalize_text()
    |> String.replace("\n", "\\n")
  end

  defp run_git(workspace, args, max_bytes) do
    case git_cmd(workspace, args) do
      {:ok, output} ->
        {:ok, bound_text(output, max_bytes)}

      {:error, {status, output, executed_args}} ->
        {:error, {:git_failed, git_failure(executed_args, status, output, max_bytes)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp git_cmd(workspace, args) do
    safe_args = safe_git_args(workspace, args)

    case System.cmd("git", safe_args, cd: workspace, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, status} -> {:error, {status, output, safe_args}}
    end
  rescue
    error in ErlangError ->
      if error.original == :enoent do
        {:error, {:git_executable_not_found, "git"}}
      else
        reraise(error, __STACKTRACE__)
      end
  end

  defp safe_git_args(workspace, args) do
    @git_config_overrides ++ filter_config_overrides(workspace) ++ args
  end

  defp filter_config_overrides(workspace) do
    args = @git_config_overrides ++ ["config", "--get-regexp", "^filter\\..*\\.(clean|process)$"]

    case System.cmd("git", args, cd: workspace, stderr_to_stdout: true) do
      {output, 0} -> filter_override_args(output)
      {_output, _status} -> []
    end
  rescue
    error in ErlangError ->
      if error.original == :enoent do
        []
      else
        reraise(error, __STACKTRACE__)
      end
  end

  defp filter_override_args(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&filter_driver_name/1)
    |> Enum.uniq()
    |> Enum.flat_map(fn driver ->
      [
        "-c",
        "filter.#{driver}.clean=",
        "-c",
        "filter.#{driver}.process=",
        "-c",
        "filter.#{driver}.required=false"
      ]
    end)
  end

  defp filter_driver_name(line) do
    key = line |> String.split(~r/\s+/, parts: 2) |> List.first()

    cond do
      not is_binary(key) ->
        []

      String.starts_with?(key, "filter.") and String.ends_with?(key, ".clean") ->
        [key |> String.replace_prefix("filter.", "") |> String.trim_trailing(".clean")]

      String.starts_with?(key, "filter.") and String.ends_with?(key, ".process") ->
        [key |> String.replace_prefix("filter.", "") |> String.trim_trailing(".process")]

      true ->
        []
    end
  end

  defp git_failure(args, status, output, max_bytes) do
    bounded = bound_text(output, max_bytes)
    %{args: args, exit_status: status, output: bounded.text, truncated?: bounded.truncated?}
  end

  defp output_error(output, max_bytes) do
    bounded = bound_text(output, max_bytes)
    %{output: bounded.text, truncated?: bounded.truncated?}
  end

  defp bound_text(value, max_bytes) do
    value = normalize_text(value)

    if byte_size(value) > max_bytes do
      prefix_bytes = max_bytes - byte_size(@truncation_marker)
      %{text: utf8_prefix(value, prefix_bytes) <> @truncation_marker, truncated?: true}
    else
      %{text: value, truncated?: false}
    end
  end

  defp normalize_text(value) do
    if String.valid?(value) do
      value
    else
      String.replace_invalid(value, "?")
    end
  end

  defp utf8_prefix(_value, limit) when limit <= 0, do: ""
  defp utf8_prefix(value, limit), do: utf8_prefix(value, limit, [])

  defp utf8_prefix(_value, limit, acc) when limit <= 0,
    do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp utf8_prefix(<<>>, _limit, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp utf8_prefix(<<codepoint::utf8, rest::binary>>, limit, acc) do
    char = <<codepoint::utf8>>
    size = byte_size(char)

    if size <= limit do
      utf8_prefix(rest, limit - size, [char | acc])
    else
      acc |> Enum.reverse() |> IO.iodata_to_binary()
    end
  end

  defp utf8_prefix(_invalid_tail, _limit, acc),
    do: acc |> Enum.reverse() |> IO.iodata_to_binary()
end
