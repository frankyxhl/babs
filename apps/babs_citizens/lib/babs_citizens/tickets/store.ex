defmodule Babs.Citizens.Tickets.Store do
  @moduledoc """
  Read-only Ticket store operations.
  """

  alias Babs.Citizens.Tickets.Config
  alias Babs.Citizens.Tickets.History
  alias Babs.Citizens.Tickets.TicketId
  alias Babs.Citizens.Tickets.TicketMarkdown

  @spec list(keyword()) :: {:ok, %{tickets: list(), invalid: list()}} | {:error, term()}
  def list(opts \\ []) do
    root = Config.tickets_root(opts)

    entries =
      if File.dir?(root) do
        root
        |> Path.join("T-*.md")
        |> Path.wildcard()
        |> Enum.map(&read_ticket_file(&1, opts))
      else
        []
      end

    tickets =
      entries
      |> Enum.flat_map(fn
        {:ok, ticket} -> [ticket]
        _ -> []
      end)
      |> filter(opts)
      |> Enum.sort(&ticket_sorter/2)

    invalid =
      Enum.flat_map(entries, fn
        {:invalid, invalid} -> [invalid]
        _ -> []
      end)

    {:ok, %{tickets: tickets, invalid: invalid}}
  end

  @spec show(String.t(), keyword()) ::
          {:ok, %{ticket: struct(), history: [map()]}} | {:error, term()}
  def show(id, opts \\ []) do
    root = Config.tickets_root(opts)

    with :ok <- TicketId.validate(id),
         {:ok, ticket} <- read_ticket(root, id, opts),
         {:ok, history} <- History.read(root, id) do
      {:ok, %{ticket: ticket, history: history}}
    end
  end

  def read_ticket(root, id, opts \\ []) do
    path = TicketMarkdown.path(root, id)

    case File.read(path) do
      {:ok, content} -> TicketMarkdown.parse(content, Keyword.put(opts, :path, path))
      {:error, :enoent} -> {:error, {:not_found, id}}
      {:error, reason} -> {:error, {:redacted_io_error, {:read_ticket, reason}}}
    end
  end

  defp read_ticket_file(path, opts) do
    case File.read(path) do
      {:ok, content} ->
        case TicketMarkdown.parse(content, Keyword.put(opts, :path, path)) do
          {:ok, ticket} ->
            root = Path.dirname(path)

            case History.read(root, ticket.id) do
              {:ok, _history} -> {:ok, ticket}
              {:error, reason} -> {:invalid, %{path: path, reason: reason}}
            end

          {:error, reason} ->
            {:invalid, %{path: path, reason: reason}}
        end

      {:error, reason} ->
        {:invalid, %{path: path, reason: {:redacted_io_error, {:read_ticket, reason}}}}
    end
  end

  defp filter(tickets, opts) do
    tickets
    |> filter_state(Keyword.get(opts, :state))
    |> filter_assignee(Keyword.get(opts, :assignee))
  end

  defp filter_state(tickets, nil), do: tickets
  defp filter_state(tickets, state), do: Enum.filter(tickets, &(&1.state == state))

  defp filter_assignee(tickets, nil), do: tickets
  defp filter_assignee(tickets, assignee), do: Enum.filter(tickets, &(assignee in &1.assignees))

  defp ticket_sorter(left, right) do
    {left.updated_at, left.id} >= {right.updated_at, right.id}
  end
end
