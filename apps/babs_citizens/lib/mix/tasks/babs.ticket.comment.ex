defmodule Mix.Tasks.Babs.Ticket.Comment do
  @moduledoc "Append a Ticket comment through the temporary M3 Mix bridge."

  use Mix.Task

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Error

  @shortdoc "Comment on a Ticket"
  @requirements ["app.start"]

  @impl true
  def run(args) do
    with {:ok, id, body, by} <- parse_args(args) do
      case Api.comment_ticket(id, %{body: body, by: by}) do
        {:ok, %{ticket: ticket, delivery: {:comment_notified, []}}} ->
          Mix.shell().info("#{ticket.id} comment stored")
          Mix.shell().info("no assignees to notify")

        {:ok, %{ticket: ticket, delivery: {:comment_notified, slugs}}} ->
          Mix.shell().info("#{ticket.id} comment stored")
          Mix.shell().info("notified #{Enum.join(slugs, ", ")}")

        {:ok, %{ticket: ticket, delivery: {:comment_notification_failed, ok_slugs, failures}}} ->
          Mix.shell().info("#{ticket.id} comment stored")

          if ok_slugs != [] do
            Mix.shell().info("notified #{Enum.join(ok_slugs, ", ")}")
          end

          Mix.shell().info("notification failed for #{failed_slugs(failures)}")

        {:error, reason} ->
          Mix.raise(Error.message(reason))
      end
    else
      :error ->
        Mix.raise(~s(Usage: mix babs.ticket.comment T-YYYY-MM-DD-NNN "comment body" [--by actor]))
    end
  end

  defp parse_args(args) do
    with {:ok, opts, [id, body]} <- parse_args(args, %{}, []) do
      {:ok, id, body, Map.get(opts, :by) || System.get_env("BABS_CITIZEN_SLUG") || "user"}
    else
      :error -> :error
    end
  end

  defp parse_args(["--by", by | rest], opts, []),
    do: parse_args(rest, Map.put(opts, :by, by), [])

  defp parse_args(["--by"], _opts, []), do: :error

  defp parse_args([value | rest], opts, []) do
    if String.starts_with?(value, "--") do
      :error
    else
      parse_args(rest, opts, [value])
    end
  end

  defp parse_args([body | rest], opts, [id]) do
    with {:ok, opts} <- parse_options(rest, opts) do
      {:ok, opts, [id, body]}
    end
  end

  defp parse_args([], _opts, _positional), do: :error

  defp parse_options(["--by", by | rest], opts),
    do: parse_options(rest, Map.put(opts, :by, by))

  defp parse_options(["--by"], _opts), do: :error

  defp parse_options([], opts), do: {:ok, opts}

  defp parse_options(_unknown, _opts), do: :error

  defp failed_slugs(failures) do
    failures
    |> Enum.map(fn {slug, _reason} -> slug end)
    |> Enum.join(", ")
  end
end
