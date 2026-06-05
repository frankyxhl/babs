defmodule BabsWeb.NewCitizenLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Babs.Citizens.CitizenRecord

  @endpoint BabsWeb.Endpoint

  setup do
    original = Application.get_env(:babs, BabsWeb.NewCitizenLive)

    on_exit(fn ->
      if original do
        Application.put_env(:babs, BabsWeb.NewCitizenLive, original)
      else
        Application.delete_env(:babs, BabsWeb.NewCitizenLive)
      end
    end)

    :ok
  end

  test "GET /citizens/new routes to NewCitizenLive before the slug terminal route" do
    conn = get(build_conn(), "/citizens/new")

    assert conn.status == 200
    assert conn.resp_body =~ ~s(data-testid="new-citizen-form")
    refute conn.resp_body =~ "citizen not found: new"
  end

  test "renders form fields, presets, and LiveView boot script" do
    {:ok, _view, html} = live(build_conn(), "/citizens/new")

    assert html =~ ~s(data-testid="citizen-slug")
    assert html =~ ~s(data-testid="citizen-display-name")
    assert html =~ ~s(data-testid="citizen-cli-preset")
    assert html =~ ~s(data-testid="citizen-ticket-backend")
    assert html =~ ~s(value="hardline")
    assert html =~ ~s(value="direct_cli")
    refute html =~ ~s(value="lazy_tmux")
    assert html =~ ~s(data-testid="citizen-cwd")
    assert html =~ ~s(data-testid="citizen-roles")
    assert html =~ ~s(value="copilot-cli")
    assert html =~ "/js/live_boot.js"
  end

  test "successful submit sends role text and redirects to the new citizen terminal" do
    parent = self()

    Application.put_env(:babs, BabsWeb.NewCitizenLive,
      spawner: fn params ->
        send(parent, {:submitted, params})
        {:ok, %CitizenRecord{slug: "ui-created"}}
      end
    )

    {:ok, view, _html} = live(build_conn(), "/citizens/new")

    assert {:error, {:redirect, %{to: "/citizens/ui-created"}}} =
             view
             |> form("[data-testid='new-citizen-form']",
               citizen: %{
                 slug: "ui-created",
                 display_name: "UI Created",
                 description: "Created from LiveView",
                 cli_preset: "copilot-cli",
                 ticket_backend: "hardline",
                 cwd: "ui-created",
                 roles: "Developer\nInspector"
               }
             )
             |> render_submit()

    assert_receive {:submitted,
                    %{
                      "slug" => "ui-created",
                      "display_name" => "UI Created",
                      "description" => "Created from LiveView",
                      "cli_preset" => "copilot-cli",
                      "ticket_backend" => "hardline",
                      "cwd" => "ui-created",
                      "roles" => "Developer\nInspector"
                    }}
  end

  test "successful direct_cli submit redirects to citizens index" do
    parent = self()

    Application.put_env(:babs, BabsWeb.NewCitizenLive,
      spawner: fn params ->
        send(parent, {:submitted, params})

        {:ok,
         %CitizenRecord{slug: "direct-created", ticket_backend: "direct_cli", status: "stopped"}}
      end
    )

    {:ok, view, _html} = live(build_conn(), "/citizens/new?socket_token=socket-token")

    assert {:error, {:redirect, %{to: "/citizens?socket_token=socket-token"}}} =
             view
             |> form("[data-testid='new-citizen-form']",
               citizen: %{
                 slug: "direct-created",
                 display_name: "Direct Created",
                 description: "Created from LiveView",
                 cli_preset: "copilot-cli",
                 ticket_backend: "direct_cli",
                 cwd: "direct-created"
               }
             )
             |> render_submit()

    assert_receive {:submitted,
                    %{
                      "slug" => "direct-created",
                      "display_name" => "Direct Created",
                      "description" => "Created from LiveView",
                      "cli_preset" => "copilot-cli",
                      "ticket_backend" => "direct_cli",
                      "cwd" => "direct-created",
                      "roles" => ""
                    }}
  end

  test "successful submit preserves socket token in terminal redirect" do
    Application.put_env(:babs, BabsWeb.NewCitizenLive,
      spawner: fn _params ->
        {:ok, %CitizenRecord{slug: "token-created"}}
      end
    )

    {:ok, view, _html} = live(build_conn(), "/citizens/new?socket_token=socket-token")

    assert {:error, {:redirect, %{to: "/citizens/token-created?socket_token=socket-token"}}} =
             view
             |> form("[data-testid='new-citizen-form']",
               citizen: %{
                 slug: "token-created",
                 display_name: "Token Created",
                 cli_preset: "shell",
                 cwd: "token-created"
               }
             )
             |> render_submit()
  end

  test "validation errors render inline and stay on the form" do
    Application.put_env(:babs, BabsWeb.NewCitizenLive,
      spawner: fn _params ->
        {:error, {:validation_failed, %{slug: "is reserved", cwd: "must be relative"}}}
      end
    )

    {:ok, view, _html} = live(build_conn(), "/citizens/new")

    html =
      view
      |> form("[data-testid='new-citizen-form']",
        citizen: %{
          slug: "new",
          display_name: "New",
          cli_preset: "shell",
          cwd: "/absolute"
        }
      )
      |> render_submit()

    assert html =~ ~s(data-testid="slug-error")
    assert html =~ "is reserved"
    assert html =~ ~s(data-testid="cwd-error")
    assert html =~ "must be relative"
  end

  test "role validation errors render inline and stay on the form" do
    Application.put_env(:babs, BabsWeb.NewCitizenLive,
      spawner: fn _params ->
        {:error, {:validation_failed, %{roles: "must be valid role labels"}}}
      end
    )

    {:ok, view, _html} = live(build_conn(), "/citizens/new")

    html =
      view
      |> form("[data-testid='new-citizen-form']",
        citizen: %{
          slug: "role-error",
          display_name: "Role Error",
          cli_preset: "shell",
          roles: "bad/role"
        }
      )
      |> render_submit()

    assert html =~ ~s(data-testid="roles-error")
    assert html =~ "must be valid role labels"
  end

  test "known non-validation errors render status without leaking raw internals" do
    Application.put_env(:babs, BabsWeb.NewCitizenLive,
      spawner: fn _params ->
        {:error, {:duplicate_sqlite, "sentinel"}}
      end
    )

    {:ok, view, _html} = live(build_conn(), "/citizens/new")

    html =
      view
      |> form("[data-testid='new-citizen-form']",
        citizen: %{
          slug: "sentinel",
          display_name: "Sentinel",
          cli_preset: "shell"
        }
      )
      |> render_submit()

    assert html =~ ~s(data-testid="spawn-error")
    assert html =~ "Citizen already exists"
    refute html =~ "duplicate_sqlite"
  end

  test "TOML writer errors render actionable status" do
    Application.put_env(:babs, BabsWeb.NewCitizenLive,
      spawner: fn _params ->
        {:error, {:toml_write_failed, "/tmp/citizen.toml.tmp", :eacces}}
      end
    )

    {:ok, view, _html} = live(build_conn(), "/citizens/new")

    html =
      view
      |> form("[data-testid='new-citizen-form']",
        citizen: %{
          slug: "toml-error",
          display_name: "Toml Error",
          cli_preset: "shell"
        }
      )
      |> render_submit()

    assert html =~ ~s(data-testid="spawn-error")
    assert html =~ "Could not write Citizen TOML"
    refute html =~ "citizen.toml.tmp"
    refute html =~ "eacces"
  end

  test "Readme seed errors render actionable status without leaking internals" do
    Application.put_env(:babs, BabsWeb.NewCitizenLive,
      spawner: fn _params ->
        {:error, {:readme_seed_failed, {:redacted_io_error, {:mkdir_knowledge, :eacces}}}}
      end
    )

    {:ok, view, _html} = live(build_conn(), "/citizens/new")

    html =
      view
      |> form("[data-testid='new-citizen-form']",
        citizen: %{
          slug: "readme-error",
          display_name: "Readme Error",
          cli_preset: "shell"
        }
      )
      |> render_submit()

    assert html =~ ~s(data-testid="spawn-error")
    assert html =~ "Could not create Citizen home"
    refute html =~ "redacted_io_error"
    refute html =~ "eacces"
  end

  test "unexpected spawner errors render generic status without inspect output" do
    Application.put_env(:babs, BabsWeb.NewCitizenLive,
      spawner: fn _params ->
        {:error, {:unexpected, %{secret: "raw-internal-value"}}}
      end
    )

    {:ok, view, _html} = live(build_conn(), "/citizens/new")

    html =
      view
      |> form("[data-testid='new-citizen-form']",
        citizen: %{
          slug: "fallback",
          display_name: "Fallback",
          cli_preset: "shell"
        }
      )
      |> render_submit()

    assert html =~ ~s(data-testid="spawn-error")
    assert html =~ "Could not create Citizen due to an unexpected error"
    refute html =~ "raw-internal-value"
    refute html =~ "secret"
  end
end
