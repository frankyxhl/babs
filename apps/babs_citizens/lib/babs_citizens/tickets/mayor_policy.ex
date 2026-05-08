defmodule Babs.Citizens.Tickets.MayorPolicy do
  @moduledoc """
  Normalizes and validates Phase 16 Mayor proposal metadata.
  """

  alias Babs.Citizens.Citizen.Config, as: CitizenConfig
  alias Babs.Citizens.Roles

  @max_policy_list 10
  @max_children 10

  @atom_fields %{
    "mode" => :mode,
    "mayor" => :mayor,
    "rules_refs" => :rules_refs,
    "max_children" => :max_children,
    "allowed_roles" => :allowed_roles,
    "require_human_approval" => :require_human_approval
  }

  @spec from_metadata(map()) :: {:ok, map()} | :missing | {:error, term()}
  def from_metadata(metadata) when is_map(metadata) do
    case mayor_value(metadata) do
      {:ok, value} -> normalize(value)
      :missing -> :missing
    end
  end

  def from_metadata(value), do: {:error, {:mayor_policy, {:invalid_metadata, value}}}

  @spec normalize_metadata(map()) :: {:ok, map()} | {:error, term()}
  def normalize_metadata(metadata) when is_map(metadata) do
    metadata = string_key_metadata(metadata)

    case mayor_value(metadata) do
      {:ok, value} ->
        with {:ok, policy} <- normalize(value) do
          {:ok, Map.put(metadata, "mayor", policy)}
        end

      :missing ->
        {:ok, metadata}
    end
  end

  def normalize_metadata(value), do: {:error, {:mayor_policy, {:invalid_metadata, value}}}

  @spec normalize(map()) :: {:ok, map()} | {:error, term()}
  def normalize(policy) when is_map(policy) do
    with {:ok, mode} <- mode_field(policy),
         {:ok, mayor} <- mayor_field(policy),
         {:ok, rules_refs} <- string_list(policy, "rules_refs", [], :rules_refs),
         {:ok, max_children} <- max_children_field(policy),
         {:ok, allowed_roles} <- allowed_roles_field(policy),
         {:ok, require_human_approval} <- require_human_approval_field(policy) do
      {:ok,
       %{
         "mode" => mode,
         "mayor" => mayor,
         "rules_refs" => rules_refs,
         "max_children" => max_children,
         "allowed_roles" => allowed_roles,
         "require_human_approval" => require_human_approval
       }}
    end
  end

  def normalize(value), do: {:error, {:mayor_policy, {:invalid_policy, value}}}

  defp mayor_value(metadata) do
    cond do
      Map.has_key?(metadata, "mayor") -> {:ok, Map.get(metadata, "mayor")}
      Map.has_key?(metadata, :mayor) -> {:ok, Map.get(metadata, :mayor)}
      true -> :missing
    end
  end

  defp mode_field(policy) do
    case field(policy, "mode", nil) do
      "propose" -> {:ok, "propose"}
      value -> {:error, {:mayor_policy, {:invalid_mode, value}}}
    end
  end

  defp mayor_field(policy) do
    case field(policy, "mayor", nil) do
      nil ->
        {:ok, nil}

      slug when is_binary(slug) ->
        slug = String.trim(slug)

        if CitizenConfig.valid_slug?(slug) do
          {:ok, slug}
        else
          {:error, {:mayor_policy, {:invalid_mayor_slug, slug}}}
        end

      value ->
        {:error, {:mayor_policy, {:invalid_mayor_slug, value}}}
    end
  end

  defp string_list(policy, key, default, error_key) do
    case field(policy, key, default) do
      values when is_list(values) ->
        values
        |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
          case normalize_string(value) do
            {:ok, normalized} ->
              {:cont, {:ok, append_unique(acc, normalized)}}

            {:error, _reason} ->
              {:halt, {:error, {:mayor_policy, {:"invalid_#{error_key}", value}}}}
          end
        end)
        |> case do
          {:ok, normalized} when length(normalized) <= @max_policy_list ->
            {:ok, normalized}

          {:ok, normalized} ->
            {:error, {:mayor_policy, {:"too_many_#{error_key}", length(normalized)}}}

          {:error, reason} ->
            {:error, reason}
        end

      value ->
        {:error, {:mayor_policy, {:"invalid_#{error_key}", value}}}
    end
  end

  defp max_children_field(policy) do
    value = field(policy, "max_children", 5)

    if is_integer(value) and value >= 1 and value <= @max_children do
      {:ok, value}
    else
      {:error, {:mayor_policy, {:invalid_max_children, value}}}
    end
  end

  defp allowed_roles_field(policy) do
    case field(policy, "allowed_roles", []) do
      values when is_list(values) ->
        case Roles.normalize(values) do
          {:ok, roles} ->
            names = Enum.map(roles, & &1["name"])

            if length(names) <= @max_policy_list do
              {:ok, names}
            else
              {:error, {:mayor_policy, {:too_many_allowed_roles, length(names)}}}
            end

          {:error, reason} ->
            {:error, {:mayor_policy, reason}}
        end

      value ->
        {:error, {:mayor_policy, {:invalid_allowed_roles, value}}}
    end
  end

  defp require_human_approval_field(policy) do
    case field(policy, "require_human_approval", nil) do
      true -> {:ok, true}
      value -> {:error, {:mayor_policy, {:human_approval_required, value}}}
    end
  end

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, :blank}
      trimmed -> {:ok, trimmed}
    end
  end

  defp normalize_string(_value), do: {:error, :invalid}

  defp append_unique(values, value) do
    if value in values, do: values, else: values ++ [value]
  end

  defp field(policy, key, default),
    do: Map.get(policy, key, Map.get(policy, Map.fetch!(@atom_fields, key), default))

  defp string_key_metadata(metadata) do
    Map.new(metadata, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end
end
