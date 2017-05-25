defmodule MyMsgHandler do
  require Logger

  def cmd(payload) do
    Logger.debug ":cmd command received with: #{inspect payload}"
  end
end

defmodule MyFacade do
  use     Extreme.System.Facade
  require Logger
 
  def on_init,
    do: Logger.info "Started MyFacade"

  route :cmd,  MyMsgHandler
  route :cmd2, {MyMsgHandler, :cmd}
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
end
