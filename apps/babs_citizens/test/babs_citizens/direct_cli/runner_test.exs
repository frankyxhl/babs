defmodule Babs.Citizens.DirectCli.RunnerTest do
  use Babs.Citizens.RepoCase, async: false

  alias Babs.Citizens.{ExecutionLock, ProviderSession, ProviderSessions, Repo}
  alias Babs.Citizens.CitizenConfig
  alias Babs.Citizens.DirectCli.Adapters.Fake
  alias Babs.Citizens.DirectCli.Runner
  alias Babs.Citizens.Tickets.Api

  test "runs a direct turn, stores the provider session, and appends a captured reply" do
    root = tmp_root!()
    config = fake_config("elena")
    ticket = create_ticket!(root)
    parent = self()

    executor = fn command ->
      send(parent, {:direct_command, command})

      {:ok,
       %{
         stdout:
           Jason.encode!(%{
             "session_id" => command.provider_session_id,
             "content" => "fake direct reply"
           }),
         stderr: ""
       }}
    end

    assert :ok =
             Runner.run_turn(turn(root, ticket.id, config),
               adapter: Fake,
               executor: executor,
               fallback: :none
             )

    assert_receive {:direct_command, %{resume?: false, provider_session_id: "fake-session-elena"}}

    session = Repo.one!(ProviderSession)
    assert session.citizen_slug == "elena"
    assert session.ticket_id == ticket.id
    assert session.provider == "fake"
    assert session.provider_session_id == "fake-session-elena"
    assert session.status == "active"

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

    assert Enum.any?(
             history,
             &match?(%{"event" => "turn_execution_started", "backend" => "direct_cli"}, &1)
           )

    assert Enum.any?(
             history,
             &match?(%{"event" => "turn_delivered", "backend" => "direct_cli"}, &1)
           )

    assert Enum.any?(
             history,
             &match?(%{"event" => "comment", "by" => "elena", "body" => "fake direct reply"}, &1)
           )

    assert Enum.any?(
             history,
             &match?(%{"event" => "turn_reply_captured", "by_citizen" => "elena"}, &1)
           )
  end

  test "redacts configured secret values from persisted direct replies" do
    root = tmp_root!()
    config = %{fake_config("elena") | env: %{"OPENAI_API_KEY" => "sk-test-secret-value"}}
    ticket = create_ticket!(root)

    executor = fn command ->
      {:ok,
       %{
         stdout:
           Jason.encode!(%{
             "session_id" => command.provider_session_id,
             "content" => "provider echoed sk-test-secret-value"
           }),
         stderr: "debug sk-test-secret-value"
       }}
    end

    assert :ok =
             Runner.run_turn(turn(root, ticket.id, config),
               adapter: Fake,
               executor: executor,
               fallback: :none
             )

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

    assert Enum.any?(
             history,
             &match?(
               %{"event" => "comment", "body" => "provider echoed [REDACTED]"},
               &1
             )
           )

    refute inspect(history) =~ "sk-test-secret-value"
  end

  test "resumes an existing provider session on the next direct turn" do
    root = tmp_root!()
    config = fake_config("dylan")
    ticket = create_ticket!(root)
    parent = self()

    assert {:ok, _session} =
             ProviderSessions.upsert_active(%{
               citizen_slug: "dylan",
               ticket_id: ticket.id,
               provider: "fake",
               backend: "direct_cli",
               provider_session_id: "stored-session",
               workspace_ref: "citizen:dylan"
             })

    executor = fn command ->
      send(parent, {:direct_command, command})

      {:ok,
       %{stdout: Jason.encode!(%{"session_id" => "stored-session", "content" => "resumed reply"})}}
    end

    assert :ok =
             Runner.run_turn(turn(root, ticket.id, config),
               adapter: Fake,
               executor: executor,
               fallback: :none
             )

    assert_receive {:direct_command,
                    %{
                      resume?: true,
                      provider_session_id: "stored-session",
                      args: ["babs-fake-ai", "--resume", "stored-session", "--reply", _prompt]
                    }}
  end

  test "comment_ticket uses compact prompt for resumed direct provider sessions" do
    root = tmp_root!()
    config = fake_config("flora")
    parent = self()

    insert_citizen!(%{
      slug: "flora",
      display_name: "Flora",
      cli: "babs-fake-ai",
      cli_args: [],
      cwd: config.cwd,
      ticket_backend: "direct_cli"
    })

    ticket =
      create_ticket!(root, %{
        title: "Full title should not repeat",
        body: "Full ticket body should not repeat",
        state: "in_progress",
        assignees: ["flora"]
      })

    assert {:ok, _session} =
             ProviderSessions.upsert_active(%{
               citizen_slug: "flora",
               ticket_id: ticket.id,
               provider: "fake",
               backend: "direct_cli",
               provider_session_id: "stored-session",
               workspace_ref: "citizen:flora"
             })

    assert {:ok, _stored} =
             Api.comment_ticket(ticket.id, %{body: "Earlier operator message.", by: "user"},
               tickets_root: root,
               notify_assignees: false
             )

    executor = fn command ->
      send(parent, {:direct_command, command})

      {:ok,
       %{
         stdout:
           Jason.encode!(%{
             "session_id" => "stored-session",
             "content" => "compact reply"
           })
       }}
    end

    assert {:ok, %{delivery: {:comment_notified, ["flora"]}}} =
             Api.comment_ticket(ticket.id, %{body: "Only this new message.", by: "user"},
               tickets_root: root,
               citizen_config_fetcher: fn "flora" -> config end,
               adapter: Fake,
               executor: executor,
               reply_capture: fn _turn -> :ok end
             )

    assert_receive {:direct_command,
                    %{
                      resume?: true,
                      provider_session_id: "stored-session",
                      args: ["babs-fake-ai", "--resume", "stored-session", "--reply", prompt]
                    }},
                   1_000

    assert prompt =~ "Ticket: #{ticket.id}"
    assert prompt =~ "Latest operator message:\nOnly this new message."
    assert prompt =~ "BABS_REPLY #{ticket.id}:"
    refute prompt =~ "Full title should not repeat"
    refute prompt =~ "Full ticket body should not repeat"
    refute prompt =~ "Earlier operator message."
    refute prompt =~ "Recent visible chat messages"
  end

  test "comment_ticket keeps full prompt when direct provider session cannot resume" do
    parent = self()

    assert_full_prompt = fn slug, seed_session ->
      root = tmp_root!()
      config = fake_config(slug)

      insert_citizen!(%{
        slug: slug,
        display_name: String.capitalize(slug),
        cli: "babs-fake-ai",
        cli_args: [],
        cwd: config.cwd,
        ticket_backend: "direct_cli"
      })

      ticket =
        create_ticket!(root, %{
          title: "Fallback title #{slug}",
          body: "Fallback body #{slug}",
          state: "in_progress",
          assignees: [slug]
        })

      seed_session.(slug, ticket.id)

      executor = fn command ->
        send(parent, {:direct_command, slug, command})

        {:ok,
         %{
           stdout:
             Jason.encode!(%{
               "session_id" => "fake-session-#{slug}",
               "content" => "full prompt reply"
             })
         }}
      end

      assert {:ok, %{delivery: {:comment_notified, [^slug]}}} =
               Api.comment_ticket(ticket.id, %{body: "Please use full context.", by: "user"},
                 tickets_root: root,
                 citizen_config_fetcher: fn ^slug -> config end,
                 adapter: Fake,
                 executor: executor,
                 reply_capture: fn _turn -> :ok end
               )

      assert_receive {:direct_command, ^slug,
                      %{
                        resume?: false,
                        args: [
                          "babs-fake-ai",
                          "--session",
                          "fake-session-" <> _,
                          "--reply",
                          prompt
                        ]
                      }},
                     1_000

      assert prompt =~ "Title: Fallback title #{slug}"
      assert prompt =~ "Fallback body #{slug}"
      assert prompt =~ "Please use full context."
      assert prompt =~ "Recent visible chat messages:"
    end

    assert_full_prompt.("flora", fn slug, ticket_id ->
      assert {:ok, _session} =
               ProviderSessions.upsert_active(%{
                 citizen_slug: slug,
                 ticket_id: ticket_id,
                 provider: "fake",
                 backend: "direct_cli",
                 workspace_ref: "citizen:#{slug}"
               })
    end)

    assert_full_prompt.("iris", fn slug, ticket_id ->
      assert {:ok, session} =
               ProviderSessions.upsert_active(%{
                 citizen_slug: slug,
                 ticket_id: ticket_id,
                 provider: "fake",
                 backend: "direct_cli",
                 provider_session_id: "stale-session",
                 workspace_ref: "citizen:#{slug}"
               })

      assert {:ok, _session} = ProviderSessions.mark_non_resumable(session, :resume_disabled)
    end)
  end

  test "comment_ticket uses full prompt for hardline fallback after compact direct failure" do
    root = tmp_root!()
    config = fake_config("flora")
    parent = self()

    insert_citizen!(%{
      slug: "flora",
      display_name: "Flora",
      cli: "babs-fake-ai",
      cli_args: [],
      cwd: config.cwd,
      ticket_backend: "direct_cli"
    })

    ticket =
      create_ticket!(root, %{
        title: "Fallback hardline title",
        body: "Fallback hardline body",
        state: "in_progress",
        assignees: ["flora"]
      })

    assert {:ok, _session} =
             ProviderSessions.upsert_active(%{
               citizen_slug: "flora",
               ticket_id: ticket.id,
               provider: "fake",
               backend: "direct_cli",
               provider_session_id: "stored-session",
               workspace_ref: "citizen:flora"
             })

    executor = fn command ->
      send(parent, {:direct_command, command})
      {:error, :resume_failed}
    end

    hardline_injector = fn slug, prompt, _opts ->
      send(parent, {:hardline_fallback, slug, prompt})
      :ok
    end

    assert {:ok, %{delivery: {:comment_notified, ["flora"]}}} =
             Api.comment_ticket(ticket.id, %{body: "Fallback should get context.", by: "user"},
               tickets_root: root,
               citizen_config_fetcher: fn "flora" -> config end,
               adapter: Fake,
               executor: executor,
               hardline_injector: hardline_injector,
               reply_capture: fn _turn -> :ok end
             )

    assert_receive {:direct_command,
                    %{
                      resume?: true,
                      args: ["babs-fake-ai", "--resume", "stored-session", "--reply", compact]
                    }},
                   1_000

    assert compact =~ "Latest operator message:\nFallback should get context."
    refute compact =~ "Fallback hardline title"
    refute compact =~ "Fallback hardline body"

    assert_receive {:hardline_fallback, "flora", fallback_prompt}, 1_000
    assert fallback_prompt =~ "Title: Fallback hardline title"
    assert fallback_prompt =~ "Fallback hardline body"
    assert fallback_prompt =~ "Fallback should get context."
    assert fallback_prompt =~ "Recent visible chat messages:"
  end

  test "falls back to hardline when direct execution fails" do
    root = tmp_root!()
    config = fake_config("clare")
    ticket = create_ticket!(root)
    parent = self()

    executor = fn _command -> {:error, :boom} end

    hardline_injector = fn slug, prompt, _opts ->
      send(parent, {:fallback_injected, slug, prompt})
      :ok
    end

    reply_capture = fn turn ->
      send(parent, {:reply_capture, turn})
      :ok
    end

    assert :ok =
             Runner.run_turn(turn(root, ticket.id, config),
               adapter: Fake,
               executor: executor,
               hardline_injector: hardline_injector,
               reply_capture: reply_capture
             )

    assert_receive {:fallback_injected, "clare", "Please answer."}
    assert_receive {:reply_capture, %{slug: "clare", ticket_id: ticket_id}}
    assert ticket_id == ticket.id

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

    assert Enum.any?(
             history,
             &match?(%{"event" => "turn_delivery_failed", "backend" => "direct_cli"}, &1)
           )

    assert Enum.any?(
             history,
             &match?(%{"event" => "turn_delivery_attempted", "backend" => "hardline"}, &1)
           )

    assert Enum.any?(
             history,
             &match?(%{"event" => "turn_delivered", "backend" => "hardline"}, &1)
           )

    failed_session = Repo.one!(ProviderSession)
    assert failed_session.status == "failed"
    assert failed_session.os_pid == nil
    assert failed_session.started_at == nil
  end

  test "falls back to hardline when direct executor exits" do
    root = tmp_root!()
    config = fake_config("dylan")
    ticket = create_ticket!(root)
    parent = self()

    executor = fn _command -> exit(:timeout) end

    hardline_injector = fn slug, prompt, _opts ->
      send(parent, {:fallback_injected, slug, prompt})
      :ok
    end

    assert :ok =
             Runner.run_turn(turn(root, ticket.id, config),
               adapter: Fake,
               executor: executor,
               hardline_injector: hardline_injector,
               reply_capture: fn _turn -> :ok end
             )

    assert_receive {:fallback_injected, "dylan", "Please answer."}

    failed_session = Repo.one!(ProviderSession)
    assert failed_session.status == "failed"

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

    assert Enum.any?(
             history,
             &match?(
               %{"event" => "turn_delivery_failed", "backend" => "direct_cli", "error" => _error},
               &1
             )
           )

    assert Enum.any?(
             history,
             &match?(%{"event" => "turn_delivered", "backend" => "hardline"}, &1)
           )
  end

  test "does not fall back to hardline when direct reply persistence fails after success" do
    root = tmp_root!()
    config = fake_config("clare")
    ticket = create_ticket!(root, %{state: "closed", assignees: ["clare"]})

    executor = fn command ->
      {:ok,
       %{
         stdout:
           Jason.encode!(%{
             "session_id" => command.provider_session_id,
             "content" => "already completed"
           })
       }}
    end

    assert {:error, {:terminal_ticket, ticket_id, "closed"}} =
             Runner.run_turn(turn(root, ticket.id, config),
               adapter: Fake,
               executor: executor,
               hardline_injector: fn _slug, _prompt, _opts ->
                 flunk("successful direct execution must not be redelivered to hardline")
               end
             )

    assert ticket_id == ticket.id

    session = Repo.one!(ProviderSession)
    assert session.status == "active"

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

    assert Enum.any?(
             history,
             &match?(%{"event" => "turn_delivered", "backend" => "direct_cli"}, &1)
           )

    assert Enum.any?(
             history,
             &match?(%{"event" => "turn_reply_capture_failed", "error" => _error}, &1)
           )

    refute Enum.any?(
             history,
             &match?(%{"event" => "turn_delivered", "backend" => "hardline"}, &1)
           )
  end

  test "comment_ticket routes direct backend comments through the runner" do
    root = tmp_root!()
    config = fake_config("flora")
    parent = self()

    insert_citizen!(%{
      slug: "flora",
      display_name: "Flora",
      cli: "babs-fake-ai",
      cli_args: [],
      cwd: config.cwd,
      ticket_backend: "direct_cli"
    })

    ticket =
      create_ticket!(root, %{
        state: "in_progress",
        assignees: ["flora"]
      })

    executor = fn command ->
      send(parent, {:direct_command, command})

      {:ok,
       %{
         stdout:
           Jason.encode!(%{"session_id" => "fake-session-flora", "content" => "flora says hi"})
       }}
    end

    assert {:ok, %{delivery: {:comment_notified, ["flora"]}}} =
             Api.comment_ticket(ticket.id, %{body: "Say hi.", by: "user"},
               tickets_root: root,
               citizen_config_fetcher: fn "flora" -> config end,
               adapter: Fake,
               executor: executor,
               reply_capture: fn _turn -> :ok end
             )

    assert_receive {:direct_command, %{provider: "fake", resume?: false} = command}, 1_000
    prompt = List.last(command.args)
    assert prompt =~ "Title: Direct CLI Ticket"
    assert prompt =~ "Use a direct CLI provider."
    assert prompt =~ "Recent visible chat messages:"

    wait_until(fn ->
      {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

      Enum.any?(
        history,
        &match?(%{"event" => "comment", "by" => "flora", "body" => "flora says hi"}, &1)
      )
    end)

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

    attempted =
      Enum.find(history, &match?(%{"event" => "turn_delivery_attempted", "to" => "flora"}, &1))

    assert attempted["backend"] == "direct_cli"
    assert attempted["status"] == "queued"
  end

  test "comment_ticket direct backend surfaces busy notification failure" do
    root = tmp_root!()
    config = fake_config("flora")

    insert_citizen!(%{
      slug: "flora",
      display_name: "Flora",
      cli: "babs-fake-ai",
      cli_args: [],
      cwd: config.cwd,
      ticket_backend: "direct_cli"
    })

    ticket =
      create_ticket!(root, %{
        state: "in_progress",
        assignees: ["flora"]
      })

    assert {:ok,
            %{
              delivery:
                {:comment_notification_failed, [], [{"flora", {:execution_busy, "flora"}}]}
            }} =
             ExecutionLock.with_lock("flora", fn ->
               Api.comment_ticket(ticket.id, %{body: "Please reply.", by: "user"},
                 tickets_root: root,
                 citizen_config_fetcher: fn "flora" -> config end,
                 adapter: Fake,
                 executor: fn _command -> flunk("busy direct comment should not execute") end,
                 hardline_injector: fn _slug, _prompt, _opts ->
                   flunk("busy direct comment should not fall back to hardline")
                 end,
                 startup_ack_timeout_ms: 1_000
               )
             end)

    wait_until(fn ->
      {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

      Enum.any?(
        history,
        &match?(
          %{
            "event" => "turn_delivery_attempted",
            "backend" => "direct_cli",
            "status" => "busy"
          },
          &1
        )
      ) and
        Enum.any?(
          history,
          &match?(%{"event" => "turn_delivery_failed", "backend" => "direct_cli"}, &1)
        )
    end)

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

    assert Enum.any?(
             history,
             &match?(
               %{"event" => "comment", "by" => "user", "body" => "Please reply."},
               &1
             )
           )

    assert Enum.any?(
             history,
             &match?(
               %{
                 "event" => "turn_delivery_attempted",
                 "backend" => "direct_cli",
                 "status" => "busy"
               },
               &1
             )
           )

    refute Enum.any?(history, &match?(%{"event" => "comment_notified"}, &1))
  end

  test "assign_ticket routes direct backend assignment prompts through the runner" do
    root = tmp_root!()
    config = fake_config("flora")
    parent = self()
    ticket = create_ticket!(root)

    executor = fn command ->
      send(parent, {:direct_assignment_command, command})

      {:ok,
       %{
         stdout:
           Jason.encode!(%{
             "session_id" => "fake-session-flora",
             "content" => "assignment acknowledged"
           })
       }}
    end

    assert {:ok, %{ticket: assigned, delivery: {:injected, "flora"}}} =
             Api.assign_ticket(ticket.id, "flora",
               tickets_root: root,
               citizen_config_fetcher: fn "flora" -> config end,
               adapter: Fake,
               executor: executor,
               reply_capture: fn _turn -> :ok end,
               pane_lookup: fn "flora" -> flunk("direct assignment should not look up a pane") end,
               citizen_starter: fn "flora" ->
                 flunk("direct assignment should not start a hardline citizen")
               end,
               pane_injector: fn "flora", _prompt ->
                 flunk("direct assignment should not inject into a pane")
               end
             )

    assert assigned.state == "in_progress"
    assert assigned.assignees == ["flora"]

    assert_receive {:direct_assignment_command, command}, 1_000
    prompt = List.last(command.args)
    assert command.provider == "fake"
    assert command.resume? == false
    assert prompt =~ "[Babs Ticket #{ticket.id} assigned]"
    assert prompt =~ "Use a direct CLI provider."

    wait_until(fn ->
      {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

      Enum.any?(
        history,
        &match?(
          %{"event" => "comment", "by" => "flora", "body" => "assignment acknowledged"},
          &1
        )
      )
    end)

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

    assert Enum.any?(
             history,
             &match?(%{"event" => "turn_delivery_attempted", "backend" => "direct_cli"}, &1)
           )

    assert Enum.any?(history, &match?(%{"event" => "injected", "injected_to" => ["flora"]}, &1))
  end

  test "assign_ticket direct backend reports busy instead of injected delivery" do
    root = tmp_root!()
    config = fake_config("flora")
    ticket = create_ticket!(root)

    assert {:error, {:execution_busy, "flora"}} =
             ExecutionLock.with_lock("flora", fn ->
               Api.assign_ticket(ticket.id, "flora",
                 tickets_root: root,
                 citizen_config_fetcher: fn "flora" -> config end,
                 adapter: Fake,
                 executor: fn _command -> flunk("busy direct assignment should not execute") end,
                 hardline_injector: fn _slug, _prompt, _opts ->
                   flunk("busy direct assignment should not fall back to hardline")
                 end,
                 startup_ack_timeout_ms: 1_000
               )
             end)

    wait_until(fn ->
      {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

      Enum.any?(
        history,
        &match?(
          %{
            "event" => "turn_delivery_attempted",
            "backend" => "direct_cli",
            "status" => "busy"
          },
          &1
        )
      ) and
        Enum.any?(
          history,
          &match?(%{"event" => "turn_delivery_failed", "backend" => "direct_cli"}, &1)
        )
    end)

    assert {:ok, %{ticket: assigned, history: history}} =
             Api.show_ticket(ticket.id, tickets_root: root)

    assert assigned.state == "in_progress"
    assert assigned.assignees == ["flora"]

    assert Enum.any?(
             history,
             &match?(
               %{
                 "event" => "turn_delivery_attempted",
                 "backend" => "direct_cli",
                 "status" => "busy"
               },
               &1
             )
           )

    assert Enum.any?(
             history,
             &match?(%{"event" => "turn_delivery_failed", "backend" => "direct_cli"}, &1)
           )

    assert Enum.any?(history, &match?(%{"event" => "injection_failed"}, &1))
    refute Enum.any?(history, &match?(%{"event" => "injected"}, &1))
  end

  test "reject_ticket routes direct backend feedback prompts through the runner" do
    root = tmp_root!()
    config = fake_config("flora")
    parent = self()

    ticket =
      create_ticket!(root, %{
        state: "pending_approval",
        assignees: ["flora"]
      })

    executor = fn command ->
      send(parent, {:direct_feedback_command, command})

      {:ok,
       %{
         stdout:
           Jason.encode!(%{
             "session_id" => "fake-session-flora",
             "content" => "feedback acknowledged"
           })
       }}
    end

    assert {:ok, %{ticket: rejected, delivery: {:feedback_injected, ["flora"]}}} =
             Api.reject_ticket(ticket.id, "Please add the regression test.",
               tickets_root: root,
               citizen_config_fetcher: fn "flora" -> config end,
               adapter: Fake,
               executor: executor,
               reply_capture: fn _turn -> :ok end,
               pane_lookup: fn "flora" -> flunk("direct feedback should not look up a pane") end,
               citizen_starter: fn "flora" ->
                 flunk("direct feedback should not start a hardline citizen")
               end,
               pane_injector: fn "flora", _prompt ->
                 flunk("direct feedback should not inject into a pane")
               end
             )

    assert rejected.state == "in_progress"
    assert rejected.assignees == ["flora"]

    assert_receive {:direct_feedback_command, command}, 1_000
    prompt = List.last(command.args)
    assert command.provider == "fake"
    assert prompt =~ "[Babs Ticket #{ticket.id} rejected]"
    assert prompt =~ "Please add the regression test."

    wait_until(fn ->
      {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

      Enum.any?(
        history,
        &match?(
          %{"event" => "comment", "by" => "flora", "body" => "feedback acknowledged"},
          &1
        )
      )
    end)

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

    assert Enum.any?(
             history,
             &match?(%{"event" => "turn_delivery_attempted", "backend" => "direct_cli"}, &1)
           )

    assert Enum.any?(
             history,
             &match?(%{"event" => "feedback_injected", "injected_to" => ["flora"]}, &1)
           )
  end

  test "per-citizen execution lock reports busy for overlapping work" do
    assert :held =
             ExecutionLock.with_lock("clare", fn ->
               assert {:error, {:execution_busy, "clare"}} =
                        ExecutionLock.with_lock("clare", fn -> :unexpected end)

               :held
             end)
  end

  test "busy direct turn records failed delivery instead of dropping the prompt" do
    root = tmp_root!()
    config = fake_config("clare")
    ticket = create_ticket!(root)

    assert {:error, {:execution_busy, "clare"}} =
             ExecutionLock.with_lock("clare", fn ->
               Runner.run_turn(turn(root, ticket.id, config),
                 adapter: Fake,
                 executor: fn _command -> flunk("busy direct turn should not execute") end,
                 hardline_injector: fn _slug, _prompt, _opts ->
                   flunk("busy direct turn should not bypass the lock through hardline")
                 end
               )
             end)

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

    assert Enum.any?(
             history,
             &match?(
               %{
                 "event" => "turn_delivery_attempted",
                 "backend" => "direct_cli",
                 "status" => "busy"
               },
               &1
             )
           )

    assert Enum.any?(
             history,
             &match?(
               %{"event" => "turn_delivery_failed", "backend" => "direct_cli", "error" => _error},
               &1
             )
           )

    refute Enum.any?(
             history,
             &match?(%{"event" => "turn_delivered", "backend" => "hardline"}, &1)
           )
  end

  test "start_turn reports busy before the caller records delivery success" do
    root = tmp_root!()
    config = fake_config("clare")
    ticket = create_ticket!(root)

    assert {:error, {:execution_busy, "clare"}} =
             ExecutionLock.with_lock("clare", fn ->
               Runner.start_turn(turn(root, ticket.id, config),
                 adapter: Fake,
                 executor: fn _command -> flunk("busy direct turn should not execute") end,
                 hardline_injector: fn _slug, _prompt, _opts ->
                   flunk("busy direct turn should not fall back to hardline")
                 end,
                 startup_ack_timeout_ms: 1_000
               )
             end)

    wait_until(fn ->
      {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

      Enum.any?(
        history,
        &match?(
          %{
            "event" => "turn_delivery_attempted",
            "backend" => "direct_cli",
            "status" => "busy"
          },
          &1
        )
      ) and
        Enum.any?(
          history,
          &match?(%{"event" => "turn_delivery_failed", "backend" => "direct_cli"}, &1)
        )
    end)

    assert {:ok, %{history: history}} = Api.show_ticket(ticket.id, tickets_root: root)

    assert Enum.any?(
             history,
             &match?(
               %{
                 "event" => "turn_delivery_attempted",
                 "backend" => "direct_cli",
                 "status" => "busy"
               },
               &1
             )
           )

    assert Enum.any?(
             history,
             &match?(%{"event" => "turn_delivery_failed", "backend" => "direct_cli"}, &1)
           )

    refute Enum.any?(
             history,
             &match?(%{"event" => "turn_delivered", "backend" => "direct_cli"}, &1)
           )
  end

  defp create_ticket!(root, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          title: "Direct CLI Ticket",
          body: "Use a direct CLI provider.",
          state: "open",
          assignees: []
        },
        attrs
      )

    assert {:ok, ticket} =
             Api.create_ticket(attrs,
               tickets_root: root,
               date: ~D[2026-05-07],
               now: "2026-05-07T10:00:00Z"
             )

    ticket
  end

  defp turn(root, ticket_id, config) do
    %{
      root: root,
      ticket_id: ticket_id,
      slug: config.slug,
      turn_id: "turn_20260507100100_testturn01",
      attempt_id: "attempt_20260507100100_testatt01",
      backend: "direct_cli",
      prompt: "Please answer.",
      config: config,
      fallback: :hardline
    }
  end

  defp fake_config(slug) do
    cwd = tmp_cwd!()

    %CitizenConfig{
      id: "BAB-CIT-#{String.upcase(slug)}",
      slug: slug,
      display_name: String.capitalize(slug),
      cli: "babs-fake-ai",
      cli_args: [],
      launch_profile: "trusted_autonomous",
      ticket_backend: "direct_cli",
      cwd: cwd,
      env: %{}
    }
  end

  defp wait_until(fun, timeout_ms \\ 1_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    wait_until(fun, deadline, nil)
  end

  defp wait_until(fun, deadline, last_result) do
    case fun.() do
      true ->
        :ok

      other ->
        if System.monotonic_time(:millisecond) >= deadline do
          flunk(
            "condition did not become true before timeout, last result: #{inspect(last_result || other)}"
          )
        else
          Process.sleep(20)
          wait_until(fun, deadline, other)
        end
    end
  end
end
