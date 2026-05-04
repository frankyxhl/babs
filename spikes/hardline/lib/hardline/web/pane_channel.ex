defmodule Hardline.Web.PaneChannel do
  @moduledoc false

  use Phoenix.Channel

  @impl true
  def join("pane:" <> name, _payload, socket) do
    # Phoenix subscribes the channel process to its joined topic. An explicit
    # PubSub.subscribe/2 here causes duplicate output delivery.
    case Registry.lookup(Hardline.Web.PaneRegistry, name) do
      [{_pid, _value}] -> {:ok, assign(socket, :pane_name, name)}
      [] -> {:error, %{reason: "not_found"}}
    end
  end

  @impl true
  def handle_in("input", %{"data" => data}, socket) when is_binary(data) do
    Hardline.Web.PaneServer.inject(socket.assigns.pane_name, data)
    {:noreply, socket}
  end

  @impl true
  def handle_in("resize", %{"cols" => cols, "rows" => rows}, socket) do
    with {:ok, cols} <- positive_integer(cols),
         {:ok, rows} <- positive_integer(rows) do
      Hardline.Web.PaneServer.resize(socket.assigns.pane_name, rows, cols)
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

  def handle_info({:pane_bytes, seq, bytes}, socket) when is_integer(seq) and is_binary(bytes) do
    push(socket, "output", %{"stream_id" => nil, "seq" => seq, "base64" => Base.encode64(bytes)})
    {:noreply, socket}
  end

  def handle_info({:pane_bytes, bytes}, socket) when is_binary(bytes) do
    push(socket, "output", %{"stream_id" => nil, "seq" => nil, "base64" => Base.encode64(bytes)})
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, _socket), do: :ok

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive_integer(_value), do: :error
end
