defmodule Babs.Citizens.Catalog do
  @moduledoc """
  Persistence boundary for durable Citizen records.
  """

  import Ecto.Query

  require Logger

  alias Babs.Citizens.Citizen.Config, as: TomlConfig
  alias Babs.Citizens.{CitizenConfig, CitizenRecord, ImportedHardline, Repo}

  @sensitive_key_value ~r/("[a-z0-9_]*(?:secret|token)[a-z0-9_]*"|\b[a-z0-9_]*(?:secret|token)[a-z0-9_]*\b)(\s*(?:=>|:)\s*)("[^"]*"|[^\s,\]}]+)/i
  @sensitive_assignment ~r/\b([a-z0-9_]*(?:secret|token)[a-z0-9_]*=)([^\s,\]}]+)/i

  def import_configs(opts \\ []) do
    opts = Keyword.put(opts, :create_cwd, false)

    opts
    |> TomlConfig.list_configs()
    |> Enum.reduce(%{records: [], warnings: [], errors: []}, fn
      {:ok, config}, acc ->
        case import_config(config) do
          {:ok, record, warnings} ->
            %{acc | records: acc.records ++ [record], warnings: acc.warnings ++ warnings}

          {:error, reason} ->
            %{acc | errors: acc.errors ++ [reason]}
        end

      {:error, reason}, acc ->
        %{acc | errors: acc.errors ++ [reason]}
    end)
  end

  def import_config(%CitizenConfig{} = config) do
    case get_by_slug(config.slug) do
      nil -> insert_import(config)
      %CitizenRecord{} = existing -> update_import(existing, config)
    end
  end

  def list_citizens do
    Repo.all(from(citizen in CitizenRecord, order_by: [asc: citizen.slug]))
  end

  def get_by_slug(slug) when is_binary(slug) do
    Repo.get_by(CitizenRecord, slug: slug)
  end

  def insert_new(%CitizenConfig{} = config) do
    attrs =
      config
      |> config_attrs()
      |> Map.put(:status, "running")
      |> Map.put(:metadata, %{})
      |> Map.put(:is_mayor, false)

    %CitizenRecord{}
    |> CitizenRecord.changeset(attrs)
    |> Repo.insert()
  end

  def merge_import(%CitizenRecord{} = existing, %CitizenConfig{} = incoming) do
    warnings =
      if existing.id != incoming.id do
        warning = {:id_mismatch, existing.slug, existing.id, incoming.id}
        Logger.warning("Babs citizen #{existing.slug} TOML id mismatch; preserving SQLite id")
        [warning]
      else
        []
      end

    spawn_attrs =
      if existing.status in ["stopped", "failed"] do
        %{
          cli: incoming.cli,
          cli_args: incoming.cli_args,
          env: incoming.env
        }
      else
        %{
          cli: existing.cli,
          cli_args: existing.cli_args,
          env: existing.env
        }
      end

    attrs =
      %{
        id: existing.id,
        slug: existing.slug,
        display_name: incoming.display_name,
        description: incoming.description,
        cwd: existing.cwd,
        status: existing.status,
        metadata: existing.metadata || %{},
        role: incoming.role,
        is_mayor: existing.is_mayor || false,
        last_error: existing.last_error
      }
      |> Map.merge(spawn_attrs)

    {attrs, warnings}
  end

  def mark_running(slug_or_record), do: update_status(slug_or_record, "running", nil)

  def mark_stopped(slug_or_record), do: update_status(slug_or_record, "stopped", nil)

  def mark_failed(slug_or_record, reason),
    do: update_status(slug_or_record, "failed", redact_reason(reason))

  def mark_imported_external(%CitizenRecord{} = record, pane, opts \\ []) when is_map(pane) do
    now = Keyword.get(opts, :now, DateTime.utc_now(:second))
    metadata = ImportedHardline.put_external(record.metadata || %{}, pane, now)

    record
    |> CitizenRecord.changeset(%{metadata: metadata, status: "running", last_error: nil})
    |> Repo.update()
  end

  def mark_import_attach_failed(%CitizenRecord{} = record, reason) do
    metadata =
      record.metadata
      |> Kernel.||(%{})
      |> ImportedHardline.put_last_attach_error(redact_reason(reason))

    record
    |> CitizenRecord.changeset(%{
      metadata: metadata,
      status: "failed",
      last_error: redact_reason(reason)
    })
    |> Repo.update()
  end

  def redact_reason(reason) do
    reason
    |> inspect()
    |> String.replace(@sensitive_key_value, "\\1\\2[REDACTED]")
    |> String.replace(@sensitive_assignment, "\\1[REDACTED]")
    |> String.slice(0, 2_000)
  end

  def to_config(%CitizenRecord{} = record) do
    %CitizenConfig{
      id: record.id,
      slug: record.slug,
      display_name: record.display_name,
      description: record.description,
      cli: record.cli,
      cli_args: record.cli_args || [],
      cwd: record.cwd,
      env: record.env || %{},
      role: record.role,
      path: nil
    }
  end

  defp insert_import(%CitizenConfig{} = config) do
    with :ok <- File.mkdir_p(config.cwd) do
      attrs =
        config
        |> config_attrs()
        |> Map.put(:status, "running")
        |> Map.put(:metadata, %{})
        |> Map.put(:is_mayor, false)

      %CitizenRecord{}
      |> CitizenRecord.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, record} -> {:ok, record, []}
        {:error, changeset} -> {:error, changeset}
      end
    else
      {:error, reason} -> {:error, {:cwd_mkdir_failed, config.cwd, reason}}
    end
  end

  defp update_import(%CitizenRecord{} = existing, %CitizenConfig{} = config) do
    {attrs, warnings} = merge_import(existing, config)

    existing
    |> CitizenRecord.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, record} -> {:ok, record, warnings}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp config_attrs(%CitizenConfig{} = config) do
    %{
      id: config.id,
      slug: config.slug,
      display_name: config.display_name,
      description: config.description,
      cwd: config.cwd,
      cli: config.cli,
      cli_args: config.cli_args || [],
      env: config.env || %{},
      role: config.role
    }
  end

  defp update_status(slug_or_record, status, last_error) do
    case fetch_record(slug_or_record) do
      {:ok, record} ->
        record
        |> CitizenRecord.changeset(%{status: status, last_error: last_error})
        |> Repo.update()

      {:error, :not_found} = error ->
        error
    end
  end

  defp fetch_record(%CitizenRecord{} = record), do: {:ok, record}

  defp fetch_record(slug) when is_binary(slug) do
    case get_by_slug(slug) do
      %CitizenRecord{} = record -> {:ok, record}
      nil -> {:error, :not_found}
    end
  end
end
