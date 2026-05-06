defmodule BabsWeb.AttachCitizenLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Babs.Citizens.CitizenRecord

  @endpoint BabsWeb.Endpoint

  setup do
    {:ok, _apps} = Application.ensure_all_started(:babs)
    previous = Application.get_env(:babs, BabsWeb.AttachCitizenLive)

    on_exit(fn ->
      if previous do
        Application.put_env(:babs, BabsWeb.AttachCitizenLive, previous)
      else
        Application.delete_env(:babs, BabsWeb.AttachCitizenLive)
      end
    end)
  end

  test "renders eligible Citizens, attachable tmux panes, inventory classes, and token links" do
    Application.put_env(:babs, BabsWeb.AttachCitizenLive,
      citizen_provider: fn -> [citizen("clare", "stopped"), citizen("busy", "running")] end,
      inventory_provider: fn _records ->
        [pane("operator:0.0", "%101", :attachable), pane("babs-clare:0.0", "%102", :babs_owned)]
      end,
      lifecycle_lookup: fn
        "busy" -> {:ok, self()}
        _slug -> {:error, :not_found}
      end
    )

    {:ok, _view, html} = live(build_conn(), "/citizens/attach?socket_token=socket-token")

    assert html =~ ~s(data-testid="attach-citizen-page")
    assert html =~ ~s(href="/citizens?socket_token=socket-token")
    assert html =~ ~s(data-testid="attach-citizen-clare")
    refute html =~ ~s(data-testid="attach-citizen-busy")
    assert html =~ ~s(data-testid="attach-pane-%101")
    assert html =~ "operator:0.0 %101"
    assert html =~ "Attachable"
    assert html =~ "Babs-owned"
  end

  test "submitting an attach imports the selected pane and redirects to the Citizen terminal" do
    parent = self()

    Application.put_env(:babs, BabsWeb.AttachCitizenLive,
      citizen_provider: fn -> [citizen("clare", "stopped")] end,
      inventory_provider: fn _records -> [pane("operator:0.0", "%101", :attachable)] end,
      lifecycle_lookup: fn _slug -> {:error, :not_found} end,
      attach_action: fn slug, target ->
        send(parent, {:attach_action, slug, target})
        {:ok, self()}
      end
    )

    {:ok, view, _html} = live(build_conn(), "/citizens/attach?socket_token=socket-token")

    view
    |> form(~s(form[data-testid="attach-form"]), %{
      "attach" => %{"slug" => "clare", "target" => "operator:0.0"}
    })
    |> render_submit()

    assert_receive {:attach_action, "clare", "operator:0.0"}
    assert_redirect(view, "/citizens/clare?socket_token=socket-token")
  end

  test "attach failure keeps the page, refreshes inventory, and redacts details" do
    parent = self()

    Application.put_env(:babs, BabsWeb.AttachCitizenLive,
      citizen_provider: fn -> [citizen("clare", "stopped")] end,
      inventory_provider: fn _records ->
        send(parent, :inventory_requested)
        [pane("operator:0.0", "%101", :attachable)]
      end,
      lifecycle_lookup: fn _slug -> {:error, :not_found} end,
      attach_action: fn slug, target ->
        send(parent, {:attach_action, slug, target})
        {:error, {:tmux_failed, "api_token=super-secret"}}
      end
    )

    {:ok, view, _html} = live(build_conn(), "/citizens/attach")
    assert_receive :inventory_requested

    view
    |> form(~s(form[data-testid="attach-form"]), %{
      "attach" => %{"slug" => "clare", "target" => "operator:0.0"}
    })
    |> render_submit()

    assert_receive {:attach_action, "clare", "operator:0.0"}
    html = render_async(view, 1_000)

    assert_receive :inventory_requested
    assert html =~ ~s(data-testid="attach-flash-error")
    assert html =~ "Attach failed:"
    assert html =~ "[REDACTED]"
    refute html =~ "super-secret"
    assert html =~ ~s(data-testid="attach-citizen-page")
  end

  test "blank submit keeps the page and reports a selection error" do
    Application.put_env(:babs, BabsWeb.AttachCitizenLive,
      citizen_provider: fn -> [citizen("clare", "stopped")] end,
      inventory_provider: fn _records -> [pane("operator:0.0", "%101", :attachable)] end,
      lifecycle_lookup: fn _slug -> {:error, :not_found} end
    )

    {:ok, view, _html} = live(build_conn(), "/citizens/attach")

    html =
      view
      |> form(~s(form[data-testid="attach-form"]), %{"attach" => %{"slug" => "", "target" => ""}})
      |> render_submit()

    assert html =~ ~s(data-testid="attach-flash-error")
    assert html =~ "Select a Citizen and tmux pane"
    assert html =~ ~s(data-testid="attach-citizen-page")
  end

  defp citizen(slug, status) do
    %CitizenRecord{
      id: "BAB-CIT-#{slug}",
      slug: slug,
      display_name: String.capitalize(slug),
      cwd: "/tmp/#{slug}",
      cli: "/bin/zsh",
      cli_args: ["-f"],
      env: %{},
      status: status,
      metadata: %{},
      is_mayor: false
    }
  end

  defp pane(target, pane_id, classification) do
    [session_name, rest] = String.split(target, ":", parts: 2)
    [window_index, pane_index] = String.split(rest, ".", parts: 2)

    %{
      session_name: session_name,
      window_index: window_index,
      window_name: "zsh",
      pane_index: pane_index,
      pane_id: pane_id,
      target: target,
      current_command: "zsh",
      current_path: "/tmp/project",
      attached?: false,
      classification: classification
    }
  end
end
