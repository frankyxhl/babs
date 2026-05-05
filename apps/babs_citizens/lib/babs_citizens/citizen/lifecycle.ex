defmodule Babs.Citizens.Lifecycle do
  @moduledoc """
  Starts, stops, and reattaches Phase 1 Citizen hardlines.
  """

  alias Babs.Citizens.Citizen.Config
  alias Babs.Citizens.Catalog
  alias Babs.Citizens.Hardline.Pane
  alias Babs.Citizens.Runner

  def start_citizen(slug, opts \\ []) when is_binary(slug) do
    with {:ok, config} <- Config.load_slug(slug, opts) do
      start_config(config)
    end
  end

  def start_config(config) do
    session = Runner.session_name(config.slug)

    result =
      with :ok <- maybe_start_tmux(config, session) do
        start_pane(config, session)
      end

    case result do
      {:ok, _pid} = ok ->
        maybe_mark_running(config.slug)
        ok

      {:error, reason} = error ->
        maybe_mark_failed(config.slug, reason)
        error
    end
  end

  def reattach(config) do
    session = Runner.session_name(config.slug)

    result =
      if Runner.tmux_session_alive?(session) do
        start_pane(config, session)
      else
        {:error, :tmux_session_not_found}
      end

    case result do
      {:ok, _pid} = ok ->
        maybe_mark_running(config.slug)
        ok

      {:error, reason} = error ->
        maybe_mark_failed(config.slug, reason)
        error
    end
  end

  def stop_citizen(slug) when is_binary(slug) do
    session = Runner.session_name(slug)

    with :ok <- stop_pane(slug),
         :ok <- stop_tmux_session(session) do
      maybe_mark_stopped(slug)
      :ok
    end
  end

  def lookup(slug) when is_binary(slug) do
    case Registry.lookup(Babs.Citizens.PaneRegistry, slug) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  defp maybe_start_tmux(config, session) do
    if Runner.tmux_session_alive?(session) do
      :ok
    else
      case Runner.start_session(config) do
        :ok ->
          :ok

        {:error, {:tmux_new_session_failed, _status, output}} = error ->
          if String.contains?(output, "duplicate session") and Runner.tmux_session_alive?(session) do
            :ok
          else
            error
          end

        {:error, _reason} = error ->
          error
      end
    end
  end

  defp start_pane(config, session) do
    child = %{
      id: {:hardline_pane, config.slug},
      start: {Pane, :start_link, [[config: config, session: session]]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(Babs.Citizens.DynamicSupervisor, child) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp stop_pane(slug) do
    case lookup(slug) do
      {:ok, pid} ->
        case DynamicSupervisor.terminate_child(Babs.Citizens.DynamicSupervisor, pid) do
          :ok -> :ok
          {:error, :not_found} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, :not_found} ->
        :ok
    end
  end

  defp stop_tmux_session(session) do
    case Runner.kill_session(session) do
      :ok ->
        :ok

      {:error, {:tmux_kill_session_failed, _status, output}} = error ->
        if tmux_session_absent_output?(output), do: :ok, else: error

      {:error, _reason} = error ->
        error
    end
  end

  defp tmux_session_absent_output?(output) when is_binary(output) do
    String.contains?(output, "can't find session") or
      String.contains?(output, "no server running")
  end

  defp maybe_mark_running(slug) do
    case Catalog.mark_running(slug) do
      {:ok, _record} -> :ok
      {:error, :not_found} -> :ok
      {:error, _changeset} -> :ok
    end
  end

  defp maybe_mark_stopped(slug) do
    case Catalog.mark_stopped(slug) do
      {:ok, _record} -> :ok
      {:error, :not_found} -> :ok
      {:error, _changeset} -> :ok
    end
  end

  defp maybe_mark_failed(slug, reason) do
    case Catalog.mark_failed(slug, reason) do
      {:ok, _record} -> :ok
      {:error, :not_found} -> :ok
      {:error, _changeset} -> :ok
    end
  end
end
