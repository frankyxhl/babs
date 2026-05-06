defmodule Babs.Citizens.Tickets.Api do
  @moduledoc """
  Public Ticket storage API used by commands, web code, and tests.
  """

  alias Babs.Citizens.Tickets.Config
  alias Babs.Citizens.Tickets.Store
  alias Babs.Citizens.Tickets.Ticket
  alias Babs.Citizens.Tickets.TicketId
  alias Babs.Citizens.Tickets.Writer
  alias Babs.Citizens.Tickets.WriterSupervisor

  @spec create_ticket(map() | keyword(), keyword()) :: {:ok, Ticket.t()} | {:error, term()}
  def create_ticket(attrs, opts \\ []) do
    with {:ok, root} <- Config.ensure_root(opts),
         {:ok, title} <- required_attr(attrs, :title),
         {:ok, body} <- required_attr(attrs, :body),
         {:ok, id, path} <- TicketId.claim_next(root, opts) do
      ticket = new_ticket(id, title, body, path, attrs, opts)

      case write_new_ticket(root, ticket, opts) do
        {:ok, ticket} ->
          {:ok, ticket}

        {:error, reason} ->
          cleanup_empty_claim(path)
          {:error, reason}
      end
    end
  end

  @spec list_tickets(keyword()) :: {:ok, %{tickets: list(), invalid: list()}} | {:error, term()}
  def list_tickets(opts \\ []) do
    Store.list(opts)
  end

  @spec show_ticket(String.t(), keyword()) ::
          {:ok, %{ticket: Ticket.t(), history: [map()]}} | {:error, term()}
  def show_ticket(id, opts \\ []) do
    Store.show(id, opts)
  end

  @spec comment_ticket(String.t(), map() | keyword(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def comment_ticket(id, attrs, opts \\ []) do
    with :ok <- TicketId.validate(id),
         opts <- runtime_opts(opts),
         {:ok, root} <- Config.ensure_root(opts),
         opts <- Keyword.put(opts, :tickets_root, root),
         {:ok, pid} <- WriterSupervisor.start_writer(id, opts) do
      Writer.comment(pid, id, attrs, opts)
    end
  end

  @spec assign_ticket(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def assign_ticket(id, slug, opts \\ []) when is_binary(slug) do
    with :ok <- TicketId.validate(id),
         opts <- runtime_opts(opts),
         {:ok, root} <- Config.ensure_root(opts),
         opts <- Keyword.put(opts, :tickets_root, root),
         {:ok, pid} <- WriterSupervisor.start_writer(id, opts) do
      Writer.assign(pid, id, slug, opts)
    end
  end

  @spec unassign_ticket(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def unassign_ticket(id, slug, opts \\ []) when is_binary(slug) do
    with :ok <- TicketId.validate(id),
         opts <- runtime_opts(opts),
         {:ok, root} <- Config.ensure_root(opts),
         opts <- Keyword.put(opts, :tickets_root, root),
         {:ok, pid} <- WriterSupervisor.start_writer(id, opts) do
      Writer.unassign(pid, id, slug, opts)
    end
  end

  @spec transition_ticket(String.t(), String.t(), String.t() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def transition_ticket(id, to_state, event, opts \\ []) do
    with :ok <- TicketId.validate(id),
         opts <- runtime_opts(opts),
         {:ok, root} <- Config.ensure_root(opts),
         opts <- Keyword.put(opts, :tickets_root, root),
         {:ok, pid} <- WriterSupervisor.start_writer(id, opts) do
      Writer.transition(pid, id, to_state, event, opts)
    end
  end

  defp new_ticket(id, title, body, path, attrs, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now(:second) |> DateTime.to_iso8601())

    %Ticket{
      id: id,
      type: attr(attrs, :type) || "assignment",
      state: attr(attrs, :state) || "open",
      assigner: attr(attrs, :assigner) || "user",
      assignees: attr(attrs, :assignees) || [],
      assignee_role: attr(attrs, :assignee_role),
      inspector: attr(attrs, :inspector) || "user",
      priority: attr(attrs, :priority) || "normal",
      parent_ticket: attr(attrs, :parent_ticket),
      created_at: now,
      updated_at: now,
      metadata: attr(attrs, :metadata) || %{},
      title: title,
      body: body,
      path: path,
      warnings: []
    }
  end

  defp write_new_ticket(root, ticket, opts) do
    with :ok <- validate_ticket(ticket, opts),
         {:ok, pid} <-
           WriterSupervisor.start_writer(ticket.id, Keyword.put(opts, :tickets_root, root)) do
      Writer.create(pid, ticket, opts)
    end
  end

  defp validate_ticket(ticket, opts) do
    case Babs.Citizens.Tickets.TicketMarkdown.parse(
           Babs.Citizens.Tickets.TicketMarkdown.render(ticket),
           path: ticket.path,
           known_citizens: Keyword.get(opts, :known_citizens)
         ) do
      {:ok, _ticket} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp cleanup_empty_claim(path) do
    case File.read(path) do
      {:ok, ""} -> File.rm(path)
      _ -> :ok
    end
  end

  defp required_attr(attrs, key) do
    case attr(attrs, key) do
      value when is_binary(value) ->
        validate_required_string(key, value)

      _ ->
        {:error, {:invalid_frontmatter, {:missing_keys, [Atom.to_string(key)]}}}
    end
  end

  defp validate_required_string(key, value) do
    cond do
      String.trim(value) == "" ->
        {:error, {:invalid_frontmatter, {:blank, Atom.to_string(key)}}}

      key == :title and String.contains?(value, ["\n", "\r"]) ->
        {:error, {:invalid_frontmatter, {:multiline, "title"}}}

      true ->
        {:ok, value}
    end
  end

  defp attr(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp attr(attrs, key) when is_list(attrs),
    do: Keyword.get(attrs, key) || Keyword.get(attrs, Atom.to_string(key))

  defp runtime_opts(opts) do
    :babs_citizens
    |> Application.get_env(:ticket_runtime_opts, [])
    |> Keyword.merge(opts)
  end
end
