defmodule Mix.Tasks.BabsGateATest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Babs.GateA

  test "start_citizens_app_without_autostart disables bootstrap before app start" do
    previous = Application.get_env(:babs_citizens, :autostart)

    on_exit(fn ->
      Application.put_env(:babs_citizens, :autostart, previous)
    end)

    Application.put_env(:babs_citizens, :autostart, true)

    assert :ok =
             GateA.start_citizens_app_without_autostart(fn :babs_citizens ->
               {:ok, [:babs_citizens]}
             end)

    refute Application.get_env(:babs_citizens, :autostart)
  end

  test "start_citizens_app_without_autostart returns starter failures" do
    previous = Application.get_env(:babs_citizens, :autostart)

    on_exit(fn ->
      Application.put_env(:babs_citizens, :autostart, previous)
    end)

    assert {:error, :boom} =
             GateA.start_citizens_app_without_autostart(fn :babs_citizens ->
               {:error, :boom}
             end)
  end
end
