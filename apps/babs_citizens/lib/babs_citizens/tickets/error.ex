defmodule Babs.Citizens.Tickets.Error do
  @moduledoc """
  Stable user-facing error messages for Ticket commands.
  """

  def message({:not_found, id}), do: "Ticket #{id} was not found"
  def message({:invalid_id, id}), do: "Invalid Ticket id: #{inspect(id)}"

  def message({:invalid_frontmatter, reason}),
    do: "Invalid Ticket frontmatter: #{inspect(reason)}"

  def message({:invalid_history, {_id, line, reason}}),
    do: "Invalid Ticket history at line #{line}: #{inspect(reason)}"

  def message({:invalid_history_event, reason}),
    do: "Invalid Ticket history event: #{inspect(reason)}"

  def message({:history_event_too_large, id}), do: "Ticket #{id} history event is too large"
  def message({:write_conflict, id}), do: "Ticket #{id} changed while Babs was writing it"

  def message({:redacted_io_error, {operation, _reason}}),
    do: "Ticket IO failed during #{operation}"

  def message({:redacted_io_error, operation}), do: "Ticket IO failed during #{operation}"
  def message(reason), do: "Ticket operation failed: #{inspect(reason)}"
end
