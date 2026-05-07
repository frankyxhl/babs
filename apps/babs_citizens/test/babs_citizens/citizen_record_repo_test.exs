defmodule Babs.Citizens.CitizenRecordRepoTest do
  use Babs.Citizens.RepoCase, async: false

  import Ecto.Changeset

  test "inserts and round-trips JSON-backed citizen fields" do
    record =
      insert_citizen!(%{
        slug: "round-trip",
        cli_args: ["--continue"],
        ticket_backend: "direct_cli",
        env: %{"TOKEN" => "secret"},
        metadata: %{"seed" => true},
        role: %{"name" => "developer", "skills" => ["elixir"]}
      })

    reloaded = Repo.get!(CitizenRecord, record.id)

    assert reloaded.cli_args == ["--continue"]
    assert reloaded.ticket_backend == "direct_cli"
    assert reloaded.env == %{"TOKEN" => "secret"}
    assert reloaded.metadata == %{"seed" => true}
    assert reloaded.role == %{"name" => "developer", "skills" => ["elixir"]}
  end

  test "database check constraint rejects invalid status even if changeset validation is bypassed" do
    changeset =
      change(%CitizenRecord{}, %{
        id: "BAB-CIT-BAD-STATUS",
        slug: "bad-status",
        display_name: "Bad Status",
        cwd: tmp_cwd!(),
        cli: "/bin/zsh",
        cli_args: [],
        ticket_backend: "hardline",
        env: %{},
        status: "paused",
        metadata: %{}
      })
      |> check_constraint(:status, name: :citizens_status_check)

    assert {:error, changeset} = Repo.insert(changeset)
    assert {"is invalid", _metadata} = Keyword.fetch!(changeset.errors, :status)
  end

  test "database check constraint rejects invalid ticket backend if validation is bypassed" do
    changeset =
      change(%CitizenRecord{}, %{
        id: "BAB-CIT-BAD-TICKET-BACKEND",
        slug: "bad-ticket-backend",
        display_name: "Bad Ticket Backend",
        cwd: tmp_cwd!(),
        cli: "/bin/zsh",
        cli_args: [],
        ticket_backend: "batch",
        env: %{},
        status: "running",
        metadata: %{}
      })
      |> check_constraint(:ticket_backend, name: :citizens_ticket_backend_check)

    assert {:error, changeset} = Repo.insert(changeset)
    assert {"is invalid", _metadata} = Keyword.fetch!(changeset.errors, :ticket_backend)
  end
end
