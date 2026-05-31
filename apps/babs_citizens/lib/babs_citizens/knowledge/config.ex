defmodule Babs.Citizens.Knowledge.Config do
  @moduledoc """
  Resolves Citizen-scoped knowledge home paths.
  """

  require Logger

  alias Babs.Citizens.Citizen.Config, as: CitizenConfig

  @path_separator "/"

  @type resolve_error ::
          {:invalid_slug, term()}
          | {:invalid_relative_path, term()}
          | {:null_byte, term()}
          | {:empty_relative_path, term()}
          | {:non_relative_path, term()}
          | {:path_traversal, term()}
          | {:path_escape, term()}

  @spec root(keyword()) :: String.t()
  def root(opts \\ []) do
    opts
    |> Keyword.get(:root, Application.get_env(:babs_citizens, :root, File.cwd!()))
    |> Path.expand()
  end

  @spec workspace_root(keyword()) :: String.t()
  def workspace_root(opts \\ []) do
    root = root(opts)
    default = Path.join(root, "workspaces")

    opts
    |> Keyword.get(:workspace_root, Application.get_env(:babs_citizens, :workspace_root))
    |> normalize_root(:workspace_root, default, root)
  end

  @spec knowledge_root(keyword()) :: String.t()
  def knowledge_root(opts \\ []) do
    root = root(opts)
    default = workspace_root(opts)

    opts
    |> Keyword.get(:knowledge_root, Application.get_env(:babs_citizens, :knowledge_root))
    |> normalize_root(:knowledge_root, default, root)
  end

  @spec citizen_home(term(), keyword()) :: {:ok, String.t()} | {:error, {:invalid_slug, term()}}
  def citizen_home(slug, opts \\ []) do
    if CitizenConfig.valid_slug?(slug) do
      {:ok, Path.expand(Path.join(knowledge_root(opts), slug))}
    else
      {:error, {:invalid_slug, slug}}
    end
  end

  @spec resolve(term(), term(), keyword()) :: {:ok, String.t()} | {:error, resolve_error()}
  def resolve(slug, relative_path, opts \\ []) do
    with :ok <- validate_slug(slug),
         :ok <- validate_relative_path(relative_path),
         {:ok, home} <- citizen_home(slug, opts),
         expanded_path <- Path.expand(relative_path, home),
         :ok <- validate_inside_home(expanded_path, home) do
      {:ok, expanded_path}
    end
  end

  defp validate_slug(slug) do
    if CitizenConfig.valid_slug?(slug), do: :ok, else: {:error, {:invalid_slug, slug}}
  end

  defp validate_relative_path(relative_path) when is_binary(relative_path) do
    segments = Path.split(relative_path)

    cond do
      String.contains?(relative_path, <<0>>) ->
        {:error, {:null_byte, relative_path}}

      String.trim(relative_path) == "" ->
        {:error, {:empty_relative_path, relative_path}}

      Path.type(relative_path) != :relative ->
        {:error, {:non_relative_path, relative_path}}

      first_segment_tilde?(segments) ->
        {:error, {:non_relative_path, relative_path}}

      Enum.any?(segments, &(&1 == "..")) ->
        {:error, {:path_traversal, relative_path}}

      true ->
        :ok
    end
  end

  defp validate_relative_path(relative_path),
    do: {:error, {:invalid_relative_path, relative_path}}

  defp first_segment_tilde?([]), do: false

  defp first_segment_tilde?([first | _rest]) do
    String.starts_with?(first, "~")
  end

  defp validate_inside_home(expanded_path, home) do
    # Defense: keep containment correct if citizen_home/2 root derivation changes.
    expanded_home = Path.expand(home)

    if expanded_path == expanded_home or
         String.starts_with?(expanded_path, expanded_home <> @path_separator) do
      :ok
    else
      {:error, {:path_escape, expanded_path}}
    end
  end

  defp normalize_root(value, _key, default, root) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      default
    else
      Path.expand(value, root)
    end
  end

  defp normalize_root(nil, _key, default, _root), do: default

  defp normalize_root(value, key, default, _root) do
    Logger.warning(
      "Babs #{key} #{inspect(value)} is not a string; falling back to #{inspect(default)}"
    )

    default
  end
end
