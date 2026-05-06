defmodule Babs.Citizens.Tickets.Injector do
  @moduledoc """
  Boundary for delivering Ticket prompts to Citizen hardline panes.
  """

  alias Babs.Citizens.Catalog
  alias Babs.Citizens.Hardline.Pane
  alias Babs.Citizens.Lifecycle
  alias Babs.Citizens.Tickets.Ticket

  @spec prompt(Ticket.t(), String.t()) :: String.t()
  def prompt(%Ticket{} = ticket, slug) when is_binary(slug) do
    """
    [Babs Ticket #{ticket.id} assigned]
    Title: #{ticket.title}
    State: in_progress
    Assignee: #{slug}
    Path: #{ticket.path || ticket.id <> ".md"}

    #{String.trim(ticket.body)}

    Please acknowledge the assignment and work in this terminal.
    """
  end

  @spec feedback_prompt(Ticket.t(), String.t(), String.t()) :: String.t()
  def feedback_prompt(%Ticket{} = ticket, slug, feedback)
      when is_binary(slug) and is_binary(feedback) do
    """
    [Babs Ticket #{ticket.id} rejected]
    State: in_progress
    Assignee: #{slug}

    Feedback from user:
    #{String.trim(feedback)}

    Please address the feedback and continue work in this terminal.
    """
  end

  @spec comment_prompt(Ticket.t(), String.t(), String.t(), String.t()) :: String.t()
  def comment_prompt(%Ticket{} = ticket, slug, by, body)
      when is_binary(slug) and is_binary(by) and is_binary(body) do
    """
    [Babs Ticket #{ticket.id} comment]
    State: #{ticket.state}
    Assignee: #{slug}
    From: #{by}

    #{String.trim(body)}

    This comment is persisted in Ticket history. Continue coordination through `bb ticket comment`.
    """
  end

  @spec prepare(String.t(), keyword()) :: :ok | {:error, term()}
  def prepare(slug, opts \\ []) when is_binary(slug) do
    with {:ok, _record} <- fetch_citizen(slug, opts),
         :ok <- ensure_live_pane(slug, opts) do
      :ok
    end
  end

  @spec inject(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def inject(slug, prompt, opts \\ []) when is_binary(slug) and is_binary(prompt) do
    with {:ok, _pid} <- lookup_pane(slug, opts) do
      case pane_injector(opts).(slug, prompt) do
        :ok -> :ok
        {:error, reason} -> {:error, {:ticket_injection_failed, slug, redact(reason)}}
        other -> {:error, {:ticket_injection_failed, slug, redact(other)}}
      end
    else
      {:error, :not_found} -> {:error, {:citizen_not_running, slug}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_citizen(slug, opts) do
    case citizen_fetcher(opts).(slug) do
      nil -> {:error, {:unknown_citizen, slug}}
      {:ok, record} -> {:ok, record}
      {:error, reason} -> {:error, reason}
      record -> {:ok, record}
    end
  end

  defp ensure_live_pane(slug, opts) do
    case lookup_pane(slug, opts) do
      {:ok, _pid} ->
        :ok

      {:error, :not_found} ->
        start_and_verify(slug, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_and_verify(slug, opts) do
    case citizen_starter(opts).(slug) do
      {:ok, _pid} ->
        verify_started(slug, opts)

      :ok ->
        verify_started(slug, opts)

      {:error, reason} ->
        {:error, {:citizen_start_failed, slug, redact(reason)}}

      other ->
        {:error, {:citizen_start_failed, slug, redact(other)}}
    end
  end

  defp verify_started(slug, opts) do
    case lookup_pane(slug, opts) do
      {:ok, _pid} -> :ok
      {:error, :not_found} -> {:error, {:citizen_not_running, slug}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lookup_pane(slug, opts) do
    case pane_lookup(opts).(slug) do
      {:ok, pid} -> {:ok, pid}
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, {:citizen_lookup_failed, slug, redact(reason)}}
      other -> {:error, {:citizen_lookup_failed, slug, redact(other)}}
    end
  end

  defp citizen_fetcher(opts) do
    Keyword.get(opts, :citizen_fetcher, fn slug -> Catalog.get_by_slug(slug) end)
  end

  defp pane_lookup(opts), do: Keyword.get(opts, :pane_lookup, &Lifecycle.lookup/1)

  defp citizen_starter(opts) do
    Keyword.get(opts, :citizen_starter, fn slug -> Lifecycle.start_registered_citizen(slug) end)
  end

  defp pane_injector(opts), do: Keyword.get(opts, :pane_injector, &Pane.inject/2)

  defp redact(reason), do: Catalog.redact_reason(reason)
end
