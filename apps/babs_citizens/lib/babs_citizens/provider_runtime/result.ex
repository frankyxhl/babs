defmodule Babs.Citizens.ProviderRuntime.Result do
  @moduledoc """
  Provider runtime result helpers.

  Phase 13f.2 starts with direct CLI success results and preserves legacy keys
  while exposing the normalized provider runtime shape.
  """

  @direct_backend "direct_cli"
  @default_diagnostics %{redacted: true, summary: nil}

  def direct_success(provider, reply, opts \\ []) when is_binary(provider) and is_binary(reply) do
    capabilities = Keyword.get(opts, :capabilities, %{"direct" => true})

    %{
      status: :ok,
      provider: provider,
      backend: @direct_backend,
      provider_session_id: Keyword.get(opts, :provider_session_id),
      reply: reply,
      text: reply,
      diagnostics: Keyword.get(opts, :diagnostics, @default_diagnostics),
      capabilities: capabilities,
      raw_artifact_refs: []
    }
  end
end
