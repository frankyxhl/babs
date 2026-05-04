defmodule Hardline.Validation do
  @moduledoc """
  Runnable Phase 0 validation harness.

  The full profile intentionally runs for many hours. The smoke profile keeps
  the same scenario shape but compresses durations for local harness checks.
  """

  alias Hardline.{Chaos, Observer, Runner}
  alias Hardline.Scenarios.DetachReattach

  @profiles %{
    "smoke" => %{
      fleet_count: 1,
      soak_seconds: 5,
      chaos_seconds: 5,
      chaos_interval_seconds: 2,
      resize_seconds: 3,
      slow_reader_seconds: 3,
      detach_count: 1,
      detach_seconds: 5,
      web_seconds: 30
    },
    "quick10" => %{
      fleet_count: 2,
      soak_seconds: 3 * 60,
      chaos_seconds: 3 * 60,
      chaos_interval_seconds: 30,
      resize_seconds: 60,
      slow_reader_seconds: 60,
      detach_count: 1,
      detach_seconds: 60,
      web_seconds: 10 * 60
    },
    "full" => %{
      fleet_count: 5,
      soak_seconds: 24 * 60 * 60,
      chaos_seconds: 12 * 60 * 60,
      chaos_interval_seconds: 30 * 60,
      resize_seconds: 60 * 60,
      slow_reader_seconds: 60 * 60,
      detach_count: 3,
      detach_seconds: 30 * 60,
      web_seconds: 30 * 60
    }
  }

  def profiles, do: Map.keys(@profiles)

  def profile!(name) when is_binary(name) do
    Map.fetch!(@profiles, name)
  end

  def run(opts \\ []) do
    profile_name = Keyword.get(opts, :profile, "smoke")
    profile = Keyword.get_lazy(opts, :profile_config, fn -> profile!(profile_name) end)
    prefix = Keyword.get(opts, :prefix, run_prefix(profile_name))
    command = Keyword.get(opts, :command, validation_workload())
    web_confirmed? = Keyword.get(opts, :web_confirmed?, false)

    validate_web_confirmation!(profile_name, web_confirmed?)

    run_dir = Keyword.get_lazy(opts, :run_dir, fn -> create_run_dir!() end)
    File.mkdir_p!(run_dir)

    log_path = Path.join(run_dir, "events.log")

    Observer.append_event(log_path, :validation_start, %{
      profile: profile_name,
      prefix: prefix,
      command: command
    })

    results =
      []
      |> step(:provision_fleet, fn _ctx -> provision_fleet(profile, prefix, command, log_path) end)
      |> step(:soak, fn ctx -> observe_for(ctx, :soak, profile.soak_seconds, log_path) end)
      |> step(:chaos, fn ctx -> chaos(ctx, profile, log_path) end)
      |> step(:resize_storm, fn ctx -> resize_storm(ctx, profile.resize_seconds, log_path) end)
      |> step(:slow_reader, fn ctx -> slow_reader(ctx, profile.slow_reader_seconds, log_path) end)
      |> step(:detach_reattach, fn ctx -> detach_reattach(ctx, profile, prefix, log_path) end)
      |> step(:web_byte_path, fn ctx -> web_byte_path(ctx, web_confirmed?, log_path) end)
      |> cleanup(log_path)

    status = overall_status(results)
    summary = write_summary!(run_dir, profile_name, profile, results, web_confirmed?)

    Observer.append_event(log_path, :validation_finish, %{
      status: status,
      summary: summary
    })

    {:ok,
     %{run_dir: run_dir, log_path: log_path, summary: summary, results: results, status: status}}
  end

  def create_run_dir!(root \\ Path.expand("results", File.cwd!())) do
    timestamp =
      DateTime.utc_now()
      |> Calendar.strftime("%Y-%m-%d-%H%M%S")

    Path.join(root, "run-#{timestamp}")
    |> tap(&File.mkdir_p!/1)
  end

  defp step(results, name, fun) do
    ctx = context(results)

    if previous_failure?(results) do
      [
        %{name: name, status: :skip, details: "skipped after previous failure", ctx: ctx}
        | results
      ]
    else
      try do
        case fun.(ctx) do
          {:ok, next_ctx, details} ->
            [%{name: name, status: :pass, details: details, ctx: next_ctx} | results]

          {:warn, next_ctx, details} ->
            [%{name: name, status: :warn, details: details, ctx: next_ctx} | results]

          {:error, next_ctx, reason} ->
            [%{name: name, status: :fail, details: inspect(reason), ctx: next_ctx} | results]
        end
      rescue
        exception ->
          [
            %{name: name, status: :fail, details: Exception.message(exception), ctx: ctx}
            | results
          ]
      end
    end
  end

  defp previous_failure?([%{status: :fail} | _results]), do: true
  defp previous_failure?(_results), do: false

  defp context([]), do: %{}
  defp context([%{ctx: ctx} | _results]), do: ctx

  defp provision_fleet(profile, prefix, command, log_path) do
    case Runner.start_fleet(profile.fleet_count, prefix: prefix, command: command) do
      {:ok, fleet} ->
        provision_attachments(fleet, log_path)

      {:error, reason} ->
        {:error, %{fleet: [], attachments: []}, reason}
    end
  end

  defp provision_attachments(fleet, log_path) do
    case Runner.attach_fleet(fleet) do
      {:ok, attachments} ->
        case prove_bidirectional_bytes(attachments, log_path) do
          :ok ->
            {:ok, %{fleet: fleet, attachments: attachments},
             "started #{length(fleet)} tmux session(s)"}

          {:error, reason} ->
            {:error, %{fleet: fleet, attachments: attachments}, reason}
        end

      {:error, reason} ->
        {:error, %{fleet: fleet, attachments: []}, reason}
    end
  end

  defp prove_bidirectional_bytes(attachments, log_path) do
    Enum.reduce_while(attachments, :ok, fn attach, :ok ->
      suffix = "#{attach.session}_#{System.unique_integer([:positive])}"
      sentinel = "BABS_PHASE0_OUT_#{suffix}"

      with :ok <- Runner.inject(attach, "printf 'BABS_PHASE0_OUT_'; printf '#{suffix}\\n'\n"),
           {:ok, _output} <- Runner.collect_until(attach, sentinel, 5_000) do
        Observer.append_event(log_path, :bidirectional_bytes, %{
          session: attach.session,
          os_pid: attach.os_pid,
          sentinel: sentinel
        })

        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp observe_for(ctx, phase, seconds, log_path) do
    memory_before = :erlang.memory(:total)
    deadline = monotonic_deadline(seconds)
    port_downs = drain_until(deadline, log_path, phase, :all)
    memory_after = :erlang.memory(:total)
    dead_sessions = dead_sessions(ctx.fleet)
    allowed_port_downs = allowed_unprovoked_port_downs(length(ctx.fleet), seconds)

    details =
      "seconds=#{seconds} port_downs=#{port_downs} dead_sessions=#{length(dead_sessions)} " <>
        "allowed_port_downs=#{allowed_port_downs} memory_delta=#{memory_after - memory_before}"

    cond do
      dead_sessions != [] ->
        {:error, ctx, {:tmux_sessions_dead, dead_sessions}}

      port_downs > allowed_port_downs ->
        {:error, ctx, {:unprovoked_port_downs_exceeded, port_downs, allowed_port_downs}}

      true ->
        {:ok, ctx, details}
    end
  end

  defp chaos(ctx, profile, log_path) do
    deadline = monotonic_deadline(profile.chaos_seconds)
    result = chaos_loop(ctx.attachments, deadline, profile.chaos_interval_seconds, log_path, 0)

    case result do
      {:ok, attachments, kills} ->
        {:ok, %{ctx | attachments: attachments}, "intentional_port_kills=#{kills}"}

      {:error, attachments, reason} ->
        {:error, %{ctx | attachments: attachments}, reason}
    end
  end

  defp chaos_loop(attachments, deadline, interval_seconds, log_path, kills) do
    if System.monotonic_time(:second) >= deadline do
      {:ok, attachments, kills}
    else
      target = Chaos.choose_target(attachments, signal: Enum.random([:sigterm, :sigkill]))

      Observer.append_event(log_path, :chaos_kill, %{
        session: target.session,
        os_pid: target.os_pid,
        signal: target.signal
      })

      with :ok <- Chaos.kill(target),
           true <- Runner.tmux_session_alive?(target.session),
           {:ok, reattached} <- Runner.attach(target.session) do
        next_attachments =
          Enum.map(attachments, fn attach ->
            if attach.session == target.session, do: reattached, else: attach
          end)

        drain_for(
          min(interval_seconds, max(deadline - System.monotonic_time(:second), 0)),
          log_path,
          :chaos
        )

        chaos_loop(next_attachments, deadline, interval_seconds, log_path, kills + 1)
      else
        false -> {:error, attachments, {:tmux_session_died, target.session}}
        {:error, reason} -> {:error, attachments, reason}
      end
    end
  end

  defp resize_storm(ctx, seconds, log_path) do
    deadline = System.monotonic_time(:millisecond) + max(seconds, 0) * 1_000

    {resize_count, resize_errors, port_downs} =
      resize_loop(ctx.attachments, deadline, log_path, 0, 0, 0)

    dead_sessions = dead_sessions(ctx.fleet)

    details =
      "resize_calls=#{resize_count} resize_errors=#{resize_errors} port_downs=#{port_downs}"

    cond do
      dead_sessions != [] ->
        {:error, ctx, {:tmux_sessions_dead, dead_sessions}}

      resize_errors > 0 ->
        {:error, ctx, {:resize_errors, resize_errors}}

      port_downs > 0 ->
        {:error, ctx, {:resize_port_downs, port_downs}}

      true ->
        {:ok, ctx, details}
    end
  end

  defp resize_loop(attachments, deadline, log_path, count, errors, port_downs) do
    if System.monotonic_time(:millisecond) >= deadline do
      {count, errors, port_downs}
    else
      errors =
        errors +
          Enum.reduce(attachments, 0, fn %{os_pid: os_pid, session: session}, acc ->
            cols = 80 + :rand.uniform(80)
            rows = 24 + :rand.uniform(36)

            case Runner.resize(%{os_pid: os_pid}, rows, cols) do
              :ok ->
                acc

              other ->
                Observer.append_event(log_path, :resize_error, %{
                  session: session,
                  os_pid: os_pid,
                  result: inspect(other)
                })

                acc + 1
            end
          end)

      port_downs = port_downs + poll_messages(log_path, :resize_storm)
      Process.sleep(100)

      resize_loop(
        attachments,
        deadline,
        log_path,
        count + length(attachments),
        errors,
        port_downs
      )
    end
  end

  defp slow_reader(ctx, seconds, log_path) do
    skip =
      ctx.attachments
      |> List.first()
      |> Map.fetch!(:os_pid)

    memory_before = :erlang.memory(:total)

    drained_os_pids =
      ctx.attachments
      |> Enum.map(&Map.fetch!(&1, :os_pid))
      |> Enum.reject(&(&1 == skip))
      |> Map.new(&{&1, true})

    port_downs =
      drain_until(monotonic_deadline(seconds), log_path, :slow_reader, drained_os_pids)

    memory_after = :erlang.memory(:total)
    recovery_port_downs = drain_for(1, log_path, :slow_reader_recovery)
    total_port_downs = port_downs + recovery_port_downs

    details =
      "seconds=#{seconds} skipped_os_pid=#{skip} port_downs=#{total_port_downs} " <>
        "memory_delta=#{memory_after - memory_before}"

    if total_port_downs == 0 do
      {:ok, ctx, details}
    else
      {:error, ctx, {:slow_reader_port_downs, total_port_downs}}
    end
  end

  defp detach_reattach(ctx, profile, prefix, log_path) do
    if profile.detach_count == 0 do
      {:ok, ctx, "detach_reattach_runs=0"}
    else
      result =
        1..profile.detach_count
        |> Enum.reduce_while(:ok, fn index, :ok ->
          session = "#{prefix}-detach-#{index}"

          case DetachReattach.run(
                 session: session,
                 seconds: profile.detach_seconds,
                 log_path: log_path
               ) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      case result do
        :ok -> {:ok, ctx, "detach_reattach_runs=#{profile.detach_count}"}
        {:error, reason} -> {:error, ctx, reason}
      end
    end
  end

  defp web_byte_path(ctx, true, _log_path), do: {:ok, ctx, "operator_confirmed=true"}

  defp web_byte_path(ctx, false, _log_path) do
    {:warn, ctx,
     "manual check required: run `mix hardline.web` and confirm xterm.js renders for 30 minutes"}
  end

  defp cleanup(results, log_path) do
    ctx = context(results)

    Enum.each(Map.get(ctx, :attachments, []), &Runner.detach/1)
    Runner.stop_fleet(Map.get(ctx, :fleet, []))
    Observer.append_event(log_path, :cleanup, %{fleet_count: length(Map.get(ctx, :fleet, []))})

    Enum.reverse(results)
  end

  defp write_summary!(run_dir, profile_name, profile, results, web_confirmed?) do
    path = Path.join(run_dir, "SUMMARY.md")

    body = """
    # Hardline Phase 0 Validation Summary

    - Profile: `#{profile_name}`
    - Generated: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    - Overall status: **#{overall_status(results)}**
    - Web byte-path confirmed: #{web_confirmed?}

    ## Scenario Plan

    #{profile_table(profile)}

    ## Results

    #{results_table(results)}

    ## Phase 1 Handoff Notes

    - erlexec attach command: `tmux attach-session -t <session>`
    - default workload shell: `#{Runner.default_shell_command()}`
    - erlexec resize command: `:exec.winsz(os_pid, rows, cols)`
    - tmux session shape: detached sessions, `tmux new-session -d -s <session> <command>`
    - PubSub byte contract: `{:pane_bytes, stream_id, seq, binary}` on topic `pane:<name>`, chunks <= 4096 bytes
    - xterm.js page: run `mix hardline.web --port 4010`, then open `http://localhost:4010/`
    - Browser resize path: xterm FitAddon -> Channel `resize` event -> `:exec.winsz(os_pid, rows, cols)`
    - Browser assets: `@xterm/xterm@5.5.0`, `@xterm/addon-fit@0.10.0`, `phoenix@1.8.5`
    - Toolchain: see `spikes/hardline/README.md`
    """

    File.write!(path, body)
    path
  end

  defp profile_table(profile) do
    profile
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join("\n", fn {key, value} -> "- #{key}: #{value}" end)
  end

  defp results_table(results) do
    Enum.map_join(results, "\n", fn result ->
      "- #{result.name}: #{String.upcase(to_string(result.status))} - #{result.details}"
    end)
  end

  defp overall_status(results) do
    cond do
      Enum.any?(results, &(&1.status == :fail)) -> "FAIL"
      Enum.any?(results, &(&1.status == :warn)) -> "INCOMPLETE"
      true -> "PASS"
    end
  end

  defp validate_web_confirmation!("full", _web_confirmed?), do: :ok
  defp validate_web_confirmation!(_profile_name, false), do: :ok

  defp validate_web_confirmation!(profile_name, true) do
    raise ArgumentError, "--web-confirmed is only valid with --profile full, got #{profile_name}"
  end

  defp allowed_unprovoked_port_downs(fleet_count, seconds) do
    div(fleet_count * seconds, 48 * 60 * 60)
  end

  defp dead_sessions(fleet) do
    Enum.reject(fleet, fn %{session: session} -> Runner.tmux_session_alive?(session) end)
  end

  defp drain_for(seconds, log_path, phase) do
    drain_until(monotonic_deadline(seconds), log_path, phase, :all)
  end

  defp poll_messages(log_path, phase) do
    do_poll_messages(log_path, phase, 0)
  end

  defp do_poll_messages(log_path, phase, port_downs) do
    receive do
      {:stdout, os_pid, data} ->
        Observer.append_event(log_path, :stdout, %{
          phase: phase,
          os_pid: os_pid,
          bytes: byte_size(data)
        })

        do_poll_messages(log_path, phase, port_downs)

      {:DOWN, _monitor_ref, :process, pid, reason} ->
        Observer.append_event(log_path, :port_down, %{
          phase: phase,
          pid: inspect(pid),
          reason: inspect(reason)
        })

        do_poll_messages(log_path, phase, port_downs + 1)
    after
      0 -> port_downs
    end
  end

  @doc false
  def drain_until(deadline, log_path, phase, drained_os_pids) do
    do_drain_until(deadline, log_path, phase, drained_os_pids)
  end

  defp do_drain_until(deadline, log_path, phase, drained_os_pids) do
    if System.monotonic_time(:second) >= deadline do
      0
    else
      remaining = max(deadline - System.monotonic_time(:second), 0)

      receive do
        {:stdout, os_pid, data}
        when drained_os_pids == :all or is_map_key(drained_os_pids, os_pid) ->
          Observer.append_event(log_path, :stdout, %{
            phase: phase,
            os_pid: os_pid,
            bytes: byte_size(data)
          })

          do_drain_until(deadline, log_path, phase, drained_os_pids)

        {:DOWN, _monitor_ref, :process, pid, reason} ->
          Observer.append_event(log_path, :port_down, %{
            phase: phase,
            pid: inspect(pid),
            reason: inspect(reason)
          })

          1 + do_drain_until(deadline, log_path, phase, drained_os_pids)
      after
        min(1, remaining) * 1_000 ->
          do_drain_until(deadline, log_path, phase, drained_os_pids)
      end
    end
  end

  defp monotonic_deadline(seconds) do
    System.monotonic_time(:second) + max(seconds, 0)
  end

  defp run_prefix(profile_name) do
    "babs-phase0-#{profile_name}-#{System.system_time(:second)}"
  end

  defp validation_workload do
    ~S[/bin/zsh -f -c 'i=0; while true; do printf "BABS_TICK:%06d\n" "$i"; i=$((i+1)); sleep 1; done & exec /bin/zsh -f']
  end
end
