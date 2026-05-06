defmodule Babs.Citizens.Lifecycle do
  @moduledoc """
  Starts, stops, and reattaches Citizen hardlines.
  """

  alias Babs.Citizens.Citizen.Config
  alias Babs.Citizens.Catalog
  alias Babs.Citizens.Hardline.Pane
  alias Babs.Citizens.ImportedHardline
  alias Babs.Citizens.Runner
  alias Babs.Citizens.TmuxInventory

  @lock_registry Babs.Citizens.LifecycleRegistry

  def start_citizen(slug, opts \\ []) when is_binary(slug) do
    with {:ok, config} <- Config.load_slug(slug, opts) do
      start_config(config)
    end
  end

  def start_registered_citizen(slug, opts \\ []) when is_binary(slug) do
    with_slug_lock(slug, opts, fn -> do_start_registered_citizen(slug, opts) end)
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

  def restart_registered_citizen(slug, opts \\ []) when is_binary(slug) do
    with_slug_lock(slug, opts, fn ->
      with {:ok, record} <- registered_record(slug),
           :ok <- do_stop_citizen(slug) do
        run_start_record(record, opts)
      end
    end)
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

  def stop_citizen(slug, opts \\ []) when is_binary(slug) do
    with_slug_lock(slug, opts, fn -> do_stop_citizen(slug) end)
  end

  def attach_imported_citizen(slug, target, opts \\ [])
      when is_binary(slug) and is_binary(target) do
    with_slug_lock(slug, opts, fn -> do_attach_imported_citizen(slug, target, opts) end)
  end

  def lookup(slug) when is_binary(slug) do
    case Registry.lookup(Babs.Citizens.PaneRegistry, slug) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  defp do_stop_citizen(slug) do
    case Catalog.get_by_slug(slug) do
      nil ->
        stop_babs_owned(slug)

      record ->
        if ImportedHardline.external?(record) do
          detach_external(slug)
        else
          stop_babs_owned(slug)
        end
    end
  end

  defp stop_babs_owned(slug) do
    session = Runner.session_name(slug)

    with :ok <- stop_pane(slug),
         :ok <- stop_tmux_session(session) do
      maybe_mark_stopped(slug)
      :ok
    end
  end

  defp detach_external(slug) do
    with :ok <- stop_pane(slug) do
      maybe_mark_stopped(slug)
      :ok
    end
  end

  defp do_start_registered_citizen(slug, opts) do
    with {:ok, record} <- registered_record(slug) do
      run_start_record(record, opts)
    end
  end

  defp registered_record(slug) do
    case Catalog.get_by_slug(slug) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  defp run_start_record(record, opts) do
    if ImportedHardline.external?(record) do
      run_start_imported(record, opts)
    else
      record
      |> Catalog.to_config()
      |> run_start_config(opts)
    end
  end

  defp run_start_config(config, opts) do
    start = Keyword.get(opts, :start_config, &start_config/1)

    result =
      try do
        start.(config)
      rescue
        error ->
          {:error, {error.__struct__, Exception.message(error)}}
      catch
        kind, reason ->
          {:error, {kind, reason}}
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

  defp do_attach_imported_citizen(slug, target, opts) do
    with {:ok, record} <- registered_record(slug),
         :ok <- ensure_no_active_pane(slug),
         {:ok, pane} <- find_attachable_pane(target, opts),
         {:ok, record} <- Catalog.mark_imported_external(record, pane),
         {:ok, _pid} = ok <- run_start_imported(record, opts) do
      ok
    end
  end

  defp ensure_no_active_pane(slug) do
    case lookup(slug) do
      {:ok, _pid} -> {:error, :active_hardline_exists}
      {:error, :not_found} -> :ok
    end
  end

  defp find_attachable_pane(target, opts) do
    pane_finder =
      Keyword.get(opts, :find_attachable_pane, fn target ->
        TmuxInventory.find_attachable(target, Catalog.list_citizens())
      end)

    pane_finder.(target)
  end

  defp run_start_imported(record, opts) do
    target = ImportedHardline.operational_target(record)

    result =
      with target when is_binary(target) and target != "" <- target,
           true <- imported_target_exists?(target, opts) do
        start_imported_pane(record, target, opts)
      else
        nil -> {:error, :missing_import_target}
        "" -> {:error, :missing_import_target}
        false -> {:error, {:import_target_missing, target}}
      end

    case result do
      {:ok, _pid} = ok ->
        maybe_mark_running(record.slug)
        ok

      {:error, reason} = error ->
        maybe_mark_import_failed(record, reason)
        error
    end
  end

  defp imported_target_exists?(target, opts) do
    target_exists? = Keyword.get(opts, :target_exists?, &TmuxInventory.target_exists?/1)
    target_exists?.(target)
  end

  defp start_imported_pane(record, target, opts) do
    starter = Keyword.get(opts, :start_imported_pane, &start_pane/3)
    attach_session = ImportedHardline.attach_session(record)
    call_start_imported_pane(starter, Catalog.to_config(record), target, attach_session)
  end

  defp call_start_imported_pane(starter, config, target, attach_session) do
    case :erlang.fun_info(starter, :arity) do
      {:arity, 2} -> starter.(config, target)
      {:arity, 3} -> starter.(config, target, attach_session: attach_session)
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

  defp start_pane(config, session, opts \\ []) do
    child = %{
      id: {:hardline_pane, config.slug},
      start: {Pane, :start_link, [[config: config, session: session] ++ opts]},
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

  defp with_slug_lock(slug, opts, fun) do
    case acquire_lock(slug, lock_deadline(opts)) do
      :ok ->
        try do
          fun.()
        after
          Registry.unregister(@lock_registry, slug)
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp acquire_lock(slug, deadline) do
    case Registry.register(@lock_registry, slug, nil) do
      {:ok, _pid} ->
        :ok

      {:error, {:already_registered, _pid}} ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, {:lifecycle_lock_timeout, slug}}
        else
          Process.sleep(10)
          acquire_lock(slug, deadline)
        end
    end
  end

  defp lock_deadline(opts) do
    timeout_ms = Keyword.get(opts, :lock_timeout_ms, 5_000)
    System.monotonic_time(:millisecond) + timeout_ms
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

  defp maybe_mark_import_failed(record, reason) do
    case Catalog.mark_import_attach_failed(record, reason) do
      {:ok, _record} -> :ok
      {:error, _changeset} -> maybe_mark_failed(record.slug, reason)
    end
  end
end
