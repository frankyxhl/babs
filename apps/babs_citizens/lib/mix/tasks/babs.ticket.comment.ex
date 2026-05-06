defmodule Mix.Tasks.Babs.Ticket.Comment do
  @moduledoc "Append a storage-only Ticket comment through the temporary Phase 7 Mix bridge."

  use Mix.Task

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Error

  @shortdoc "Comment on a Ticket"
  @requirements ["app.start"]

  @impl true
  def run([id, body]) do
    case Api.comment_ticket(id, %{body: body}) do
      {:ok, %{ticket: ticket, delivery: :deferred}} ->
        Mix.shell().info("#{ticket.id} comment stored")
        Mix.shell().info("live delivery is deferred until Phase 12")

      {:error, reason} ->
        Mix.raise(Error.message(reason))
    end
  end

  def run(_args) do
    Mix.raise("Usage: mix babs.ticket.comment T-YYYY-MM-DD-NNN \"comment body\"")
  end
end
