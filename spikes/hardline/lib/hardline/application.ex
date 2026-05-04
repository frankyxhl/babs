defmodule Hardline.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Hardline.PubSub},
      {Registry, keys: :unique, name: Hardline.Web.PaneRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Hardline.Web.PaneSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Hardline.Supervisor)
  end
end
