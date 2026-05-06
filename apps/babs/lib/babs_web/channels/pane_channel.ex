defmodule BabsWeb.PaneChannel do
  @moduledoc false

  use Phoenix.Channel

  alias Babs.Citizens.Lifecycle
  alias Babs.Citizens.Hardline.Pane
  alias Babs.Citizens.Hardline.Transcript
  alias Babs.Citizens.Runner

  @max_input_bytes 4096
  @blocked_terminal_controls ["\e]", <<0x9D>>, <<0xC2, 0x9D>>, "\eP", "\e_", "\e^"]
  @terminal_response_pattern ~r/(?:\e\[\?[0-9;]*c|\e\[>[0-9;]*c|\e\[[0-9;]*R|\e\[[0-9?;]*n)/

  @impl true
  def join("pane:" <> slug, _payload, socket) do
    # Phoenix subscribes the channel process to its joined topic. Do not call
    # Phoenix.PubSub.subscribe/2 for the same `pane:<slug>` topic.
    case Lifecycle.lookup(slug) do
      {:ok, _pid} ->
        send(self(), :send_snapshot)

        {:ok,
         socket
         |> assign(:slug, slug)
         |> assign(:cwd, pane_cwd(slug))
         |> assign(:pubsub_pid, Process.whereis(Babs.Citizens.PubSub))}

      {:error, :not_found} ->
        {:error, %{reason: "not_found"}}
    end
  end

  @impl true
  def handle_in("input", %{"data" => data}, socket) when is_binary(data) do
    socket = ensure_pubsub_subscription(socket)

    if allowed_input?(data) do
      Pane.inject(socket.assigns.slug, data)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_in("resize", %{"cols" => cols, "rows" => rows}, socket) do
    with {:ok, cols} <- positive_integer(cols),
         {:ok, rows} <- positive_integer(rows) do
      Pane.resize(socket.assigns.slug, rows, cols)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:pane_bytes, stream_id, seq, bytes}, socket)
      when is_integer(stream_id) and is_integer(seq) and is_binary(bytes) do
    push(socket, "output", %{
      "stream_id" => stream_id,
      "seq" => seq,
      "base64" => Base.encode64(bytes)
    })

    {:noreply, socket}
  end

  def handle_info(:send_snapshot, socket) do
    send_initial_snapshot(socket)

    {:noreply, socket}
  end

  defp send_initial_snapshot(%{assigns: %{cwd: cwd}} = socket) when is_binary(cwd) do
    _ = Pane.flush_transcript(socket.assigns.slug)

    case tmux_snapshot(socket) do
      {:ok, snapshot} ->
        push_snapshot(socket, snapshot)

      {:error, _reason} ->
        send_transcript_snapshot(socket, cwd)
    end
  end

  defp send_initial_snapshot(socket) do
    case tmux_snapshot(socket) do
      {:ok, snapshot} -> push_snapshot(socket, snapshot)
      {:error, _reason} -> :ok
    end
  end

  defp tmux_snapshot(socket) do
    Runner.capture_pane(snapshot_target(socket.assigns.slug))
  end

  defp snapshot_target(slug) do
    case Pane.tmux_target(slug) do
      {:ok, target} when is_binary(target) and target != "" -> target
      _other -> Runner.session_name(slug)
    end
  end

  defp send_transcript_snapshot(socket, cwd) do
    case Transcript.replay_output(cwd, slug: socket.assigns.slug) do
      {:ok, ""} -> :ok
      {:ok, snapshot} -> push_snapshot(socket, snapshot)
      {:error, _reason} -> :ok
    end
  end

  defp push_snapshot(socket, snapshot) do
    push(socket, "output", %{
      "stream_id" => 0,
      "seq" => 0,
      "base64" => Base.encode64(snapshot)
    })
  end

  defp pane_cwd(slug) do
    case Pane.cwd(slug) do
      {:ok, cwd} when is_binary(cwd) -> cwd
      _other -> nil
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive_integer(_value), do: :error

  defp ensure_pubsub_subscription(socket) do
    current_pid = Process.whereis(Babs.Citizens.PubSub)

    if is_pid(current_pid) and socket.assigns[:pubsub_pid] != current_pid and
         is_binary(socket.topic) do
      :ok = Phoenix.PubSub.subscribe(Babs.Citizens.PubSub, socket.topic)
      assign(socket, :pubsub_pid, current_pid)
    else
      socket
    end
  end

  def allowed_input?(data)
      when is_binary(data) and byte_size(data) > 0 and byte_size(data) <= @max_input_bytes do
    not contains_nul?(data) and not blocked_terminal_control?(data) and
      not terminal_response?(data)
  end

  def allowed_input?(_data), do: false

  defp contains_nul?(data), do: :binary.match(data, <<0>>) != :nomatch

  defp blocked_terminal_control?(data) do
    Enum.any?(@blocked_terminal_controls, &(:binary.match(data, &1) != :nomatch))
  end

  defp terminal_response?(data), do: Regex.match?(@terminal_response_pattern, data)
end
