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

  @impl true
  def request(method, url, headers, body, opts \\ [])

  def request(:post, url, headers, body, opts) do
    timeout = Keyword.get(opts, :timeout, 1_500)

    request = {
      String.to_charlist(url),
      httpc_headers(headers),
      ~c"application/json",
      body
    }

    http_opts = [timeout: timeout]
    request_opts = [body_format: :binary]

    case :httpc.request(:post, request, http_opts, request_opts) do
      {:ok, {{_version, status, _reason}, _headers, body}} ->
        {:ok, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def request(:delete, url, headers, _body, opts) do
    timeout = Keyword.get(opts, :timeout, 1_500)

    request = {String.to_charlist(url), httpc_headers(headers)}
    http_opts = [timeout: timeout]
    request_opts = [body_format: :binary]

    case :httpc.request(:delete, request, http_opts, request_opts) do
      {:ok, {{_version, status, _reason}, _headers, body}} ->
        {:ok, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def request(:get, url, _headers, _body, opts), do: get(url, opts)

  def request(method, _url, _headers, _body, _opts), do: {:error, {:unsupported_method, method}}

  defp httpc_headers(headers) do
    Enum.map(headers, fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)
  end
end
