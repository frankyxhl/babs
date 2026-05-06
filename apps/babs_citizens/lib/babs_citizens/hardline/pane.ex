defmodule Babs.Citizens.Hardline.Pane do
  @moduledoc """
  GenServer owning one erlexec attachment to a Babs-managed tmux session.
  """

  use GenServer

  alias Babs.Citizens.Hardline.Transcript
  alias Babs.Citizens.Hardline.SystemDelivery
  alias Babs.Citizens.Runner

  require Logger

  # PubSub payload ceiling from BAB-1106.
  @pubsub_chunk_size 4096

  def start_link(opts) do
    config = Keyword.fetch!(opts, :config)
    GenServer.start_link(__MODULE__, opts, name: via(config.slug))
  end

  def inject(slug, data) when is_binary(slug) and is_binary(data) do
    GenServer.cast(via(slug), {:inject, data, :manual})
  end

  def inject_system(slug, data) when is_binary(slug) and is_binary(data) do
    GenServer.call(via(slug), {:inject, data, :system}, system_delivery_timeout_ms())
  catch
    :exit, _reason -> {:error, :not_found}
  end

  def resize(slug, rows, cols) when is_binary(slug) do
    GenServer.cast(via(slug), {:resize, rows, cols})
  end

  def cwd(slug) when is_binary(slug) do
    GenServer.call(via(slug), :cwd)
  catch
    :exit, _reason -> {:error, :not_found}
  end

  def tmux_target(slug) when is_binary(slug) do
    GenServer.call(via(slug), :tmux_target)
  catch
    :exit, _reason -> {:error, :not_found}
  end

  def flush_transcript(slug) when is_binary(slug) do
    GenServer.call(via(slug), :flush_transcript)
  catch
    :exit, _reason -> {:error, :not_found}
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
    Process.flag(:trap_exit, true)

    config = Keyword.fetch!(opts, :config)
    session = Keyword.get(opts, :session, Runner.session_name(config.slug))
    attach_session = Keyword.get(opts, :attach_session, session)

    case Runner.attach(session, attach_session: attach_session) do
      {:ok, attach} ->
        transcript_io =
          case Transcript.open(config.cwd) do
            {:ok, io} ->
              io

            {:error, reason} ->
              Logger.warning(
                "babs hardline transcript open failed for #{config.slug}: #{inspect(reason)}"
              )

              nil
          end

        {:ok,
         %{
           config: config,
           session: session,
           attach: attach,
           stream_id: System.unique_integer([:positive]),
           seq: 0,
           input_seq: 0,
           transcript_io: transcript_io
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:cwd, _from, state) do
    {:reply, {:ok, state.config.cwd}, state}
  end

  def handle_call(:tmux_target, _from, state) do
    {:reply, {:ok, state.session}, state}
  end

  @impl true
  def handle_call(:flush_transcript, _from, state) do
    case Transcript.flush(Map.get(state, :transcript_io)) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        Logger.warning(
          "babs hardline transcript flush failed for #{state.config.slug}: #{inspect(reason)}"
        )

        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:inject, data, source}, _from, state) when source in [:manual, :system] do
    {result, state} = inject_into_state(data, source, state)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:inject, data}, state) do
    handle_cast({:inject, data, :manual}, state)
  end

  def handle_cast({:inject, data, source}, state) when source in [:manual, :system] do
    {_result, state} = inject_into_state(data, source, state)
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

        write_transcript(state, %{
          slug: state.config.slug,
          direction: :output,
          stream_id: state.stream_id,
          seq: next_seq,
          payload: chunk
        })

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
    Transcript.close(state[:transcript_io])
    :ok
  end

  defp via(slug), do: {:via, Registry, {Babs.Citizens.PaneRegistry, slug}}

  defp system_delivery_timeout_ms do
    :babs_citizens
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:system_delivery_timeout_ms, 5_000)
  end

  defp write_transcript(state, record) do
    # During dev hot reload, pre-transcript Pane state can briefly run new code.
    case Map.get(state, :transcript_io) do
      nil ->
        :ok

      io ->
        case Transcript.append(io, record) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "babs hardline transcript write failed for #{state.config.slug}: #{inspect(reason)}"
            )

            :ok
        end
    end
  end

  defp inject_into_state(data, source, state) do
    {result, delivered_data} = deliver_into_state(data, source, state)

    next_input_seq = state.input_seq + 1

    write_transcript(state, %{
      slug: state.config.slug,
      direction: :input,
      stream_id: state.stream_id,
      seq: next_input_seq,
      payload: delivered_data
    })

    if source == :system, do: flush_transcript_for_system_injection(state)

    {normalize_inject_result(result), %{state | input_seq: next_input_seq}}
  end

  defp normalize_inject_result(:ok), do: :ok
  defp normalize_inject_result(other), do: {:error, other}

  defp runner(state), do: Map.get(state, :runner, &Runner.inject/2)

  defp deliver_into_state(data, :manual, state) do
    {runner(state).(state.attach, data), data}
  end

  defp deliver_into_state(data, :system, state) do
    delivery = Map.get(state, :system_delivery, &SystemDelivery.deliver/4)
    opts = system_delivery_opts(state)

    case delivery.(state.config, state.attach, data, opts) do
      {:ok, delivered_data} -> {:ok, delivered_data}
      {:error, reason, delivered_data} -> {{:error, reason}, delivered_data}
      other -> {{:error, other}, data}
    end
  end

  defp system_delivery_opts(state) do
    opts = Map.get(state, :system_delivery_opts, [])
    ops = opts |> Keyword.get(:ops, %{}) |> Map.new() |> Map.put_new(:inject, runner(state))
    Keyword.put(opts, :ops, ops)
  end

  defp flush_transcript_for_system_injection(state) do
    case Transcript.flush(Map.get(state, :transcript_io)) do
      :ok ->
        :ok

      {:error, :no_transcript} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "babs hardline transcript flush failed for #{state.config.slug}: #{inspect(reason)}"
        )

        :ok
    end
  end

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
