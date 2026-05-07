defmodule Babs.Citizens.Repo.Migrations.AddLaunchProfileToCitizens do
  use Ecto.Migration

  def change do
    alter table(:citizens) do
      add(:launch_profile, :string, null: false, default: "safe_interactive")
    end
  end
end
