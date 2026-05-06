defmodule Babs.Citizens.Tickets.Ticket do
  @moduledoc """
  Normalized in-memory representation of a Ticket markdown file.
  """

  @enforce_keys [
    :id,
    :type,
    :state,
    :assigner,
    :assignees,
    :assignee_role,
    :inspector,
    :priority,
    :parent_ticket,
    :created_at,
    :updated_at,
    :metadata,
    :title,
    :body
  ]
  defstruct [
    :id,
    :type,
    :state,
    :assigner,
    :assignees,
    :assignee_role,
    :inspector,
    :priority,
    :parent_ticket,
    :created_at,
    :updated_at,
    :metadata,
    :title,
    :body,
    :path,
    warnings: []
  ]
end
