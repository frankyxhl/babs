defmodule BabsWeb.Api.V1.Presenter do
  @moduledoc false

  @citizen_projection_keys [
    "id",
    "slug",
    "display_name",
    "cli_label",
    "roles",
    "ticket_backend",
    "ticket_backend_label",
    "cwd_label",
    "durable_status",
    "live_status",
    "visual_state",
    "actions",
    "provider_runtime",
    "provider_runtime_capabilities",
    "interactive_attach",
    "kill_authority",
    "detach_authority",
    "ownership",
    "imported",
    "ownership_badge",
    "lifecycle_reminder"
  ]

  @ticket_summary_keys [
    :id,
    :type,
    :state,
    :assigner,
    :assignees,
    :assignee_role,
    :inspector,
    :priority,
    :parent_ticket,
    :created_at,
    :updated_at,
    :metadata,
    :title
  ]

  def node_summary(%{"node" => node}), do: Map.take(node, ["id", "name"])

  def citizen_projection(snapshot) do
    values = %{
      "id" => snapshot.id,
      "slug" => snapshot.slug,
      "display_name" => snapshot.display_name,
      "cli_label" => snapshot.cli_label,
      "roles" => role_names(snapshot.roles),
      "ticket_backend" => snapshot.ticket_backend,
      "ticket_backend_label" => snapshot.ticket_backend_label,
      "cwd_label" => snapshot.cwd_label,
      "durable_status" => snapshot.durable_status,
      "live_status" => string_value(snapshot.live_status),
      "visual_state" => string_value(snapshot.visual_state),
      "actions" => Enum.map(snapshot.actions || [], &string_value/1),
      "provider_runtime" => safe_provider_runtime(snapshot.provider_runtime),
      "provider_runtime_capabilities" => snapshot.provider_runtime_capabilities || %{},
      "interactive_attach" => Map.get(snapshot, :interactive_attach?),
      "kill_authority" => Map.get(snapshot, :kill_authority?),
      "detach_authority" => Map.get(snapshot, :detach_authority?),
      "ownership" => snapshot.ownership,
      "imported" => Map.get(snapshot, :imported?),
      "ownership_badge" => snapshot.ownership_badge,
      "lifecycle_reminder" => snapshot.lifecycle_reminder
    }

    Map.new(@citizen_projection_keys, &{&1, Map.get(values, &1)})
  end

  def ticket_summary(ticket) do
    Map.new(@ticket_summary_keys, fn key -> {Atom.to_string(key), Map.get(ticket, key)} end)
  end

  def ticket_detail(ticket) do
    ticket
    |> ticket_summary()
    |> Map.put("body", ticket.body)
  end

  def safe_history(history) when is_list(history) do
    Enum.map(history, fn
      event when is_map(event) -> Map.drop(event, ["path", "warnings"])
      event -> event
    end)
  end

  def safe_history(_history), do: []

  def json_safe_output(output) when is_binary(output) do
    if String.valid?(output) do
      output
    else
      replace_invalid_utf8(output, [])
    end
  end

  def json_safe_output(_output), do: ""

  defp role_names(roles) when is_list(roles) do
    Enum.flat_map(roles, fn
      %{"name" => name} when is_binary(name) -> [name]
      %{name: name} when is_binary(name) -> [name]
      value when is_binary(value) -> [value]
      _value -> []
    end)
  end

  defp role_names(_roles), do: []

  defp safe_provider_runtime(runtime) when is_map(runtime) do
    %{
      "provider" => map_value(runtime, :provider),
      "backend" => map_value(runtime, :backend),
      "ownership" => map_value(runtime, :ownership),
      "status" => map_value(runtime, :status)
    }
  end

  defp safe_provider_runtime(_runtime) do
    %{"provider" => nil, "backend" => nil, "ownership" => nil, "status" => nil}
  end

  defp map_value(map, key) do
    if Map.has_key?(map, key) do
      Map.get(map, key)
    else
      Map.get(map, Atom.to_string(key))
    end
  end

  defp string_value(value) when is_atom(value), do: Atom.to_string(value)
  defp string_value(value) when is_binary(value), do: value
  defp string_value(value), do: value

  defp replace_invalid_utf8("", acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp replace_invalid_utf8(binary, acc) do
    case :unicode.characters_to_binary(binary, :utf8, :utf8) do
      valid when is_binary(valid) ->
        [valid | acc]
        |> Enum.reverse()
        |> IO.iodata_to_binary()

      {:error, valid, <<_bad_byte, rest::binary>>} ->
        replace_invalid_utf8(rest, [<<0xEF, 0xBF, 0xBD>>, valid | acc])

      {:incomplete, valid, _rest} ->
        [<<0xEF, 0xBF, 0xBD>>, valid | acc]
        |> Enum.reverse()
        |> IO.iodata_to_binary()
    end
  end
end
