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

  route :cmd, MyMsgHandler
end

defmodule Extreme.System.FacadeTest do
  use     ExUnit.Case
  require Logger

  setup do
    {:ok, _} = Task.Supervisor.start_link name: :request_sup
    {:ok, _} = MyFacade.start_link :request_sup, name: MyFacade
    :ok
  end

  test "proxies message to handler's action with the same name" do
    assert :ok = GenServer.call MyFacade, {:cmd, 123}
  end
end
