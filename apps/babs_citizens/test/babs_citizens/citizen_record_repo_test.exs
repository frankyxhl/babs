defmodule Babs.Citizens.CitizenRecordRepoTest do
  use Babs.Citizens.RepoCase, async: false

  import Ecto.Changeset

  test "inserts and round-trips JSON-backed citizen fields" do
    record =
      insert_citizen!(%{
        slug: "round-trip",
        cli_args: ["--continue"],
        env: %{"TOKEN" => "secret"},
        metadata: %{"seed" => true},
        role: %{"name" => "developer", "skills" => ["elixir"]}
      })

    reloaded = Repo.get!(CitizenRecord, record.id)

    assert reloaded.cli_args == ["--continue"]
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
        env: %{},
        status: "paused",
        metadata: %{}
      })
      |> check_constraint(:status, name: :citizens_status_check)

    assert {:error, changeset} = Repo.insert(changeset)
    assert {"is invalid", _metadata} = Keyword.fetch!(changeset.errors, :status)
  end
end
