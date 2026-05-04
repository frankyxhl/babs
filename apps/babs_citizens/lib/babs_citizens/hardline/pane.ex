defmodule Babs.Citizens.Hardline.Pane do
  @moduledoc """
  GenServer owning one erlexec attachment to a Babs-managed tmux session.
  """

  use GenServer

  alias Babs.Citizens.Runner

  # PubSub payload ceiling from BAB-1106.
  @pubsub_chunk_size 4096

  def start_link(opts) do
    config = Keyword.fetch!(opts, :config)
    GenServer.start_link(__MODULE__, opts, name: via(config.slug))
  end

  def inject(slug, data) when is_binary(slug) and is_binary(data) do
    GenServer.cast(via(slug), {:inject, data})
  end

  def resize(slug, rows, cols) when is_binary(slug) do
    GenServer.cast(via(slug), {:resize, rows, cols})
  end

  def chunk_bytes(bytes, max_size \\ @pubsub_chunk_size)

  def chunk_bytes(_bytes, max_size) when not (is_integer(max_size) and max_size > 0) do
    raise ArgumentError, "max_size must be a positive integer"
  end

  def chunk_bytes(bytes, max_size) when is_binary(bytes) do
    do_chunk(bytes, max_size, [])
  end

  @impl true
  def init(opts) do
    config = Keyword.fetch!(opts, :config)
    session = Keyword.get(opts, :session, Runner.session_name(config.slug))

    case Runner.attach(session) do
      {:ok, attach} ->
        {:ok,
         %{
           config: config,
           session: session,
           attach: attach,
           stream_id: System.unique_integer([:positive]),
           seq: 0
         }}

      {:error, reason} ->
        {:stop, reason}
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
      Enum.reduce(chunk_bytes(data), state.seq, fn chunk, seq ->
        next_seq = seq + 1

        Phoenix.PubSub.broadcast(
          Babs.Citizens.PubSub,
          "pane:#{state.config.slug}",
          {:pane_bytes, state.stream_id, next_seq, chunk}
        )

        next_seq
      end)

    {:noreply, %{state | seq: seq}}
  end

  def handle_info({:DOWN, _monitor_ref, :process, _pid, reason}, state) do
    message = "\r\n[babs hardline detached: #{inspect(reason)}]\r\n"

    Phoenix.PubSub.broadcast(
      Babs.Citizens.PubSub,
      "pane:#{state.config.slug}",
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

  defp via(slug), do: {:via, Registry, {Babs.Citizens.PaneRegistry, slug}}

  defp do_chunk("", _max_size, acc), do: Enum.reverse(acc)

  defp do_chunk(bytes, max_size, acc) do
    size = min(byte_size(bytes), max_size)
    chunk = binary_part(bytes, 0, size)
    rest = binary_part(bytes, size, byte_size(bytes) - size)

    do_chunk(rest, max_size, [chunk | acc])
  end

  defp normalize_down_reason(:normal), do: :normal
  defp normalize_down_reason({:exit_status, 0}), do: :normal
  defp normalize_down_reason(reason), do: reason
end
