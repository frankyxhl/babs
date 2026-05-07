defmodule Babs.Citizens.DirectCli.Adapters do
  @moduledoc """
  Adapter resolver for supported direct CLI providers.
  """

  alias Babs.Citizens.DirectCli.Adapters.{Claude, Codex, Copilot, Fake}

  @adapters [Claude, Codex, Copilot, Fake]

  def resolve(config, opts \\ []) do
    adapters = Keyword.get(opts, :adapters, @adapters)

    case Enum.find(adapters, & &1.supports?(config)) do
      nil -> {:error, {:unsupported_direct_cli, Path.basename(config.cli || "")}}
      adapter -> {:ok, adapter}
    end
  end
end
