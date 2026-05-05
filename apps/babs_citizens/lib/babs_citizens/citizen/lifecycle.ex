defmodule Babs.Citizens.Lifecycle do
  @moduledoc """
  Starts, stops, and reattaches Phase 1 Citizen hardlines.
  """

  alias Babs.Citizens.Citizen.Config
  alias Babs.Citizens.Hardline.Pane
  alias Babs.Citizens.Runner

  def start_citizen(slug, opts \\ []) when is_binary(slug) do
    with {:ok, config} <- Config.load_slug(slug, opts) do
      start_config(config)
    end
  end

  def start_config(config) do
    session = Runner.session_name(config.slug)

    with :ok <- maybe_start_tmux(config, session) do
      start_pane(config, session)
    end
  end

  def reattach(config) do
    session = Runner.session_name(config.slug)

    if Runner.tmux_session_alive?(session) do
      start_pane(config, session)
    else
      {:error, :tmux_session_not_found}
    end
  end

  def stop_citizen(slug) when is_binary(slug) do
    session = Runner.session_name(slug)

    with :ok <- stop_pane(slug),
         :ok <- Runner.kill_session(session) do
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
end
