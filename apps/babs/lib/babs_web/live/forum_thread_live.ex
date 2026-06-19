defmodule BabsWeb.ForumThreadLive do
  @moduledoc """
  Forum thread view: read-only Reddit-style comment tree for a Ticket's conversation.
  """

  use Phoenix.LiveView

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Conversation
  alias Babs.Citizens.Tickets.ConversationTree
  alias Babs.Citizens.Tickets.Watcher

  @max_visual_depth 6

  @impl true
  def mount(params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Babs.Citizens.PubSub, Watcher.topic())
    end

    id =
      case params do
        p when is_map(p) -> Map.get(p, "id")
        _other -> nil
      end || Map.get(session, "id")

    socket =
      socket
      |> assign(:id, id)
      |> assign(:socket_token, Map.get(session, "socket_token", ""))
      |> assign_thread()

    {:ok, socket}
  end

  @impl true
  def handle_info({:tickets_changed, _payload}, socket) do
    {:noreply, assign_thread(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      <%= Phoenix.HTML.raw(thread_styles()) %>
    </style>

    <div class="forum-thread-page" data-testid="forum-thread">
      <main class="forum-thread-shell">
        <header class="forum-thread-header">
          <a class="forum-back" href="/forum">← Forum</a>
          <h1 class="forum-thread-title">{@ticket_title}</h1>
          <span class="forum-thread-id">{@id}</span>
        </header>

        <section class="forum-comments">
          <.comment_node :for={node <- @tree} node={node} max_depth={@max_visual_depth} />
        </section>
      </main>
    </div>

    <script type="module" src="/js/live_boot.js">
    </script>
    """
  end

  attr :node, :map, required: true
  attr :max_depth, :integer, required: true

  def comment_node(assigns) do
    visual_depth = min(assigns.node.depth, assigns.max_depth)
    assigns = assign(assigns, :visual_depth, visual_depth)

    ~H"""
    <div
      class={"forum-comment forum-comment-depth-#{@visual_depth}"}
      data-testid="forum-comment"
      data-testid-depth={"forum-comment-depth-#{@visual_depth}"}
      data-depth={@node.depth}
      style={"margin-left: #{indent_px(@visual_depth)}px;"}
    >
      <span data-testid={"forum-comment-depth-#{@visual_depth}"} class="forum-depth-marker sr-only"></span>
      <div
        :if={@node.depth > @max_depth and @visual_depth == @max_depth}
        class="forum-deeper-marker"
        data-testid="forum-deeper-replies"
      >
        ↳ deeper replies
      </div>

      <div :for={msg <- @node.messages} class="forum-message" data-testid="forum-message">
        <div class="forum-message-meta">
          <span
            class={"forum-role-badge forum-role-#{msg.role}"}
            data-testid="forum-role-badge"
          >
            {role_label(msg)}
          </span>
          <span class="forum-author">{msg.author}</span>
          <span class="forum-ts">{msg.ts}</span>
        </div>
        <div class="forum-message-body">{msg.body}</div>
      </div>

      <.comment_node :for={child <- @node.children} node={child} max_depth={@max_depth} />
    </div>
    """
  end

  defp assign_thread(socket) do
    id = socket.assigns.id

    case Api.show_ticket(id) do
      {:ok, %{ticket: ticket, history: history}} ->
        conversation = Conversation.from_history(history)
        tree = ConversationTree.build(conversation)

        socket
        |> assign(:ticket_title, ticket.title)
        |> assign(:tree, tree)
        |> assign(:max_visual_depth, @max_visual_depth)
        |> assign(:error, nil)

      {:error, _reason} ->
        socket
        |> assign(:ticket_title, "Ticket not found")
        |> assign(:tree, [])
        |> assign(:max_visual_depth, @max_visual_depth)
        |> assign(:error, "Ticket not found")
    end
  end

  defp role_label(%{role: :user}), do: "you"
  defp role_label(%{role: :system}), do: "system"
  defp role_label(%{author: author}), do: author

  defp indent_px(depth), do: depth * 24

  defp thread_styles do
    """
    * { box-sizing: border-box; }
    .sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px;
      overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border-width: 0; }
    html, body { min-height: 100%; margin: 0; background: var(--bg); color: var(--text);
      font: 15px/1.5 system-ui, -apple-system, sans-serif; }
    .forum-thread-page { min-height: 100vh; padding: 28px clamp(14px, 3vw, 38px); }
    .forum-thread-shell { width: min(900px, 100%); margin: 0 auto; display: grid; gap: 18px; }
    .forum-thread-header { border-bottom: 1px solid var(--line); padding-bottom: 12px; }
    .forum-back { color: var(--accent); text-decoration: none; font-size: 13px; }
    .forum-back:hover { text-decoration: underline; }
    h1.forum-thread-title { margin: 8px 0 4px; font-size: 22px; font-weight: 700; }
    .forum-thread-id { color: var(--muted); font-size: 12px; }
    .forum-comments { display: grid; gap: 2px; }
    .forum-comment {
      border-left: 2px solid var(--line);
      padding: 6px 0 6px 10px;
      margin-top: 6px;
    }
    .forum-comment-depth-0 { border-left: none; padding-left: 0; margin-left: 0 !important; }
    .forum-message { padding: 6px 0; }
    .forum-message-meta {
      display: flex; align-items: center; gap: 8px;
      margin-bottom: 4px; flex-wrap: wrap;
    }
    .forum-role-badge {
      border-radius: 999px;
      padding: 2px 8px;
      font-size: 11px;
      font-weight: 700;
      border: 1px solid var(--line);
    }
    .forum-role-user { background: var(--accent); color: var(--accent-text); border-color: transparent; }
    .forum-role-citizen { background: var(--panel-2); color: var(--ok); border-color: var(--ok); }
    .forum-role-system { background: transparent; color: var(--muted); }
    .forum-author { font-weight: 600; font-size: 13px; }
    .forum-ts { color: var(--muted); font-size: 12px; }
    .forum-message-body { line-height: 1.6; white-space: pre-wrap; word-break: break-word; }
    .forum-deeper-marker { color: var(--muted); font-size: 12px; margin-bottom: 4px; }
    """
  end
end
