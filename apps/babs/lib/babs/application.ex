defmodule Babs.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BabsWeb.Endpoint,
      Babs.DevReloader
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Babs.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    BabsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
