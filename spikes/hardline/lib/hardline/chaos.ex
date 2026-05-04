defmodule Hardline.Chaos do
  @moduledoc """
  Chooses erlexec OS process targets for chaos scenarios.
  """

  def choose_target(ports, opts \\ [])

  def choose_target([], _opts) do
    raise ArgumentError, "ports must not be empty"
  end

  def choose_target(ports, opts) when is_list(ports) do
    signal = Keyword.get(opts, :signal, :sigterm)
    index = target_index(length(ports), Keyword.get(opts, :seed))

    ports
    |> Enum.at(index)
    |> Map.put(:signal, signal)
  end

  def kill(%{os_pid: os_pid, signal: signal}) when is_integer(os_pid) and is_atom(signal) do
    signal
    |> signal_arg()
    |> then(&System.cmd("kill", [&1, Integer.to_string(os_pid)], stderr_to_stdout: true))
    |> case do
      {_output, 0} -> :ok
      {output, status} -> {:error, {:kill_failed, status, output}}
    end
  end

  defp signal_arg(:sigterm), do: "-TERM"
  defp signal_arg(:sigkill), do: "-KILL"

  defp target_index(length, nil), do: :rand.uniform(length) - 1
  defp target_index(length, seed) when is_integer(seed), do: abs(seed) |> rem(length)
end
