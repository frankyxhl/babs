defmodule Babs.Citizens.RunnerTest do
  use ExUnit.Case, async: true

  alias Babs.Citizens.{CitizenConfig, Runner}

  test "builds a detached Babs-owned tmux session command with cwd and env" do
    config = %CitizenConfig{
      id: "BAB-CIT-0000",
      slug: "sentinel",
      display_name: "Sentinel",
      cli: "/bin/zsh",
      cli_args: ["-f"],
      cwd: "/tmp/babs-sentinel",
      env: %{"TERM" => "xterm-256color"}
    }

    assert Runner.new_session_args(config) == [
             "new-session",
             "-d",
             "-s",
             "babs-sentinel",
             "-c",
             "/tmp/babs-sentinel",
             "-e",
             "TERM=xterm-256color",
             "/bin/zsh",
             "-f"
           ]
  end

  test "identifies only babs-prefixed sessions as managed" do
    assert Runner.managed_session?("babs-clare")
    refute Runner.managed_session?("personal-clare")
  end
end
