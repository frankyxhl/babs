defmodule Babs.Citizens.Tickets.WorkspaceResolverTest do
  use Babs.Citizens.RepoCase, async: false

  alias Babs.Citizens.Tickets.Api

  test "resolves a Ticket to its primary assignee workspace", %{test: test} do
    tickets_root = tmp_root!()
    workspace = git_repo!()
    insert_citizen!(%{slug: slug(test, "clare"), cwd: workspace})
    ticket = ticket!(tickets_root, [slug(test, "clare")])

    assert {:ok, resolved} = Api.resolve_workspace(ticket.id, tickets_root: tickets_root)

    assert resolved == %{
             ticket_id: ticket.id,
             assignee: slug(test, "clare"),
             workspace: workspace
           }
  end

  test "unassigned Tickets return a tagged error" do
    tickets_root = tmp_root!()
    ticket = ticket!(tickets_root, [])

    assert Api.resolve_workspace(ticket.id, tickets_root: tickets_root) ==
             {:error, {:no_assignee, ticket.id}}
  end

  test "missing assignee Citizen returns a tagged error", %{test: test} do
    tickets_root = tmp_root!()
    ticket = ticket!(tickets_root, [slug(test, "missing")])

    assert Api.resolve_workspace(ticket.id, tickets_root: tickets_root) ==
             {:error, {:citizen_not_found, slug(test, "missing")}}
  end

  test "blank Citizen cwd returns a tagged error", %{test: test} do
    tickets_root = tmp_root!()
    insert_citizen!(%{slug: slug(test, "clare"), cwd: git_repo!()})
    Repo.update_all(CitizenRecord, set: [cwd: " "])
    ticket = ticket!(tickets_root, [slug(test, "clare")])

    assert Api.resolve_workspace(ticket.id, tickets_root: tickets_root) ==
             {:error, {:no_cwd, slug(test, "clare")}}
  end

  test "non-git workspaces return a tagged error with workspace context", %{test: test} do
    tickets_root = tmp_root!()
    workspace = tmp_root!()
    insert_citizen!(%{slug: slug(test, "clare"), cwd: workspace})
    ticket = ticket!(tickets_root, [slug(test, "clare")])

    assert {:error, {:not_git_repo, details}} =
             Api.resolve_workspace(ticket.id, tickets_root: tickets_root)

    assert details.assignee == slug(test, "clare")
    assert details.workspace == workspace
    assert details.truncated? == false
    assert details.output =~ "not a git repository"
  end

  test "multi-assignee Tickets use the first assignee as primary", %{test: test} do
    tickets_root = tmp_root!()
    first_workspace = git_repo!()
    second_workspace = git_repo!()
    first_slug = slug(test, "alpha")
    second_slug = slug(test, "beta")

    insert_citizen!(%{slug: first_slug, cwd: first_workspace})
    insert_citizen!(%{slug: second_slug, cwd: second_workspace})
    ticket = ticket!(tickets_root, [first_slug, second_slug])

    assert {:ok, resolved} = Api.resolve_workspace(ticket.id, tickets_root: tickets_root)
    assert resolved.assignee == first_slug
    assert resolved.workspace == first_workspace
  end

  defp ticket!(tickets_root, assignees) do
    assert {:ok, ticket} =
             Api.create_ticket(
               %{
                 title: "Review diff",
                 body: "Resolve the workspace for diff review.",
                 assignees: assignees
               },
               tickets_root: tickets_root,
               date: ~D[2026-06-06],
               now: "2026-06-06T00:00:00Z"
             )

    ticket
  end

  defp git_repo! do
    workspace = tmp_root!()
    git!(workspace, ["init"])
    workspace
  end

  defp git!(repo, args) do
    case System.cmd("git", args, cd: repo, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, status} ->
        flunk("git #{Enum.join(args, " ")} failed with #{status}: #{output}")
    end
  end

  defp slug(test, suffix) do
    test
    |> Atom.to_string()
    |> :erlang.phash2(100_000)
    |> then(&"#{suffix}-#{&1}")
  end
end
