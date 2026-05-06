defmodule Mix.Tasks.Babs.Ticket.New do
  @moduledoc "Create a Ticket through the temporary Phase 7 Mix bridge."

  use Mix.Task

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Error

  @shortdoc "Create a Ticket"
  @requirements ["app.start"]

  @impl true
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [title: :string, body: :string, type: :string, date: :string, now: :string]
      )

    api_opts =
      []
      |> maybe_date(opts[:date])
      |> maybe_put(:now, opts[:now])

    attrs = %{title: opts[:title], body: opts[:body], type: opts[:type] || "assignment"}

    case Api.create_ticket(attrs, api_opts) do
      {:ok, ticket} ->
        Mix.shell().info("#{ticket.id} #{ticket.title}")

      {:error, reason} ->
        Mix.raise(Error.message(reason))
    end
  end

  defp maybe_date(opts, nil), do: opts

  defp maybe_date(opts, value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> Keyword.put(opts, :date, date)
      {:error, _reason} -> Mix.raise("Invalid --date #{inspect(value)}")
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
