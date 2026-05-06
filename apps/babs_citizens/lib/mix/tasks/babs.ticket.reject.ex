defmodule Mix.Tasks.Babs.Ticket.Reject do
  @moduledoc "Reject a pending Ticket with feedback through the temporary Phase 11 Mix bridge."

  use Mix.Task

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Error

  @shortdoc "Reject a pending Ticket with feedback"
  @requirements ["app.start"]

  @impl true
  def run([id, feedback]) do
    case Api.reject_ticket(id, feedback) do
      {:ok, %{ticket: ticket}} ->
        Mix.shell().info("#{ticket.id} rejected")
        Mix.shell().info("state #{ticket.state}")

      {:error, reason} ->
        Mix.raise(Error.message(reason))
    end
  end

  def run(_args) do
    Mix.raise("Usage: mix babs.ticket.reject T-YYYY-MM-DD-NNN \"feedback text\"")
  end
end
