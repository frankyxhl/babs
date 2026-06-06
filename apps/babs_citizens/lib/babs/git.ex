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
  @pathspec ["--", "."]
  @untracked_files_args ["ls-files", "--others", "--exclude-standard", "-z"] ++ @pathspec
  @intent_to_add_chunk_size 100

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
      case git_cmd(workspace, ["status", "--porcelain=v1"] ++ @pathspec) do
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
    run_git_diff(
      workspace,
      ["diff", "--no-ext-diff", "--no-textconv", base] ++ @pathspec,
      max_bytes
    )
  end

  defp run_diff(workspace, nil, max_bytes) do
    if head?(workspace) do
      run_git_diff(
        workspace,
        ["diff", "--no-ext-diff", "--no-textconv", "HEAD"] ++ @pathspec,
        max_bytes
      )
    else
      run_unborn_diff(workspace, max_bytes)
    end
  end

  defp run_unborn_diff(workspace, max_bytes) do
    with_untracked_index(workspace, max_bytes, fn env ->
      with {:ok, cached} <-
             git_cmd(
               workspace,
               ["diff", "--no-ext-diff", "--no-textconv", "--cached"] ++ @pathspec,
               env: env
             ),
           {:ok, worktree} <-
             git_cmd(workspace, ["diff", "--no-ext-diff", "--no-textconv"] ++ @pathspec, env: env) do
        {:ok, cached |> join_diff(worktree) |> bound_text(max_bytes)}
      else
        {:error, {status, output, args}} ->
          {:error, {:git_failed, git_failure(args, status, output, max_bytes)}}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp join_diff("", right), do: right
  defp join_diff(left, ""), do: left
  defp join_diff(left, right), do: left <> "\n" <> right

  defp run_git_diff(workspace, args, max_bytes) do
    with_untracked_index(workspace, max_bytes, fn env ->
      run_git(workspace, args, max_bytes, env: env)
    end)
  end

  defp with_untracked_index(workspace, max_bytes, fun) do
    with {:ok, paths} <- untracked_paths(workspace, max_bytes) do
      if paths == [] do
        fun.([])
      else
        with_temp_index(workspace, max_bytes, fn temp_index ->
          env = [{"GIT_INDEX_FILE", temp_index}]

          with :ok <- add_intent_to_add(workspace, paths, env, max_bytes) do
            fun.(env)
          end
        end)
      end
    end
  end

  defp untracked_paths(workspace, max_bytes) do
    case git_cmd(workspace, @untracked_files_args) do
      {:ok, output} ->
        {:ok, output |> nul_split() |> Enum.reject(&(&1 == ""))}

      {:error, {status, output, args}} ->
        {:error, {:git_failed, git_failure(args, status, output, max_bytes)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp with_temp_index(workspace, max_bytes, fun) do
    temp_index =
      Path.join(
        System.tmp_dir!(),
        "babs-git-index-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      )

    try do
      with :ok <- copy_index(workspace, temp_index, max_bytes) do
        fun.(temp_index)
      end
    after
      File.rm(temp_index)
      File.rm(temp_index <> ".lock")
    end
  end

  defp copy_index(workspace, temp_index, max_bytes) do
    case git_cmd(workspace, ["rev-parse", "--git-path", "index"]) do
      {:ok, output} ->
        index_path = output |> String.trim() |> Path.expand(workspace)

        if File.exists?(index_path) do
          copy_existing_index(index_path, temp_index, max_bytes)
        else
          :ok
        end

      {:error, {status, output, args}} ->
        {:error, {:git_failed, git_failure(args, status, output, max_bytes)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp copy_existing_index(index_path, temp_index, max_bytes) do
    case File.cp(index_path, temp_index) do
      :ok ->
        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error,
         {:git_failed,
          git_failure(["rev-parse", "--git-path", "index"], 1, inspect(reason), max_bytes)}}
    end
  end

  defp add_intent_to_add(workspace, paths, env, max_bytes) do
    paths
    |> Enum.chunk_every(@intent_to_add_chunk_size)
    |> Enum.reduce_while(:ok, fn chunk, :ok ->
      case git_cmd(workspace, ["add", "-N", "--"] ++ chunk, env: env) do
        {:ok, _output} ->
          {:cont, :ok}

        {:error, {status, output, args}} ->
          {:halt, {:error, {:git_failed, git_failure(args, status, output, max_bytes)}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp nul_split(value), do: :binary.split(value, <<0>>, [:global])

  defp run_git(workspace, args, max_bytes, opts \\ []) do
    case git_cmd(workspace, args, opts) do
      {:ok, output} ->
        {:ok, bound_text(output, max_bytes)}

      {:error, {status, output, executed_args}} ->
        {:error, {:git_failed, git_failure(executed_args, status, output, max_bytes)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp git_cmd(workspace, args, opts \\ []) do
    safe_args = safe_git_args(workspace, args)

    case System.cmd("git", safe_args, cmd_opts(workspace, opts)) do
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

  defp cmd_opts(workspace, opts) do
    case Keyword.get(opts, :env, []) do
      [] -> [cd: workspace, stderr_to_stdout: true]
      env -> [cd: workspace, stderr_to_stdout: true, env: env]
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
