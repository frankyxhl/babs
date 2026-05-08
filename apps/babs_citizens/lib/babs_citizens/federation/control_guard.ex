defmodule Babs.Citizens.Federation.ControlGuard do
  @moduledoc """
  Capability gate for configured remote operator write/control requests.
  """

  alias Babs.Citizens.Citizen.Config, as: CitizenConfig
  alias Babs.Citizens.Federation.Config

  defmodule Auth do
    @moduledoc false
    defstruct [:peer_id, :peer_name, :capability, :target_slug, :actor]
  end

  defmodule Error do
    @moduledoc false
    defstruct [:status, :code, :message, :reason_code, :peer_id, :target_slug]
  end

  @capabilities ~w(read write control)

  @spec authorize(String.t() | nil, String.t(), keyword()) ::
          {:ok, Auth.t()} | {:error, Error.t()}
  def authorize(peer_id, capability, opts \\ []) do
    do_authorize(peer_id, capability, nil, opts)
  end

  @spec authorize_citizen(String.t() | nil, String.t(), String.t(), keyword()) ::
          {:ok, Auth.t()} | {:error, Error.t()}
  def authorize_citizen(peer_id, slug, capability, opts \\ []) do
    if CitizenConfig.valid_slug?(slug) do
      do_authorize(peer_id, capability, slug, opts)
    else
      {:error,
       error(400, "invalid_params", "Remote control target is invalid", "invalid_target",
         peer_id: peer_id,
         target_slug: slug
       )}
    end
  end

  defp do_authorize(peer_id, capability, target_slug, opts) do
    with {:ok, peer_id} <- normalize_peer_id(peer_id),
         {:ok, capability} <- normalize_capability(capability),
         {:ok, config} <- Config.load(opts),
         {:ok, peer} <- find_peer(config, peer_id),
         capabilities <- capabilities_for(peer, target_slug),
         :ok <- require_capability(capabilities, capability, peer_id, target_slug) do
      {:ok,
       %Auth{
         peer_id: peer.id,
         peer_name: peer.name,
         capability: capability,
         target_slug: target_slug,
         actor: "remote:#{peer.id}"
       }}
    else
      {:error, {:config_error, _reason}} ->
        {:error,
         error(503, "config_error", "Federation config is invalid", "config_error",
           peer_id: peer_id,
           target_slug: target_slug
         )}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp normalize_peer_id(peer_id) when is_binary(peer_id) do
    peer_id = String.trim(peer_id)

    cond do
      peer_id == "" ->
        {:error,
         error(403, "missing_peer_id", "Remote peer identity is required", "missing_peer_id")}

      CitizenConfig.valid_slug?(peer_id) ->
        {:ok, peer_id}

      true ->
        {:error,
         error(403, "remote_peer_forbidden", "Remote peer is not allowed", "invalid_peer_id",
           peer_id: peer_id
         )}
    end
  end

  defp normalize_peer_id(_peer_id) do
    {:error, error(403, "missing_peer_id", "Remote peer identity is required", "missing_peer_id")}
  end

  defp normalize_capability(capability) when capability in @capabilities, do: {:ok, capability}

  defp normalize_capability(_capability) do
    {:error,
     error(
       500,
       "control_gate_error",
       "Remote control gate is misconfigured",
       "invalid_capability"
     )}
  end

  defp find_peer(%Config{peers: peers}, peer_id) do
    case Enum.find(peers, &(&1.id == peer_id)) do
      nil ->
        {:error,
         error(403, "remote_peer_forbidden", "Remote peer is not allowed", "unknown_peer",
           peer_id: peer_id
         )}

      peer ->
        {:ok, peer}
    end
  end

  defp capabilities_for(peer, nil), do: peer.capabilities

  defp capabilities_for(peer, target_slug) do
    Map.get(peer.citizens, target_slug, peer.capabilities)
  end

  defp require_capability(capabilities, capability, peer_id, target_slug) do
    if capability in capabilities do
      :ok
    else
      {:error,
       error(
         403,
         "remote_capability_forbidden",
         "Remote peer lacks the required capability",
         "capability_forbidden",
         peer_id: peer_id,
         target_slug: target_slug
       )}
    end
  end

  defp error(status, code, message, reason_code, opts \\ []) do
    %Error{
      status: status,
      code: code,
      message: message,
      reason_code: reason_code,
      peer_id: Keyword.get(opts, :peer_id),
      target_slug: Keyword.get(opts, :target_slug)
    }
  end
end
