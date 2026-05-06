defmodule Mix.Tasks.Babs.GateA do
  @moduledoc """
  Runs the Phase 1 scripted sentinel detach/reattach gate.
  """

  use Mix.Task

  alias Babs.Citizens.GateA.Validator

  @shortdoc "Run Phase 1 Gate A sentinel reload validation"
  @requirements ["app.config"]

  @impl true
  def run(_args) do
    with :ok <- start_citizens_app_without_autostart(),
         {:ok, %{session: session, session_id: session_id, pane_pid: pane_pid}} <- Validator.run() do
      Mix.shell().info("Gate A PASS: sentinel survived :babs_citizens restart")
      Mix.shell().info("session=#{session} session_id=#{session_id} pane_pid=#{pane_pid}")
    else
      {:error, reason} ->
        Mix.raise("Gate A failed: #{inspect(reason)}")
    end
  end

  @doc """
  Starts `:babs_citizens` for the sentinel-only gate with autostart disabled.

  This mutates process-local Mix task configuration before application start so
  the gate does not attach every configured AI Citizen.
  """
  def start_citizens_app_without_autostart(starter \\ &Application.ensure_all_started/1) do
    Application.put_env(:babs_citizens, :autostart, false)

    case starter.(:babs_citizens) do
      {:ok, _apps} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
