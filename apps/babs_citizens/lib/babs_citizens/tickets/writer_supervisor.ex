defmodule Babs.Citizens.Tickets.WriterSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Babs.Citizens.Tickets.Writer

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_writer(id, opts \\ []) do
    root = Keyword.fetch!(opts, :tickets_root)

    child_spec = %{
      id: {Writer, root, id},
      start: {Writer, :start_link, [Keyword.put(opts, :id, id)]},
      restart: :temporary,
      type: :worker
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end
end
