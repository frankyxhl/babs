defmodule Babs.Citizens.Repo.Migrations.AddTicketBackendToCitizens do
  use Ecto.Migration

  def change do
    alter table(:citizens) do
      add(:ticket_backend, :string,
        null: false,
        default: "hardline",
        check: %{
          name: "citizens_ticket_backend_check",
          expr: "ticket_backend IN ('hardline','direct_cli','lazy_tmux')"
        }
      )
    end
  end
end
