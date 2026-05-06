defmodule Babs.Citizens.Tickets.ConfigTest do
  use ExUnit.Case, async: false

  alias Babs.Citizens.Tickets.Config

  setup do
    old_root = Application.get_env(:babs_citizens, :root)
    old_tickets_root = Application.get_env(:babs_citizens, :tickets_root)

    on_exit(fn ->
      restore_env(:root, old_root)
      restore_env(:tickets_root, old_tickets_root)
    end)

    :ok
  end

  test "tickets_root resolves opts, application env, then default under root" do
    root = tmp_root()
    configured = Path.join(root, "configured-tickets")
    explicit = Path.join(root, "explicit-tickets")

    Application.put_env(:babs_citizens, :root, root)
    Application.put_env(:babs_citizens, :tickets_root, configured)

    assert Config.tickets_root(tickets_root: explicit) == explicit
    assert Config.tickets_root() == configured

    Application.delete_env(:babs_citizens, :tickets_root)
    assert Config.tickets_root() == Path.join(root, "var/tickets")
  end

  test "blank tickets_root values fall back to the default" do
    root = tmp_root()
    Application.put_env(:babs_citizens, :root, root)
    Application.put_env(:babs_citizens, :tickets_root, "   ")

    assert Config.tickets_root() == Path.join(root, "var/tickets")
    assert Config.tickets_root(tickets_root: "") == Path.join(root, "var/tickets")
  end

  test "ensure_root creates the configured tickets root on first write" do
    root = tmp_root()
    tickets_root = Path.join(root, "runtime/tickets")

    refute File.exists?(tickets_root)
    assert {:ok, ^tickets_root} = Config.ensure_root(tickets_root: tickets_root)
    assert File.dir?(tickets_root)
  end

  defp tmp_root do
    root =
      Path.join([
        System.tmp_dir!(),
        "babs-ticket-config-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      ])

    File.rm_rf!(root)
    File.mkdir_p!(root)
    root
  end

  defp restore_env(key, nil), do: Application.delete_env(:babs_citizens, key)
  defp restore_env(key, value), do: Application.put_env(:babs_citizens, key, value)
end
