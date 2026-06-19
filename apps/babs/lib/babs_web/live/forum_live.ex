defmodule BabsWeb.ForumLive do
  @moduledoc """
  Forum index: lists Tickets as posts with links to /forum/:id threads.
  """

  use Phoenix.LiveView

  alias Babs.Citizens.Tickets.Api
  alias Babs.Citizens.Tickets.Watcher

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Babs.Citizens.PubSub, Watcher.topic())
    end

    socket =
      socket
      |> assign(:socket_token, Map.get(session, "socket_token", ""))
      |> assign_posts()

    {:ok, socket}
  end

  @impl true
  def handle_info({:tickets_changed, _payload}, socket) do
    {:noreply, assign_posts(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      <%= Phoenix.HTML.raw(forum_styles()) %>
    </style>

    <div class="forum-page" data-testid="forum-index">
      <main class="forum-shell">
        <header class="forum-header">
          <h1>Forum</h1>
          <p class="forum-subtitle">Ticket discussions</p>
        </header>

        <section :if={@posts == []} class="forum-empty" data-testid="forum-empty">
          No tickets yet.
        </section>

        <div class="forum-post-list">
          <article
            :for={post <- @posts}
            class="forum-post-row"
            data-testid={"forum-post-#{post.id}"}
          >
            <a class="forum-post-title" href={"/forum/#{post.id}"}>
              {post.title}
            </a>
            <span class="forum-post-meta">{post.id}</span>
            <span class="forum-post-meta">{post.state}</span>
          </article>
        </div>
      </main>
    </div>

    <script type="module" src="/js/live_boot.js">
    </script>
    """
  end

  defp assign_posts(socket) do
    case Api.list_tickets() do
      {:ok, %{tickets: tickets}} ->
        posts =
          tickets
          |> Enum.sort_by(& &1.id)
          |> Enum.map(fn t -> %{id: t.id, title: t.title, state: t.state} end)

        assign(socket, :posts, posts)

      {:error, _reason} ->
        assign(socket, :posts, [])
    end
  end

  defp forum_styles do
    """
    * { box-sizing: border-box; }
    html, body { min-height: 100%; margin: 0; background: var(--bg); color: var(--text);
      font: 15px/1.5 system-ui, -apple-system, sans-serif; }
    .forum-page { min-height: 100vh; padding: 28px clamp(14px, 3vw, 38px); }
    .forum-shell { width: min(900px, 100%); margin: 0 auto; display: grid; gap: 18px; }
    .forum-header { border-bottom: 1px solid var(--line); padding-bottom: 12px; }
    h1 { margin: 0; font-size: 27px; font-weight: 700; }
    .forum-subtitle { margin: 4px 0 0; color: var(--muted); font-size: 13px; }
    .forum-empty { color: var(--muted); padding: 24px; }
    .forum-post-list { display: grid; gap: 8px; }
    .forum-post-row {
      border: 1px solid var(--line); border-radius: 8px;
      background: var(--panel); padding: 12px 16px;
      display: flex; align-items: center; gap: 12px;
    }
    .forum-post-title {
      flex: 1; font-weight: 700; color: var(--text);
      text-decoration: none; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
    }
    .forum-post-title:hover { color: var(--accent); }
    .forum-post-meta { color: var(--muted); font-size: 13px; white-space: nowrap; }
    """
  end
end
