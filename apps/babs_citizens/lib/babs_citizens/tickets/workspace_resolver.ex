defmodule Babs.Citizens.Tickets.WorkspaceResolver do
  @moduledoc """
  Resolves the git workspace for a Ticket's primary assignee.

  Multi-assignee tickets use the first slug in the Ticket `assignees` list. The
  Ticket writer preserves assignment order, so this gives Phase 4 diff review a
  stable primary workspace until the UI grows explicit assignee selection.
  """

  alias Babs.Citizens.{Catalog, CitizenRecord}
  alias Babs.Citizens.Tickets.Store
  alias Babs.Git

  @type resolved_workspace :: %{
          ticket_id: String.t(),
          assignee: String.t(),
          workspace: String.t()
        }

  @type error ::
          {:no_assignee, String.t()}
          | {:citizen_not_found, String.t()}
          | {:no_cwd, String.t()}
          | {:invalid_workspace, map()}
          | {:not_git_repo, map()}
          | Git.error()

  @spec resolve_workspace(String.t(), keyword()) ::
          {:ok, resolved_workspace()} | {:error, term()}
  def resolve_workspace(ticket_id, opts \\ []) do
    with {:ok, %{ticket: ticket}} <- Store.show(ticket_id, opts),
         {:ok, assignee} <- primary_assignee(ticket),
         {:ok, citizen} <- fetch_citizen(assignee),
         {:ok, workspace} <- resolve_cwd(citizen),
         :ok <- validate_git_repo(workspace, assignee, Keyword.get(opts, :git_opts, [])) do
      {:ok, %{ticket_id: ticket.id, assignee: assignee, workspace: workspace}}
    end
  end

  defp primary_assignee(%{assignees: [assignee | _rest]}) when is_binary(assignee) do
    {:ok, assignee}
  end

  defp primary_assignee(%{id: ticket_id}), do: {:error, {:no_assignee, ticket_id}}

  defp fetch_citizen(slug) do
    case Catalog.get_by_slug(slug) do
      %CitizenRecord{} = citizen -> {:ok, citizen}
      nil -> {:error, {:citizen_not_found, slug}}
    end
  end

  defp resolve_cwd(%CitizenRecord{slug: slug, cwd: cwd}) when is_binary(cwd) do
    case String.trim(cwd) do
      "" -> {:error, {:no_cwd, slug}}
      cwd -> {:ok, Path.expand(cwd)}
    end
  end

  defp resolve_cwd(%CitizenRecord{slug: slug}), do: {:error, {:no_cwd, slug}}

  defp validate_git_repo(workspace, assignee, git_opts) do
    case Git.status(workspace, git_opts) do
      {:ok, _status} ->
        :ok

      {:error, {:not_git_repo, details}} ->
        {:error,
         {:not_git_repo,
          details
          |> Map.put(:assignee, assignee)
          |> Map.put(:workspace, workspace)}}

      {:error, {:invalid_workspace, reason}} ->
        {:error,
         {:invalid_workspace,
          %{
            assignee: assignee,
            workspace: workspace,
            reason: reason
          }}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
