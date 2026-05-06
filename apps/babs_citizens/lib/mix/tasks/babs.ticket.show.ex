defmodule Mix.Tasks.Babs.Ticket.Show do
  @moduledoc "Show a Ticket through the temporary Phase 7 Mix bridge."

  use Mix.Task

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Error
  alias Babs.Citizens.Tickets.TicketMarkdown

  @shortdoc "Show a Ticket"
  @requirements ["app.start"]

  @impl true
  def run([id]) do
    case Api.show_ticket(id) do
      {:ok, %{ticket: ticket, history: history}} ->
        Mix.shell().info(TicketMarkdown.render(ticket))
        Mix.shell().info("History:")

        Enum.each(history, fn event ->
          Mix.shell().info(Jason.encode!(event))
        end)

      {:error, reason} ->
        Mix.raise(Error.message(reason))
    end
  end

  def run(_args) do
    Mix.raise("Usage: mix babs.ticket.show T-YYYY-MM-DD-NNN")
  end
end
