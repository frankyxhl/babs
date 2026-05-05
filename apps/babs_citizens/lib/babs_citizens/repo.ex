defmodule Babs.Citizens.Repo do
  @moduledoc """
  SQLite repository for durable Citizen registry state.
  """

  use Ecto.Repo,
    otp_app: :babs_citizens,
    adapter: Ecto.Adapters.SQLite3
end
