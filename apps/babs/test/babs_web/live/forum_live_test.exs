defmodule BabsWeb.ForumLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.{Repo, CitizenRecord}

  @endpoint BabsWeb.Endpoint

  setup do
    ensure_apps!()
    root = tmp_root!()
    previous_root = Application.get_env(:babs_citizens, :tickets_root)
    Application.put_env(:babs_citizens, :tickets_root, root)
    Babs.Citizens.RepoCase.ensure_repo!()
    Repo.delete_all(CitizenRecord)

    on_exit(fn ->
      File.rm_rf!(root)
      Repo.delete_all(CitizenRecord)

      if previous_root do
        Application.put_env(:babs_citizens, :tickets_root, previous_root)
      else
        Application.delete_env(:babs_citizens, :tickets_root)
      end
    end)

    {:ok, root: root}
  end

  test "renders posts list with ticket titles and links to threads", %{root: root} do
    ticket = create_ticket!(root, "Forum Post Alpha", "Post alpha body.")
    _ticket2 = create_ticket!(root, "Forum Post Beta", "Post beta body.")

    {:ok, _view, html} = live(build_conn(), "/forum")

    assert html =~ ~s(data-testid="forum-index")
    assert html =~ "Forum Post Alpha"
    assert html =~ "Forum Post Beta"
    assert html =~ ~s(href="/forum/#{ticket.id}")
  end

  test "renders empty state when no tickets exist" do
    {:ok, _view, html} = live(build_conn(), "/forum")

    assert html =~ ~s(data-testid="forum-index")
  end

  defp create_ticket!(root, title, body, opts \\ []) do
    attrs = Enum.into(opts, %{title: title, body: body})

    api_opts = [
      tickets_root: root,
      date: ~D[2026-06-01],
      now: "2026-06-01T10:00:00Z"
    ]

    {:ok, ticket} = Api.create_ticket(attrs, api_opts)
    ticket
  end

  defp ensure_apps! do
    {:ok, _apps} = Application.ensure_all_started(:babs)
  end

  defp tmp_root! do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-forum-index-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end
end
