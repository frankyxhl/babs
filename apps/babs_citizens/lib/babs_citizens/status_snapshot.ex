defmodule Babs.Citizens.StatusSnapshot do
  @moduledoc """
  Read-only display snapshots for the browser Citizen fleet UI.

  `:reattaching` is a best-effort lifecycle label. It can mean a normal transient
  reattach window or a stale `running` SQLite row until a future heartbeat or
  lifecycle audit exists. Phase 5 intentionally does not map the UI `typing`
  state because this snapshot tracks lifecycle presence, not output activity.
  """

  alias Babs.Citizens.{Catalog, CitizenRecord, ImportedHardline, Lifecycle, TicketBackend}

  @known_cli_labels ~w(claude codex copilot droid pi)

  def list(opts \\ []) do
    lookup = Keyword.get(opts, :lookup, &Lifecycle.lookup/1)
    workspace_root = workspace_root(opts)

    opts
    |> citizen_records()
    |> Enum.map(&from_record(&1, lookup, workspace_root))
  end

  defp citizen_records(opts) do
    if Keyword.get(opts, :include_stale?, false) do
      Catalog.list_citizens()
    else
      opts
      |> Keyword.take([:root, :config_dir])
      |> Catalog.list_configured_or_imported_citizens()
    end
  end

  defp from_record(%CitizenRecord{} = record, lookup, workspace_root) do
    {live_status, visual_state} = status(record, lookup)

    %{
      id: record.id,
      slug: record.slug,
      display_name: record.display_name,
      cli_label: cli_label(record.cli, record.cli_args || []),
      ticket_backend: record.ticket_backend || "hardline",
      ticket_backend_label: TicketBackend.label(record.ticket_backend || "hardline"),
      cwd: record.cwd,
      cwd_label: cwd_label(record.cwd, workspace_root),
      durable_status: record.status,
      live_status: live_status,
      visual_state: visual_state,
      actions: actions(live_status),
      ownership: ImportedHardline.ownership(record),
      imported?: ImportedHardline.external?(record),
      ownership_badge: ImportedHardline.badge(record),
      lifecycle_reminder: ImportedHardline.reminder(record),
      target_label: ImportedHardline.target_label(record),
      last_error: last_error(record)
    }
  end

  defp status(%CitizenRecord{status: "running", slug: slug}, lookup) do
    case lookup.(slug) do
      {:ok, _pid} -> {:up, :idle}
      {:error, :not_found} -> {:reattaching, :waiting}
      {:error, _reason} -> {:reattaching, :waiting}
    end
  end

  defp status(%CitizenRecord{status: "stopped"}, _lookup), do: {:stopped, :paused}
  defp status(%CitizenRecord{status: "failed"}, _lookup), do: {:failed, :dead}
  defp status(_record, _lookup), do: {:failed, :dead}

  defp actions(:up), do: [:open, :full, :stop, :restart]
  defp actions(:reattaching), do: [:start, :stop]
  defp actions(:stopped), do: [:start]
  defp actions(:failed), do: [:start]
  defp actions(_status), do: []

  defp cli_label(cli, ["-f"]) when is_binary(cli) do
    if Path.basename(cli) == "zsh", do: "shell", else: custom_cli_label(cli)
  end

  defp cli_label("gh", ["copilot"]), do: "copilot-cli"
  defp cli_label(cli, _args) when cli in @known_cli_labels, do: cli
  defp cli_label(cli, _args) when is_binary(cli), do: custom_cli_label(cli)
  defp cli_label(_cli, _args), do: "custom"

  defp custom_cli_label(cli) do
    basename = cli |> Path.basename() |> String.trim()

    if basename == "" do
      "custom"
    else
      "#{basename} (custom)"
    end
  end

  defp cwd_label(cwd, workspace_root) when is_binary(cwd) do
    cwd = Path.expand(cwd)
    workspace_root = Path.expand(workspace_root)

    if path_under?(cwd, workspace_root) do
      relative_parts =
        cwd
        |> Path.split()
        |> Enum.drop(length(Path.split(workspace_root)))

      Path.join(["workspaces" | relative_parts])
    else
      ".../#{Path.basename(cwd)}"
    end
  end

  defp cwd_label(_cwd, _workspace_root), do: ""

  defp path_under?(path, root) do
    path_parts = Path.split(path)
    root_parts = Path.split(root)

    Enum.take(path_parts, length(root_parts)) == root_parts
  end

  defp last_error(%CitizenRecord{status: "failed", last_error: last_error}), do: last_error
  defp last_error(_record), do: nil

  defp workspace_root(opts) do
    root =
      opts
      |> Keyword.get(:root, Application.get_env(:babs_citizens, :root, File.cwd!()))
      |> Path.expand()

    case Keyword.get(opts, :workspace_root, Application.get_env(:babs_citizens, :workspace_root)) do
      value when is_binary(value) and value != "" -> Path.expand(value, root)
      _value -> Path.join(root, "workspaces")
    end
  end
end
