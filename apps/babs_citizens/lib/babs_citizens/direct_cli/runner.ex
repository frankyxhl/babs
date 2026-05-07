defmodule Babs.Citizens.DirectCli.Runner do
  @moduledoc """
  Supervised async runner for direct CLI Ticket turns.
  """

  use GenServer

  alias Babs.Citizens.{ExecutionLock, ProviderSessions}
  alias Babs.Citizens.DirectCli.{Adapters, Env, Executor, Redactor}
  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.TurnIds

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_turn(turn, opts \\ []) when is_map(turn) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:start_turn, turn, opts})
    else
      {:error, :direct_runner_unavailable}
    end
  end

  @impl true
  def init(_opts) do
    _ignored = ProviderSessions.mark_stale_in_flight_failed()
    {:ok, %{}}
  rescue
    error ->
      Logger.warning("Babs direct CLI stale cleanup failed: #{Exception.message(error)}")
      {:ok, %{}}
  end

  @impl true
  def handle_call({:start_turn, turn, opts}, _from, state) do
    child_opts = Keyword.get(opts, :task_supervisor, Babs.Citizens.DirectCli.TaskSupervisor)
    task_opts = Keyword.put(opts, :caller, self())

    result =
      Task.Supervisor.start_child(child_opts, fn ->
        run_turn(turn, task_opts)
      end)

    reply =
      case result do
        {:ok, _pid} -> :ok
        {:error, reason} -> {:error, reason}
      end

    {:reply, reply, state}
  end

  def run_turn(turn, opts \\ []) do
    ExecutionLock.with_lock(turn.slug, fn -> run_locked(turn, opts) end)
    |> case do
      {:error, {:execution_busy, _slug}} ->
        append_events(turn, [attempt_busy_event(turn)])

      result ->
        result
    end
  end

  defp run_locked(turn, opts) do
    with {:ok, adapter} <- adapter(turn, opts),
         {:ok, session} <- ensure_session(turn, adapter, opts),
         {:ok, command} <- command_for_turn(turn, adapter, session, opts),
         :ok <- append_events(turn, [execution_started_event(turn)]),
         {:ok, started} <- ProviderSessions.mark_started(session, %{started_at: now_datetime()}) do
      execute_started_turn(started, turn, adapter, command, opts)
    else
      {:error, reason} ->
        handle_direct_failure(turn, reason, opts)
    end
  end

  defp execute_started_turn(started, turn, adapter, command, opts) do
    with {:ok, artifacts} <- execute_command(command, opts),
         artifacts <- Map.put_new(artifacts, :provider_session_id, command.provider_session_id),
         {:ok, result} <-
           adapter.parse_result(artifacts, secret_names: Env.secret_names(turn.config)),
         {:ok, _updated_session} <- finish_session(started, turn, result),
         :ok <- append_events(turn, [delivered_event(turn, result)]),
         {:ok, _comment} <- append_reply(turn, result) do
      :ok
    else
      {:error, reason} ->
        _ignored = ProviderSessions.mark_failed(started, reason)
        handle_direct_failure(turn, reason, opts)
    end
  end

  defp execute_command(command, opts) do
    executor(opts).(command)
  rescue
    error -> {:error, {:executor_exception, Exception.message(error)}}
  catch
    :exit, reason -> {:error, {:executor_exit, reason}}
    kind, reason -> {:error, {kind, reason}}
  end

  defp adapter(turn, opts) do
    case Keyword.fetch(opts, :adapter) do
      {:ok, adapter} -> {:ok, adapter}
      :error -> Adapters.resolve(turn.config, opts)
    end
  end

  defp ensure_session(turn, adapter, _opts) do
    provider = adapter.provider()
    existing = ProviderSessions.get_active(turn.slug, turn.ticket_id, provider, "direct_cli")

    attrs = %{
      citizen_slug: turn.slug,
      ticket_id: turn.ticket_id,
      provider: provider,
      backend: "direct_cli",
      workspace_ref: "citizen:#{turn.slug}",
      status: "active",
      last_turn_id: turn.turn_id,
      capabilities: %{"direct" => true}
    }

    case existing do
      nil -> ProviderSessions.upsert_active(attrs)
      session -> {:ok, session}
    end
  end

  defp command_for_turn(turn, adapter, session, opts) do
    command_opts =
      [
        timeout_ms: Keyword.get(opts, :timeout_ms, 120_000),
        output_limit: Keyword.get(opts, :output_limit, 65_536)
      ]
      |> maybe_command_provider_session_id(session.provider_session_id)

    if is_binary(session.provider_session_id) and session.provider_session_id != "" and
         session.status == "active" do
      adapter.resume_command(turn.config, session.provider_session_id, turn.prompt, command_opts)
    else
      adapter.start_command(turn.config, turn.prompt, command_opts)
    end
  end

  defp maybe_command_provider_session_id(opts, provider_session_id)
       when is_binary(provider_session_id) and provider_session_id != "" do
    Keyword.put(opts, :provider_session_id, provider_session_id)
  end

  defp maybe_command_provider_session_id(opts, _provider_session_id), do: opts

  defp finish_session(session, turn, result) do
    status =
      if is_binary(result.provider_session_id) and result.provider_session_id != "",
        do: "active",
        else: "non_resumable"

    ProviderSessions.mark_finished(session, %{
      provider_session_id: result.provider_session_id,
      provider_cli_version: Map.get(result, :provider_cli_version),
      capabilities: result.capabilities || %{"direct" => true, "resume" => status == "active"},
      last_turn_id: turn.turn_id,
      status: status,
      metadata: Map.get(result, :metadata, %{})
    })
  end

  defp append_reply(turn, result) do
    Api.comment_ticket(
      turn.ticket_id,
      %{
        body: result.text,
        by: turn.slug,
        turn_id: turn.turn_id,
        attempt_id: turn.attempt_id
      },
      tickets_root: turn.root,
      notify_assignees: false
    )
  end

  defp handle_direct_failure(turn, reason, opts) do
    _ignored = append_events(turn, [delivery_failed_event(turn, reason)])

    case Map.get(turn, :fallback, :hardline) do
      :hardline ->
        fallback_to_hardline(turn, reason, opts)

      _other ->
        {:error, reason}
    end
  end

  defp fallback_to_hardline(turn, reason, opts) do
    attempt_id = TurnIds.generate!(:attempt, now_iso())

    fallback_turn =
      turn
      |> Map.put(:attempt_id, attempt_id)
      |> Map.put(:backend, "hardline")

    with :ok <-
           append_events(fallback_turn, [
             delivery_attempted_event(fallback_turn, "queued", reason)
           ]),
         :ok <- hardline_injector(opts).(turn.slug, turn.prompt, opts),
         :ok <-
           append_events(fallback_turn, [
             delivered_event(fallback_turn, %{provider_session_id: nil})
           ]) do
      reply_capture(opts).(%{
        root: turn.root,
        ticket_id: turn.ticket_id,
        slug: turn.slug,
        started_at: now_iso(),
        turn_id: turn.turn_id,
        attempt_id: attempt_id
      })

      :ok
    else
      {:error, fallback_reason} ->
        append_events(fallback_turn, [delivery_failed_event(fallback_turn, fallback_reason)])
        {:error, fallback_reason}
    end
  end

  defp append_events(turn, events) do
    Api.append_ticket_events(turn.ticket_id, events, tickets_root: turn.root)
  end

  defp executor(opts), do: Keyword.get(opts, :executor, &Executor.run/1)

  defp hardline_injector(opts) do
    Keyword.get(opts, :hardline_injector, fn slug, prompt, injector_opts ->
      Babs.Citizens.Tickets.Injector.prepare(slug, injector_opts)
      |> case do
        :ok -> Babs.Citizens.Tickets.Injector.inject(slug, prompt, injector_opts)
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp reply_capture(opts),
    do: Keyword.get(opts, :reply_capture, &Babs.Citizens.Tickets.ReplyCapture.track/1)

  defp delivery_attempted_event(turn, status, reason) do
    %{
      "ts" => now_iso(),
      "event" => "turn_delivery_attempted",
      "by" => "system",
      "ticket_id" => turn.ticket_id,
      "turn_id" => turn.turn_id,
      "attempt_id" => turn.attempt_id,
      "to" => turn.slug,
      "backend" => turn.backend || "direct_cli",
      "status" => status
    }
    |> maybe_error(reason)
  end

  defp attempt_busy_event(turn), do: delivery_attempted_event(turn, "busy", :execution_busy)

  defp execution_started_event(turn) do
    %{
      "ts" => now_iso(),
      "event" => "turn_execution_started",
      "by" => "system",
      "ticket_id" => turn.ticket_id,
      "turn_id" => turn.turn_id,
      "attempt_id" => turn.attempt_id,
      "to" => turn.slug,
      "backend" => turn.backend || "direct_cli"
    }
  end

  defp delivered_event(turn, result) do
    %{
      "ts" => now_iso(),
      "event" => "turn_delivered",
      "by" => "system",
      "ticket_id" => turn.ticket_id,
      "turn_id" => turn.turn_id,
      "attempt_id" => turn.attempt_id,
      "to" => turn.slug,
      "backend" => turn.backend || "direct_cli"
    }
    |> maybe_provider_session_id(Map.get(result, :provider_session_id))
  end

  defp delivery_failed_event(turn, reason) do
    %{
      "ts" => now_iso(),
      "event" => "turn_delivery_failed",
      "by" => "system",
      "ticket_id" => turn.ticket_id,
      "turn_id" => turn.turn_id,
      "attempt_id" => turn.attempt_id,
      "to" => turn.slug,
      "backend" => turn.backend || "direct_cli",
      "error" => Redactor.redact_text(inspect(reason))
    }
  end

  defp maybe_error(event, nil), do: event

  defp maybe_error(event, reason),
    do: Map.put(event, "error", Redactor.redact_text(inspect(reason)))

  defp maybe_provider_session_id(event, session_id)
       when is_binary(session_id) and session_id != "",
       do: Map.put(event, "provider_session_id", session_id)

  defp maybe_provider_session_id(event, _session_id), do: event

  defp now_iso, do: DateTime.utc_now(:second) |> DateTime.to_iso8601()
  defp now_datetime, do: DateTime.utc_now(:second)
end
