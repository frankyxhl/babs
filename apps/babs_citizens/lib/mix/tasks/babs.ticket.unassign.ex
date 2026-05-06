defmodule Mix.Tasks.Babs.Ticket.Unassign do
  @moduledoc "Unassign a Ticket from a Citizen through the temporary Phase 10 Mix bridge."

  use Mix.Task

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Error

  @shortdoc "Unassign a Ticket from a Citizen"
  @requirements ["app.start"]

  @impl true
  def run([id, slug]) do
    case Api.unassign_ticket(id, slug) do
      {:ok, %{ticket: ticket}} ->
        Mix.shell().info("#{ticket.id} unassigned from #{slug}")
        Mix.shell().info("state #{ticket.state}")

      {:error, reason} ->
        Mix.raise(Error.message(reason))
    end
  end

  def run(_args) do
    Mix.raise("Usage: mix babs.ticket.unassign T-YYYY-MM-DD-NNN citizen-slug")
  end
end
