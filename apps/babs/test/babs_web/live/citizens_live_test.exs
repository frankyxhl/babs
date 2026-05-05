defmodule BabsWeb.CitizensLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Babs.Citizens.{CitizenRecord, Repo}

  @endpoint BabsWeb.Endpoint

  setup do
    ensure_repo!()
    Repo.delete_all(CitizenRecord)
    :ok
  end

  test "renders empty state with new citizen link" do
    {:ok, _view, html} = live(build_conn(), "/citizens")

    assert html =~ ~s(data-testid="citizens-index")
    assert html =~ ~s(data-testid="citizens-empty-state")
    assert html =~ ~s(href="/citizens/new")
  end

  test "renders sorted citizens, counts, statuses, labels, and token-preserving links" do
    workspace_root = Path.join(tmp_root!(), "workspaces")
    Application.put_env(:babs_citizens, :workspace_root, workspace_root)

    on_exit(fn -> Application.delete_env(:babs_citizens, :workspace_root) end)

    insert_citizen!(%{
      slug: "clare",
      display_name: "Clare",
      cli: "claude",
      cwd: Path.join(workspace_root, "clare"),
      env: %{"SECRET_TOKEN" => "raw-secret-value"}
    })

    insert_citizen!(%{
      slug: "dylan",
      display_name: "Dylan",
      cli: "gh",
      cli_args: ["copilot"],
      cwd: Path.join(workspace_root, "dylan")
    })

    insert_citizen!(%{
      slug: "failed-one",
      display_name: "Failed One",
      status: "failed",
      last_error: "redacted boom"
    })

    insert_citizen!(%{slug: "stopped-one", display_name: "Stopped One", status: "stopped"})
    {:ok, _value} = Registry.register(Babs.Citizens.PaneRegistry, "clare", nil)

    {:ok, _view, html} = live(build_conn(), "/citizens?socket_token=socket-token")

    assert html =~ ~s(data-testid="citizens-count-total")
    assert html =~ "4"
    assert html =~ ~s(data-testid="citizens-count-up")
    assert html =~ ~s(data-testid="citizens-count-reattaching")
    assert html =~ ~s(data-testid="citizens-count-stopped")
    assert html =~ ~s(data-testid="citizens-count-failed")

    assert html =~ ~s(data-testid="citizen-row-clare")
    assert html =~ ~s(data-testid="citizen-status-clare")
    assert html =~ "up"
    assert html =~ "claude"
    assert html =~ "workspaces/clare"
    assert html =~ ~s(data-testid="citizen-row-dylan")
    assert html =~ "copilot-cli"
    assert html =~ "reattaching"
    assert html =~ "stopped"
    assert html =~ "failed"
    assert html =~ "redacted boom"

    refute html =~ "raw-secret-value"
    refute html =~ "SECRET_TOKEN"

    assert ordered?(html, [
             ~s(data-testid="citizen-row-clare"),
             ~s(data-testid="citizen-row-dylan"),
             ~s(data-testid="citizen-row-failed-one"),
             ~s(data-testid="citizen-row-stopped-one")
           ])

    assert html =~ ~s(href="/citizens/new?socket_token=socket-token")
    assert html =~ ~s(href="/citizens/clare?socket_token=socket-token")
    assert html =~ ~s(href="/citizens/clare?full=1&amp;socket_token=socket-token")
    assert html =~ ~s(data-testid="citizen-open-dylan")
    assert html =~ ~s(data-testid="citizen-full-dylan")
    refute html =~ ~s(href="/citizens/dylan?socket_token=socket-token")
    refute html =~ ~s(href="/citizens/dylan?full=1&amp;socket_token=socket-token")
  end

  test "refresh tick reflects status changes" do
    record = insert_citizen!(%{slug: "tick-one", status: "running"})

    {:ok, view, html} = live(build_conn(), "/citizens")
    assert html =~ "reattaching"

    {:ok, _value} = Registry.register(Babs.Citizens.PaneRegistry, record.slug, nil)
    send(view.pid, :refresh_citizens)

    assert render(view) =~ "up"
  end

  defp ensure_repo! do
    {:ok, _apps} = Application.ensure_all_started(:babs)

    Ecto.Migrator.with_repo(Babs.Citizens.Repo, fn repo ->
      Ecto.Migrator.run(repo, Application.app_dir(:babs_citizens, "priv/repo/migrations"), :up,
        all: true
      )
    end)
  end

  defp insert_citizen!(attrs) do
    attrs =
      Map.merge(
        %{
          id: "BAB-CIT-#{System.unique_integer([:positive])}",
          slug: "citizen-#{System.unique_integer([:positive])}",
          display_name: "Test Citizen",
          cwd: tmp_cwd!(),
          cli: "/bin/zsh",
          cli_args: ["-f"],
          env: %{},
          status: "running",
          metadata: %{},
          is_mayor: false
        },
        attrs
      )

    %CitizenRecord{}
    |> CitizenRecord.changeset(attrs)
    |> Repo.insert!()
  end

  defp tmp_root! do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-web-case-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end

  defp tmp_cwd! do
    cwd = Path.join(tmp_root!(), "workspace")
    File.mkdir_p!(cwd)
    cwd
  end

  defp ordered?(text, needles) do
    needles
    |> Enum.map(&(:binary.match(text, &1) |> elem(0)))
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [left, right] -> left < right end)
  end
end
