defmodule Babs.Citizens.ImportedHardline do
  @moduledoc """
  Helpers for externally owned imported Hardline metadata.
  """

  @hardline_key "hardline"
  @tmux_key "tmux"
  @external "external"
  @babs "babs"

  def ownership(%{metadata: metadata}), do: ownership(metadata)

  def ownership(metadata) when is_map(metadata),
    do: get_in(metadata, [@hardline_key, "ownership"]) || @babs

  def ownership(_metadata), do: @babs

  def external?(record_or_metadata), do: ownership(record_or_metadata) == @external

  def badge(%{metadata: metadata}), do: badge(metadata)

  def badge(metadata) when is_map(metadata),
    do: if(external?(metadata), do: "Imported · External-owned", else: nil)

  def badge(_metadata), do: nil

  def reminder(%{metadata: metadata}), do: reminder(metadata)

  def reminder(metadata) when is_map(metadata),
    do: if(external?(metadata), do: "Detach only · tmux stays running", else: nil)

  def reminder(_metadata), do: nil

  def target(%{metadata: metadata}), do: target(metadata)

  def target(metadata) when is_map(metadata) do
    case get_in(metadata, [@hardline_key, @tmux_key]) do
      %{} = tmux ->
        tmux["target"] || tmux["pane_id"] || tmux["session_name"]

      _value ->
        nil
    end
  end

  def target(_metadata), do: nil

  def pane_id(%{metadata: metadata}), do: pane_id(metadata)

  def pane_id(metadata) when is_map(metadata) do
    get_in(metadata, [@hardline_key, @tmux_key, "pane_id"])
  end

  def pane_id(_metadata), do: nil

  def operational_target(%{metadata: metadata}), do: operational_target(metadata)

  def operational_target(metadata) when is_map(metadata) do
    case get_in(metadata, [@hardline_key, @tmux_key]) do
      %{} = tmux ->
        tmux["pane_id"] || tmux["target"] || tmux["session_name"]

      _value ->
        nil
    end
  end

  def operational_target(_metadata), do: nil

  def attach_session(%{metadata: metadata}), do: attach_session(metadata)

  def attach_session(metadata) when is_map(metadata) do
    case get_in(metadata, [@hardline_key, @tmux_key]) do
      %{} = tmux ->
        tmux["session_id"] || tmux["session_name"] || tmux["target"] || tmux["pane_id"]

      _value ->
        nil
    end
  end

  def attach_session(_metadata), do: nil

  def target_label(%{metadata: metadata}), do: target_label(metadata)

  def target_label(metadata) when is_map(metadata) do
    case get_in(metadata, [@hardline_key, @tmux_key]) do
      %{} = tmux ->
        [tmux["session_name"], tmux["window_index"], tmux["pane_index"]]
        |> Enum.reject(&blank?/1)
        |> case do
          [session, window, pane] -> "#{session}:#{window}.#{pane}"
          [session] -> session
          _parts -> target(metadata)
        end

      _value ->
        nil
    end
  end

  def target_label(_metadata), do: nil

  def current_command(%{metadata: metadata}),
    do: get_in(metadata || %{}, [@hardline_key, @tmux_key, "current_command"])

  def current_path(%{metadata: metadata}),
    do: get_in(metadata || %{}, [@hardline_key, @tmux_key, "current_path"])

  def put_external(metadata, pane, now \\ DateTime.utc_now(:second)) when is_map(metadata) do
    hardline =
      metadata
      |> Map.get(@hardline_key, %{})
      |> Map.merge(%{
        "ownership" => @external,
        "imported_at" => DateTime.to_iso8601(now),
        "last_attach_error" => nil,
        @tmux_key => tmux_metadata(pane)
      })

    Map.put(metadata, @hardline_key, hardline)
  end

  def put_last_attach_error(metadata, reason) when is_map(metadata) do
    reason = if is_binary(reason), do: reason, else: inspect(reason)

    update_in(metadata, [Access.key(@hardline_key, %{}), "last_attach_error"], fn _old ->
      reason
    end)
  end

  defp tmux_metadata(pane) when is_map(pane) do
    %{
      "session_name" => Map.get(pane, :session_name),
      "window_index" => Map.get(pane, :window_index),
      "window_name" => Map.get(pane, :window_name),
      "pane_index" => Map.get(pane, :pane_index),
      "pane_id" => Map.get(pane, :pane_id),
      "target" => Map.get(pane, :target) || target_from_pane(pane),
      "current_command" => Map.get(pane, :current_command),
      "current_path" => Map.get(pane, :current_path),
      "attached" => Map.get(pane, :attached?, false)
    }
  end

  defp target_from_pane(pane) do
    case {Map.get(pane, :session_name), Map.get(pane, :window_index), Map.get(pane, :pane_index)} do
      {session, window, pane_index}
      when is_binary(session) and is_binary(window) and is_binary(pane_index) ->
        "#{session}:#{window}.#{pane_index}"

      _other ->
        Map.get(pane, :pane_id) || Map.get(pane, :session_name)
    end
  end

  defp blank?(value), do: value in [nil, ""]
end
