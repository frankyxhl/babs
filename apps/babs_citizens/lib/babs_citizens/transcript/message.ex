defmodule Babs.Citizens.Transcript.Message do
  @moduledoc """
  Durable store for transcript messages ingested from AI CLI sessions.

  `occurred_at` is the message's own source timestamp from the upstream transcript.
  It is distinct from the row-level `inserted_at`/`updated_at` timestamps.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Babs.Citizens.SqliteJson

  @primary_key {:id, :string, autogenerate: false}

  @roles ~w(user assistant tool system)

  schema "messages" do
    field(:owner_id, :string)
    field(:role, :string)
    field(:content, :string)
    field(:occurred_at, :utc_datetime_usec)
    field(:raw, SqliteJson, default: %{})

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:id, :owner_id, :role, :content, :occurred_at, :raw])
    |> validate_required([:id, :owner_id, :role, :occurred_at, :raw])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:id)
  end
end
