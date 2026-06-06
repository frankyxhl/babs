defmodule BabsWeb.TicketLive do
  @moduledoc """
  Read-only Ticket detail view.
  """

  use Phoenix.LiveView

  alias Babs.Citizens.Catalog
  alias Babs.Citizens.TicketBackend
  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Conversation
  alias Babs.Citizens.Tickets.Error
  alias Babs.Citizens.Tickets.Watcher
  alias Babs.Git
  alias BabsWeb.CitizenPath
  alias BabsWeb.GitDiffComponent
  alias BabsWeb.TicketPath
  alias BabsWeb.TicketPresenter

  @impl true
  def mount(params, session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Babs.Citizens.PubSub, Watcher.topic())

    id = param(params, "id") || Map.get(session, "id")

    {:ok,
     socket
     |> assign(:id, id)
     |> assign(:socket_token, Map.get(session, "socket_token", ""))
     |> assign(:ticket_action_inflight, nil)
     |> assign_ticket()}
  end

  @impl true
  def handle_event("assign", %{"slug" => slug}, socket) do
    {:noreply,
     start_ticket_action(socket, {:assign, slug}, fn ->
       with :ok <- ensure_assignable_citizen(slug) do
         Api.assign_ticket(socket.assigns.id, slug)
       end
     end)}
  end

  def handle_event("assign_role", _params, socket) do
    role = socket.assigns.ticket.assignee_role

    {:noreply,
     start_ticket_action(socket, {:assign_role, role}, fn ->
       Api.assign_ticket_by_role(socket.assigns.id)
     end)}
  end

  def handle_event("transition", %{"to" => to_state} = params, socket) do
    event = blank_to_nil(Map.get(params, "event"))

    {:noreply,
     start_ticket_action(socket, {:transition, to_state, event}, fn ->
       Api.transition_ticket(socket.assigns.id, to_state, event)
     end)}
  end

  def handle_event("unassign", %{"slug" => slug}, socket) do
    {:noreply,
     start_ticket_action(socket, {:unassign, slug}, fn ->
       Api.unassign_ticket(socket.assigns.id, slug)
     end)}
  end

  def handle_event("approve", _params, socket) do
    {:noreply,
     start_ticket_action(socket, :approve, fn ->
       Api.approve_ticket(socket.assigns.id)
     end)}
  end

  def handle_event("reject", %{"feedback" => feedback}, socket) do
    case String.trim(feedback || "") do
      "" ->
        {:noreply, put_flash(socket, :error, "Rejection feedback is required")}

      value ->
        {:noreply,
         start_ticket_action(socket, :reject, fn ->
           Api.reject_ticket(socket.assigns.id, value)
         end)}
    end
  end

  def handle_event("comment", %{"body" => body}, socket) do
    case String.trim(body || "") do
      "" ->
        {:noreply, put_flash(socket, :error, "Comment body is required")}

      value ->
        {:noreply,
         start_ticket_action(socket, {:comment, value}, fn ->
           Api.comment_ticket(socket.assigns.id, %{body: value, by: "user"})
         end)}
    end
  end

  def handle_event(
        "proposal_edit_child",
        %{"proposal_id" => proposal_id, "child_index" => child_index, "child" => attrs} = params,
        socket
      ) do
    case parse_index(child_index) do
      {:ok, index} ->
        {:noreply,
         start_ticket_action(socket, {:proposal_edit_child, index}, fn ->
           Api.revise_mayor_proposal_child(socket.assigns.id, proposal_id, index, attrs,
             proposal_revision: Map.get(params, "proposal_revision")
           )
         end)}

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid proposal child index")}
    end
  end

  def handle_event(
        "proposal_remove_child",
        %{"proposal_id" => proposal_id, "child_index" => child_index} = params,
        socket
      ) do
    case parse_index(child_index) do
      {:ok, index} ->
        {:noreply,
         start_ticket_action(socket, {:proposal_remove_child, index}, fn ->
           Api.remove_mayor_proposal_child(socket.assigns.id, proposal_id, index,
             proposal_revision: Map.get(params, "proposal_revision")
           )
         end)}

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid proposal child index")}
    end
  end

  def handle_event("proposal_approve", %{"proposal_id" => proposal_id} = params, socket) do
    {:noreply,
     start_ticket_action(socket, :proposal_approve, fn ->
       Api.approve_mayor_proposal(socket.assigns.id, proposal_id,
         proposal_revision: Map.get(params, "proposal_revision")
       )
     end)}
  end

  def handle_event(
        "proposal_reject",
        %{"proposal_id" => proposal_id, "feedback" => feedback} = params,
        socket
      ) do
    case String.trim(feedback || "") do
      "" ->
        {:noreply, put_flash(socket, :error, "Proposal rejection feedback is required")}

      value ->
        {:noreply,
         start_ticket_action(socket, :proposal_reject, fn ->
           Api.reject_mayor_proposal(socket.assigns.id, proposal_id, value,
             proposal_revision: Map.get(params, "proposal_revision")
           )
         end)}
    end
  end

  @impl true
  def handle_async({:ticket_action, action}, {:ok, result}, socket) do
    {:noreply, apply_ticket_action_result(socket, action, result)}
  end

  def handle_async({:ticket_action, action}, {:exit, reason}, socket) do
    {:noreply, apply_ticket_action_result(socket, action, {:error, reason})}
  end

  @impl true
  def handle_info({:tickets_changed, _payload}, socket) do
    {:noreply, assign_ticket(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(%{error: nil} = assigns) do
    ~H"""
    <div class="ks-page" data-testid="ticket-detail">
      <main class="ks-shell">
        <header class="ks-header">
          <div>
            <a class="ks-button" href={TicketPath.index(@socket_token)}>
              <BabsWeb.Icon.icon name="arrow-left" /> Tickets
            </a>
            <h1>{@ticket.title}</h1>
            <p class="ks-subtitle">{@ticket.id}</p>
          </div>

          <nav class="ks-nav" aria-label="Ticket detail navigation">
            <a class="ks-button" href={CitizenPath.index(@socket_token)}>
              <BabsWeb.Icon.icon name="users" /> Citizens
            </a>
            <a class="ks-button" href={TicketPath.index(@socket_token)}>
              <BabsWeb.Icon.icon name="list" /> Ticket List
            </a>
          </nav>
        </header>

        <div :if={Phoenix.Flash.get(@flash, :info)} class="ks-card ticket-flash" data-testid="ticket-flash-info">
          {Phoenix.Flash.get(@flash, :info)}
        </div>

        <div
          :if={Phoenix.Flash.get(@flash, :error)}
          class="ks-card ticket-flash ticket-flash-error"
          data-testid="ticket-flash-error"
        >
          {Phoenix.Flash.get(@flash, :error)}
        </div>

        <section class="ticket-layout">
          <aside class="ticket-rail" data-testid="ticket-state-rail">
            <section class="rail-block">
              <p class="rail-label">State</p>
              <span class={state_badge_class(@ticket.state)}><span class="dot"></span>{@ticket.state}</span>
            </section>

            <section class="rail-block inspection-panel" data-testid="ticket-inspection-panel">
              <p class="rail-label">Inspection</p>
              <div class="inspection-mode">
                <BabsWeb.Icon.icon name="shield-check" />
                <span data-testid="ticket-inspection-mode">{@inspection_panel.label}</span>
              </div>

              <dl class="stat-list compact">
                <div :if={@inspection_panel.quorum}>
                  <dt>Quorum</dt>
                  <dd>{@inspection_panel.quorum}</dd>
                </div>
                <div :if={@inspection_panel.result}>
                  <dt>Result</dt>
                  <dd>
                    <span class={inspection_badge_class(@inspection_panel.result)}>
                      <span class="dot"></span>{@inspection_panel.result}
                    </span>
                  </dd>
                </div>
                <div :if={@inspection_panel.roles != []}>
                  <dt>Roles</dt>
                  <dd>{join_values(@inspection_panel.roles)}</dd>
                </div>
                <div :if={@inspection_panel.citizens != []}>
                  <dt>Citizens</dt>
                  <dd>{join_values(@inspection_panel.citizens)}</dd>
                </div>
              </dl>

              <ol :if={@inspection_panel.inspectors != []} class="inspection-list">
                <li
                  :for={inspector <- @inspection_panel.inspectors}
                  data-testid={"ticket-inspector-#{inspector.slug}"}
                >
                  <div class="inspection-row">
                    <strong>{inspector.slug}</strong>
                    <span class={inspection_badge_class(inspector.status)}>
                      <span class="dot"></span>{inspector.status_label}
                    </span>
                  </div>
                  <p :if={inspector.summary} class="inspection-summary">{inspector.summary}</p>
                  <ul :if={inspector.findings != []} class="inspection-findings">
                    <li :for={finding <- inspector.findings}>{finding_text(finding)}</li>
                  </ul>
                </li>
              </ol>
            </section>

            <section class="rail-block">
              <p class="rail-label">Ticket Body</p>
              <pre class="ticket-body">{@ticket.body}</pre>
            </section>

            <section class="rail-block" data-testid="ticket-actions">
              <p class="rail-label">Actions</p>
              <div class="rail-actions">
                <button
                  :if={role_assignable?(@ticket)}
                  type="button"
                  class="ks-button primary"
                  phx-click="assign_role"
                  disabled={ticket_action_busy?(@ticket_action_inflight)}
                  data-testid={"ticket-assign-role-#{@ticket.assignee_role}"}
                  aria-label={"Assign #{@ticket.id} by role #{@ticket.assignee_role}"}
                  title={"Assign by role #{@ticket.assignee_role}"}
                >
                  <BabsWeb.Icon.icon name="route" /> Route {@ticket.assignee_role}
                </button>

                <button
                  :for={citizen <- @citizens}
                  :if={assignable?(@ticket)}
                  type="button"
                  class="ks-button"
                  phx-click="assign"
                  phx-value-slug={citizen.slug}
                  disabled={ticket_action_busy?(@ticket_action_inflight)}
                  data-testid={"ticket-assign-#{citizen.slug}"}
                  aria-label={"Assign #{@ticket.id} to #{citizen.display_name} using #{citizen.ticket_backend_label}"}
                  title={"Assign to #{citizen.display_name} using #{citizen.ticket_backend_label}: #{citizen.assign_hint}"}
                >
                  <BabsWeb.Icon.icon name="user-plus" />
                  <span>{citizen.display_name}</span>
                  <span class="badge">{citizen.ticket_backend_label}</span>
                  <span class="muted-inline">{citizen.assign_hint}</span>
                </button>

                <button
                  :if={ready_for_approval?(@ticket)}
                  type="button"
                  class="ks-button"
                  phx-click="transition"
                  phx-value-to="pending_approval"
                  disabled={ticket_action_busy?(@ticket_action_inflight)}
                  data-testid="ticket-transition-pending_approval"
                  aria-label="Move to pending approval"
                  title="Move to pending approval"
                >
                  <BabsWeb.Icon.icon name="route" /> Pending Approval
                </button>

                <button
                  :if={approvable?(@ticket)}
                  type="button"
                  class="ks-button primary"
                  phx-click="approve"
                  disabled={ticket_action_busy?(@ticket_action_inflight)}
                  data-testid="ticket-approve"
                  aria-label="Approve ticket"
                  title="Approve ticket"
                >
                  <BabsWeb.Icon.icon name="check" /> Approve
                </button>

                <form
                  :if={rejectable?(@ticket)}
                  class="reject-form"
                  phx-submit="reject"
                  data-testid="ticket-reject-form"
                >
                  <textarea
                    name="feedback"
                    class="reject-feedback"
                    rows="4"
                    required
                    disabled={ticket_action_busy?(@ticket_action_inflight)}
                    data-testid="ticket-reject-feedback"
                    aria-label="Rejection feedback"
                  ></textarea>
                  <button
                    type="submit"
                    class="ks-button danger"
                    disabled={ticket_action_busy?(@ticket_action_inflight)}
                    data-testid="ticket-reject"
                    aria-label="Reject ticket"
                    title="Reject ticket"
                  >
                    <BabsWeb.Icon.icon name="x" /> Reject
                  </button>
                </form>

                <button
                  :for={slug <- @ticket.assignees}
                  :if={unassignable?(@ticket)}
                  type="button"
                  class="ks-button"
                  phx-click="unassign"
                  phx-value-slug={slug}
                  phx-confirm={"Unassign #{slug} from #{@ticket.id}?"}
                  disabled={ticket_action_busy?(@ticket_action_inflight)}
                  data-testid={"ticket-unassign-#{slug}"}
                  aria-label={"Unassign #{slug}"}
                  title={"Unassign #{slug}"}
                >
                  <BabsWeb.Icon.icon name="undo" /> Unassign {slug}
                </button>

                <button
                  :if={cancellable?(@ticket)}
                  type="button"
                  class="ks-button danger"
                  phx-click="transition"
                  phx-value-to="cancelled"
                  phx-value-event="cancelled"
                  phx-confirm={"Cancel #{@ticket.id}?"}
                  disabled={ticket_action_busy?(@ticket_action_inflight)}
                  data-testid="ticket-transition-cancelled"
                  aria-label="Cancel ticket"
                  title="Cancel ticket"
                >
                  <BabsWeb.Icon.icon name="ban" /> Cancel
                </button>
              </div>
            </section>

            <section class="rail-block">
              <p class="rail-label">Frontmatter</p>
              <dl class="stat-list">
                <div :for={{label, value} <- TicketPresenter.frontmatter(@ticket)} class="summary-row">
                  <dt>{label}</dt>
                  <dd>{value}</dd>
                </div>
              </dl>
            </section>

            <section :if={@ticket.warnings != []} class="rail-block warning-panel">
              <p class="rail-label">Warnings</p>
              <p :for={warning <- @ticket.warnings}>{TicketPresenter.warning(warning)}</p>
            </section>

            <section :if={failed_attempts(@conversation) != []} class="rail-block">
              <p class="rail-label">Failed Delivery</p>
              <div class="rail-actions">
                <button
                  :for={attempt <- failed_attempts(@conversation)}
                  type="button"
                  class="ks-button danger"
                  disabled
                  data-testid="ticket-retry-delivery"
                  title={"Retry #{attempt.citizen_slug}"}
                  aria-label={"Retry #{attempt.citizen_slug}"}
                >
                  <BabsWeb.Icon.icon name="refresh" /> Retry {attempt.citizen_slug}
                </button>
                <a
                  :for={attempt <- failed_attempts(@conversation)}
                  class="ks-button"
                  href={CitizenPath.terminal(attempt.citizen_slug, @socket_token)}
                  data-testid="ticket-open-terminal"
                  title={"Open #{attempt.citizen_slug} terminal"}
                  aria-label={"Open #{attempt.citizen_slug} terminal"}
                >
                  <BabsWeb.Icon.icon name="maximize" /> Open Terminal
                </a>
              </div>
            </section>
          </aside>

          <div class="ticket-main-stack">
          <section
            :if={proposal_panel_visible?(@proposal_panel)}
            class="ks-card proposal-panel"
            data-testid="ticket-proposal-panel"
          >
            <header class="proposal-head">
              <div>
                <h2><BabsWeb.Icon.icon name="git-branch" /> Mayor Proposal</h2>
                <p>Human-gated child Ticket proposal.</p>
              </div>
              <span class={proposal_status_badge_class(@proposal_panel.status)}>
                <span class="dot"></span>{@proposal_panel.status}
              </span>
            </header>

            <div :if={@proposal_panel.kind == :awaiting} class="proposal-awaiting" data-testid="ticket-proposal-awaiting">
              <BabsWeb.Icon.icon name="clock" />
              <div>
                <strong>Awaiting Mayor proposal</strong>
                <p>Mayor: {@proposal_panel.mayor}</p>
                <ul :if={@proposal_panel.rules_refs != []} class="proposal-inline-list">
                  <li :for={ref <- @proposal_panel.rules_refs}>{ref}</li>
                </ul>
              </div>
            </div>

            <div :if={@proposal_panel.kind == :invalid} class="proposal-invalid" data-testid="ticket-proposal-invalid">
              <BabsWeb.Icon.icon name="triangle-alert" />
              <p>{@proposal_panel.error}</p>
            </div>

            <div :if={@proposal_panel.kind == :proposal} class="proposal-review">
              <p class="proposal-summary" data-testid="ticket-proposal-summary">
                {@proposal_panel.summary}
              </p>

              <dl class="proposal-facts">
                <div>
                  <dt>Proposal</dt>
                  <dd>{@proposal_panel.proposal_id}</dd>
                </div>
                <div :if={@proposal_panel.roles != []}>
                  <dt>Roles</dt>
                  <dd>{join_values(@proposal_panel.roles)}</dd>
                </div>
              </dl>

              <div class="proposal-tree" data-testid="ticket-proposal-tree">
                <div class="proposal-tree-root">
                  <BabsWeb.Icon.icon name="git-branch" />
                  <strong>{@ticket.id}</strong>
                  <span>{@ticket.title}</span>
                </div>
                <ol>
                  <li :for={child <- @proposal_panel.children}>
                    <span>{child.title}</span>
                    <span class="badge">{child.assignee_role}</span>
                  </li>
                </ol>
              </div>

              <div
                :if={@proposal_panel.created_children != []}
                class="proposal-created"
                data-testid="ticket-proposal-created"
              >
                <h3><BabsWeb.Icon.icon name="check" /> Created child Tickets</h3>
                <ol>
                  <li
                    :for={child <- @proposal_panel.created_children}
                    data-testid={"ticket-proposal-created-child-#{child.ticket_id}"}
                  >
                    <a class="ticket-link" href={TicketPath.detail(child.ticket_id, @socket_token)}>
                      {child.ticket_id}
                    </a>
                    <span class="proposal-created-title">{child.title}</span>
                    <span class={proposal_routing_badge_class(child.routing_status)}>
                      {child.routing_label}
                    </span>
                    <span class="badge">{child.assignee_role}</span>
                    <span class="badge">{child.inspector}</span>
                  </li>
                </ol>
              </div>

              <div class="proposal-lists">
                <div :if={@proposal_panel.rules_refs != []}>
                  <h3>Rule Refs</h3>
                  <ul><li :for={ref <- @proposal_panel.rules_refs}>{ref}</li></ul>
                </div>
                <div :if={@proposal_panel.risks != []}>
                  <h3>Risks</h3>
                  <ul><li :for={risk <- @proposal_panel.risks}>{risk}</li></ul>
                </div>
                <div :if={@proposal_panel.questions != []}>
                  <h3>Questions</h3>
                  <ul><li :for={question <- @proposal_panel.questions}>{question}</li></ul>
                </div>
              </div>

              <ol class="proposal-child-list">
                <li
                  :for={child <- @proposal_panel.children}
                  class="proposal-child"
                  data-testid={"ticket-proposal-child-#{child.index}"}
                >
                  <div class="proposal-child-head">
                    <div>
                      <strong>{child.number}. {child.title}</strong>
                      <p>{child.body}</p>
                    </div>
                    <div class="proposal-child-badges">
                      <span class="badge">{child.priority}</span>
                      <span class="badge">{child.assignee_role}</span>
                      <span class="badge">{child.inspector}</span>
                    </div>
                  </div>

                  <form
                    :if={proposal_actionable?(@proposal_panel)}
                    class="proposal-edit-form"
                    phx-submit="proposal_edit_child"
                    data-testid={"ticket-proposal-edit-#{child.index}"}
                  >
                    <input type="hidden" name="proposal_id" value={@proposal_panel.proposal_id} />
                    <input type="hidden" name="proposal_revision" value={@proposal_panel.revision_token} />
                    <input type="hidden" name="child_index" value={child.index} />
                    <label>
                      Title
                      <input name="child[title]" value={child.title} data-testid={"ticket-proposal-title-#{child.index}"} />
                    </label>
                    <label>
                      Body
                      <textarea name="child[body]" rows="3">{child.body}</textarea>
                    </label>
                    <div class="proposal-edit-grid">
                      <label>
                        Role
                        <input name="child[assignee_role]" value={child.assignee_role} />
                      </label>
                      <label>
                        Priority
                        <select name="child[priority]">
                          <option :for={priority <- ~w(low normal high urgent)} value={priority} selected={child.priority == priority}>
                            {priority}
                          </option>
                        </select>
                      </label>
                      <label>
                        Inspector
                        <select name="child[inspector]">
                          <option value="user" selected={child.inspector == "user"}>user</option>
                          <option value="auto" selected={child.inspector == "auto"}>auto</option>
                        </select>
                      </label>
                    </div>
                    <div class="proposal-child-actions">
                      <button
                        type="submit"
                        class="ks-button"
                        disabled={ticket_action_busy?(@ticket_action_inflight)}
                        aria-label={"Save proposed child #{child.number}"}
                        title={"Save proposed child #{child.number}"}
                      >
                        <BabsWeb.Icon.icon name="edit" /> Save
                      </button>
                      <button
                        type="button"
                        class="ks-button danger"
                        phx-click="proposal_remove_child"
                        phx-value-proposal_id={@proposal_panel.proposal_id}
                        phx-value-proposal_revision={@proposal_panel.revision_token}
                        phx-value-child_index={child.index}
                        disabled={ticket_action_busy?(@ticket_action_inflight)}
                        data-testid={"ticket-proposal-remove-#{child.index}"}
                        aria-label={"Remove proposed child #{child.number}"}
                        title={"Remove proposed child #{child.number}"}
                      >
                        <BabsWeb.Icon.icon name="trash" /> Remove
                      </button>
                    </div>
                  </form>
                </li>
              </ol>

              <div :if={proposal_actionable?(@proposal_panel)} class="proposal-actions">
                <form
                  class="proposal-reject-form"
                  phx-submit="proposal_reject"
                  data-testid="ticket-proposal-reject-form"
                >
                  <input type="hidden" name="proposal_id" value={@proposal_panel.proposal_id} />
                  <input type="hidden" name="proposal_revision" value={@proposal_panel.revision_token} />
                  <textarea name="feedback" rows="3" required placeholder="Why reject this proposal?"></textarea>
                  <button
                    type="submit"
                    class="ks-button danger"
                    disabled={ticket_action_busy?(@ticket_action_inflight)}
                    aria-label="Reject proposal"
                    title="Reject proposal"
                  >
                    <BabsWeb.Icon.icon name="x" /> Reject
                  </button>
                </form>
                <button
                  type="button"
                  class="ks-button primary"
                  phx-click="proposal_approve"
                  phx-value-proposal_id={@proposal_panel.proposal_id}
                  phx-value-proposal_revision={@proposal_panel.revision_token}
                  disabled={ticket_action_busy?(@ticket_action_inflight)}
                  data-testid="ticket-proposal-approve"
                  aria-label="Approve proposal"
                  title="Approve proposal"
                >
                  <BabsWeb.Icon.icon name="check" /> Approve
                </button>
              </div>

              <p :if={@proposal_panel.feedback} class="proposal-feedback">
                {@proposal_panel.feedback}
              </p>
            </div>
          </section>

          <section :if={@ticket_diff} class="ticket-review-diff" data-testid="ticket-review-diff">
            <GitDiffComponent.git_diff
              branch={@ticket_diff.branch}
              status={@ticket_diff.status}
              diff={@ticket_diff.diff}
              error={@ticket_diff.error}
            />
          </section>

          <article class="chat-card" data-testid="ticket-detail-chat">
            <header class="chat-head">
            <div>
              <h2>Ticket Chat</h2>
              <p>Operator follow-ups, Citizen replies, and delivery state.</p>
            </div>
            </header>

          <div :if={@conversation.messages == []} class="empty-state" data-testid="ticket-comments-empty">
            No comments yet.
          </div>

          <ol :if={@conversation.messages != []} class="message-list">
            <li
              :for={message <- @conversation.messages}
              class={message_class(message)}
              data-testid="ticket-chat-message"
            >
              <div class="bubble">
                <div class="meta">
                  <strong>{message.author}</strong>
                  <time>{message.ts}</time>
                  <span
                    :for={attempt <- message_attempts(@conversation, message)}
                    class={status_badge_class(attempt.status)}
                    data-testid="ticket-turn-status"
                  >
                    <span class="dot"></span>{attempt.citizen_slug}: {attempt.status}
                  </span>
                  <span :if={message.legacy?} class="badge imported">legacy</span>
                </div>
                <p>{message.body}</p>
              </div>
            </li>
          </ol>

          <form
            :if={commentable?(@ticket)}
            class="composer"
            phx-submit="comment"
            data-testid="ticket-comment-form"
          >
            <textarea
              name="body"
              rows="3"
              required
              disabled={ticket_action_busy?(@ticket_action_inflight)}
              data-testid="ticket-comment-body"
              aria-label="Ticket comment"
              placeholder="Write a message to this ticket..."
            ></textarea>
            <button
              type="submit"
              class="ks-button primary"
              disabled={ticket_action_busy?(@ticket_action_inflight)}
              data-testid="ticket-comment"
              aria-label="Add ticket comment"
              title="Add ticket comment"
            >
              <BabsWeb.Icon.icon name="send" /> Send
            </button>
          </form>
          </article>
          </div>
        </section>

        <section class="ks-card">
          <h2>History</h2>
          <ol class="history-list">
            <li :for={event <- @history} class="history-event" data-testid="ticket-history-event">
              <span class="history-event-name">{event["event"]}</span>
              <span class="history-event-meta">{event["ts"]} by {event["by"]}</span>
              <p :if={history_event_text(event)} class="history-event-body">
                {history_event_text(event)}
              </p>
            </li>
          </ol>
        </section>
      </main>
    </div>

    <script type="module" src="/js/live_boot.js">
    </script>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="ks-page" data-testid="ticket-detail-error">
      <main class="ks-shell">
        <header class="ks-header">
          <div>
            <a class="ks-button" href={TicketPath.index(@socket_token)}>
              <BabsWeb.Icon.icon name="arrow-left" /> Tickets
            </a>
            <h1>Ticket unavailable</h1>
            <p class="ks-subtitle">{@id}</p>
          </div>
          <a class="ks-button" href={CitizenPath.index(@socket_token)}>
            <BabsWeb.Icon.icon name="users" /> Citizens
          </a>
        </header>

        <section class="ks-card error-panel">
          <BabsWeb.Icon.icon name="triangle-alert" />
          <div>
            <h2>{@error}</h2>
            <p>The Ticket file is missing or invalid in the configured runtime root.</p>
          </div>
        </section>
      </main>
    </div>

    <script type="module" src="/js/live_boot.js">
    </script>
    """
  end

  defp assign_ticket(socket) do
    citizens = citizen_options()

    case Api.show_ticket(socket.assigns.id, known_citizens: Enum.map(citizens, & &1.slug)) do
      {:ok, %{ticket: ticket, history: history}} ->
        socket
        |> assign(:ticket, ticket)
        |> assign(:history, history)
        |> assign(:conversation, Conversation.from_history(history))
        |> assign(:inspection_panel, TicketPresenter.inspection_panel(ticket, history))
        |> assign(:proposal_panel, TicketPresenter.proposal_panel(ticket, history))
        |> assign(:citizens, citizens)
        |> assign(:ticket_diff, ticket_diff(ticket))
        |> assign(:error, nil)

      {:error, reason} ->
        socket
        |> assign(:ticket, nil)
        |> assign(:history, [])
        |> assign(:conversation, Conversation.from_history([]))
        |> assign(:inspection_panel, nil)
        |> assign(:proposal_panel, %{kind: :hidden})
        |> assign(:citizens, citizens)
        |> assign(:ticket_diff, nil)
        |> assign(:error, TicketPresenter.error_message(reason))
    end
  end

  defp param(params, key) when is_map(params), do: Map.get(params, key)
  defp param(_params, _key), do: nil

  defp citizen_options do
    Catalog.list_configured_or_imported_citizens()
    |> Enum.map(fn citizen ->
      backend = citizen.ticket_backend || "hardline"

      %{
        slug: citizen.slug,
        display_name: citizen.display_name || citizen.slug,
        ticket_backend: backend,
        ticket_backend_label: TicketBackend.label(backend),
        assign_hint: TicketBackend.assign_hint(backend)
      }
    end)
  rescue
    _error -> []
  end

  defp ensure_assignable_citizen(slug) do
    if Enum.any?(Catalog.list_configured_or_imported_citizens(), &(&1.slug == slug)) do
      :ok
    else
      {:error, {:unknown_citizen, slug}}
    end
  end

  defp ticket_diff(%{state: "pending_approval", id: ticket_id}) do
    case Api.resolve_workspace(ticket_id) do
      {:ok, %{workspace: workspace}} -> read_ticket_diff(workspace)
      {:error, reason} -> ticket_diff_error(reason)
    end
  end

  defp ticket_diff(_ticket), do: nil

  defp read_ticket_diff(workspace) do
    with {:ok, branch} <- Git.branch(workspace),
         {:ok, status} <- Git.status(workspace),
         {:ok, diff} <- Git.diff(workspace) do
      %{branch: branch, status: status, diff: diff, error: nil}
    else
      {:error, reason} -> ticket_diff_error(reason)
    end
  end

  defp ticket_diff_error(reason), do: %{branch: nil, status: nil, diff: nil, error: reason}

  defp assignable?(ticket), do: ticket.state == "open" and ticket.assignees == []
  defp role_assignable?(ticket), do: assignable?(ticket) and has_assignee_role?(ticket)
  defp ready_for_approval?(ticket), do: ticket.state == "in_progress" and ticket.assignees != []
  defp unassignable?(ticket), do: ticket.state == "in_progress" and ticket.assignees != []
  defp cancellable?(ticket), do: ticket.state in ["open", "in_progress", "pending_approval"]
  defp approvable?(ticket), do: ticket.state == "pending_approval" and ticket.assignees != []
  defp rejectable?(ticket), do: ticket.state == "pending_approval" and ticket.assignees != []
  defp commentable?(ticket), do: ticket.state not in ["closed", "cancelled"]

  defp has_assignee_role?(%{assignee_role: role}) when is_binary(role),
    do: String.trim(role) != ""

  defp has_assignee_role?(_ticket), do: false

  defp ticket_action_busy?(nil), do: false
  defp ticket_action_busy?(_action), do: true

  defp history_event_text(%{"body" => body}) when is_binary(body) and body != "", do: body

  defp history_event_text(%{"feedback" => feedback})
       when is_binary(feedback) and feedback != "",
       do: feedback

  defp history_event_text(%{"event" => event, "proposal" => %{"summary" => summary}})
       when event in [
              "mayor_proposal_received",
              "mayor_proposal_revised",
              "mayor_proposal_approved",
              "mayor_proposal_rejected"
            ] and is_binary(summary) and summary != "",
       do: summary

  defp history_event_text(_event), do: nil

  defp state_badge_class("open"), do: "badge open"
  defp state_badge_class("in_progress"), do: "badge working"
  defp state_badge_class("pending_approval"), do: "badge pending"
  defp state_badge_class("closed"), do: "badge captured"
  defp state_badge_class("cancelled"), do: "badge failed"
  defp state_badge_class(_state), do: "badge"

  defp status_badge_class("captured"), do: "badge captured"
  defp status_badge_class("delivered"), do: "badge delivered"
  defp status_badge_class("failed"), do: "badge failed"
  defp status_badge_class("queued"), do: "badge queued"
  defp status_badge_class("busy"), do: "badge pending"
  defp status_badge_class(_status), do: "badge"

  defp inspection_badge_class("approved"), do: "badge captured"
  defp inspection_badge_class("approve"), do: "badge captured"
  defp inspection_badge_class("rejected"), do: "badge failed"
  defp inspection_badge_class("reject"), do: "badge failed"
  defp inspection_badge_class("needs_changes"), do: "badge pending"
  defp inspection_badge_class("requires_human"), do: "badge pending"
  defp inspection_badge_class("failed"), do: "badge failed"
  defp inspection_badge_class("delivered"), do: "badge delivered"
  defp inspection_badge_class("pending"), do: "badge queued"
  defp inspection_badge_class(_status), do: "badge"

  defp proposal_status_badge_class(:pending), do: "badge pending"
  defp proposal_status_badge_class(:approved), do: "badge captured"
  defp proposal_status_badge_class(:rejected), do: "badge failed"
  defp proposal_status_badge_class(:awaiting), do: "badge queued"
  defp proposal_status_badge_class(:invalid), do: "badge failed"
  defp proposal_status_badge_class(_status), do: "badge"

  defp proposal_routing_badge_class("assigned"), do: "badge captured"
  defp proposal_routing_badge_class("failed"), do: "badge failed"
  defp proposal_routing_badge_class(_status), do: "badge queued"

  defp proposal_panel_visible?(%{kind: :hidden}), do: false
  defp proposal_panel_visible?(_panel), do: true

  defp proposal_actionable?(%{actionable?: true}), do: true
  defp proposal_actionable?(_panel), do: false

  defp join_values(values), do: Enum.join(values, ", ")

  defp finding_text(%{"body" => body}) when is_binary(body) and body != "", do: body

  defp finding_text(%{"message" => message}) when is_binary(message) and message != "",
    do: message

  defp finding_text(%{"summary" => summary}) when is_binary(summary) and summary != "",
    do: summary

  defp finding_text(%{"path" => path} = finding) when is_binary(path) and path != "" do
    case Map.get(finding, "line") do
      line when is_integer(line) -> "#{path}:#{line}"
      line when is_binary(line) and line != "" -> "#{path}:#{line}"
      _line -> path
    end
  end

  defp finding_text(finding) when is_map(finding) do
    finding
    |> Map.values()
    |> Enum.find(&is_binary/1)
    |> case do
      nil -> "Finding"
      value -> value
    end
  end

  defp finding_text(_finding), do: "Finding"

  defp message_class(%{legacy?: true}), do: "message legacy"
  defp message_class(%{role: :user}), do: "message mine"
  defp message_class(%{role: :system}), do: "message system"
  defp message_class(_message), do: "message citizen"

  defp message_attempts(conversation, %{turn_id: turn_id}) do
    Conversation.attempts_for_turn(conversation, turn_id)
  end

  defp failed_attempts(conversation) do
    conversation.attempts
    |> Map.values()
    |> Enum.filter(&(&1.status == "failed"))
    |> Enum.sort_by(&{&1.turn_id, &1.citizen_slug, &1.attempt_id})
  end

  defp start_ticket_action(socket, action, fun) do
    if ticket_action_busy?(socket.assigns.ticket_action_inflight) do
      put_flash(socket, :error, "Ticket action already running")
    else
      socket
      |> assign(:ticket_action_inflight, action)
      |> start_async({:ticket_action, action}, fun)
    end
  end

  defp apply_ticket_action_result(
         socket,
         {:comment, _body},
         {:ok, %{delivery: {:comment_notification_failed, _ok_slugs, failures}}}
       ) do
    socket
    |> assign(:ticket_action_inflight, nil)
    |> assign_ticket()
    |> put_flash(:error, "Comment stored; notification failed for #{failed_slugs(failures)}")
  end

  defp apply_ticket_action_result(socket, action, {:ok, _result}) do
    socket
    |> assign(:ticket_action_inflight, nil)
    |> assign_ticket()
    |> put_flash(:info, ticket_action_success(action))
  end

  defp apply_ticket_action_result(socket, _action, {:error, reason}) do
    socket
    |> assign(:ticket_action_inflight, nil)
    |> assign_ticket()
    |> put_flash(:error, Error.message(reason))
  end

  defp ticket_action_success({:assign, slug}), do: "Assigned to #{slug}"
  defp ticket_action_success({:assign_role, role}), do: "Assigned by role #{role}"
  defp ticket_action_success({:transition, to_state, _event}), do: "Moved to #{to_state}"
  defp ticket_action_success({:unassign, slug}), do: "Unassigned #{slug}"
  defp ticket_action_success({:comment, _body}), do: "Comment stored"

  defp ticket_action_success({:proposal_edit_child, index}),
    do: "Updated proposed child #{index + 1}"

  defp ticket_action_success({:proposal_remove_child, index}),
    do: "Removed proposed child #{index + 1}"

  defp ticket_action_success(:proposal_approve), do: "Approved proposal"
  defp ticket_action_success(:proposal_reject), do: "Rejected proposal"
  defp ticket_action_success(:approve), do: "Approved ticket"
  defp ticket_action_success(:reject), do: "Rejected ticket"

  defp failed_slugs(failures) do
    failures
    |> Enum.map(fn {slug, _reason} -> slug end)
    |> Enum.join(", ")
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp parse_index(value) when is_binary(value) do
    case Integer.parse(value) do
      {index, ""} when index >= 0 -> {:ok, index}
      _other -> :error
    end
  end

  defp parse_index(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp parse_index(_value), do: :error
end
