defmodule Babs.Citizens.TicketBackend do
  @moduledoc """
  Shared labels and creation policy for Ticket delivery backends.
  """

  @hardline "hardline"
  @direct_cli "direct_cli"
  @lazy_tmux "lazy_tmux"

  @browser_create_backends [@hardline, @direct_cli]

  def browser_create_options do
    Enum.map(@browser_create_backends, fn backend ->
      %{
        value: backend,
        label: label(backend),
        description: creation_description(backend)
      }
    end)
  end

  def browser_creatable?(backend), do: backend in @browser_create_backends

  def label(@hardline), do: "Hardline"
  def label(@direct_cli), do: "Direct CLI"
  def label(@lazy_tmux), do: "Lazy tmux"
  def label(_backend), do: "Hardline"

  def creation_description(@hardline), do: "Starts a tmux Hardline now"
  def creation_description(@direct_cli), do: "Ticket turns run without a default tmux"
  def creation_description(@lazy_tmux), do: "Deferred until lazy tmux is implemented"
  def creation_description(_backend), do: creation_description(@hardline)

  def assign_hint(@hardline), do: "starts tmux if stopped"
  def assign_hint(@direct_cli), do: "no tmux start"
  def assign_hint(@lazy_tmux), do: "opens tmux only when needed"
  def assign_hint(_backend), do: assign_hint(@hardline)
end
