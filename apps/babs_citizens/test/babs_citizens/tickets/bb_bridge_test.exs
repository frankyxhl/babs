defmodule Babs.Citizens.Tickets.BbBridgeTest do
  use ExUnit.Case, async: false

  test "bb ticket comment invokes the Mix bridge with argument-safe argv" do
    root = tmp_root()
    fake_bin = Path.join(root, "fake-bin")
    marker = Path.join(root, "should-not-exist")
    body = "$(touch #{marker}); literal"
    File.mkdir_p!(fake_bin)

    mise_path = Path.join(fake_bin, "mise")

    File.write!(mise_path, """
    #!/bin/sh
    for arg in "$@"; do
      printf '<%s>\\n' "$arg"
    done
    """)

    File.chmod!(mise_path, 0o755)

    {output, 0} =
      System.cmd(bb_path(), ["ticket", "comment", "T-2026-05-06-001", body],
        env: [
          {"BABS_ROOT", root},
          {"BABS_CITIZEN_SLUG", "clare"},
          {"PATH", fake_bin <> ":" <> System.get_env("PATH", "")}
        ],
        stderr_to_stdout: true
      )

    assert output =~ "<exec>"
    assert output =~ "<-->"
    assert output =~ "<mix>"
    assert output =~ "<babs.ticket.comment>"
    assert output =~ "<T-2026-05-06-001>"
    assert output =~ "<#{body}>"
    assert output =~ "<--by>"
    assert output =~ "<clare>"
    refute File.exists?(marker)
  end

  defp bb_path, do: Path.expand("../../../../../bin/bb", __DIR__)

  defp tmp_root do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-bb-bridge-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end
end
