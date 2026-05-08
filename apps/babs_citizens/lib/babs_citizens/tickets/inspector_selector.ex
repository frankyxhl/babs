defmodule Babs.Citizens.Tickets.InspectorSelector do
  @moduledoc """
  Selects eligible Inspector Citizens for Phase 15 automatic inspection.
  """

  alias Babs.Citizens.{Catalog, CitizenRecord, ImportedHardline, Roles}
  alias Babs.Citizens.Tickets.History
  alias Babs.Citizens.Tickets.InspectionPolicy
  alias Babs.Citizens.Tickets.Ticket

  @execution_lock_registry Babs.Citizens.ExecutionLockRegistry

  @spec select(Ticket.t(), keyword()) ::
          {:ok, %{policy: map(), inspectors: [map()]}} | {:error, term()}
  def select(%Ticket{} = ticket, opts \\ []) do
    with {:ok, policy} <- InspectionPolicy.from_metadata(ticket.metadata || %{}),
         :ok <- ensure_auto(policy),
         candidates <- eligible_records(ticket, policy, opts),
         explicit <- explicit_candidates(candidates, policy),
         role_candidates <- role_candidates(candidates, policy, explicit, opts),
         inspectors <- (explicit ++ role_candidates) |> Enum.take(policy["max_inspectors"]),
         :ok <- ensure_inspectors(inspectors) do
      {:ok, %{policy: policy, inspectors: inspectors}}
    end
  end

  defp ensure_auto(%{"mode" => "auto"}), do: :ok
  defp ensure_auto(%{"mode" => mode}), do: {:error, {:inspection_not_auto, mode}}

  defp eligible_records(ticket, policy, opts) do
    assignees = MapSet.new(ticket.assignees || [])
    allow_self? = policy["allow_self_inspection"]

    opts
    |> citizens()
    |> Enum.filter(&eligible_record?(&1, assignees, allow_self?))
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

  defp eligible_record?(%CitizenRecord{status: "failed"}, _assignees, _allow_self?), do: false

  defp eligible_record?(%CitizenRecord{slug: slug} = record, assignees, allow_self?) do
    (allow_self? or not MapSet.member?(assignees, slug)) and
      not execution_busy?(slug) and
      executable_record?(record)
  end

  defp executable_record?(%CitizenRecord{} = record) do
    if ImportedHardline.external?(record) do
      present?(ImportedHardline.operational_target(record))
    else
      true
    end
  end

  defp explicit_candidates(candidates, policy) do
    policy["citizens"]
    |> Enum.flat_map(fn slug ->
      case Enum.find(candidates, &(&1.slug == slug)) do
        %CitizenRecord{} = record -> [candidate(record, :explicit, nil)]
        nil -> []
      end
    end)
  end

  defp role_candidates(candidates, policy, explicit, opts) do
    selected = explicit |> Enum.map(& &1.slug) |> MapSet.new()
    roles = policy["roles"]
    latest = latest_inspection_requests(opts)

    candidates
    |> Enum.reject(&MapSet.member?(selected, &1.slug))
    |> Enum.flat_map(&role_candidate(&1, roles))
    |> Enum.sort_by(fn candidate ->
      ts = Map.get(latest, candidate.slug)
      {not is_nil(ts), ts || "", candidate.slug}
    end)
  end

  defp role_candidate(%CitizenRecord{} = record, requested_roles) do
    record_roles = record_role_names(record)

    case Enum.find(requested_roles, &(&1 in record_roles)) do
      nil -> []
      role -> [candidate(record, :role, role)]
    end
  end

  defp candidate(%CitizenRecord{} = record, source, role) do
    %{slug: record.slug, source: source, role: role}
  end

  defp record_role_names(%CitizenRecord{} = record) do
    record
    |> Catalog.to_config()
    |> Map.get(:roles, [])
    |> Roles.normalize()
    |> case do
      {:ok, roles} -> Enum.map(roles, & &1["name"])
      {:error, _reason} -> []
    end
  end

  defp latest_inspection_requests(opts) do
    opts
    |> Keyword.get(:tickets_root)
    |> case do
      root when is_binary(root) and root != "" -> scan_history(root)
      _root -> %{}
    end
  end

  defp scan_history(root) do
    root
    |> Path.join("*.history.jsonl")
    |> Path.wildcard()
    |> Enum.reduce(%{}, fn path, acc ->
      id = path |> Path.basename() |> String.replace_suffix(".history.jsonl", "")

      case History.read(root, id) do
        {:ok, events} -> merge_inspection_requests(acc, events)
        {:error, _reason} -> acc
      end
    end)
  end

  defp merge_inspection_requests(acc, events) do
    Enum.reduce(events, acc, fn
      %{"event" => "inspection_requested", "inspectors" => slugs, "ts" => ts}, acc
      when is_list(slugs) and is_binary(ts) ->
        Enum.reduce(slugs, acc, &max_ts(&2, &1, ts))

      _event, acc ->
        acc
    end)
  end

  defp max_ts(acc, slug, ts) when is_binary(slug), do: Map.update(acc, slug, ts, &max(&1, ts))
  defp max_ts(acc, _slug, _ts), do: acc

  defp ensure_inspectors([]), do: {:error, {:inspection_requires_human, :no_eligible_inspectors}}
  defp ensure_inspectors(_inspectors), do: :ok

  defp execution_busy?(slug) do
    @execution_lock_registry
    |> Registry.lookup(slug)
    |> Enum.any?()
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
