defmodule Babs.Citizens.Tickets.TicketIdTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.TicketId

  test "parses valid ticket ids and rejects malformed ids" do
    assert {:ok, %{date: ~D[2026-05-06], sequence: 1}} = TicketId.parse("T-2026-05-06-001")
    assert :ok = TicketId.validate("T-2026-05-06-999")
    assert {:error, {:invalid_id, "T-2026-5-6-1"}} = TicketId.parse("T-2026-5-6-1")
  end

  test "allocates the next id by scanning markdown files for the requested date" do
    root = tmp_root()
    File.write!(Path.join(root, "T-2026-05-06-001.md"), "")
    File.write!(Path.join(root, "T-2026-05-06-003.md"), "")
    File.write!(Path.join(root, "T-2026-05-05-999.md"), "")

    assert {:ok, "T-2026-05-06-004"} = TicketId.allocate(root, date: ~D[2026-05-06])
  end

  test "claim_next atomically creates unique placeholders under concurrent creates" do
    root = tmp_root()

    results =
      1..20
      |> Task.async_stream(
        fn _ ->
          TicketId.claim_next(root, date: ~D[2026-05-06])
        end,
        max_concurrency: 20,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, _id, _path}, &1))

    ids = Enum.map(results, fn {:ok, id, _path} -> id end)

    assert Enum.sort(ids) ==
             Enum.map(1..20, &"T-2026-05-06-#{String.pad_leading(to_string(&1), 3, "0")}")

    assert Enum.uniq(ids) == ids
  end

  test "returns sequence_exhausted instead of creating unparseable ids above 999" do
    root = tmp_root()
    File.write!(Path.join(root, "T-2026-05-06-999.md"), "")

    assert {:error, {:sequence_exhausted, ~D[2026-05-06]}} =
             TicketId.allocate(root, date: ~D[2026-05-06])

    assert {:error, {:sequence_exhausted, ~D[2026-05-06]}} =
             TicketId.claim_next(root, date: ~D[2026-05-06])
  end

  defp tmp_root do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-ticket-id-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end
end
