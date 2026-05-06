defmodule Mix.Tasks.Babs.Ticket.Assign do
  @moduledoc "Assign a Ticket to a Citizen through the temporary Phase 9 Mix bridge."

  use Mix.Task

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Error

  @shortdoc "Assign a Ticket to a Citizen"
  @requirements ["app.start"]

  @impl true
  def run([id, slug]) do
    case Api.assign_ticket(id, slug) do
      {:ok, %{ticket: ticket, delivery: {:injected, ^slug}}} ->
        Mix.shell().info("#{ticket.id} assigned to #{slug}")
        Mix.shell().info("prompt injected")

      {:ok, %{ticket: ticket}} ->
        Mix.shell().info("#{ticket.id} assigned to #{slug}")

      {:error, reason} ->
        Mix.raise(Error.message(reason))
    end
  end

  def run(_args) do
    Mix.raise("Usage: mix babs.ticket.assign T-YYYY-MM-DD-NNN citizen-slug")
  end
end
