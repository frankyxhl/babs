defmodule Babs.DevReloaderTest do
  use ExUnit.Case, async: true

  alias Babs.DevReloader

  test "matches Elixir source changes under the watched citizens path" do
    watch_path = "/repo/apps/babs_citizens/lib"

    assert DevReloader.watched_elixir_file?(
             "/repo/apps/babs_citizens/lib/babs_citizens/hardline/pane.ex",
             [:modified],
             watch_path
           )

    refute DevReloader.watched_elixir_file?(
             "/repo/apps/babs/lib/babs_web/router.ex",
             [:modified],
             watch_path
           )

    refute DevReloader.watched_elixir_file?(
             "/repo/apps/babs_citizens/lib/babs_citizens/readme.md",
             [:modified],
             watch_path
           )
  end
end
