defmodule Babs.Citizens.ImportedHardlineTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.ImportedHardline

  test "missing metadata defaults to Babs ownership" do
    refute ImportedHardline.external?(%{})
    assert ImportedHardline.ownership(%{}) == "babs"
    assert ImportedHardline.badge(%{}) == nil
  end

  test "stores external tmux target metadata with operator-facing labels" do
    pane = %{
      session_name: "external-work",
      window_index: "0",
      window_name: "main",
      pane_index: "1",
      pane_id: "%42",
      target: "external-work:0.1",
      current_command: "claude",
      current_path: "/tmp/project",
      attached?: false
    }

    metadata = ImportedHardline.put_external(%{"seed" => true}, pane, ~U[2026-05-06 00:00:00Z])

    assert ImportedHardline.external?(metadata)
    assert ImportedHardline.ownership(metadata) == "external"
    assert ImportedHardline.badge(metadata) == "Imported · External-owned"
    assert ImportedHardline.reminder(metadata) == "Detach only · tmux stays running"
    assert ImportedHardline.target(metadata) == "external-work:0.1"
    assert ImportedHardline.pane_id(metadata) == "%42"
    assert ImportedHardline.operational_target(metadata) == "%42"
    assert ImportedHardline.attach_session(metadata) == "external-work"
    assert ImportedHardline.target_label(metadata) == "external-work:0.1"
    assert metadata["hardline"]["imported_at"] == "2026-05-06T00:00:00Z"
    assert metadata["seed"] == true
  end
end
