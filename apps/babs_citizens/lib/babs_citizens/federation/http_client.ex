defmodule Babs.Citizens.Federation.HttpClient do
  @moduledoc false

  @callback get(String.t(), keyword()) ::
              {:ok, %{status: pos_integer(), body: binary()}} | {:error, term()}

  @callback request(atom(), String.t(), [{String.t(), String.t()}], binary(), keyword()) ::
              {:ok, %{status: pos_integer(), body: binary()}} | {:error, term()}
end
