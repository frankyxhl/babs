defmodule BabsWeb.NewTicketLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Babs.Citizens.{CitizenRecord, Repo}
  alias Babs.Citizens.Tickets.Api

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

  test "new ticket form defaults to human approval metadata", %{root: root} do
    {:ok, view, html} = live(build_conn(), "/tickets/new?socket_token=token-1")

    assert html =~ ~s(data-testid="new-ticket-inspection-fields")
    assert html =~ ~s(data-testid="ticket-inspection-mode")
    refute html =~ ~s(data-testid="ticket-auto-inspection-controls")

    assert {:error, {:redirect, %{to: to}}} =
             view
             |> form("[data-testid='new-ticket-form']",
               ticket: %{
                 title: "Human approval ticket",
                 body: "Keep the default human approval path.",
                 priority: "normal"
               }
             )
             |> render_submit()

    id = redirected_ticket_id(to)
    assert {:ok, %{ticket: ticket}} = Api.show_ticket(id, tickets_root: root)
    assert ticket.metadata == %{}
  end

  test "new ticket form creates auto inspection metadata from known inspectors", %{root: root} do
    with_role_catalog(fn config_root ->
      Babs.Citizens.RepoCase.write_citizen_toml!(config_root, "dylan")

      Babs.Citizens.RepoCase.insert_citizen!(%{
        slug: "dylan",
        display_name: "Dylan",
        roles: ["inspector"]
      })

      {:ok, view, html} = live(build_conn(), "/tickets/new?socket_token=token-1")
      assert html =~ ~s(value="inspector")

      html =
        view
        |> form("[data-testid='new-ticket-form']",
          ticket: %{
            title: "Auto inspection ticket",
            body: "Ask inspector citizens.",
            priority: "high",
            inspection_mode: "auto"
          }
        )
        |> render_change()

      assert html =~ ~s(data-testid="ticket-auto-inspection-controls")
      assert html =~ "Dylan"

      assert {:error, {:redirect, %{to: to}}} =
               view
               |> form("[data-testid='new-ticket-form']",
                 ticket: %{
                   title: "Auto inspection ticket",
                   body: "Ask inspector citizens.",
                   priority: "high",
                   inspection_mode: "auto",
                   inspection_strategy: "council",
                   inspection_role: "inspector",
                   inspection_citizen: "dylan",
                   inspection_max_inspectors: "2"
                 }
               )
               |> render_submit()

      id = redirected_ticket_id(to)
      assert {:ok, %{ticket: ticket}} = Api.show_ticket(id, tickets_root: root)

      assert ticket.metadata["inspection"] == %{
               "mode" => "auto",
               "strategy" => "council",
               "roles" => ["inspector"],
               "citizens" => ["dylan"],
               "quorum" => "all_pass",
               "max_inspectors" => 2,
               "allow_self_inspection" => false
             }
    end)
  end

  test "new ticket form validates auto inspection candidates" do
    {:ok, view, _html} = live(build_conn(), "/tickets/new")

    params = %{
      title: "Missing inspector",
      body: "Auto inspection requires a target.",
      priority: "normal",
      inspection_mode: "auto",
      inspection_strategy: "single",
      inspection_role: "",
      inspection_citizen: "",
      inspection_max_inspectors: "1"
    }

    view
    |> form("[data-testid='new-ticket-form']",
      ticket: Map.take(params, [:title, :body, :priority, :inspection_mode])
    )
    |> render_change()

    html =
      view
      |> form("[data-testid='new-ticket-form']", ticket: params)
      |> render_submit()

    assert html =~ ~s(data-testid="inspection-error")
    assert html =~ "Choose an inspector role or citizen"
  end

  defp redirected_ticket_id(to) do
    to
    |> URI.parse()
    |> Map.fetch!(:path)
    |> Path.basename()
  end

  defp ensure_apps! do
    {:ok, _apps} = Application.ensure_all_started(:babs)
  end

  defp tmp_root! do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-new-ticket-web-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end

  defp with_role_catalog(fun) do
    config_root = Babs.Citizens.RepoCase.tmp_root!()
    previous_root = Application.get_env(:babs_citizens, :root)
    Application.put_env(:babs_citizens, :root, config_root)

    try do
      fun.(config_root)
    after
      File.rm_rf!(config_root)

      if previous_root do
        Application.put_env(:babs_citizens, :root, previous_root)
      else
        Application.delete_env(:babs_citizens, :root)
      end
    end
  end
end
