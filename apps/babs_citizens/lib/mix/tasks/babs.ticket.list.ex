defmodule Mix.Tasks.Babs.Ticket.List do
  @moduledoc "List Tickets through the temporary Phase 7 Mix bridge."

  use Mix.Task

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Error

  @shortdoc "List Tickets"
  @requirements ["app.start"]

  @impl true
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args, strict: [state: :string, assignee: :string])

    api_opts =
      []
      |> maybe_put(:state, opts[:state])
      |> maybe_put(:assignee, opts[:assignee])

    case Api.list_tickets(api_opts) do
      {:ok, %{tickets: tickets, invalid: invalid}} ->
        Enum.each(tickets, fn ticket ->
          Mix.shell().info("#{ticket.id}\t#{ticket.state}\t#{ticket.title}")
        end)

        Enum.each(invalid, fn invalid ->
          Mix.shell().error("invalid\t#{Path.basename(invalid.path)}\t#{inspect(invalid.reason)}")
        end)

      {:error, reason} ->
        Mix.raise(Error.message(reason))
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
