defmodule Babs.Citizens.Federation.HttpcClient do
  @moduledoc false

  @behaviour Babs.Citizens.Federation.HttpClient

  @impl true
  def get(url, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1_500)

    request = {String.to_charlist(url), []}
    http_opts = [timeout: timeout]
    request_opts = [body_format: :binary]

    case :httpc.request(:get, request, http_opts, request_opts) do
      {:ok, {{_version, status, _reason}, _headers, body}} ->
        {:ok, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
