defmodule Babs.Citizens.Hardline.PaneTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Hardline.Pane
  alias Babs.Citizens.CitizenConfig

  test "chunks PubSub payloads to the configured maximum size" do
    payload = :binary.copy("a", 9)

    assert Pane.chunk_bytes(payload, 4) == ["aaaa", "aaaa", "a"]
  end

  test "defaults chunking to the BAB-1106 4 KB ceiling" do
    payload = :binary.copy("x", 4097)
    chunks = Pane.chunk_bytes(payload)

    assert Enum.map(chunks, &byte_size/1) == [4096, 1]
  end

  test "rejects non-positive chunk sizes" do
    assert_raise ArgumentError, fn -> Pane.chunk_bytes("abc", 0) end
  end

  test "cwd call returns the configured citizen cwd" do
    cwd = Path.join(System.tmp_dir!(), "pane-cwd-#{System.unique_integer([:positive])}")

    state = %{
      config: %CitizenConfig{
        id: "BAB-CIT-CWD",
        slug: "cwd-pane",
        display_name: "Cwd Pane",
        cli: "/bin/zsh",
        cwd: cwd
      }
    }

    assert {:reply, {:ok, ^cwd}, ^state} = Pane.handle_call(:cwd, {self(), make_ref()}, state)
  end

  test "cwd/1 returns not_found when no pane is registered" do
    slug = "missing-cwd-pane-#{System.unique_integer([:positive])}"

    assert {:error, :not_found} = Pane.cwd(slug)
  end

  test "stdout handler tolerates pre-transcript hot-reload state" do
    slug = "legacy-pane-#{System.unique_integer([:positive])}"
    stream_id = 123

    Phoenix.PubSub.subscribe(Babs.Citizens.PubSub, "pane:#{slug}")

    state = %{
      attach: %{os_pid: 456},
      config: %CitizenConfig{
        id: "BAB-CIT-LEGACY",
        slug: slug,
        display_name: "Legacy Pane",
        cli: "/bin/zsh",
        cwd: System.tmp_dir!()
      },
      seq: 0,
      stream_id: stream_id
    }

    assert {:noreply, %{seq: 1}} = Pane.handle_info({:stdout, 456, "legacy"}, state)
    assert_receive {:pane_bytes, ^stream_id, 1, "legacy"}
  end

  test "ignores stdout from an unrelated os pid" do
    state = %{attach: %{os_pid: 456}, seq: 0}

    assert {:noreply, ^state} = Pane.handle_info({:stdout, 999, "ignored"}, state)
  end

  test "DOWN handler broadcasts detach message and normalizes clean exits" do
    slug = "down-pane-#{System.unique_integer([:positive])}"
    stream_id = 987
    Phoenix.PubSub.subscribe(Babs.Citizens.PubSub, "pane:#{slug}")

    state = %{
      attach: %{os_pid: 456},
      config: %CitizenConfig{
        id: "BAB-CIT-DOWN",
        slug: slug,
        display_name: "Down Pane",
        cli: "/bin/zsh",
        cwd: System.tmp_dir!()
      },
      seq: 4,
      stream_id: stream_id
    }

    assert {:stop, :normal, ^state} =
             Pane.handle_info({:DOWN, make_ref(), :process, self(), {:exit_status, 0}}, state)

    assert_receive {:pane_bytes, ^stream_id, 5, message}
    assert message =~ "[babs hardline detached:"
  end
end
