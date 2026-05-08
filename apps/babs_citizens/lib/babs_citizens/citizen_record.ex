defmodule Babs.Citizens.CitizenRecord do
  @moduledoc """
  Durable SQLite representation of a Babs Citizen.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Babs.Citizens.{Roles, SqliteJson}

  @primary_key {:id, :string, autogenerate: false}
  @statuses ~w(running stopped failed)
  @launch_profiles ~w(safe_interactive trusted_autonomous)
  @ticket_backends ~w(hardline direct_cli lazy_tmux)
  @slug_regex ~r/^[a-z][a-z0-9-]{0,47}$/
  @fields [
    :id,
    :slug,
    :display_name,
    :description,
    :cwd,
    :cli,
    :cli_args,
    :launch_profile,
    :ticket_backend,
    :env,
    :status,
    :metadata,
    :role,
    :roles,
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
    field(:launch_profile, :string, default: "safe_interactive")
    field(:ticket_backend, :string, default: "hardline")
    field(:env, SqliteJson, default: %{})
    field(:status, :string, default: "running")
    field(:metadata, SqliteJson, default: %{})
    field(:role, SqliteJson)
    field(:roles, SqliteJson, default: [])
    field(:is_mayor, :boolean, default: false)
    field(:last_error, :string)

    timestamps()
  end

  def generate_id, do: "BAB-CIT-" <> Ecto.UUID.generate()

  def role_names(%__MODULE__{} = record) do
    case Roles.normalize(record.roles || []) do
      {:ok, roles} when roles != [] ->
        Enum.map(roles, & &1["name"])

      _other ->
        case Roles.normalize(record.role) do
          {:ok, roles} -> Enum.map(roles, & &1["name"])
          {:error, _reason} -> []
        end
    end
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_format(:slug, @slug_regex)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:launch_profile, @launch_profiles)
    |> validate_inclusion(:ticket_backend, @ticket_backends)
    |> validate_cli_args()
    |> validate_map(:env)
    |> validate_map(:metadata)
    |> normalize_role()
    |> normalize_roles()
    |> sync_role_fields()
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

  defp normalize_role(changeset) do
    case fetch_change(changeset, :role) do
      {:ok, nil} ->
        changeset

      {:ok, value} ->
        case Roles.normalize(value) do
          {:ok, roles} -> put_change(changeset, :role, Roles.legacy_first_role(roles))
          {:error, _reason} -> add_error(changeset, :role, "must be nil, a string, or a role map")
        end

      :error ->
        changeset
    end
  end

  defp normalize_roles(changeset) do
    case fetch_change(changeset, :roles) do
      {:ok, value} ->
        case Roles.normalize(value || []) do
          {:ok, roles} ->
            put_change(changeset, :roles, roles)

          {:error, _reason} ->
            add_error(changeset, :roles, "must be a list of role labels or maps")
        end

      :error ->
        changeset
    end
  end

  defp sync_role_fields(changeset) do
    cond do
      match?({:ok, _roles}, fetch_change(changeset, :roles)) ->
        roles = get_change(changeset, :roles) || []
        put_change(changeset, :role, Roles.legacy_first_role(roles))

      match?({:ok, _role}, fetch_change(changeset, :role)) ->
        case Roles.normalize(get_change(changeset, :role)) do
          {:ok, roles} -> put_change(changeset, :roles, roles)
          {:error, _reason} -> changeset
        end

      true ->
        changeset
    end
  end
end
