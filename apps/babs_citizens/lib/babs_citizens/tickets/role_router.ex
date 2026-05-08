defmodule Babs.Citizens.Tickets.RoleRouter do
  @moduledoc """
  Selects an eligible Citizen for a Ticket `assignee_role`.
  """

  alias Babs.Citizens.{Catalog, CitizenRecord, Roles}
  alias Babs.Citizens.Tickets.History
  alias Babs.Citizens.Tickets.Ticket

  @execution_lock_registry Babs.Citizens.ExecutionLockRegistry

  @spec resolve(Ticket.t(), keyword()) ::
          {:ok, %{slug: String.t(), role: String.t(), citizen: CitizenRecord.t()}}
          | {:error, term()}
  def resolve(%Ticket{} = ticket, opts \\ []) do
    with {:ok, role} <- normalize_ticket_role(ticket),
         candidates <- eligible_candidates(role, opts),
         {:ok, candidate} <- select_candidate(candidates, role, opts) do
      {:ok, %{slug: candidate.slug, role: role, citizen: candidate.record}}
    end
  end

  defp normalize_ticket_role(%Ticket{id: id, assignee_role: value}) do
    case Roles.normalize(value) do
      {:ok, [%{"name" => role} | _roles]} -> {:ok, role}
      {:ok, []} -> {:error, {:missing_assignee_role, id}}
      {:error, _reason} -> {:error, {:invalid_assignee_role, value}}
    end
  end

  defp eligible_candidates(role, opts) do
    opts
    |> citizens()
    |> Enum.filter(&eligible_record?/1)
    |> Enum.flat_map(&candidate_for(&1, role))
  end

  defp citizens(opts) do
    case Keyword.fetch(opts, :citizens) do
      {:ok, citizens} ->
        citizens

      :error ->
        opts
        |> Keyword.take([:root, :config_dir])
        |> Catalog.list_configured_or_imported_citizens()
    end
  end

  defp eligible_record?(%CitizenRecord{status: "failed"}), do: false
  defp eligible_record?(%CitizenRecord{slug: slug}), do: not execution_busy?(slug)

  defp candidate_for(%CitizenRecord{} = record, role) do
    roles = record_role_names(record)

    if role in roles do
      [%{slug: record.slug, record: record}]
    else
      []
    end
  end

  defp record_role_names(%CitizenRecord{} = record) do
    CitizenRecord.role_names(record)
  end

  defp execution_busy?(slug) do
    @execution_lock_registry
    |> Registry.lookup(slug)
    |> Enum.any?()
  end

  defp select_candidate([], role, _opts), do: {:error, {:no_role_candidate, role}}

  defp select_candidate(candidates, role, opts) do
    latest_assignments = latest_role_assignments(role, opts)

    candidate =
      Enum.min_by(candidates, fn candidate ->
        latest = Map.get(latest_assignments, candidate.slug)
        {not is_nil(latest), latest || "", candidate.slug}
      end)

    {:ok, candidate}
  end

  defp latest_role_assignments(role, opts) do
    opts
    |> Keyword.get(:tickets_root)
    |> case do
      root when is_binary(root) and root != "" -> scan_history(root, role)
      _root -> %{}
    end
  end

  defp scan_history(root, role) do
    root
    |> Path.join("*.history.jsonl")
    |> Path.wildcard()
    |> Enum.reduce(%{}, fn path, acc ->
      id = path |> Path.basename() |> String.replace_suffix(".history.jsonl", "")

      case History.read(root, id) do
        {:ok, events} -> merge_role_assignments(acc, events, role)
        {:error, _reason} -> acc
      end
    end)
  end

  defp merge_role_assignments(acc, events, role) do
    Enum.reduce(events, acc, fn
      %{"event" => "assigned", "via_role" => ^role, "to" => slugs, "ts" => ts}, acc
      when is_list(slugs) and is_binary(ts) ->
        Enum.reduce(slugs, acc, &max_ts(&2, &1, ts))

      _event, acc ->
        acc
    end)
  end

  defp max_ts(acc, slug, ts) when is_binary(slug) do
    Map.update(acc, slug, ts, &max(&1, ts))
  end

  defp max_ts(acc, _slug, _ts), do: acc
end
