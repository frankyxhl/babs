defmodule Babs.Citizens.Repo.Migrations.DropMessages do
  use Ecto.Migration

  # The transcript `messages` table (added in #158 as a placeholder for a future
  # SQLite transcript store) was never consumed by any code path: the forum reads
  # ticket JSONL history, and citizen state lives in CitizenRecord/ProviderSession.
  # Drop it so conversation data has a single source of truth (markdown + JSONL).

  def up do
    drop_if_exists(
      index(:messages, [:owner_id, :occurred_at, :id], name: :messages_owner_occurred_at_id_index)
    )

    drop_if_exists(table(:messages))
  end

  def down do
    create table(:messages, primary_key: false) do
      add(:id, :string, primary_key: true)
      add(:owner_id, :string, null: false)

      add(:role, :string,
        null: false,
        check: %{
          name: "messages_role_check",
          expr: "role IN ('user','assistant','tool','system')"
        }
      )

      add(:content, :text)
      add(:occurred_at, :utc_datetime_usec, null: false)
      add(:raw, :text, null: false, default: "{}")

      timestamps()
    end

    create(
      index(:messages, [:owner_id, :occurred_at, :id], name: :messages_owner_occurred_at_id_index)
    )
  end
end
