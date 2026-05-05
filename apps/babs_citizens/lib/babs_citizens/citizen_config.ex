defmodule Babs.Citizens.CitizenConfig do
  @moduledoc """
  Runtime configuration for one Phase 1 Citizen seed.
  """

  @enforce_keys [:id, :slug, :display_name, :cli, :cwd]
  defstruct [
    :id,
    :slug,
    :display_name,
    :cli,
    :cwd,
    :description,
    cli_args: [],
    env: %{},
    role: nil,
    path: nil
  ]
end
