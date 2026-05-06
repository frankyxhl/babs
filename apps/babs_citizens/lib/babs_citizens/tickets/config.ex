defmodule Babs.Citizens.Tickets.Config do
  @moduledoc """
  Resolves the runtime Ticket root.
  """

  require Logger

  @spec root(keyword()) :: String.t()
  def root(opts \\ []) do
    opts
    |> Keyword.get(:root, Application.get_env(:babs_citizens, :root, File.cwd!()))
    |> Path.expand()
  end

  @spec tickets_root(keyword()) :: String.t()
  def tickets_root(opts \\ []) do
    root = root(opts)
    default = Path.join(root, "var/tickets")

    opts
    |> Keyword.get(:tickets_root, Application.get_env(:babs_citizens, :tickets_root))
    |> normalize_root(default, root)
  end

  @spec ensure_root(keyword()) :: {:ok, String.t()} | {:error, term()}
  def ensure_root(opts \\ []) do
    tickets_root = tickets_root(opts)

    case File.mkdir_p(tickets_root) do
      :ok -> {:ok, tickets_root}
      {:error, reason} -> {:error, {:redacted_io_error, {:mkdir_tickets_root, reason}}}
    end
  end

  defp normalize_root(value, default, root) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      default
    else
      Path.expand(value, root)
    end
  end

  defp normalize_root(nil, default, _root), do: default

  defp normalize_root(value, default, _root) do
    Logger.warning(
      "Babs tickets_root #{inspect(value)} is not a string; falling back to #{inspect(default)}"
    )

    default
  end
end
