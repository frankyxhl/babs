defmodule Babs.Citizens.DirectCli.Executor do
  @moduledoc """
  erlexec-backed non-PTY command executor for direct CLI turns.
  """

  alias Babs.Citizens.DirectCli.{Command, Redactor}

  def run(%Command{} = command) do
    with {:ok, args} <- resolve_args(command.args),
         {:ok, _apps} <- Application.ensure_all_started(:erlexec) do
      opts =
        [:sync, :stdout, :stderr, {:env, [:clear | command.env]}]
        |> maybe_cd(command.cwd)

      args
      |> :exec.run(opts, command.timeout_ms)
      |> normalize_result(command)
    end
  rescue
    error in ErlangError ->
      if error.original == :enoent do
        {:error, {:executable_not_found, List.first(command.args)}}
      else
        reraise(error, __STACKTRACE__)
      end
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
