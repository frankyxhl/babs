defmodule Babs.Citizens.Hardline.PaneTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Hardline.Pane
  alias Babs.Citizens.Hardline.Transcript
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

  test "tmux target call returns the attached tmux target" do
    state = %{
      session: "%42"
    }

    assert {:reply, {:ok, "%42"}, ^state} =
             Pane.handle_call(:tmux_target, {self(), make_ref()}, state)
  end

  test "tmux_target/1 returns not_found when no pane is registered" do
    slug = "missing-target-pane-#{System.unique_integer([:positive])}"

    assert {:error, :not_found} = Pane.tmux_target(slug)
  end

  test "flush_transcript/1 returns not_found when no pane is registered" do
    slug = "missing-flush-pane-#{System.unique_integer([:positive])}"

    assert {:error, :not_found} = Pane.flush_transcript(slug)
  end

  test "flush transcript call syncs the open transcript device" do
    cwd = Path.join(System.tmp_dir!(), "pane-flush-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(cwd) end)
    {:ok, io} = Transcript.open(cwd)

    state = %{
      config: %CitizenConfig{
        id: "BAB-CIT-FLUSH",
        slug: "flush-pane",
        display_name: "Flush Pane",
        cli: "/bin/zsh",
        cwd: cwd
      },
      transcript_io: io
    }

    assert {:reply, :ok, ^state} =
             Pane.handle_call(:flush_transcript, {self(), make_ref()}, state)

    assert :ok = Transcript.close(io)
  end

  test "system injection auto-submits prompts for AI CLIs and records the submitted input" do
    parent = self()

    state = %{
      attach: %{os_pid: 456},
      config: %CitizenConfig{
        id: "BAB-CIT-AI",
        slug: "ai-pane",
        display_name: "AI Pane",
        cli: "claude",
        cli_args: [],
        cwd: System.tmp_dir!()
      },
      input_seq: 0,
      stream_id: 1,
      transcript_io: nil,
      system_delivery: fn _config, %{os_pid: 456}, data, _opts ->
        send(parent, {:injected, data <> "\r"})
        {:ok, data <> "\r"}
      end
    }

    assert {:noreply, next_state} = Pane.handle_cast({:inject, "hello", :system}, state)

    assert_receive {:injected, "hello\r"}
    assert next_state.input_seq == 1
  end

  test "system injection call returns after the pane accepts the prompt" do
    parent = self()

    state = %{
      attach: %{os_pid: 456},
      config: %CitizenConfig{
        id: "BAB-CIT-SYNC",
        slug: "sync-pane",
        display_name: "Sync Pane",
        cli: "codex",
        cli_args: [],
        cwd: System.tmp_dir!()
      },
      input_seq: 0,
      stream_id: 1,
      transcript_io: nil,
      system_delivery: fn _config, %{os_pid: 456}, data, _opts ->
        send(parent, {:injected, data})
        {:ok, data <> "\r"}
      end
    }

    assert {:reply, :ok, next_state} =
             Pane.handle_call({:inject, "sync", :system}, {self(), make_ref()}, state)

    assert_receive {:injected, "sync"}
    assert next_state.input_seq == 1
  end

  test "manual injection and shell system prompts do not auto-submit" do
    parent = self()

    state = %{
      attach: %{os_pid: 456},
      config: %CitizenConfig{
        id: "BAB-CIT-SHELL",
        slug: "shell-pane",
        display_name: "Shell Pane",
        cli: "/bin/zsh",
        cli_args: ["-f"],
        cwd: System.tmp_dir!()
      },
      input_seq: 0,
      stream_id: 1,
      transcript_io: nil,
      runner: fn %{os_pid: 456}, data -> send(parent, {:injected, data}) end
    }

    assert {:noreply, next_state} = Pane.handle_cast({:inject, "manual", :manual}, state)
    assert_receive {:injected, "manual"}
    assert next_state.input_seq == 1

    assert {:noreply, final_state} = Pane.handle_cast({:inject, "system", :system}, next_state)
    assert_receive {:injected, "system"}
    assert final_state.input_seq == 2
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
