defmodule Mix.Tasks.Babs.GateA do
  @moduledoc """
  Runs the Phase 1 scripted sentinel detach/reattach gate.
  """

  use Mix.Task

  alias Babs.Citizens.GateA.Validator

  @shortdoc "Run Phase 1 Gate A sentinel reload validation"
  @requirements ["app.start"]

  @impl true
  def run(_args) do
    case Validator.run() do
      {:ok, %{session: session, session_id: session_id, pane_pid: pane_pid}} ->
        Mix.shell().info("Gate A PASS: sentinel survived :babs_citizens restart")
        Mix.shell().info("session=#{session} session_id=#{session_id} pane_pid=#{pane_pid}")

      {:error, reason} ->
        Mix.raise("Gate A failed: #{inspect(reason)}")
    end
  end
end
