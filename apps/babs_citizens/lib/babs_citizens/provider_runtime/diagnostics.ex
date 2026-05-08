defmodule Babs.Citizens.ProviderRuntime.Diagnostics do
  @moduledoc """
  Standardized direct provider failure diagnostics.

  Diagnostics are intentionally summaries, not raw provider output. Raw stdout,
  stderr, local paths, private IPs, and configured secret values must stay out of
  persisted ticket events and provider session rows.
  """

  alias Babs.Citizens.DirectCli.Redactor

  @summary_limit 2_000

  def failure(reason, opts \\ []) do
    status = status(reason)

    %{
      redacted: true,
      summary: summary(reason, opts),
      category: category(status),
      raw_included: false
    }
  end

  def status(:failed), do: :failed
  def status(:timeout), do: :timeout
  def status(:cancelled), do: :cancelled
  def status(:unsupported), do: :unsupported
  def status(:direct_runner_startup_timeout), do: :timeout
  def status({:timeout, _context}), do: :timeout
  def status({:exit_status, _status}), do: :failed
  def status({:exit_status, _status, _artifacts}), do: :failed
  def status({:unsupported_direct_cli, _provider}), do: :unsupported
  def status({:executable_not_found, _executable}), do: :unsupported
  def status(:invalid_command_args), do: :unsupported
  def status({:executor_exit, :normal}), do: :cancelled
  def status(_reason), do: :failed

  def category(status) when status in [:failed, :timeout, :cancelled, :unsupported],
    do: Atom.to_string(status)

  def category(reason), do: reason |> status() |> category()

  def summary(reason, opts \\ [])

  def summary(:timeout, _opts), do: "provider execution timed out"
  def summary(:direct_runner_startup_timeout, _opts), do: "provider execution timed out"
  def summary({:timeout, _context}, _opts), do: "provider execution timed out"
  def summary(:cancelled, _opts), do: "provider execution was cancelled"
  def summary(:no_assistant_reply, _opts), do: "provider did not produce an assistant reply"
  def summary({:exit_status, status}, _opts), do: "provider exited with status #{status}"

  def summary({:exit_status, status, _artifacts}, _opts),
    do: "provider exited with status #{status}"

  def summary({:unsupported_direct_cli, provider}, opts),
    do: redact("direct CLI provider is unsupported: #{provider}", opts)

  def summary({:executable_not_found, executable}, opts),
    do: redact("provider executable was not found: #{executable}", opts)

  def summary(:invalid_command_args, _opts), do: "provider command arguments were invalid"

  def summary(reason, opts),
    do: reason |> inspect(limit: 20, printable_limit: @summary_limit) |> redact(opts)

  defp redact(value, opts) do
    value
    |> Redactor.redact_text(opts)
    |> Redactor.bound_output(@summary_limit)
  end
end
