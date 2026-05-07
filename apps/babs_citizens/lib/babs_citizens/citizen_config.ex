defmodule Babs.Citizens.CitizenConfig do
  @moduledoc """
  Runtime configuration for one Phase 1 Citizen seed.
  """

  @enforce_keys [:id, :slug, :display_name, :cli, :cwd]
  @type t :: %__MODULE__{
          id: String.t(),
          slug: String.t(),
          display_name: String.t(),
          cli: String.t(),
          cwd: String.t(),
          description: String.t() | nil,
          cli_args: [String.t()],
          launch_profile: String.t(),
          ticket_backend: String.t(),
          env: %{optional(String.t()) => String.t()},
          role: map() | String.t() | nil,
          path: String.t() | nil
        }

  defstruct [
    :id,
    :slug,
    :display_name,
    :cli,
    :cwd,
    :description,
    cli_args: [],
    launch_profile: "safe_interactive",
    ticket_backend: "hardline",
    env: %{},
    role: nil,
    path: nil
  ]
end
