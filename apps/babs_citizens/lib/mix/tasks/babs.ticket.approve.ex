defmodule Mix.Tasks.Babs.Ticket.Approve do
  @moduledoc "Approve a pending Ticket through the temporary Phase 11 Mix bridge."

  use Mix.Task

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Error

  @shortdoc "Approve a pending Ticket"
  @requirements ["app.start"]

  @impl true
  def run([id]) do
    case Api.approve_ticket(id) do
      {:ok, %{ticket: ticket}} ->
        Mix.shell().info("#{ticket.id} approved")
        Mix.shell().info("state #{ticket.state}")

      {:error, reason} ->
        Mix.raise(Error.message(reason))
    end
  end

  def run(_args) do
    Mix.raise("Usage: mix babs.ticket.approve T-YYYY-MM-DD-NNN")
  end
end
