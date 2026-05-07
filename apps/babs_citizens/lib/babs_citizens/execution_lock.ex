defmodule Babs.Citizens.ExecutionLock do
  @moduledoc """
  Per-Citizen execution lock shared by Hardline and direct CLI delivery.
  """

  @registry Babs.Citizens.ExecutionLockRegistry

  def with_lock(slug, fun) when is_binary(slug) and is_function(fun, 0) do
    case Registry.register(@registry, slug, nil) do
      {:ok, _pid} ->
        try do
          fun.()
        after
          Registry.unregister(@registry, slug)
        end

      {:error, {:already_registered, _pid}} ->
        {:error, {:execution_busy, slug}}
    end
  end
end
