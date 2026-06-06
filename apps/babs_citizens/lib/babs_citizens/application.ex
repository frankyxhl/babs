defmodule Babs.Citizens.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: Babs.Citizens.PubSub},
        {Registry, keys: :unique, name: Babs.Citizens.PaneRegistry},
        {Registry, keys: :unique, name: Babs.Citizens.SpawnerRegistry},
        {Registry, keys: :unique, name: Babs.Citizens.LifecycleRegistry},
        {Registry, keys: :unique, name: Babs.Citizens.ExecutionLockRegistry},
        {Registry, keys: :unique, name: Babs.Citizens.Knowledge.WriteRegistry},
        {Registry, keys: :unique, name: Babs.Citizens.Tickets.WriterRegistry},
        {Task.Supervisor, name: Babs.Citizens.DirectCli.TaskSupervisor},
        Babs.Citizens.Repo,
        Babs.Citizens.DirectCli.Runner,
        Babs.Citizens.Tickets.WriterSupervisor,
        Babs.Citizens.Tickets.Watcher,
        Babs.Knowledge.Watcher,
        Babs.Citizens.Tickets.ReplyCapture,
        {DynamicSupervisor, strategy: :one_for_one, name: Babs.Citizens.DynamicSupervisor}
      ] ++ reattach_children()

    Supervisor.start_link(children, strategy: :one_for_one, name: Babs.Citizens.Supervisor)
  end

  defp reattach_children do
    if Application.get_env(:babs_citizens, :autostart, true) do
      [Babs.Citizens.Bootstrap]
    else
      []
    end
  end
end
