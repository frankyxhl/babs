defmodule Babs.Citizens.Tickets.TicketMarkdownTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.Tickets.TicketMarkdown

  @id "T-2026-05-06-001"

  test "parses strict frontmatter and renders a round-trip markdown ticket" do
    path = Path.join(tmp_root(), "#{@id}.md")

    assert {:ok, ticket} =
             sample_markdown()
             |> TicketMarkdown.parse(path: path, known_citizens: ["clare"])

    assert ticket.id == @id
    assert ticket.title == "Wire ticket storage"
    assert ticket.body == "Build the storage layer first."
    assert ticket.assignees == []
    assert ticket.metadata == %{"source" => "test"}
    assert ticket.warnings == []

    rendered = TicketMarkdown.render(ticket)
    assert {:ok, reparsed} = TicketMarkdown.parse(rendered, path: path, known_citizens: ["clare"])
    assert reparsed.id == ticket.id
    assert reparsed.title == ticket.title
    assert reparsed.body == ticket.body
  end

  test "unknown assignees are warnings before Phase 9" do
    content = sample_markdown("assignees: [clare, ghost]\nstate: in_progress\n")

    assert {:ok, ticket} =
             TicketMarkdown.parse(content,
               path: Path.join(tmp_root(), "#{@id}.md"),
               known_citizens: ["clare"]
             )

    assert {:unknown_citizen, "ghost"} in ticket.warnings
  end

  test "rejects unknown top-level frontmatter keys" do
    content =
      String.replace(sample_markdown(), "metadata: {source: test}", "metadata: {}\nextra: nope")

    assert {:error, {:invalid_frontmatter, {:unknown_keys, ["extra"]}}} =
             TicketMarkdown.parse(content, path: Path.join(tmp_root(), "#{@id}.md"))
  end

  test "rejects file stem and frontmatter id mismatch" do
    assert {:error, {:invalid_frontmatter, {:id_mismatch, @id, "T-2026-05-06-002"}}} =
             TicketMarkdown.parse(sample_markdown(),
               path: Path.join(tmp_root(), "T-2026-05-06-002.md")
             )
  end

  test "enforces billboard state invariant for empty assignees" do
    content = sample_markdown("assignees: []\nstate: in_progress\n")

    assert {:error, {:invalid_frontmatter, {:invalid_billboard_state, "in_progress"}}} =
             TicketMarkdown.parse(content, path: Path.join(tmp_root(), "#{@id}.md"))
  end

  test "requires first markdown H1 and body content" do
    no_h1 =
      String.replace(sample_markdown(), "# Wire ticket storage\n\n", "Wire ticket storage\n\n")

    only_h1 =
      String.replace(
        sample_markdown(),
        "# Wire ticket storage\n\nBuild the storage layer first.\n",
        "# Wire ticket storage\n\n"
      )

    assert {:error, {:invalid_frontmatter, :missing_title}} =
             TicketMarkdown.parse(no_h1, path: Path.join(tmp_root(), "#{@id}.md"))

    assert {:error, {:invalid_frontmatter, :empty_body}} =
             TicketMarkdown.parse(only_h1, path: Path.join(tmp_root(), "#{@id}.md"))
  end

  defp sample_markdown(overrides \\ "assignees: []\nstate: open\n") do
    """
    ---
    id: #{@id}
    type: assignment
    #{overrides}assigner: user
    assignee_role: null
    inspector: user
    priority: normal
    parent_ticket: null
    created_at: 2026-05-06T00:00:00Z
    updated_at: 2026-05-06T00:00:00Z
    metadata: {source: test}
    ---

    # Wire ticket storage

    Build the storage layer first.
    """
  end

  defp tmp_root do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-ticket-markdown-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end
end
