defmodule Babs.Citizens.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
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
