defmodule Babs.Citizens.Roles do
  @moduledoc """
  Canonical role normalization for Citizens.

  Public/runtime role data is stored as a list of string-keyed maps:

      [%{"name" => "developer", "skills" => ["elixir"]}]

  Legacy `role` values remain supported during the Phase 14 migration window.
  """

  @label_regex ~r/^[a-z][a-z0-9-]{0,47}$/

  def normalize(nil), do: {:ok, []}
  def normalize([]), do: {:ok, []}

  def normalize(value) when is_binary(value) or is_map(value), do: normalize([value])

  def normalize(values) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case normalize_one(value) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, role} -> {:cont, {:ok, merge_role(acc, role)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def normalize(value), do: {:error, {:invalid_roles, value}}

  def legacy_first_role([]), do: nil

  def legacy_first_role([%{"name" => name, "skills" => []} | _roles]), do: name

  def legacy_first_role([%{"name" => name, "skills" => skills} | _roles]),
    do: %{"name" => name, "skills" => skills}

  def legacy_first_role(value) do
    case normalize(value) do
      {:ok, roles} -> legacy_first_role(roles)
      {:error, _reason} -> nil
    end
  end

  defp normalize_one(value) when is_binary(value) do
    case normalize_label(value) do
      {:ok, ""} -> {:ok, nil}
      {:ok, name} -> {:ok, %{"name" => name, "skills" => []}}
      {:error, _reason} -> {:error, {:invalid_role_name, value}}
    end
  end

  defp normalize_one(%{} = value) do
    case fetch_name(value) do
      nil ->
        {:error, {:missing_role_name, value}}

      raw_name ->
        with {:ok, name} <- normalize_role_name(raw_name),
             {:ok, skills} <- normalize_skills(fetch_skills(value)) do
          {:ok, %{"name" => name, "skills" => skills}}
        end
    end
  end

  defp normalize_one(value), do: {:error, {:invalid_role, value}}

  defp fetch_name(value), do: Map.get(value, "name") || Map.get(value, :name)
  defp fetch_skills(value), do: Map.get(value, "skills") || Map.get(value, :skills) || []

  defp normalize_role_name(value) when is_binary(value) do
    case normalize_label(value) do
      {:ok, ""} -> {:error, {:invalid_role_name, value}}
      {:ok, name} -> {:ok, name}
      {:error, _reason} -> {:error, {:invalid_role_name, value}}
    end
  end

  defp normalize_role_name(value), do: {:error, {:invalid_role_name, value}}

  defp normalize_skills(skills) when is_list(skills) do
    skills
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case normalize_skill(value) do
        {:ok, ""} -> {:cont, {:ok, acc}}
        {:ok, skill} -> {:cont, {:ok, append_unique(acc, skill)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_skills(value), do: {:error, {:invalid_skills, value}}

  defp normalize_skill(value) when is_binary(value) do
    case normalize_label(value) do
      {:ok, skill} -> {:ok, skill}
      {:error, _reason} -> {:error, {:invalid_skill, value}}
    end
  end

  defp normalize_skill(value), do: {:error, {:invalid_skill, value}}

  defp normalize_label(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[\s_]+/, "-")

    cond do
      normalized == "" -> {:ok, ""}
      Regex.match?(@label_regex, normalized) -> {:ok, normalized}
      true -> {:error, :invalid_label}
    end
  end

  defp merge_role([], role), do: [role]

  defp merge_role([%{"name" => name, "skills" => skills} = existing | rest], %{
         "name" => name,
         "skills" => incoming_skills
       }) do
    [%{existing | "skills" => merge_skills(skills, incoming_skills)} | rest]
  end

  defp merge_role([role | rest], incoming), do: [role | merge_role(rest, incoming)]

  defp merge_skills(existing, incoming),
    do: Enum.reduce(incoming, existing, &append_unique(&2, &1))

  defp append_unique(values, value) do
    if value in values, do: values, else: values ++ [value]
  end
end
