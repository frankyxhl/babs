defmodule Babs.Citizens.CitizenRecord do
  @moduledoc """
  Durable SQLite representation of a Babs Citizen.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Babs.Citizens.SqliteJson

  @primary_key {:id, :string, autogenerate: false}
  @statuses ~w(running stopped failed)
  @slug_regex ~r/^[a-z][a-z0-9-]{0,47}$/
  @fields [
    :id,
    :slug,
    :display_name,
    :description,
    :cwd,
    :cli,
    :cli_args,
    :env,
    :status,
    :metadata,
    :role,
    :is_mayor,
    :last_error
  ]
  @required [:id, :slug, :display_name, :cwd, :cli, :status]

  schema "citizens" do
    field(:slug, :string)
    field(:display_name, :string)
    field(:description, :string)
    field(:cwd, :string)
    field(:cli, :string)
    field(:cli_args, SqliteJson, default: [])
    field(:env, SqliteJson, default: %{})
    field(:status, :string, default: "running")
    field(:metadata, SqliteJson, default: %{})
    field(:role, SqliteJson)
    field(:is_mayor, :boolean, default: false)
    field(:last_error, :string)

    timestamps()
  end

  def generate_id, do: "BAB-CIT-" <> Ecto.UUID.generate()

  def changeset(record, attrs) do
    record
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_format(:slug, @slug_regex)
    |> validate_inclusion(:status, @statuses)
    |> validate_cli_args()
    |> validate_map(:env)
    |> validate_map(:metadata)
    |> validate_role()
    |> unique_constraint(:slug)
    |> check_constraint(:status, name: :citizens_status_check)
  end

  defp validate_cli_args(changeset) do
    validate_change(changeset, :cli_args, fn :cli_args, value ->
      if is_list(value) and Enum.all?(value, &is_binary/1) do
        []
      else
        [cli_args: "must be a list of strings"]
      end
    end)
  end

  defp validate_map(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if is_map(value), do: [], else: [{field, "must be a map"}]
    end)
  end

  defp validate_role(changeset) do
    validate_change(changeset, :role, fn :role, value ->
      if valid_role?(value), do: [], else: [role: "must be nil, a string, or a role map"]
    end)
  end

  defp valid_role?(nil), do: true
  defp valid_role?(value) when is_binary(value), do: true

  defp valid_role?(%{"name" => name} = role) when is_binary(name) do
    case Map.fetch(role, "skills") do
      :error -> true
      {:ok, skills} when is_list(skills) -> Enum.all?(skills, &is_binary/1)
      {:ok, _skills} -> false
    end
  end

  defp valid_role?(_value), do: false
end
