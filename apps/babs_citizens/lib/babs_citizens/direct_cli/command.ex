defmodule Babs.Citizens.DirectCli.Command do
  @moduledoc """
  Command description for non-PTY direct provider execution.
  """

  defstruct provider: nil,
            args: [],
            cwd: nil,
            env: [],
            stdin: nil,
            timeout_ms: 120_000,
            output_limit: 65_536,
            provider_session_id: nil,
            resume?: false
end
