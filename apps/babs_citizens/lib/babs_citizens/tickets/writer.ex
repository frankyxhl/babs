defmodule Babs.Citizens.Tickets.Writer do
  @moduledoc """
  One lazy GenServer per Ticket id that serializes Babs-owned writes.
  """

  use GenServer

  alias Babs.Citizens.Tickets.History
  alias Babs.Citizens.Tickets.Store
  alias Babs.Citizens.Tickets.TicketMarkdown

  @idle_timeout 60_000

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    root = Keyword.fetch!(opts, :tickets_root)
    GenServer.start_link(__MODULE__, opts, name: via(root, id))
  end

  def via(root, id), do: {:via, Registry, {Babs.Citizens.Tickets.WriterRegistry, {root, id}}}

  def create(pid, ticket, opts \\ []) do
    GenServer.call(pid, {:create, ticket, opts}, 30_000)
  end

  def comment(pid, id, attrs, opts \\ []) do
    GenServer.call(pid, {:comment, id, attrs, opts}, 30_000)
  end

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    root = Keyword.fetch!(opts, :tickets_root)
    cleanup_temp_files(root, id)
    {:ok, %{id: id, root: root, idle_ref: schedule_idle(opts)}}
  end

  @impl true
  def handle_call({:create, ticket, opts}, _from, state) do
    state = reset_idle(state, opts)

    result =
      with :ok <- write_markdown(state.root, ticket.id, TicketMarkdown.render(ticket)),
           :ok <- History.append(state.root, ticket.id, created_event(ticket)) do
        {:ok, ticket}
      end

    {:reply, result, state}
  end

  def handle_call({:comment, id, attrs, opts}, _from, state) do
    state = reset_idle(state, opts)
    path = TicketMarkdown.path(state.root, id)

    result =
      with {:ok, original} <- read_current(path, id),
           {:ok, ticket} <- Store.read_ticket(state.root, id, opts),
           :ok <- run_before_write(path, opts),
           :ok <- detect_conflict(path, original, id),
           {:ok, body} <- comment_body(attrs),
           {:ok, by} <- comment_by(attrs),
           now <- now(opts),
           event <- comment_event(now, by, body),
           :ok <- History.validate_appendable(id, event),
           updated = %{ticket | updated_at: now},
           :ok <- write_markdown(state.root, id, TicketMarkdown.render(updated)),
           :ok <- History.append(state.root, id, event) do
        {:ok, %{ticket: updated, delivery: :deferred}}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info({:idle_timeout, ref}, %{idle_ref: ref} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:idle_timeout, _stale_ref}, state) do
    {:noreply, state}
  end

  defp created_event(ticket) do
    %{
      "ts" => ticket.created_at,
      "event" => "created",
      "by" => ticket.assigner,
      "ticket_id" => ticket.id
    }
  end

  defp comment_event(now, by, body) do
    %{
      "ts" => now,
      "event" => "comment",
      "by" => by,
      "body" => body
    }
  end

  defp read_current(path, id) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, {:not_found, id}}
      {:error, reason} -> {:error, {:redacted_io_error, {:read_ticket, reason}}}
    end
  end

  defp run_before_write(path, opts) do
    before_write = Keyword.get(opts, :before_write, fn _path -> :ok end)

    case before_write.(path) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, {:before_write_failed, other}}
    end
  end

  defp detect_conflict(path, original, id) do
    case File.read(path) do
      {:ok, ^original} -> :ok
      {:ok, _changed} -> {:error, {:write_conflict, id}}
      {:error, :enoent} -> {:error, {:write_conflict, id}}
      {:error, reason} -> {:error, {:redacted_io_error, {:read_ticket, reason}}}
    end
  end

  defp comment_body(attrs) do
    case fetch_attr(attrs, :body) do
      value when is_binary(value) ->
        if String.trim(value) == "",
          do: {:error, {:invalid_history_event, :empty_body}},
          else: {:ok, value}

      _ ->
        {:error, {:invalid_history_event, {:missing_keys, ["body"]}}}
    end
  end

  defp comment_by(attrs) do
    case fetch_attr(attrs, :by) || "user" do
      value when is_binary(value) ->
        if String.trim(value) == "",
          do: {:error, {:invalid_history_event, {:missing_keys, ["by"]}}},
          else: {:ok, value}

      _ ->
        {:error, {:invalid_history_event, {:missing_keys, ["by"]}}}
    end
  end

  defp fetch_attr(attrs, key) when is_map(attrs),
    do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp fetch_attr(attrs, key) when is_list(attrs),
    do: Keyword.get(attrs, key) || Keyword.get(attrs, Atom.to_string(key))

  defp write_markdown(root, id, content) do
    temp_path = temp_path(root, id)
    final_path = TicketMarkdown.path(root, id)

    with :ok <- write_temp(temp_path, content),
         :ok <- install_temp(temp_path, final_path) do
      :ok
    end
  end

  defp write_temp(path, content) do
    case File.write(path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, {:redacted_io_error, {:write_ticket_temp, reason}}}
    end
  end

  defp install_temp(temp_path, final_path) do
    case File.rename(temp_path, final_path) do
      :ok -> :ok
      {:error, reason} -> {:error, {:redacted_io_error, {:install_ticket, reason}}}
    end
  end

  defp temp_path(root, id) do
    unique = System.unique_integer([:positive, :monotonic])
    Path.join(root, ".#{id}.#{unique}.babs.md.tmp")
  end

  defp cleanup_temp_files(root, id) do
    prefix = ".#{id}."

    case File.ls(root) do
      {:ok, entries} ->
        entries
        |> Enum.filter(
          &(String.starts_with?(&1, prefix) and String.ends_with?(&1, ".babs.md.tmp"))
        )
        |> Enum.each(fn entry -> File.rm(Path.join(root, entry)) end)

      {:error, _reason} ->
        :ok
    end
  end

  defp now(opts), do: Keyword.get(opts, :now, DateTime.utc_now(:second) |> DateTime.to_iso8601())

  defp schedule_idle(opts) do
    ref = make_ref()

    Process.send_after(
      self(),
      {:idle_timeout, ref},
      Keyword.get(opts, :idle_timeout, @idle_timeout)
    )

    ref
  end

  defp reset_idle(%{idle_ref: ref} = state, opts) do
    Process.cancel_timer(ref)
    %{state | idle_ref: schedule_idle(opts)}
  end
end
