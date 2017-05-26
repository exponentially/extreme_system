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

  def rnd(_) do
    {:ok, :rand.uniform}
  end

  def long_rnd(payload) do
    Logger.debug ":long_rnd command received with: #{inspect payload}"
    :timer.sleep 800
    Logger.debug "LongRnd process done"
    {:ok, :rand.uniform}
  end
end

defmodule MyFacade do
  use     Extreme.System.Facade, default_cache: 1_000, cache_overrides: [long_rnd: 2_000, no_cache: :no_cache]
  require Logger
 
  def on_init,
    do: Logger.info "Started MyFacade"

  route :cmd,      MyMsgHandler
  route :cmd2,     {MyMsgHandler, :cmd}
  route :long,     MyMsgHandler
  route :rnd,      MyMsgHandler
  route :long_rnd, MyMsgHandler
  route :no_cache, {MyMsgHandler, :rnd}
end

defmodule Extreme.System.FacadeTest do
  use     ExUnit.Case, async: false
  require Logger

  @facade {:global, MyFacade}

  setup_all do
    {:ok, _} = Extreme.System.FacadeSup.start_link MyFacade, @facade
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
      assert {:done, :long}      = GenServer.call @facade, {:long, "I shouldn't block other requests 1"}
      assert :short_done = Agent.get(agent, fn s -> s end)
    end
    :timer.sleep 10
    assert {:done, :cmd} = GenServer.call @facade, {:cmd, 234}
    Agent.update(agent, fn _ -> :short_done end)
    :timer.sleep 1_000
  end

  test "caches responses" do
    assert {:ok, response}  = GenServer.call @facade, {:rnd, nil}
    assert {:ok, ^response} = GenServer.call @facade, {:rnd, nil}
  end

  test "waits for response from already started request" do
    spawn fn ->
      assert {:done, :long} = GenServer.call @facade, {:long, "I shouldn't block other requests 2"}
    end
    :timer.sleep 700
    assert {:done, :long} = GenServer.call @facade, {:long, "I shouldn't block other requests 2"}, 200
  end

  test "same commands with different params are not mixed in cache" do
    assert {:ok, response}  = GenServer.call @facade, {:rnd, 1}
    refute {:ok, response} == GenServer.call @facade, {:rnd, 2}
  end

  test "different commands with the same params are not mixed in cache" do
    assert {:ok, _}        = GenServer.call @facade, {:rnd, 1}
    assert {:done, :cmd}   = GenServer.call @facade, {:cmd, 1}
  end

  test "proxies request after cache is timeouted" do
    assert {:ok, response}  = GenServer.call @facade, {:rnd, nil}
    :timer.sleep 1_010
    refute {:ok, response} == GenServer.call @facade, {:rnd, nil}
  end

  test "command can override caching time" do
    assert {:ok, response}  = GenServer.call @facade, {:long_rnd, nil}
    :timer.sleep 1_500
    assert {:ok, ^response} = GenServer.call @facade, {:long_rnd, nil}
  end

  test "command can disable caching" do
    assert {:ok, response}  = GenServer.call @facade, {:no_cache, nil}
    refute {:ok, response} == GenServer.call @facade, {:no_cache, nil}
  end
end
