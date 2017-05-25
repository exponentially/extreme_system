defmodule MyMsgHandler do
  require Logger

  def cmd(payload) do
    Logger.debug ":cmd command received with: #{inspect payload}"
  end

  def long(payload) do
    Logger.debug ":long command received with: #{inspect payload}"
    :timer.sleep 800
    Logger.debug "Long process done"
    :done
  end
end

defmodule MyFacade do
  use     Extreme.System.Facade
  require Logger
 
  def on_init,
    do: Logger.info "Started MyFacade"

  route :cmd,  MyMsgHandler
  route :cmd2, {MyMsgHandler, :cmd}
  route :long, MyMsgHandler
end

defmodule Extreme.System.FacadeTest do
  use     ExUnit.Case
  require Logger

  setup do
    {:ok, _}      = Task.Supervisor.start_link name: :request_sup
    {:ok, facade} = MyFacade.start_link :request_sup
    {:ok, %{facade: facade}}
  end

  test "proxies message to handler's action with the same name", %{facade: facade} do
    assert :ok = GenServer.call facade, {:cmd, 123}
  end

  test "proxies message to handler's action with different name", %{facade: facade} do
    assert :ok = GenServer.call facade, {:cmd2, "different call"}
  end

  test "can handle concurrent requests", %{facade: facade} do
    spawn fn ->
      assert :done = GenServer.call facade, {:long, "I shouldn't block other requests"}
    end
    :timer.sleep 10
    assert :ok = GenServer.call facade, {:cmd, 123}
    :timer.sleep 1_000
  end
end
