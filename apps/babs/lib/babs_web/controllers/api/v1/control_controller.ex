defmodule BabsWeb.Api.V1.ControlController do
  @moduledoc false

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn

  alias Babs.Citizens.Federation.{Audit, ControlGuard}
  alias Babs.Citizens.Hardline.Pane
  alias Babs.Citizens.Lifecycle
  alias Babs.Citizens.Tickets.Api, as: TicketApi

  require Logger

  @max_body_bytes 65_536
  @max_injection_bytes 4096
  @lifecycle_actions ~w(start stop restart)

  def init(action), do: action

  def call(conn, action), do: apply(__MODULE__, action, [conn, conn.params])

  def comment(conn, %{"id" => id}) do
    with {:ok, auth} <- authorize(conn, "write", nil, "ticket.comment", "ticket", id),
         {:ok, payload, conn} <- read_json_body(conn),
         {:ok, body} <- required_string(payload, "body"),
         {:ok, %{ticket: ticket}} <-
           TicketApi.comment_ticket(
             id,
             %{"body" => body, "by" => auth.actor},
             Keyword.merge(ticket_api_opts(), notify_assignees: false)
           ) do
      json(conn, %{"ok" => true, "ticket_id" => ticket.id, "action" => "comment"})
    else
      {:error, %ControlGuard.Error{} = guard} ->
        guard_error(conn, guard, "ticket.comment", "ticket", id)

      {:error, :invalid_params} ->
        error(conn, 400, "invalid_params", "Request body is invalid")

      {:error, reason} ->
        ticket_error(conn, reason)
    end
  end

  def transition(conn, %{"id" => id}) do
    with {:ok, auth} <- authorize(conn, "write", nil, "ticket.transition", "ticket", id),
         {:ok, payload, conn} <- read_json_body(conn),
         {:ok, to_state} <- required_string(payload, "to"),
         {:ok, %{ticket: ticket}} <-
           TicketApi.transition_ticket(
             id,
             to_state,
             "remote_transition",
             Keyword.merge(ticket_api_opts(), by: auth.actor)
           ) do
      json(conn, %{
        "ok" => true,
        "ticket_id" => ticket.id,
        "action" => "transition",
        "state" => ticket.state
      })
    else
      {:error, %ControlGuard.Error{} = guard} ->
        guard_error(conn, guard, "ticket.transition", "ticket", id)

      {:error, :invalid_params} ->
        error(conn, 400, "invalid_params", "Request body is invalid")

      {:error, reason} ->
        ticket_error(conn, reason)
    end
  end

  def assign(conn, %{"id" => id}) do
    # Assignment authorization needs the body slug so per-Citizen overrides can apply.
    with {:ok, payload, conn} <- read_json_body(conn),
         {:ok, slug} <- required_string(payload, "slug"),
         {:ok, auth} <- authorize(conn, "control", slug, "ticket.assign", "ticket", id),
         {:ok, %{ticket: ticket}} <-
           TicketApi.assign_ticket(
             id,
             slug,
             Keyword.merge(ticket_api_opts(), by: auth.actor)
           ) do
      json(conn, %{
        "ok" => true,
        "ticket_id" => ticket.id,
        "action" => "assign",
        "assignees" => ticket.assignees
      })
    else
      {:error, %ControlGuard.Error{} = guard} ->
        guard_error(conn, guard, "ticket.assign", "ticket", id)

      {:error, :invalid_params} ->
        error(conn, 400, "invalid_params", "Request body is invalid")

      {:error, reason} ->
        ticket_error(conn, reason)
    end
  end

  def unassign(conn, %{"id" => id, "slug" => slug}) do
    with {:ok, auth} <- authorize(conn, "control", slug, "ticket.unassign", "ticket", id),
         {:ok, %{ticket: ticket}} <-
           TicketApi.unassign_ticket(
             id,
             slug,
             Keyword.merge(ticket_api_opts(), by: auth.actor)
           ) do
      json(conn, %{
        "ok" => true,
        "ticket_id" => ticket.id,
        "action" => "unassign",
        "assignees" => ticket.assignees
      })
    else
      {:error, %ControlGuard.Error{} = guard} ->
        guard_error(conn, guard, "ticket.unassign", "ticket", id)

      {:error, reason} ->
        ticket_error(conn, reason)
    end
  end

  def inject(conn, %{"slug" => slug}) do
    with {:ok, auth} <- authorize(conn, "control", slug, "citizen.inject", "citizen", slug),
         {:ok, payload, conn} <- read_json_body(conn),
         {:ok, data} <- injection_data(payload),
         {:ok, _pid} <- Lifecycle.lookup(slug),
         :ok <- Pane.inject(slug, data),
         :ok <-
           Audit.success(
             auth,
             %{
               action: "citizen.inject",
               target_type: "citizen",
               target_id: slug,
               result: "ok"
             }
           ) do
      json(conn, %{"ok" => true, "citizen_slug" => slug, "action" => "inject"})
    else
      {:error, %ControlGuard.Error{} = guard} ->
        guard_error(conn, guard, "citizen.inject", "citizen", slug)

      {:error, :invalid_params} ->
        error(conn, 400, "invalid_params", "Request body is invalid")

      {:error, :not_found} ->
        error(conn, 404, "not_found", "Citizen #{slug} was not found")

      {:error, _reason} ->
        error(conn, 500, "control_failed", "Citizen injection failed")
    end
  end

  def lifecycle(conn, %{"slug" => slug}) do
    with {:ok, auth} <-
           authorize(conn, "control", slug, "citizen.lifecycle", "citizen", slug),
         {:ok, payload, conn} <- read_json_body(conn),
         {:ok, action} <- lifecycle_action(payload),
         :ok <- run_lifecycle(action, slug),
         :ok <-
           Audit.success(
             auth,
             %{
               action: "citizen.lifecycle.#{action}",
               target_type: "citizen",
               target_id: slug,
               result: "ok"
             }
           ) do
      json(conn, %{"ok" => true, "citizen_slug" => slug, "action" => action})
    else
      {:error, %ControlGuard.Error{} = guard} ->
        guard_error(conn, guard, "citizen.lifecycle", "citizen", slug)

      {:error, :invalid_params} ->
        error(conn, 400, "invalid_params", "Request body is invalid")

      {:error, :not_found} ->
        error(conn, 404, "not_found", "Citizen #{slug} was not found")

      {:error, _reason} ->
        error(conn, 500, "control_failed", "Citizen lifecycle action failed")
    end
  end

  defp authorize(conn, capability, nil, _action, _target_type, _target_id) do
    ControlGuard.authorize(peer_id(conn), capability)
  end

  defp authorize(conn, capability, slug, _action, _target_type, _target_id) do
    ControlGuard.authorize_citizen(peer_id(conn), slug, capability)
  end

  defp guard_error(conn, %ControlGuard.Error{} = guard, action, target_type, target_id) do
    if guard.status == 403 do
      audit_denied(%{
        peer_id: guard.peer_id || peer_id(conn),
        action: action,
        target_type: target_type,
        target_id: target_id,
        reason_code: guard.reason_code
      })
    end

    error(conn, guard.status, guard.code, guard.message)
  end

  defp audit_denied(attrs) do
    case Audit.denied(attrs) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("babs federation denied audit write failed: #{inspect(reason)}")
        :ok
    end
  end

  defp read_json_body(conn) do
    case read_body(conn, length: @max_body_bytes, read_length: @max_body_bytes) do
      {:ok, body, conn} ->
        decode_json_body(body, conn)

      {:more, _partial, _conn} ->
        {:error, :invalid_params}

      {:error, _reason} ->
        {:error, :invalid_params}
    end
  end

  defp decode_json_body("", _conn), do: {:error, :invalid_params}

  defp decode_json_body(body, conn) do
    case Jason.decode(body) do
      {:ok, payload} when is_map(payload) -> {:ok, payload, conn}
      _other -> {:error, :invalid_params}
    end
  end

  defp required_string(payload, key) do
    case Map.get(payload, key) do
      value when is_binary(value) ->
        if String.trim(value) == "", do: {:error, :invalid_params}, else: {:ok, value}

      _value ->
        {:error, :invalid_params}
    end
  end

  defp injection_data(payload) do
    with {:ok, data} <- required_string(payload, "data"),
         true <- byte_size(data) <= @max_injection_bytes do
      {:ok, data}
    else
      _other -> {:error, :invalid_params}
    end
  end

  defp lifecycle_action(payload) do
    with {:ok, action} <- required_string(payload, "action"),
         true <- action in @lifecycle_actions do
      {:ok, action}
    else
      _other -> {:error, :invalid_params}
    end
  end

  defp run_lifecycle(action, slug) do
    case lifecycle_runner().(action, slug) do
      :ok -> :ok
      {:ok, _pid} -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp lifecycle_runner do
    controller_config()
    |> Keyword.get(:lifecycle_runner, &default_lifecycle/2)
  end

  defp default_lifecycle("start", slug), do: Lifecycle.start_registered_citizen(slug)
  defp default_lifecycle("stop", slug), do: Lifecycle.stop_citizen(slug)
  defp default_lifecycle("restart", slug), do: Lifecycle.restart_registered_citizen(slug)

  defp ticket_api_opts do
    controller_config()
    |> Keyword.get(:ticket_api_opts, [])
  end

  defp controller_config do
    Application.get_env(:babs, __MODULE__, [])
  end

  defp peer_id(conn) do
    conn
    |> get_req_header("x-babs-peer-id")
    |> List.first()
  end

  defp ticket_error(conn, {:invalid_id, _id}),
    do: error(conn, 400, "invalid_id", "Ticket id is invalid")

  defp ticket_error(conn, {:not_found, id}),
    do: error(conn, 404, "not_found", "Ticket #{id} was not found")

  defp ticket_error(conn, {:invalid_transition, _from, _to}),
    do: error(conn, 400, "invalid_transition", "Ticket transition is invalid")

  defp ticket_error(conn, {:invalid_state, _state}),
    do: error(conn, 400, "invalid_params", "Ticket transition target is invalid")

  defp ticket_error(conn, {:invalid_slug, _slug}),
    do: error(conn, 400, "invalid_params", "Citizen slug is invalid")

  defp ticket_error(conn, {:not_assigned, _id, _slug}),
    do: error(conn, 400, "invalid_params", "Citizen is not assigned to this Ticket")

  defp ticket_error(conn, _reason), do: error(conn, 500, "write_failed", "Ticket write failed")

  defp error(%Plug.Conn{} = conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{"error" => %{"code" => code, "message" => message}})
  end
end
