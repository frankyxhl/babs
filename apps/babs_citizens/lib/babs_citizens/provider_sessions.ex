defmodule Babs.Citizens.ProviderSessions do
  @moduledoc """
  Persistence boundary for direct CLI provider session rows.
  """

  import Ecto.Query, except: [update: 2]

  alias Babs.Citizens.ProviderRuntime.Diagnostics
  alias Babs.Citizens.{ProviderSession, Repo}

  @active_statuses ["active", "non_resumable"]
  @attr_key_map %{
    "id" => :id,
    "citizen_slug" => :citizen_slug,
    "ticket_id" => :ticket_id,
    "provider" => :provider,
    "backend" => :backend,
    "provider_session_id" => :provider_session_id,
    "provider_cli_version" => :provider_cli_version,
    "capabilities" => :capabilities,
    "workspace_ref" => :workspace_ref,
    "cwd_fingerprint" => :cwd_fingerprint,
    "status" => :status,
    "last_turn_id" => :last_turn_id,
    "os_pid" => :os_pid,
    "os_pgid" => :os_pgid,
    "started_at" => :started_at,
    "last_error" => :last_error,
    "metadata" => :metadata
  }

  def get_active(citizen_slug, ticket_id, provider, backend \\ "direct_cli") do
    Repo.one(
      from(session in ProviderSession,
        where:
          session.citizen_slug == ^citizen_slug and session.ticket_id == ^ticket_id and
            session.provider == ^provider and session.backend == ^backend and
            session.status in ^@active_statuses
      )
    )
  end

  def list_for_ticket(ticket_id) when is_binary(ticket_id) do
    Repo.all(
      from(session in ProviderSession,
        where: session.ticket_id == ^ticket_id,
        order_by: [asc: session.citizen_slug, asc: session.provider, asc: session.inserted_at]
      )
    )
  end

  def upsert_active(attrs) when is_map(attrs) do
    attrs = normalize_attrs(attrs)

    case get_active(attrs.citizen_slug, attrs.ticket_id, attrs.provider, attrs.backend) do
      nil -> insert(attrs)
      %ProviderSession{} = session -> update(session, Map.delete(attrs, :id))
    end
  end

  def mark_started(%ProviderSession{} = session, attrs) do
    update(session, %{
      os_pid: Map.get(attrs, :os_pid) || Map.get(attrs, "os_pid"),
      os_pgid: Map.get(attrs, :os_pgid) || Map.get(attrs, "os_pgid"),
      started_at:
        Map.get(attrs, :started_at) || Map.get(attrs, "started_at") || DateTime.utc_now(:second),
      status: "active"
    })
  end

  def mark_finished(%ProviderSession{} = session, attrs \\ %{}) do
    update(
      session,
      %{
        os_pid: nil,
        os_pgid: nil,
        started_at: nil,
        provider_session_id:
          Map.get(attrs, :provider_session_id) || Map.get(attrs, "provider_session_id") ||
            session.provider_session_id,
        provider_cli_version:
          Map.get(attrs, :provider_cli_version) || Map.get(attrs, "provider_cli_version") ||
            session.provider_cli_version,
        capabilities:
          Map.get(attrs, :capabilities) || Map.get(attrs, "capabilities") || session.capabilities,
        last_turn_id:
          Map.get(attrs, :last_turn_id) || Map.get(attrs, "last_turn_id") || session.last_turn_id,
        status: Map.get(attrs, :status) || Map.get(attrs, "status") || "active",
        metadata: Map.get(attrs, :metadata) || Map.get(attrs, "metadata") || session.metadata,
        last_error: nil
      }
    )
  end

  def mark_non_resumable(%ProviderSession{} = session, reason, opts \\ []) do
    update(session, %{
      status: "non_resumable",
      os_pid: nil,
      os_pgid: nil,
      started_at: nil,
      last_error: Diagnostics.summary(reason, opts)
    })
  end

  def mark_failed(%ProviderSession{} = session, reason, opts \\ []) do
    update(session, %{
      status: "failed",
      os_pid: nil,
      os_pgid: nil,
      started_at: nil,
      last_error: Diagnostics.summary(reason, opts)
    })
  end

  def close(%ProviderSession{} = session) do
    update(session, %{status: "closed", os_pid: nil, os_pgid: nil, started_at: nil})
  end

  def mark_stale_in_flight_failed do
    Repo.update_all(
      from(session in ProviderSession,
        where: not is_nil(session.os_pid) or not is_nil(session.started_at)
      ),
      set: [
        status: "failed",
        os_pid: nil,
        os_pgid: nil,
        started_at: nil,
        last_error: "direct execution was in-flight when Babs restarted"
      ]
    )
  end

  defp insert(attrs) do
    %ProviderSession{}
    |> ProviderSession.changeset(Map.put_new(attrs, :id, ProviderSession.generate_id()))
    |> Repo.insert()
  end

  defp update(%ProviderSession{} = session, attrs) do
    session
    |> ProviderSession.changeset(attrs)
    |> Repo.update()
  end

  defp normalize_attrs(attrs) do
    attrs =
      attrs
      |> Map.new(fn {key, value} -> {normalize_key(key), value} end)
      |> Map.put_new(:id, ProviderSession.generate_id())
      |> Map.put_new(:backend, "direct_cli")
      |> Map.put_new(:status, "active")
      |> Map.put_new(:capabilities, %{})
      |> Map.put_new(:metadata, %{})

    workspace_ref =
      Map.get(attrs, :workspace_ref) || "citizen:#{Map.fetch!(attrs, :citizen_slug)}"

    Map.put(
      attrs,
      :workspace_ref,
      safe_workspace_ref(workspace_ref, Map.fetch!(attrs, :citizen_slug))
    )
  end

  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key(key) when is_binary(key), do: Map.get(@attr_key_map, key, key)

  defp safe_workspace_ref(value, slug) when is_binary(value) do
    if Regex.match?(~r{/(Users|home|workspace|tmp|var|private|Volumes)/}, value) do
      "citizen:#{slug}"
    else
      value
    end
  end

  defp safe_workspace_ref(_value, slug), do: "citizen:#{slug}"
end
