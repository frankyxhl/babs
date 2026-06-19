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
  """

  alias Babs.Citizens.Tickets.Conversation
  alias Babs.Citizens.Tickets.Ticket

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
    found_targets = targets(comment, conversation, citizen_slugs)

    if gate_enabled?(opts) do
      history = Keyword.get(opts, :history, [])
      budget = budget(opts)
      auto_count = count_auto_replies(history)

      remaining = budget - auto_count

      if remaining > 0 do
        comment_id = comment["message_id"]
        deliver = Keyword.get(opts, :deliver_fn, &default_deliver/5)
        deliver_opts = Keyword.put(opts, :focus_message_id, comment_id)

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

    ~r/@([a-zA-Z0-9_-]+)/
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
      :error -> Application.get_env(:babs_citizens, :citizen_auto_reply_enabled, false)
    end
  end

  defp budget(opts) do
    case Keyword.fetch(opts, :citizen_auto_reply_budget) do
      {:ok, value} when is_integer(value) -> value
      _ -> Application.get_env(:babs_citizens, :citizen_auto_reply_budget, @default_budget)
    end
  end

  defp count_auto_replies(history) do
    Enum.count(history, fn event ->
      event["event"] == "comment" and event["auto_reply"] == true
    end)
  end

  defp default_deliver(_slug, _root, _ticket, _conversation, _opts), do: :ok
end
