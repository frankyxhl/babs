defmodule Babs.Citizens.Tickets.InspectionPolicy do
  @moduledoc """
  Normalizes and validates Phase 15 Ticket inspection policy metadata.
  """

  alias Babs.Citizens.Citizen.Config, as: CitizenConfig
  alias Babs.Citizens.Roles

  @default %{
    "mode" => "human",
    "strategy" => "single",
    "roles" => ["inspector"],
    "citizens" => [],
    "quorum" => "all_pass",
    "max_inspectors" => 3,
    "allow_self_inspection" => false
  }
  @modes ~w(human auto)
  @strategies ~w(single council)
  @quorums ~w(all_pass)
  @max_inspectors 10
  @max_policy_list 10
  @atom_fields %{
    "mode" => :mode,
    "strategy" => :strategy,
    "roles" => :roles,
    "citizens" => :citizens,
    "quorum" => :quorum,
    "max_inspectors" => :max_inspectors,
    "allow_self_inspection" => :allow_self_inspection
  }

  @spec default() :: map()
  def default, do: @default

  @spec from_metadata(map()) :: {:ok, map()} | {:error, term()}
  def from_metadata(metadata) when is_map(metadata) do
    case inspection_value(metadata) do
      {:ok, value} -> normalize(value)
      :missing -> {:ok, @default}
    end
  end

  def from_metadata(value), do: {:error, {:inspection_policy, {:invalid_metadata, value}}}

  @spec normalize_metadata(map()) :: {:ok, map()} | {:error, term()}
  def normalize_metadata(metadata) when is_map(metadata) do
    case inspection_value(metadata) do
      {:ok, value} ->
        with {:ok, policy} <- normalize(value) do
          {:ok,
           metadata
           |> Map.delete(:inspection)
           |> Map.delete("inspection")
           |> Map.put("inspection", policy)}
        end

      :missing ->
        {:ok, metadata}
    end
  end

  def normalize_metadata(value), do: {:error, {:inspection_policy, {:invalid_metadata, value}}}

  @spec normalize(map()) :: {:ok, map()} | {:error, term()}
  def normalize(policy) when is_map(policy) do
    with {:ok, mode} <- enum_field(policy, "mode", @modes, "human", :invalid_mode),
         {:ok, strategy} <-
           enum_field(policy, "strategy", @strategies, "single", :invalid_strategy),
         {:ok, quorum} <- enum_field(policy, "quorum", @quorums, "all_pass", :unsupported_quorum),
         {:ok, roles} <- roles_field(policy),
         {:ok, citizens} <- citizens_field(policy),
         {:ok, max_inspectors} <- max_inspectors_field(policy),
         {:ok, allow_self_inspection} <- boolean_field(policy, "allow_self_inspection", false),
         :ok <- validate_auto_candidates(mode, roles, citizens) do
      {:ok,
       %{
         "mode" => mode,
         "strategy" => strategy,
         "roles" => roles,
         "citizens" => citizens,
         "quorum" => quorum,
         "max_inspectors" => max_inspectors,
         "allow_self_inspection" => allow_self_inspection
       }}
    end
  end

  def normalize(value), do: {:error, {:inspection_policy, {:invalid_policy, value}}}

  defp inspection_value(metadata) do
    cond do
      Map.has_key?(metadata, "inspection") -> {:ok, Map.get(metadata, "inspection")}
      Map.has_key?(metadata, :inspection) -> {:ok, Map.get(metadata, :inspection)}
      true -> :missing
    end
  end

  defp enum_field(policy, key, allowed, default, error_tag) do
    value = field(policy, key, default)

    if is_binary(value) and value in allowed do
      {:ok, value}
    else
      {:error, {:inspection_policy, {error_tag, value}}}
    end
  end

  defp roles_field(policy) do
    policy
    |> field("roles", ["inspector"])
    |> Roles.normalize()
    |> case do
      {:ok, roles} ->
        names = Enum.map(roles, & &1["name"])

        if length(names) <= @max_policy_list do
          {:ok, names}
        else
          {:error, {:inspection_policy, {:too_many_roles, length(names)}}}
        end

      {:error, reason} ->
        {:error, {:inspection_policy, reason}}
    end
  end

  defp citizens_field(policy) do
    value = field(policy, "citizens", [])

    if is_list(value) do
      value
      |> Enum.reduce_while({:ok, []}, fn slug, {:ok, acc} ->
        cond do
          not is_binary(slug) ->
            {:halt, {:error, {:inspection_policy, {:invalid_citizen_slug, slug}}}}

          not CitizenConfig.valid_slug?(slug) ->
            {:halt, {:error, {:inspection_policy, {:invalid_citizen_slug, slug}}}}

          slug in acc ->
            {:cont, {:ok, acc}}

          true ->
            {:cont, {:ok, acc ++ [slug]}}
        end
      end)
      |> case do
        {:ok, citizens} when length(citizens) <= @max_policy_list ->
          {:ok, citizens}

        {:ok, citizens} ->
          {:error, {:inspection_policy, {:too_many_citizens, length(citizens)}}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, {:inspection_policy, {:invalid_citizens, value}}}
    end
  end

  defp max_inspectors_field(policy) do
    value = field(policy, "max_inspectors", 3)

    if is_integer(value) and value >= 1 and value <= @max_inspectors do
      {:ok, value}
    else
      {:error, {:inspection_policy, {:invalid_max_inspectors, value}}}
    end
  end

  defp boolean_field(policy, key, default) do
    value = field(policy, key, default)

    if is_boolean(value) do
      {:ok, value}
    else
      {:error, {:inspection_policy, {:invalid_allow_self_inspection, value}}}
    end
  end

  defp validate_auto_candidates("auto", [], []),
    do: {:error, {:inspection_policy, :missing_inspection_candidates}}

  defp validate_auto_candidates(_mode, _roles, _citizens), do: :ok

  defp field(policy, key, default),
    do: Map.get(policy, key, Map.get(policy, Map.fetch!(@atom_fields, key), default))
end
