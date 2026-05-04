defmodule Hardline.ValidationTest do
  use ExUnit.Case, async: false

  alias Hardline.{Runner, Validation}

  test "rejects web confirmation for non-full profiles" do
    assert_raise ArgumentError,
                 "--web-confirmed is only valid with --profile full, got smoke",
                 fn ->
                   Validation.run(profile: "smoke", web_confirmed?: true)
                 end
  end

  test "cleans up tmux sessions when provision proof fails after attach" do
    prefix = "babs-validation-test-#{System.unique_integer([:positive])}"

    run_dir =
      Path.join(
        System.tmp_dir!(),
        "hardline-validation-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(run_dir)

    on_exit(fn ->
      prefix
      |> Runner.list_sessions()
      |> Enum.each(&Runner.kill_session/1)

      File.rm_rf!(run_dir)
    end)

    profile = %{
      fleet_count: 1,
      soak_seconds: 0,
      chaos_seconds: 0,
      chaos_interval_seconds: 1,
      resize_seconds: 0,
      slow_reader_seconds: 0,
      detach_count: 1,
      detach_seconds: 0,
      web_seconds: 0
    }

    {:ok, result} =
      Validation.run(
        profile: "smoke",
        profile_config: profile,
        prefix: prefix,
        command: "/bin/zsh -f -c 'sleep 30'",
        run_dir: run_dir
      )

    assert %{status: :fail} = Enum.find(result.results, &(&1.name == :provision_fleet))
    assert %{status: :skip} = Enum.find(result.results, &(&1.name == :soak))
    assert Runner.list_sessions(prefix) == []
  end

  test "zero-second resize polling still records queued port down messages" do
    prefix = "babs-validation-test-#{System.unique_integer([:positive])}"

    run_dir =
      Path.join(
        System.tmp_dir!(),
        "hardline-validation-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(run_dir)

    on_exit(fn ->
      prefix
      |> Runner.list_sessions()
      |> Enum.each(&Runner.kill_session/1)

      File.rm_rf!(run_dir)
    end)

    send(self(), {:DOWN, make_ref(), :process, self(), :synthetic_resize_down})

    profile = %{
      fleet_count: 1,
      soak_seconds: 0,
      chaos_seconds: 0,
      chaos_interval_seconds: 1,
      resize_seconds: 1,
      slow_reader_seconds: 0,
      detach_count: 0,
      detach_seconds: 0,
      web_seconds: 0
    }

    {:ok, result} =
      Validation.run(
        profile: "smoke",
        profile_config: profile,
        prefix: prefix,
        run_dir: run_dir
      )

    assert %{status: :fail, details: details} =
             Enum.find(result.results, &(&1.name == :resize_storm))

    assert details =~ "resize_port_downs"
    assert File.read!(result.log_path) =~ "phase=resize_storm"
  end
end
