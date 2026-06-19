defmodule Babs.Citizens.Tickets.CitizenReplyTrigger do
  @moduledoc """
  Detects which Citizens should be woken by a just-appended comment and, when
  the gate and budget allow, delivers a follow-up turn to each target.

  ## Gate

  Delivery only happens when
  `Application.get_env(:babs_citizens, :citizen_auto_reply_enabled, false)` is
  true (or the `citizen_auto_reply_enabled: true` opt is passed). The default
  is false, so merging this code changes NO default behavior.

  ## Budget

  A per-ticket cap prevents infinite Citizen↔Citizen loops.  The cap is
  `Application.get_env(:babs_citizens, :citizen_auto_reply_budget, 6)` (or the
  `citizen_auto_reply_budget: N` opt).  Auto-triggered turns carry
  `"auto_reply" => true` in their comment event and are counted against the cap.

  ## Mockable delivery

  The `deliver_fn` opt (default: `&default_deliver/5`) is the only function
  that enqueues/calls AI.  Tests pass a stub to avoid real CLI calls.

  Inside the real `default_deliver/5`, the Injector is itself injectable via
  the `:inject_fn` opt (a `fn slug, prompt, opts -> :ok | {:error, reason}`),
  defaulting to `&Injector.inject/3`. This lets unit tests substitute a stub
  without running any real AI CLI.
  """

  alias Babs.Citizens.ExecutionLock
  alias Babs.Citizens.Tickets.Conversation
  alias Babs.Citizens.Tickets.Injector
  alias Babs.Citizens.Tickets.ReplyCapture
  alias Babs.Citizens.Tickets.Ticket
  alias Babs.Citizens.Tickets.TurnIds

  @default_budget 6

  @doc """
  Pure target detection.  Returns a `MapSet` of citizen slugs that the
  just-appended `comment` (a raw comment event map) should wake.

  Detection rules (applied in order, then deduped):
    - **Reply**: if `comment["parent_comment_id"]` points to a known message
      whose author is a citizen slug ≠ the comment's own author → include it.
    - **@-mention**: parse `@<slug>` tokens in `comment["body"]`; include each
      that is a known citizen slug ≠ the comment's own author.

  The commenter never wakes itself.
  """
  @spec targets(map(), Conversation.t(), [String.t()]) :: MapSet.t(String.t())
  def targets(comment, %Conversation{} = conversation, citizen_slugs)
      when is_map(comment) and is_list(citizen_slugs) do
    author = comment["by"] || ""
    citizen_set = MapSet.new(citizen_slugs)

    reply_targets = reply_targets(comment, conversation, citizen_set, author)
    mention_targets = mention_targets(comment, citizen_set, author)

    MapSet.union(reply_targets, mention_targets)
  end

  @doc """
  Orchestrator.  Resolves targets via `targets/3`, checks the gate and budget,
  and for each surviving target calls `deliver_fn.(slug, root, ticket,
  conversation, opts)` with `focus_message_id: comment_id` added to `opts`.

  When the gate is off (the default), this is a no-op beyond computing targets.
  """
  @spec maybe_trigger(String.t(), Ticket.t(), map(), Conversation.t(), keyword()) :: :ok
  def maybe_trigger(root, %Ticket{} = ticket, comment, %Conversation{} = conversation, opts) do
    citizen_slugs = Keyword.get(opts, :citizen_slugs, [])

    # Exclude citizens already notified for this comment by the regular
    # assignee-injection path, so an assigned citizen that is also @mentioned /
    # reply-targeted is not woken twice for the same comment.
    excluded = MapSet.new(Keyword.get(opts, :exclude_slugs, []))

    found_targets =
      comment
      |> targets(conversation, citizen_slugs)
      |> MapSet.difference(excluded)

    if gate_enabled?(opts) do
      history = Keyword.get(opts, :history, [])
      budget = budget(opts)
      auto_count = count_auto_replies(history)

      remaining = budget - auto_count

      if remaining > 0 do
        comment_id = comment["message_id"]
        deliver = Keyword.get(opts, :deliver_fn, &default_deliver/5)

        deliver_opts =
          opts
          |> Keyword.put(:focus_message_id, comment_id)
          |> Keyword.put(:auto_reply, true)
          |> Keyword.put(:trigger_by, comment["by"] || "")
          |> Keyword.put(:trigger_body, comment["body"] || "")

        # Cap fan-out at the remaining budget: one comment targeting several
        # citizens must not push the per-thread auto-reply count past the cap.
        found_targets
        |> Enum.sort()
        |> Enum.take(remaining)
        |> Enum.each(fn slug ->
          deliver.(slug, root, ticket, conversation, deliver_opts)
        end)
      end
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp reply_targets(comment, conversation, citizen_set, author) do
    case comment["parent_comment_id"] do
      nil ->
        MapSet.new()

      parent_id ->
        messages_by_id = Map.new(conversation.messages, &{&1.id, &1})

        case Map.get(messages_by_id, parent_id) do
          %{author: parent_author} when is_binary(parent_author) ->
            if MapSet.member?(citizen_set, parent_author) and parent_author != author do
              MapSet.new([parent_author])
            else
              MapSet.new()
            end

          _ ->
            MapSet.new()
        end
    end
  end

  defp mention_targets(comment, citizen_set, author) do
    body = comment["body"] || ""

    # Require a mention boundary: the `@` must not follow a word character, so
    # email user-info (e.g. `ops@bob.example`) is not treated as `@bob`.
    ~r/(?<![A-Za-z0-9_])@([a-zA-Z0-9_-]+)/
    |> Regex.scan(body, capture: :all_but_first)
    |> List.flatten()
    |> Enum.filter(fn slug ->
      MapSet.member?(citizen_set, slug) and slug != author
    end)
    |> MapSet.new()
  end

  @doc """
  Whether auto-reply delivery is enabled (the `citizen_auto_reply_enabled` opt,
  else `Application.get_env(:babs_citizens, :citizen_auto_reply_enabled, false)`).
  Default is `false`. Callers can use this to skip trigger prep on the hot path.
  """
  @spec enabled?(keyword()) :: boolean()
  def enabled?(opts \\ []), do: gate_enabled?(opts)

  defp gate_enabled?(opts) do
    case Keyword.fetch(opts, :citizen_auto_reply_enabled) do
      {:ok, value} -> value == true
      # Strict: a misconfigured truthy non-boolean (e.g. "false", "0") must not
      # enable autonomous delivery. Only the literal boolean true enables it.
      :error -> Application.get_env(:babs_citizens, :citizen_auto_reply_enabled, false) == true
    end
  end

  defp budget(opts) do
    case Keyword.fetch(opts, :citizen_auto_reply_budget) do
      {:ok, value} when is_integer(value) -> value
      {:ok, _invalid} -> @default_budget
      # Normalize app-config too: a non-integer (e.g. env string "6") must not
      # reach the `budget - auto_count` subtraction and raise ArithmeticError.
      :error -> normalize_budget(Application.get_env(:babs_citizens, :citizen_auto_reply_budget))
    end
  end

  defp normalize_budget(value) when is_integer(value), do: value
  defp normalize_budget(_value), do: @default_budget

  defp count_auto_replies(history) do
    Enum.count(history, fn event ->
      event["event"] == "comment" and event["auto_reply"] == true
    end)
  end

  defp default_deliver(slug, root, ticket, conversation, opts) do
    by = Keyword.get(opts, :trigger_by, "")
    body = Keyword.get(opts, :trigger_body, "")
    now = Keyword.get(opts, :now, DateTime.utc_now(:second) |> DateTime.to_iso8601())

    prompt = Injector.comment_prompt(ticket, slug, by, body, conversation, opts)
    inject = Keyword.get(opts, :inject_fn, &Injector.inject/3)

    # Serialize on the Citizen lock like the other delivery paths, so an
    # auto-reply can't interleave a prompt into a pane that another delivery /
    # direct turn is already using (returns {:error, {:execution_busy, slug}}).
    ExecutionLock.with_lock(slug, fn ->
      with :ok <- Injector.prepare(slug, opts),
           :ok <- inject.(slug, prompt, opts) do
        turn = %{
          root: root,
          ticket_id: ticket.id,
          slug: slug,
          started_at: now,
          turn_id: TurnIds.generate!(:turn, now),
          attempt_id: TurnIds.generate!(:attempt, now),
          auto_reply: true,
          # Thread the woken Citizen's reply under the comment that triggered it,
          # so it nests in the forum tree and path_to keeps the lineage.
          parent_comment_id: Keyword.get(opts, :focus_message_id)
        }

        ReplyCapture.track(turn, opts)
        :ok
      end
    end)
  end
end
