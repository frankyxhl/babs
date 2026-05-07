defmodule Babs.Citizens.DirectCli.Executor do
  @moduledoc """
  erlexec-backed non-PTY command executor for direct CLI turns.
  """

  alias Babs.Citizens.DirectCli.{Command, Redactor}

  @kill_timeout_seconds 2
  @stop_wait_ms 5_000

  def run(%Command{} = command) do
    try do
      do_run(command)
    rescue
      error in ErlangError ->
        if error.original == :enoent do
          {:error, {:executable_not_found, List.first(command.args)}}
        else
          reraise(error, __STACKTRACE__)
        end
    catch
      :exit, {:timeout, _call} ->
        {:error, :timeout}

      :exit, reason ->
        {:error, {:exec_exit, reason}}
    end
  end

  defp do_run(command) do
    with {:ok, args} <- resolve_args(command.args),
         {:ok, _apps} <- Application.ensure_all_started(:erlexec),
         opts <- command_opts(command),
         {:ok, pid, os_pid} <- :exec.run(args, opts, command.timeout_ms) do
      await_result(pid, os_pid, command, [], [])
    end
  end

  defp command_opts(command) do
    [
      :stdout,
      :stderr,
      :monitor,
      {:group, 0},
      :kill_group,
      {:kill_timeout, @kill_timeout_seconds},
      {:env, [:clear | command.env]}
    ]
    |> maybe_cd(command.cwd)
  end

  defp resolve_args([exe | rest]) when is_binary(exe) do
    cond do
      Path.type(exe) == :absolute and File.exists?(exe) ->
        {:ok, [exe | rest]}

      resolved = System.find_executable(exe) ->
        {:ok, [resolved | rest]}

      true ->
        {:error, {:executable_not_found, exe}}
    end
  end

  defp resolve_args(_args), do: {:error, :invalid_command_args}

  defp maybe_cd(opts, cwd) when is_binary(cwd) and cwd != "", do: [{:cd, cwd} | opts]
  defp maybe_cd(opts, _cwd), do: opts

  defp await_result(pid, os_pid, command, out_acc, err_acc) do
    receive do
      {:stdout, ^os_pid, data} ->
        await_result(pid, os_pid, command, [data | out_acc], err_acc)

      {:stderr, ^os_pid, data} ->
        await_result(pid, os_pid, command, out_acc, [data | err_acc])

      {:DOWN, ^os_pid, :process, ^pid, :normal} ->
        normalize_result({:ok, sync_output(out_acc, err_acc)}, command)

      {:DOWN, ^os_pid, :process, ^pid, :noproc} ->
        normalize_result({:ok, sync_output(out_acc, err_acc)}, command)

      {:DOWN, ^os_pid, :process, ^pid, {:exit_status, status}} ->
        normalize_result(
          {:error, [{:exit_status, status} | sync_output(out_acc, err_acc)]},
          command
        )

      {:DOWN, ^os_pid, :process, ^pid, {:status, status}} ->
        normalize_result(
          {:error, [{:exit_status, status} | sync_output(out_acc, err_acc)]},
          command
        )
    after
      command.timeout_ms ->
        stop_timed_out(os_pid)
        {:error, :timeout}
    end
  end

  defp sync_output([], []), do: []
  defp sync_output(out_acc, []), do: [{:stdout, Enum.reverse(out_acc)}]
  defp sync_output([], err_acc), do: [{:stderr, Enum.reverse(err_acc)}]

  defp sync_output(out_acc, err_acc),
    do: [{:stdout, Enum.reverse(out_acc)}, {:stderr, Enum.reverse(err_acc)}]

  defp stop_timed_out(os_pid) do
    _ignored = :exec.stop_and_wait(os_pid, @stop_wait_ms)
    :ok
  catch
    _kind, _reason -> :ok
  end

  defp normalize_result({:ok, output}, command) when is_list(output) do
    artifacts = %{
      stdout: output |> Keyword.get(:stdout, []) |> Redactor.bound_output(command.output_limit),
      stderr: output |> Keyword.get(:stderr, []) |> Redactor.bound_output(command.output_limit),
      exit_status: 0,
      provider_session_id: command.provider_session_id
    }

    {:ok, Redactor.redact_artifacts(artifacts, secret_names: secret_names(command))}
  end

  defp normalize_result({:error, output}, command) when is_list(output) do
    status =
      output
      |> Keyword.get(:exit_status)
      |> Kernel.||(1)

    artifacts = %{
      stdout: output |> Keyword.get(:stdout, []) |> Redactor.bound_output(command.output_limit),
      stderr: output |> Keyword.get(:stderr, []) |> Redactor.bound_output(command.output_limit),
      exit_status: status,
      provider_session_id: command.provider_session_id
    }

    {:error,
     {:exit_status, status,
      Redactor.redact_artifacts(artifacts, secret_names: secret_names(command))}}
  end

  defp normalize_result({:error, reason}, _command), do: {:error, reason}

  defp secret_names(command) do
    command.env
    |> Enum.map(fn {key, _value} -> key end)
    |> Enum.filter(&Regex.match?(~r/(secret|token|key|password)/i, &1))
  end
end
