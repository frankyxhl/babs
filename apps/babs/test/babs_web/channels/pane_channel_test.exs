defmodule BabsWeb.PaneChannelTest do
  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  @endpoint BabsWeb.Endpoint
  alias BabsWeb.PaneChannel
  alias Babs.Citizens.Hardline.Transcript

  defmodule FakePane do
    use GenServer

    def start_link(slug, cwd, opts \\ []) do
      GenServer.start_link(
        __MODULE__,
        {cwd, Keyword.get(opts, :notify), Keyword.get(opts, :target)},
        name: {:via, Registry, {Babs.Citizens.PaneRegistry, slug}}
      )
    end

    @impl true
    def init({cwd, notify, target}), do: {:ok, %{cwd: cwd, notify: notify, target: target}}

    @impl true
    def handle_call(:cwd, _from, state), do: {:reply, {:ok, state.cwd}, state}

    def handle_call(:tmux_target, _from, %{target: target} = state) when is_binary(target) do
      {:reply, {:ok, target}, state}
    end

    def handle_call(:tmux_target, _from, state), do: {:reply, {:error, :not_found}, state}

    @impl true
    def handle_call(:flush_transcript, _from, state) do
      if state.notify, do: send(state.notify, :flushed_transcript)
      {:reply, :ok, state}
    end
  end

  setup do
    tmp =
      Path.join(System.tmp_dir!(), "babs-pane-channel-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf!(tmp) end)
    %{tmp: tmp}
  end

  test "rejects joins when no pane is registered" do
    slug = "missing-#{System.unique_integer([:positive])}"

    assert {:error, %{reason: "not_found"}} =
             PaneChannel.join("pane:#{slug}", %{}, %Phoenix.Socket{})
  end

  test "pushes pane bytes broadcast by Hardline.Pane on the citizens PubSub", %{tmp: tmp} do
    slug = "existing-#{System.unique_integer([:positive])}"
    {:ok, _pid} = FakePane.start_link(slug, tmp)

    {:ok, _reply, _socket} =
      BabsWeb.UserSocket
      |> socket(nil, %{})
      |> subscribe_and_join(PaneChannel, "pane:#{slug}")

    Phoenix.PubSub.broadcast(
      Babs.Citizens.PubSub,
      "pane:#{slug}",
      {:pane_bytes, 123, 456, "hello"}
    )

    assert_push "output", %{
      "stream_id" => 123,
      "seq" => 456,
      "base64" => encoded
    }

    assert Base.decode64!(encoded) == "hello"
  end

  test "flushes transcript and falls back to transcript replay when tmux capture fails", %{
    tmp: tmp
  } do
    slug = "transcript-#{System.unique_integer([:positive])}"

    {:ok, io} = Transcript.open(tmp)

    :ok =
      Transcript.append(io, %{
        slug: "other-#{slug}",
        direction: :output,
        stream_id: 7,
        seq: 7,
        payload: "from other citizen\n"
      })

    :ok =
      Transcript.append(io, %{
        slug: slug,
        direction: :output,
        stream_id: 7,
        seq: 8,
        payload: "from transcript\n"
      })

    :ok = Transcript.close(io)
    {:ok, _pid} = FakePane.start_link(slug, tmp, notify: self())

    {:ok, _reply, _socket} =
      BabsWeb.UserSocket
      |> socket(nil, %{})
      |> subscribe_and_join(PaneChannel, "pane:#{slug}")

    assert_receive :flushed_transcript

    assert_push "output", %{
      "stream_id" => 0,
      "seq" => 0,
      "base64" => encoded
    }

    assert Base.decode64!(encoded) == "from transcript\n"
  end

  test "captures the registered pane target for the initial snapshot", %{tmp: tmp} do
    slug = "target-snapshot-#{System.unique_integer([:positive])}"
    session = "babs-channel-target-#{System.unique_integer([:positive])}"
    marker = "BABS_CHANNEL_TARGET_SNAPSHOT"

    on_exit(fn -> System.cmd("tmux", ["kill-session", "-t", session], stderr_to_stdout: true) end)

    assert {_output, 0} =
             System.cmd("tmux", ["new-session", "-d", "-s", session, "/bin/zsh", "-f"],
               stderr_to_stdout: true
             )

    assert {_output, 0} =
             System.cmd("tmux", ["send-keys", "-t", session, "printf '#{marker}\\n'", "Enter"],
               stderr_to_stdout: true
             )

    assert wait_for_tmux_capture?(session, marker)
    {:ok, _pid} = FakePane.start_link(slug, tmp, target: session)

    {:ok, _reply, _socket} =
      BabsWeb.UserSocket
      |> socket(nil, %{})
      |> subscribe_and_join(PaneChannel, "pane:#{slug}")

    assert_push "output", %{
      "stream_id" => 0,
      "seq" => 0,
      "base64" => encoded
    }

    assert Base.decode64!(encoded) =~ marker
  end

  test "allows terminal-compatible xterm keyboard and paste data" do
    assert PaneChannel.allowed_input?("printf 'ok'\\n")
    assert PaneChannel.allowed_input?("\r")
    assert PaneChannel.allowed_input?("\t")
    assert PaneChannel.allowed_input?(<<2>>)
    assert PaneChannel.allowed_input?(<<3>>)
    assert PaneChannel.allowed_input?(<<4>>)
    assert PaneChannel.allowed_input?(<<26>>)
    assert PaneChannel.allowed_input?("\e[A")
    assert PaneChannel.allowed_input?("\e[B")
    assert PaneChannel.allowed_input?("\e[C")
    assert PaneChannel.allowed_input?("\e[D")
    assert PaneChannel.allowed_input?("\e[1;5D")
    assert PaneChannel.allowed_input?("\eOP")
    assert PaneChannel.allowed_input?("\eb")
    assert PaneChannel.allowed_input?("\e[200~paste\e[201~")
    assert PaneChannel.allowed_input?("こんにちは")
    assert PaneChannel.allowed_input?(<<127>>)

    refute PaneChannel.allowed_input?("")
    refute PaneChannel.allowed_input?(<<0>>)
    refute PaneChannel.allowed_input?(<<0x9D>>)
    refute PaneChannel.allowed_input?(<<0xC2, 0x9D>>)
    refute PaneChannel.allowed_input?("\e]52;c;clipboard\a")
    refute PaneChannel.allowed_input?("\ePpayload")
    refute PaneChannel.allowed_input?("\e[?1;2c")
    refute PaneChannel.allowed_input?("\e[>0;276;0c")
    refute PaneChannel.allowed_input?("\e[24;80R")
    refute PaneChannel.allowed_input?("\e[24;80R\n")
    refute PaneChannel.allowed_input?("pasted\e[?1;2c text")
    refute PaneChannel.allowed_input?("\e[0n")
    refute PaneChannel.allowed_input?(:binary.copy("x", 4097))
  end

  test "input and resize events tolerate invalid or unavailable panes" do
    socket = %Phoenix.Socket{assigns: %{slug: "missing-pane"}}

    assert {:noreply, ^socket} = PaneChannel.handle_in("input", %{"data" => "ok"}, socket)
    assert {:noreply, ^socket} = PaneChannel.handle_in("input", %{"data" => <<0>>}, socket)

    assert {:noreply, ^socket} =
             PaneChannel.handle_in("resize", %{"cols" => 120, "rows" => 30}, socket)

    assert {:noreply, ^socket} =
             PaneChannel.handle_in("resize", %{"cols" => 0, "rows" => 30}, socket)

    assert {:noreply, ^socket} =
             PaneChannel.handle_in("resize", %{"cols" => "120", "rows" => 30}, socket)
  end

  test "input refreshes the pane topic subscription marker after citizens PubSub restarts" do
    stale_pubsub = self()

    socket = %Phoenix.Socket{
      topic: "pane:missing-pane",
      assigns: %{slug: "missing-pane", pubsub_pid: stale_pubsub}
    }

    assert {:noreply, updated} = PaneChannel.handle_in("input", %{"data" => "ok"}, socket)
    assert updated.assigns.pubsub_pid == Process.whereis(Babs.Citizens.PubSub)
  end

  test "snapshot send is best effort when tmux capture fails" do
    socket = %Phoenix.Socket{assigns: %{slug: "missing-pane"}}

    assert {:noreply, ^socket} = PaneChannel.handle_info(:send_snapshot, socket)
  end

  test "empty transcript snapshot is a no-op when tmux capture also fails", %{tmp: tmp} do
    File.mkdir_p!(tmp)
    socket = %Phoenix.Socket{assigns: %{slug: "missing-pane", cwd: tmp}}

    assert {:noreply, ^socket} = PaneChannel.handle_info(:send_snapshot, socket)
  end

  defp wait_for_tmux_capture?(session, marker) do
    deadline = System.monotonic_time(:millisecond) + 2_000
    do_wait_for_tmux_capture?(session, marker, deadline)
  end

  defp do_wait_for_tmux_capture?(session, marker, deadline) do
    case System.cmd("tmux", ["capture-pane", "-p", "-t", session, "-S", "-80"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        if String.contains?(output, marker) do
          true
        else
          maybe_wait_for_tmux_capture(session, marker, deadline)
        end

      {_output, _status} ->
        maybe_wait_for_tmux_capture(session, marker, deadline)
    end
  end

  defp maybe_wait_for_tmux_capture(session, marker, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      false
    else
      Process.sleep(50)
      do_wait_for_tmux_capture?(session, marker, deadline)
    end
  end
end
