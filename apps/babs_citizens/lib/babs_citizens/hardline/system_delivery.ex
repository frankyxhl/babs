defmodule Babs.Citizens.Hardline.SystemDelivery do
  @moduledoc """
  Confirmed system-prompt delivery for AI CLI panes.
  """

  alias Babs.Citizens.Runner

  @receipt_attempts 20
  @receipt_interval_ms 100
  @enter_retries 2
  @editable_markers ["[Pasted text", "pasted text", "ctrl+g", "Ctrl+G"]

  @type op_result :: :ok | {:error, term()}
  @type deliver_result :: {:ok, binary()} | {:error, term(), binary()}

  @spec deliver(Babs.Citizens.CitizenConfig.t(), map(), binary(), keyword()) :: deliver_result()
  def deliver(config, attach, data, opts \\ []) when is_binary(data) do
    ops = ops(opts)

    if Runner.ai_cli?(config) do
      deliver_ai(attach, data, ops, opts)
    else
      case ops.inject.(attach, data) do
        :ok -> {:ok, data}
        {:error, reason} -> {:error, reason, data}
        other -> {:error, other, data}
      end
    end
  end

  def receipt_marker(data) when is_binary(data) do
    case Regex.run(~r/Babs Ticket [A-Z]-\d{4}-\d{2}-\d{2}-\d{3}/, data) do
      [marker] ->
        marker

      _no_ticket ->
        data
        |> String.split("\n", trim: true)
        |> List.first()
        |> case do
          nil -> String.slice(data, 0, 80)
          line -> String.slice(line, 0, 80)
        end
    end
  end

  def editable_pasted_block?(pane) when is_binary(pane) do
    Enum.any?(@editable_markers, &String.contains?(pane, &1))
  end

  defp deliver_ai(attach, data, ops, opts) do
    marker = receipt_marker(data)

    with :ok <- ops.paste_text.(attach, data),
         :ok <- wait_for_receipt(attach, marker, ops, opts),
         :ok <- ops.send_enter.(attach),
         :ok <- retry_enter_if_editable(attach, ops, opts) do
      {:ok, data <> "\r"}
    else
      {:error, reason} -> {:error, reason, data}
      other -> {:error, other, data}
    end
  end

  defp wait_for_receipt(_attach, "", _ops, _opts), do: :ok

  defp wait_for_receipt(attach, marker, ops, opts) do
    attempts = Keyword.get(opts, :receipt_attempts, @receipt_attempts)
    interval = Keyword.get(opts, :receipt_interval_ms, @receipt_interval_ms)

    poll_until(attempts, interval, ops, fn ->
      case ops.capture_pane.(attach) do
        {:ok, pane} ->
          if String.contains?(pane, marker), do: :ok, else: {:error, :not_received}

        {:error, reason} ->
          {:error, reason}
      end
    end)
    |> case do
      :ok -> :ok
      {:error, :not_received} -> {:error, {:receipt_not_observed, marker}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp retry_enter_if_editable(attach, ops, opts) do
    retries = Keyword.get(opts, :enter_retries, @enter_retries)
    interval = Keyword.get(opts, :receipt_interval_ms, @receipt_interval_ms)
    retry_enter_if_editable(attach, ops, retries, interval)
  end

  defp retry_enter_if_editable(_attach, _ops, 0, _interval), do: :ok

  defp retry_enter_if_editable(attach, ops, retries, interval) do
    ops.sleep.(interval)

    case ops.capture_pane.(attach) do
      {:ok, pane} ->
        if editable_pasted_block?(pane) do
          with :ok <- ops.send_enter.(attach) do
            retry_enter_if_editable(attach, ops, retries - 1, interval)
          end
        else
          :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp poll_until(attempts, _interval, _ops, fun) when attempts <= 1, do: fun.()

  defp poll_until(attempts, interval, ops, fun) do
    case fun.() do
      :ok ->
        :ok

      {:error, _reason} ->
        ops.sleep.(interval)
        poll_until(attempts - 1, interval, ops, fun)
    end
  end

  defp ops(opts) do
    defaults = %{
      inject: &Runner.inject/2,
      paste_text: &Runner.paste_text/2,
      capture_pane: &Runner.capture_pane/1,
      send_enter: &Runner.send_enter/1,
      sleep: &Process.sleep/1
    }

    opts
    |> Keyword.get(:ops, %{})
    |> Map.new()
    |> then(&Map.merge(defaults, &1))
  end
end
