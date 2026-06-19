defmodule Babs.Citizens.Transcript.MessageTest do
  use Babs.Citizens.RepoCase, async: false

  alias Babs.Citizens.Repo
  alias Babs.Citizens.Transcript.Message

  @valid_attrs %{
    id: "msg-001",
    owner_id: "alfred",
    role: "user",
    content: "Hello",
    occurred_at: ~U[2026-06-19 10:00:00.000000Z],
    raw: %{"source" => "test"}
  }

  describe "changeset/2" do
    test "valid attrs produce a valid changeset" do
      changeset = Message.changeset(%Message{}, @valid_attrs)
      assert changeset.valid?
    end

    test "validate_required rejects missing id" do
      changeset = Message.changeset(%Message{}, Map.delete(@valid_attrs, :id))
      refute changeset.valid?
      assert {:id, {"can't be blank", _}} = List.keyfind(changeset.errors, :id, 0)
    end

    test "validate_required rejects missing owner_id" do
      changeset = Message.changeset(%Message{}, Map.delete(@valid_attrs, :owner_id))
      refute changeset.valid?
      assert {:owner_id, {"can't be blank", _}} = List.keyfind(changeset.errors, :owner_id, 0)
    end

    test "validate_required rejects missing role" do
      changeset = Message.changeset(%Message{}, Map.delete(@valid_attrs, :role))
      refute changeset.valid?
      assert {:role, {"can't be blank", _}} = List.keyfind(changeset.errors, :role, 0)
    end

    test "validate_required rejects missing occurred_at" do
      changeset = Message.changeset(%Message{}, Map.delete(@valid_attrs, :occurred_at))
      refute changeset.valid?

      assert {:occurred_at, {"can't be blank", _}} =
               List.keyfind(changeset.errors, :occurred_at, 0)
    end

    test "validate_required rejects explicit nil raw (DB column is null: false)" do
      changeset = Message.changeset(%Message{}, Map.put(@valid_attrs, :raw, nil))
      refute changeset.valid?
      assert {:raw, {"can't be blank", _}} = List.keyfind(changeset.errors, :raw, 0)
    end

    test "validate_inclusion rejects unknown role" do
      changeset = Message.changeset(%Message{}, Map.put(@valid_attrs, :role, "banana"))
      refute changeset.valid?
      assert {:role, {"is invalid", _}} = List.keyfind(changeset.errors, :role, 0)
    end

    test "validate_inclusion accepts 'user' role" do
      changeset = Message.changeset(%Message{}, Map.put(@valid_attrs, :role, "user"))
      assert changeset.valid?
    end

    test "validate_inclusion accepts 'assistant' role" do
      changeset = Message.changeset(%Message{}, Map.put(@valid_attrs, :role, "assistant"))
      assert changeset.valid?
    end

    test "validate_inclusion accepts 'tool' role" do
      changeset = Message.changeset(%Message{}, Map.put(@valid_attrs, :role, "tool"))
      assert changeset.valid?
    end

    test "validate_inclusion accepts 'system' role" do
      changeset = Message.changeset(%Message{}, Map.put(@valid_attrs, :role, "system"))
      assert changeset.valid?
    end
  end

  describe "Repo insert and read-back" do
    test "content nullable: inserting with content nil succeeds and reads back nil" do
      attrs = Map.put(@valid_attrs, :content, nil)

      {:ok, inserted} =
        %Message{}
        |> Message.changeset(attrs)
        |> Repo.insert()

      fetched = Repo.get!(Message, inserted.id)
      assert fetched.content == nil
    end

    test "raw default round-trip: omitting raw succeeds and reads back empty map" do
      attrs = Map.delete(@valid_attrs, :raw)

      {:ok, inserted} =
        %Message{}
        |> Message.changeset(attrs)
        |> Repo.insert()

      fetched = Repo.get!(Message, inserted.id)
      assert fetched.raw == %{}
    end

    test "DB-level role CHECK constraint rejects bad role bypassing changeset" do
      now = DateTime.utc_now()

      assert_raise Exqlite.Error, ~r/messages_role_check/, fn ->
        Repo.insert_all("messages", [
          %{
            id: "probe-check-constraint",
            owner_id: "probe",
            role: "banana",
            content: nil,
            occurred_at: now,
            raw: "{}",
            inserted_at: now,
            updated_at: now
          }
        ])
      end
    end

    test "deterministic ordering on occurred_at ties returns rows in id order" do
      tied_at = ~U[2026-06-19 10:00:00.000000Z]

      attrs_a = %{@valid_attrs | id: "msg-tie-a", occurred_at: tied_at}
      attrs_b = %{@valid_attrs | id: "msg-tie-b", occurred_at: tied_at}
      attrs_c = %{@valid_attrs | id: "msg-tie-c", occurred_at: ~U[2026-06-19 09:00:00.000000Z]}

      for attrs <- [attrs_b, attrs_c, attrs_a] do
        {:ok, _} = %Message{} |> Message.changeset(attrs) |> Repo.insert()
      end

      import Ecto.Query

      results =
        Message
        |> where([m], m.owner_id == "alfred")
        |> order_by([m], asc: m.occurred_at, asc: m.id)
        |> Repo.all()

      assert Enum.map(results, & &1.id) == ["msg-tie-c", "msg-tie-a", "msg-tie-b"]
    end

    test "inserting a valid message round-trips all fields" do
      {:ok, inserted} =
        %Message{}
        |> Message.changeset(@valid_attrs)
        |> Repo.insert()

      fetched = Repo.get!(Message, inserted.id)

      assert fetched.id == "msg-001"
      assert fetched.owner_id == "alfred"
      assert fetched.role == "user"
      assert fetched.content == "Hello"
      assert fetched.occurred_at == ~U[2026-06-19 10:00:00.000000Z]
      assert fetched.raw == %{"source" => "test"}
    end

    test "inserting two rows with the same id is rejected by the PK constraint" do
      {:ok, _} =
        %Message{}
        |> Message.changeset(@valid_attrs)
        |> Repo.insert()

      assert {:error, changeset} =
               %Message{}
               |> Message.changeset(@valid_attrs)
               |> Repo.insert()

      refute changeset.valid?
    end

    test "on_conflict: :nothing is idempotent on duplicate id" do
      {:ok, first} =
        %Message{}
        |> Message.changeset(@valid_attrs)
        |> Repo.insert()

      {:ok, second} =
        %Message{}
        |> Message.changeset(Map.put(@valid_attrs, :content, "Different content"))
        |> Repo.insert(on_conflict: :nothing, conflict_target: :id)

      assert first.id == second.id
      fetched = Repo.get!(Message, first.id)
      assert fetched.content == "Hello"
    end

    test "per-owner time-ordered query returns rows ordered by occurred_at" do
      attrs1 = %{@valid_attrs | id: "msg-t1", occurred_at: ~U[2026-06-19 09:00:00.000000Z]}
      attrs2 = %{@valid_attrs | id: "msg-t2", occurred_at: ~U[2026-06-19 11:00:00.000000Z]}
      attrs3 = %{@valid_attrs | id: "msg-t3", occurred_at: ~U[2026-06-19 10:00:00.000000Z]}

      for attrs <- [attrs1, attrs2, attrs3] do
        {:ok, _} = %Message{} |> Message.changeset(attrs) |> Repo.insert()
      end

      import Ecto.Query

      results =
        Message
        |> where([m], m.owner_id == "alfred")
        |> order_by([m], asc: m.occurred_at)
        |> Repo.all()

      assert Enum.map(results, & &1.id) == ["msg-t1", "msg-t3", "msg-t2"]
    end
  end
end
