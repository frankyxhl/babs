defmodule Babs.Citizens.Repo.Migrations.AddRolesToCitizens do
  use Ecto.Migration

  @label_regex ~r/^[a-z][a-z0-9-]{0,47}$/

  def up do
    alter table(:citizens) do
      add(:roles, :text, null: false, default: "[]")
    end

    flush()
    backfill_roles()
  end

  def down do
    alter table(:citizens) do
      remove(:roles)
    end
  end

  defp backfill_roles do
    result = repo().query!("select id, role from citizens where role is not null")

    Enum.each(result.rows, fn [id, role] ->
      roles =
        role
        |> decode_role()
        |> normalize()
        |> case do
          {:ok, roles} -> roles
          {:error, _reason} -> []
        end

      repo().query!("update citizens set roles = ? where id = ?", [Jason.encode!(roles), id])
    end)
  end

  defp decode_role(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> decoded
      {:error, _reason} -> nil
    end
  end

  defp normalize(nil), do: {:ok, []}
  defp normalize([]), do: {:ok, []}
  defp normalize(value) when is_binary(value) or is_map(value), do: normalize([value])

  defp normalize(values) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case normalize_one(value) do
        {:ok, role} -> {:cont, {:ok, merge_role(acc, role)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # Migrations must tolerate malformed legacy data so one bad historical role
  # value cannot block the schema upgrade. Runtime normalization is stricter.
  defp normalize(_value), do: {:ok, []}

  defp normalize_one(value) when is_binary(value) do
    with {:ok, name} <- label(value) do
      {:ok, %{"name" => name, "skills" => []}}
    end
  end

  defp normalize_one(%{} = value) do
    with name when is_binary(name) <- Map.get(value, "name"),
         {:ok, name} <- label(name),
         {:ok, skills} <- skills(Map.get(value, "skills", [])) do
      {:ok, %{"name" => name, "skills" => skills}}
    else
      _reason -> {:error, :invalid_role}
    end
  end

  defp normalize_one(_value), do: {:error, :invalid_role}

  defp skills(values) when is_list(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case label(value) do
        {:ok, skill} -> {:cont, {:ok, append_unique(acc, skill)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp skills(_value), do: {:error, :invalid_skills}

  defp label(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[\s_]+/, "-")

    if Regex.match?(@label_regex, normalized),
      do: {:ok, normalized},
      else: {:error, :invalid_label}
  end

  defp label(_value), do: {:error, :invalid_label}

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
