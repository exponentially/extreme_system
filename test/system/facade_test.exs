defmodule MyMsgHandler do
  require Logger

  def cmd(payload) do
    Logger.debug ":cmd command received with: #{inspect payload}"
    {:done, :cmd}
  end

  def long(payload) do
    Logger.debug ":long command received with: #{inspect payload}"
    :timer.sleep 800
    Logger.debug "Long process done"
    {:done, :long}
  end

  def rnd(nil) do
    {:ok, :rand.uniform}
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
  route :rnd,  MyMsgHandler
end

defmodule Extreme.System.FacadeTest do
  use     ExUnit.Case, async: false
  require Logger

  @facade {:global, MyFacade}

  setup_all do
    {:ok, _} = Extreme.System.FacadeSup.start_link MyFacade, @facade, cache_timeout: 1_000
    :ok
  end

  test "proxies message to handler's action with the same name" do
    Logger.debug "Test pid"
    assert {:done, :cmd} == GenServer.call @facade, {:cmd, 123}
  end

  test "proxies message to handler's action with different name" do
    assert {:done, :cmd} == GenServer.call @facade, {:cmd2, "different call"}
  end

  test "can handle concurrent requests" do
    {:ok, agent} = Agent.start_link(fn -> :short_not_done_yet end)
    spawn fn ->
      assert :short_not_done_yet = Agent.get(agent, fn s -> s end)
      assert {:done, :long}      = GenServer.call @facade, {:long, "I shouldn't block other requests"}
      assert :short_done = Agent.get(agent, fn s -> s end)
    end
    :timer.sleep 10
    assert {:done, :cmd} = GenServer.call @facade, {:cmd, 123}
    Agent.update(agent, fn _ -> :short_done end)
    :timer.sleep 1_000
  end

  test "caches responses" do
    assert {:ok, response}  = GenServer.call @facade, {:rnd, nil}
    assert {:ok, ^response} = GenServer.call @facade, {:rnd, nil}
  end

  test "waits for response from already started request" do
    spawn fn ->
      assert {:done, :long} = GenServer.call @facade, {:long, "I shouldn't block other requests"}
    end
    :timer.sleep 700
    assert {:done, :long} = GenServer.call @facade, {:long, "I shouldn't block other requests"}, 200
  end
end
