defmodule Babs.Citizens.DirectCli.Adapter do
  @moduledoc """
  Behaviour for direct Ticket-turn provider adapters.
  """

  alias Babs.Citizens.DirectCli.Command

  @callback provider() :: String.t()
  @callback supports?(map()) :: boolean()
  @callback start_command(map(), String.t(), keyword()) :: {:ok, Command.t()} | {:error, term()}
  @callback resume_command(map(), String.t(), String.t(), keyword()) ::
              {:ok, Command.t()} | {:error, term()}
  @callback parse_result(map(), keyword()) :: {:ok, map()} | {:error, term()}
end
