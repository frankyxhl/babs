defmodule Babs.Citizens.Federation.HttpClient do
  @moduledoc false

  @callback get(String.t(), keyword()) ::
              {:ok, %{status: pos_integer(), body: binary()}} | {:error, term()}
end
