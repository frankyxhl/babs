defmodule BabsWeb.EndpointTest do
  use ExUnit.Case, async: true

  test "uses the citizens PubSub so Hardline.Pane broadcasts reach channels" do
    assert BabsWeb.Endpoint.config(:pubsub_server) == Babs.Citizens.PubSub
  end
end
