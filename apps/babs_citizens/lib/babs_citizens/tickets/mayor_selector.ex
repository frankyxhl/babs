defmodule Babs.Citizens.Tickets.MayorSelector do
  @moduledoc """
  Selects the Mayor Citizen for Phase 16 proposal planning.
  """

  alias Babs.Citizens.{Catalog, CitizenRecord, ImportedHardline}

  @mayor_roles ~w(mayor planner)

  @spec select(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def select(policy, opts \\ [])

  def select(policy, opts) when is_map(policy) do
    case Map.get(policy, "mayor", Map.get(policy, :mayor)) do
      slug when is_binary(slug) and slug != "" -> select_pinned(slug, opts)
      _nil_or_blank -> select_default(opts)
    end
  end

  def select(_policy, _opts), do: {:error, {:mayor_selector, {:invalid_policy, :not_map}}}

  defp select_pinned(slug, opts) do
    fetcher = Keyword.get(opts, :fetcher, &Catalog.get_by_slug/1)

    case fetcher.(slug) do
      %CitizenRecord{} = record -> validate_candidate(record, :pinned)
      nil -> {:error, {:mayor_selector, {:missing_mayor, slug}}}
    end
  end

  defp select_default(opts) do
    lister = Keyword.get(opts, :lister, &Catalog.list_configured_or_imported_citizens/0)

    lister.()
    |> Enum.sort_by(& &1.slug)
    |> Enum.reject(&ImportedHardline.external?/1)
    |> Enum.find_value(fn record ->
      case validate_candidate(record, :default) do
        {:ok, selected} -> {:ok, selected}
        {:error, _reason} -> nil
      end
    end)
    |> case do
      {:ok, selected} -> {:ok, selected}
      nil -> {:error, {:mayor_selector, :no_default_mayor}}
    end
  end

  defp validate_candidate(%CitizenRecord{} = record, selection) do
    cond do
      record.status == "failed" ->
        {:error, {:mayor_selector, {:failed_mayor, record.slug}}}

      not record.is_mayor ->
        {:error, {:mayor_selector, {:ineligible_mayor, record.slug, :not_marked_mayor}}}

      not mayor_role?(record) ->
        {:error, {:mayor_selector, {:ineligible_mayor, record.slug, :missing_mayor_role}}}

      true ->
        {:ok,
         %{
           slug: record.slug,
           role: mayor_role(record),
           selection: selection,
           citizen: record
         }}
    end
  end

  defp mayor_role?(%CitizenRecord{} = record), do: mayor_role(record) != nil

  defp mayor_role(%CitizenRecord{} = record) do
    record
    |> CitizenRecord.role_names()
    |> Enum.find(&(&1 in @mayor_roles))
  end
end
