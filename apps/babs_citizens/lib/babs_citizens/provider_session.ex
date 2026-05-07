defmodule Babs.Citizens.ProviderSession do
  @moduledoc """
  Durable provider session metadata for direct Ticket execution.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Babs.Citizens.SqliteJson

  @primary_key {:id, :string, autogenerate: false}
  @providers ~w(claude codex copilot fake)
  @backends ~w(direct_cli hardline lazy_tmux)
  @statuses ~w(active non_resumable closed failed)
  @fields [
    :id,
    :citizen_slug,
    :ticket_id,
    :provider,
    :backend,
    :provider_session_id,
    :provider_cli_version,
    :capabilities,
    :workspace_ref,
    :cwd_fingerprint,
    :status,
    :last_turn_id,
    :os_pid,
    :os_pgid,
    :started_at,
    :last_error,
    :metadata
  ]
  @required [:id, :citizen_slug, :ticket_id, :provider, :backend, :workspace_ref, :status]

  schema "provider_sessions" do
    field(:citizen_slug, :string)
    field(:ticket_id, :string)
    field(:provider, :string)
    field(:backend, :string)
    field(:provider_session_id, :string)
    field(:provider_cli_version, :string)
    field(:capabilities, SqliteJson, default: %{})
    field(:workspace_ref, :string)
    field(:cwd_fingerprint, :string)
    field(:status, :string, default: "active")
    field(:last_turn_id, :string)
    field(:os_pid, :integer)
    field(:os_pgid, :integer)
    field(:started_at, :utc_datetime)
    field(:last_error, :string)
    field(:metadata, SqliteJson, default: %{})

    timestamps()
  end

  def generate_id, do: "ps_" <> Ecto.UUID.generate()

  def changeset(session, attrs) do
    session
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:provider, @providers)
    |> validate_inclusion(:backend, @backends)
    |> validate_inclusion(:status, @statuses)
    |> validate_format(:citizen_slug, ~r/^[a-z][a-z0-9-]{0,47}$/)
    |> validate_format(:ticket_id, ~r/^T-\d{4}-\d{2}-\d{2}-\d{3}$/)
    |> validate_no_absolute_path(:workspace_ref)
    |> validate_no_absolute_path(:last_error)
    |> validate_map(:capabilities)
    |> validate_map(:metadata)
    |> unique_constraint([:citizen_slug, :ticket_id, :provider, :backend],
      name: :provider_sessions_active_unique_index
    )
    |> check_constraint(:status, name: :provider_sessions_status_check)
    |> check_constraint(:backend, name: :provider_sessions_backend_check)
  end

  defp validate_map(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if is_map(value), do: [], else: [{field, "must be a map"}]
    end)
  end

  defp validate_no_absolute_path(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if is_binary(value) and absolute_path?(value) do
        [{field, "must not contain an absolute local path"}]
      else
        []
      end
    end)
  end

  defp absolute_path?(value) do
    Regex.match?(~r{/(Users|home|workspace|tmp|var|private|Volumes)/}, value)
  end
end
