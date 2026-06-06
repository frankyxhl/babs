defmodule BabsWeb.Api.V1.ReadController do
  @moduledoc false

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn

  alias Babs.Citizens.{Catalog, Federation, StatusSnapshot}
  alias Babs.Citizens.Hardline.Transcript
  alias Babs.Citizens.Tickets.{Api, Config, PromptAssembler}
  alias BabsWeb.Api.V1.Presenter

  def init(action), do: action

  def call(conn, action), do: apply(__MODULE__, action, [conn, conn.params])

  def node(conn, _params) do
    with_federation(conn, fn conn, %{"node" => node, "peers" => peers} ->
      json(conn, %{"node" => node, "peers" => peers})
    end)
  end

  def citizens(conn, _params) do
    with_federation(conn, fn conn, info ->
      citizens =
        StatusSnapshot.list(include_stale?: true)
        |> Enum.map(&Presenter.citizen_projection/1)

      json(conn, %{"node" => Presenter.node_summary(info), "citizens" => citizens})
    end)
  end

  def citizen(conn, %{"slug" => slug}) do
    with_federation(conn, fn conn, info ->
      StatusSnapshot.list(include_stale?: true)
      |> Enum.find(&(&1.slug == slug))
      |> case do
        nil ->
          error(conn, 404, "not_found", "Citizen #{slug} was not found")

        snapshot ->
          json(conn, %{
            "node" => Presenter.node_summary(info),
            "citizen" => Presenter.citizen_projection(snapshot)
          })
      end
    end)
  end

  def citizen_transcript(conn, %{"slug" => slug} = params) do
    conn = fetch_query_params(conn)
    params = Map.merge(params, conn.query_params)

    with_federation(conn, fn conn, info ->
      with {:ok, line_limit, tail_bytes} <- transcript_params(params),
           {:ok, record} <- fetch_citizen_record(slug),
           {:ok, transcript} <-
             Transcript.replay_output_info(record.cwd,
               slug: slug,
               lines: line_limit,
               tail_bytes: tail_bytes
             ) do
        json(conn, %{
          "node" => Presenter.node_summary(info),
          "citizen_slug" => slug,
          "transcript" => %{
            "output" => Presenter.json_safe_output(transcript.output),
            "truncated" => transcript.truncated,
            "lines" => transcript.lines,
            "returned_lines" => transcript.returned_lines
          }
        })
      else
        {:error, :not_found} ->
          error(conn, 404, "not_found", "Citizen #{slug} was not found")

        {:error, :invalid_params} ->
          error(conn, 400, "invalid_params", "Transcript query parameters are invalid")

        {:error, _reason} ->
          error(conn, 500, "read_failed", "Transcript could not be read")
      end
    end)
  end

  def citizen_standing_context(conn, %{"slug" => slug}) do
    with_federation(conn, fn conn, info ->
      case fetch_citizen_record(slug) do
        {:ok, _record} ->
          json(conn, %{
            "node" => Presenter.node_summary(info),
            "citizen_slug" => slug,
            "standing_context" => PromptAssembler.standing_context_preview(slug)
          })

        {:error, :not_found} ->
          error(conn, 404, "not_found", "Citizen #{slug} was not found")
      end
    end)
  end

  def tickets(conn, _params) do
    with_federation(conn, fn conn, info ->
      with :ok <- ensure_ticket_root_readable(),
           {:ok, %{tickets: tickets, invalid: invalid}} <- Api.list_tickets() do
        json(conn, %{
          "node" => Presenter.node_summary(info),
          "tickets" => Enum.map(tickets, &Presenter.ticket_summary/1),
          "invalid" => %{"count" => length(invalid)}
        })
      else
        {:error, _reason} ->
          error(conn, 500, "read_failed", "Tickets could not be read")
      end
    end)
  end

  def ticket(conn, %{"id" => id}) do
    with_federation(conn, fn conn, info ->
      with :ok <- ensure_ticket_root_readable(),
           {:ok, %{ticket: ticket, history: history}} <- Api.show_ticket(id) do
        json(conn, %{
          "node" => Presenter.node_summary(info),
          "ticket" =>
            ticket
            |> Presenter.ticket_detail()
            |> Map.put("history", Presenter.safe_history(history))
        })
      else
        {:error, {:invalid_id, _id}} ->
          error(conn, 400, "invalid_id", "Ticket id is invalid")

        {:error, {:not_found, ^id}} ->
          error(conn, 404, "not_found", "Ticket #{id} was not found")

        {:error, _reason} ->
          error(conn, 500, "read_failed", "Ticket could not be read")
      end
    end)
  end

  defp with_federation(conn, fun) do
    case Federation.node_info() do
      {:ok, info} ->
        fun.(conn, info)

      {:error, {:config_error, _reason}} ->
        error(conn, 503, "config_error", "Federation config is invalid")
    end
  end

  defp transcript_params(params) do
    with {:ok, lines} <- bounded_integer(params, "lines", 200, 1, 1000),
         {:ok, tail_bytes} <- bounded_integer(params, "tail_bytes", 1_048_576, 1, 1_048_576) do
      {:ok, lines, tail_bytes}
    else
      {:error, _reason} -> {:error, :invalid_params}
    end
  end

  defp bounded_integer(params, key, default, min, max) do
    value = Map.get(params, key)

    cond do
      value in [nil, ""] ->
        {:ok, default}

      is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} when integer >= min and integer <= max -> {:ok, integer}
          _other -> {:error, key}
        end

      true ->
        {:error, key}
    end
  end

  defp fetch_citizen_record(slug) do
    case Catalog.get_by_slug(slug) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  defp ensure_ticket_root_readable do
    root = Config.tickets_root()

    case File.stat(root) do
      {:ok, %{type: :directory}} ->
        case File.ls(root) do
          {:ok, _entries} -> :ok
          {:error, reason} -> {:error, {:read_failed, reason}}
        end

      {:error, :enoent} ->
        :ok

      {:ok, _stat} ->
        {:error, {:read_failed, :not_directory}}

      {:error, reason} ->
        {:error, {:read_failed, reason}}
    end
  end

  defp error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{"error" => %{"code" => code, "message" => message}})
  end
end
