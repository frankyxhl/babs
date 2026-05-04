defmodule Hardline.Web.PaneServer do
  @moduledoc """
  Single-pane bridge used by the Phase 0 Channel -> xterm.js validation page.
  """

  use GenServer

  alias Hardline.{Pane, Runner}

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via(name))
  end

  def inject(name, data) when is_binary(name) and is_binary(data) do
    GenServer.cast(via(name), {:inject, data})
  end

  def resize(name, rows, cols) when is_binary(name) do
    GenServer.cast(via(name), {:resize, rows, cols})
  end

  def stop(name) when is_binary(name) do
    GenServer.stop(via(name), :normal)
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    session = Keyword.fetch!(opts, :session)
    command = Keyword.get(opts, :command, Runner.default_shell_command())
    start_session? = Keyword.get(opts, :start_session?, true)

    with :ok <- maybe_start_session(start_session?, session, command),
         {:ok, attach} <- Runner.attach(session) do
      {:ok,
       %{
         name: name,
         session: session,
         attach: attach,
         stream_id: System.unique_integer([:positive]),
         seq: 0
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_cast({:inject, data}, state) do
    Runner.inject(state.attach, data)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:resize, rows, cols}, state) do
    Runner.resize(state.attach, rows, cols)
    {:noreply, state}
  end

  @impl true
  def handle_info({:stdout, os_pid, data}, %{attach: %{os_pid: os_pid}} = state) do
    seq =
      Enum.reduce(Pane.chunk_bytes(data), state.seq, fn chunk, seq ->
        next_seq = seq + 1

        Phoenix.PubSub.broadcast(
          Hardline.PubSub,
          "pane:#{state.name}",
          {:pane_bytes, state.stream_id, next_seq, chunk}
        )

        next_seq
      end)

    {:noreply, %{state | seq: seq}}
  end

  def handle_info({:DOWN, _monitor_ref, :process, _pid, reason}, state) do
    message = "\r\n[hardline pane exited: #{inspect(reason)}]\r\n"

    Phoenix.PubSub.broadcast(
      Hardline.PubSub,
      "pane:#{state.name}",
      {:pane_bytes, state.stream_id, state.seq + 1, message}
    )

    {:stop, normalize_down_reason(reason), state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Runner.detach(state.attach)
    :ok
  end

  defp via(name), do: {:via, Registry, {Hardline.Web.PaneRegistry, name}}

  defp maybe_start_session(true, session, command), do: Runner.start_session(session, command)
  defp maybe_start_session(false, _session, _command), do: :ok

  defp normalize_down_reason(:normal), do: :normal
  defp normalize_down_reason({:exit_status, 0}), do: :normal
  defp normalize_down_reason(reason), do: reason
end
