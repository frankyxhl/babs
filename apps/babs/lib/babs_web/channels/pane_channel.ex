defmodule BabsWeb.PaneChannel do
  @moduledoc false

  use Phoenix.Channel

  alias Babs.Citizens.Lifecycle
  alias Babs.Citizens.Hardline.Pane
  alias Babs.Citizens.Runner

  @allowed_controls ["\r", "\n", "\t", <<3>>, <<4>>, <<26>>, <<127>>]
  @allowed_arrows ["\e[A", "\e[B", "\e[C", "\e[D"]
  @max_input_bytes 4096

  @impl true
  def join("pane:" <> slug, _payload, socket) do
    # Phoenix subscribes the channel process to its joined topic. Do not call
    # Phoenix.PubSub.subscribe/2 for the same `pane:<slug>` topic.
    case Lifecycle.lookup(slug) do
      {:ok, _pid} ->
        send(self(), :send_snapshot)
        {:ok, assign(socket, :slug, slug)}

      {:error, :not_found} ->
        {:error, %{reason: "not_found"}}
    end
  end

  @impl true
  def handle_in("input", %{"data" => data}, socket) when is_binary(data) do
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
    session = Runner.session_name(socket.assigns.slug)

    case Runner.capture_pane(session) do
      {:ok, snapshot} ->
        push(socket, "output", %{
          "stream_id" => 0,
          "seq" => 0,
          "base64" => Base.encode64(snapshot)
        })

      {:error, _reason} ->
        :ok
    end

    {:noreply, socket}
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive_integer(_value), do: :error

  def allowed_input?(data) when is_binary(data) and byte_size(data) <= @max_input_bytes do
    data in @allowed_controls or data in @allowed_arrows or printable_ascii_paste?(data)
  end

  def allowed_input?(_data), do: false

  defp printable_ascii_paste?(<<>>), do: false

  defp printable_ascii_paste?(data) do
    printable_ascii_bytes?(data)
  end

  defp printable_ascii_bytes?(<<>>), do: true

  defp printable_ascii_bytes?(<<byte, rest::binary>>)
       when byte in 0x20..0x7E or byte in [?\r, ?\n, ?\t, 0x7F] do
    printable_ascii_bytes?(rest)
  end

  defp printable_ascii_bytes?(_data), do: false
end
