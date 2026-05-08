defmodule Babs.Citizens.Tickets.MayorPlanner do
  @moduledoc """
  Side-effect-free preparation boundary for Phase 16 Mayor proposal planning.
  """

  alias Babs.Citizens.Catalog
  alias Babs.Citizens.Tickets.MayorPolicy
  alias Babs.Citizens.Tickets.MayorProposal
  alias Babs.Citizens.Tickets.MayorSelector
  alias Babs.Citizens.Tickets.PromptAssembler
  alias Babs.Citizens.Tickets.Ticket

  @spec prepare(Ticket.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def prepare(%Ticket{} = ticket, opts \\ []) do
    lister = Keyword.get(opts, :lister, &Catalog.list_configured_or_imported_citizens/0)
    fetcher = Keyword.get(opts, :fetcher, &Catalog.get_by_slug/1)
    history = Keyword.get(opts, :history, [])

    with {:ok, policy} <- policy(ticket) do
      citizens = lister.()

      with {:ok, mayor} <-
             MayorSelector.select(policy, lister: fn -> citizens end, fetcher: fetcher) do
        prompt =
          PromptAssembler.mayor_proposal_prompt(ticket, history, mayor, policy, citizens,
            max_messages: Keyword.get(opts, :max_messages, 12)
          )

        {:ok,
         %{
           ticket: ticket,
           policy: policy,
           mayor: mayor,
           citizens: citizens,
           prompt: prompt
         }}
      end
    end
  end

  @spec parse_reply(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def parse_reply(raw_reply, policy) when is_map(policy) do
    opts = [
      max_children: Map.get(policy, "max_children", Map.get(policy, :max_children, 5)),
      allowed_roles: Map.get(policy, "allowed_roles", Map.get(policy, :allowed_roles, []))
    ]

    case MayorProposal.parse(raw_reply, opts) do
      {:ok, proposal} -> {:ok, proposal}
      {:error, reason} -> {:error, {:mayor_planner, {:invalid_proposal, reason}}}
    end
  end

  def parse_reply(_raw_reply, policy),
    do: {:error, {:mayor_planner, {:invalid_policy, policy}}}

  defp policy(%Ticket{} = ticket) do
    case MayorPolicy.from_metadata(ticket.metadata) do
      {:ok, policy} -> {:ok, policy}
      :missing -> {:error, {:mayor_planner, :missing_policy}}
      {:error, reason} -> {:error, {:mayor_planner, {:invalid_policy, reason}}}
    end
  end
end
