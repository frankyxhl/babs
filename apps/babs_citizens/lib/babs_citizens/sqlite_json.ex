defmodule Babs.Citizens.SqliteJson do
  @moduledoc """
  Stores JSON-shaped values in SQLite text columns.
  """

  use Ecto.Type

  @impl true
  def type, do: :string

  @impl true
  def cast(value), do: normalize(value)

  @impl true
  def dump(nil), do: {:ok, nil}

  def dump(value) do
    with {:ok, normalized} <- normalize(value),
         {:ok, encoded} <- Jason.encode(normalized) do
      {:ok, encoded}
    else
      _ -> :error
    end
  end

  @impl true
  def load(nil), do: {:ok, nil}

  def load(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> :error
    end
  end

  def load(_value), do: :error

  defp normalize(value)
       when is_binary(value) or is_integer(value) or is_boolean(value) or is_nil(value),
       do: {:ok, value}

  defp normalize(value) when is_float(value), do: {:ok, value}

  defp normalize(value) when is_list(value) do
    value
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case normalize(item) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      :error -> :error
    end
  end

  defp normalize(value) when is_map(value) do
    value
    |> Enum.reduce_while({:ok, %{}}, fn {key, item}, {:ok, acc} ->
      with {:ok, normalized_key} <- normalize_key(key),
           {:ok, normalized_item} <- normalize(item) do
        {:cont, {:ok, Map.put(acc, normalized_key, normalized_item)}}
      else
        _ -> {:halt, :error}
      end
    end)
  end

  defp normalize(_value), do: :error

  defp normalize_key(key) when is_binary(key), do: {:ok, key}
  defp normalize_key(key) when is_atom(key), do: {:ok, Atom.to_string(key)}
  defp normalize_key(_key), do: :error
end
