defmodule Babs.Citizens.TmuxInventoryTest do
  use Babs.Citizens.RepoCase, async: false

  alias Babs.Citizens.TmuxInventory

  test "parses tab-delimited tmux pane inventory" do
    output =
      "babs-clare\t0\tmain\t0\t%1\tclaude\t/tmp/clare\t1\nexternal\t1\twork\t2\t%9\tzsh\t/tmp/ext\t0\n"

    assert [
             %{
               session_name: "babs-clare",
               window_index: "0",
               window_name: "main",
               pane_index: "0",
               pane_id: "%1",
               target: "babs-clare:0.0",
               current_command: "claude",
               current_path: "/tmp/clare",
               attached?: true
             },
             %{session_name: "external", pane_id: "%9", target: "external:1.2", attached?: false}
           ] = TmuxInventory.parse_panes(output)
  end

  test "classifies Babs-owned, already imported, and attachable panes" do
    imported =
      insert_citizen!(%{
        slug: "imported-one",
        metadata: imported_metadata("external:0.1", "%9")
      })

    panes =
      TmuxInventory.parse_panes("""
      babs-clare\t0\tmain\t0\t%1\tclaude\t/tmp/clare\t1
      external\t0\tmain\t1\t%9\tzsh\t/tmp/imported\t0
      personal\t1\twork\t0\t%10\tzsh\t/tmp/personal\t0
      """)

    classified = TmuxInventory.classify_panes(panes, [imported])

    assert Enum.find(classified, &(&1.pane_id == "%1")).classification == :babs_owned
    assert Enum.find(classified, &(&1.pane_id == "%9")).classification == :imported
    assert Enum.find(classified, &(&1.pane_id == "%10")).classification == :attachable
  end

  test "finds only attachable targets" do
    insert_citizen!(%{slug: "already", metadata: imported_metadata("external:0.1", "%9")})

    output = """
    external\t0\tmain\t1\t%9\tzsh\t/tmp/imported\t0
    personal\t1\twork\t0\t%10\tzsh\t/tmp/personal\t0
    """

    tmux = fn ["list-panes", "-a", "-F", _format] -> {:ok, {output, 0}} end

    assert {:ok, %{pane_id: "%10"}} =
             TmuxInventory.find_attachable("personal:1.0", Babs.Citizens.Catalog.list_citizens(),
               tmux: tmux
             )

    assert {:error, :tmux_pane_not_attachable} =
             TmuxInventory.find_attachable("external:0.1", Babs.Citizens.Catalog.list_citizens(),
               tmux: tmux
             )
  end

  defp imported_metadata(target, pane_id) do
    %{
      "hardline" => %{
        "ownership" => "external",
        "tmux" => %{"target" => target, "pane_id" => pane_id}
      }
    }
  end
end
