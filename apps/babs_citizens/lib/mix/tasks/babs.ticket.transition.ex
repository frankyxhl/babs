defmodule Mix.Tasks.Babs.Ticket.Transition do
  @moduledoc "Move a Ticket through the temporary Phase 10 Mix bridge."

  use Mix.Task

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Error

  @shortdoc "Transition a Ticket state"
  @requirements ["app.start"]

  @impl true
  def run([id, to_state]) do
    transition(id, to_state, nil)
  end

  def run([id, to_state, event]) do
    transition(id, to_state, event)
  end

  def run(_args) do
    Mix.raise("Usage: mix babs.ticket.transition T-YYYY-MM-DD-NNN state [event]")
  end

  defp transition(id, to_state, event) do
    case Api.transition_ticket(id, to_state, event) do
      {:ok, %{ticket: ticket}} ->
        Mix.shell().info("#{ticket.id} state #{ticket.state}")

      {:error, reason} ->
        Mix.raise(Error.message(reason))
    end
  end
end
