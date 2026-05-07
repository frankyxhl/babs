defmodule Babs.Citizens.Repo.Migrations.CreateProviderSessions do
  use Ecto.Migration

  def change do
    create table(:provider_sessions, primary_key: false) do
      add(:id, :string, primary_key: true)
      add(:citizen_slug, :string, null: false)
      add(:ticket_id, :string, null: false)
      add(:provider, :string, null: false)

      add(:backend, :string,
        null: false,
        check: %{
          name: "provider_sessions_backend_check",
          expr: "backend IN ('direct_cli','hardline','lazy_tmux')"
        }
      )

      add(:provider_session_id, :string)
      add(:provider_cli_version, :string)
      add(:capabilities, :text, null: false, default: "{}")
      add(:workspace_ref, :string, null: false)
      add(:cwd_fingerprint, :string)

      add(:status, :string,
        null: false,
        default: "active",
        check: %{
          name: "provider_sessions_status_check",
          expr: "status IN ('active','non_resumable','closed','failed')"
        }
      )

      add(:last_turn_id, :string)
      add(:os_pid, :integer)
      add(:os_pgid, :integer)
      add(:started_at, :utc_datetime)
      add(:last_error, :text)
      add(:metadata, :text, null: false, default: "{}")

      timestamps()
    end

    create(
      unique_index(:provider_sessions, [:citizen_slug, :ticket_id, :provider, :backend],
        name: :provider_sessions_active_unique_index,
        where: "status IN ('active','non_resumable')"
      )
    )

    create(
      index(:provider_sessions, [:citizen_slug, :status],
        name: :provider_sessions_citizen_status_index
      )
    )

    create(
      index(:provider_sessions, [:ticket_id, :citizen_slug],
        name: :provider_sessions_ticket_citizen_index
      )
    )
  end
end
