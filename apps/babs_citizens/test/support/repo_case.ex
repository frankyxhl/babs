defmodule Babs.Citizens.RepoCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Babs.Citizens.{CitizenRecord, Repo}

      import Babs.Citizens.RepoCase
    end
  end

  setup do
    Babs.Citizens.RepoCase.ensure_repo!()
    Babs.Citizens.Repo.delete_all(Babs.Citizens.CitizenRecord)
    :ok
  end

  def ensure_repo! do
    {:ok, _apps} = Application.ensure_all_started(:babs_citizens)

    Ecto.Migrator.with_repo(Babs.Citizens.Repo, fn repo ->
      Ecto.Migrator.run(repo, migrations_path(), :up, all: true)
    end)
  end

  def insert_citizen!(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          id: "BAB-CIT-#{System.unique_integer([:positive])}",
          slug: "citizen-#{System.unique_integer([:positive])}",
          display_name: "Test Citizen",
          cwd: tmp_cwd!(),
          cli: "/bin/zsh",
          cli_args: ["-f"],
          env: %{},
          status: "running",
          metadata: %{},
          is_mayor: false
        },
        attrs
      )

    %Babs.Citizens.CitizenRecord{}
    |> Babs.Citizens.CitizenRecord.changeset(attrs)
    |> Babs.Citizens.Repo.insert!()
  end

  def tmp_root! do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-repo-case-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end

  def tmp_cwd! do
    cwd = Path.join(tmp_root!(), "workspace")
    File.mkdir_p!(cwd)
    cwd
  end

  def write_citizen_toml!(root, slug, attrs \\ %{}) do
    File.mkdir_p!(Path.join(root, "citizens"))

    attrs =
      Map.merge(
        %{
          id: "BAB-CIT-#{String.upcase(String.replace(slug, "-", "_"))}",
          slug: slug,
          display_name: String.capitalize(slug),
          description: nil,
          cli: "/bin/zsh",
          cli_args: ["-f"],
          cwd: slug,
          env: %{},
          role: nil
        },
        attrs
      )

    path = Path.join(root, "citizens/citizen-#{slug}.toml")

    File.write!(path, toml_for(attrs))
    path
  end

  defp migrations_path do
    Path.expand("../../priv/repo/migrations", __DIR__)
  end

  defp toml_for(attrs) do
    [
      ~s(id = "#{attrs.id}"),
      ~s(slug = "#{attrs.slug}"),
      ~s(display_name = "#{attrs.display_name}"),
      maybe_line(:description, attrs.description),
      ~s(cli = "#{attrs.cli}"),
      "cli_args = #{inspect(attrs.cli_args)}",
      ~s(cwd = "#{attrs.cwd}"),
      env_table(attrs.env),
      role_table(attrs.role)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp maybe_line(_key, nil), do: nil
  defp maybe_line(key, value), do: ~s(#{key} = "#{value}")

  defp env_table(env) when map_size(env) == 0, do: nil

  defp env_table(env) do
    rows =
      env
      |> Enum.sort()
      |> Enum.map(fn {key, value} -> ~s(#{key} = "#{value}") end)

    Enum.join(["[env]" | rows], "\n")
  end

  defp role_table(nil), do: nil
  defp role_table(role) when is_binary(role), do: ~s(role = "#{role}")

  defp role_table(%{"name" => name} = role) do
    rows = ["name = #{inspect(name)}"]

    rows =
      case Map.fetch(role, "skills") do
        {:ok, skills} -> rows ++ ["skills = #{inspect(skills)}"]
        :error -> rows
      end

    Enum.join(["[role]" | rows], "\n")
  end
end
