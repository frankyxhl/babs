defmodule Babs.Citizens.Repo.Migrations.CreateCitizens do
  use Ecto.Migration

  def change do
    create table(:citizens, primary_key: false) do
      add(:id, :string, primary_key: true)
      add(:slug, :string, null: false)
      add(:display_name, :string, null: false)
      add(:description, :text)
      add(:cwd, :string, null: false)
      add(:cli, :string, null: false)
      add(:cli_args, :text, null: false, default: "[]")
      add(:env, :text, null: false, default: "{}")

      add(:status, :string,
        null: false,
        default: "running",
        check: %{name: "citizens_status_check", expr: "status IN ('running','stopped','failed')"}
      )

      add(:metadata, :text, null: false, default: "{}")
      add(:role, :text)
      add(:is_mayor, :boolean, null: false, default: false)
      add(:last_error, :text)

      timestamps()
    end

    create(unique_index(:citizens, [:slug], name: :citizens_slug_index))
  end
end
