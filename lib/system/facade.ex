defmodule Extreme.System.Facade do
  @moduledoc """
      defmodule MyFacade do
        use     Extreme.System.Facade
      
        route :do_something,      MyController          # calls MyController.do_something(params)
        route :do_something_else, {MyController, :else} # calls MyController.else(params)

        def handle_call({:get_timezone, :point, lat, long, metadata}, from, request_sup) do
          execute(request_sup, from, fn ->
            Logger.metadata metadata
            Timezone.get_timezone(:point, lat, long)
          end)
        end
      end


  Facade is GenServer. It requires Task.Supervisor when started. It is used as:

      @request_sup MyApp.RequestSupervisor
      children = [
        supervisor(Task.Supervisor, [[name: @request_sup]]),
        worker(MyFacade, [@request_sup, [name: {:global, MyFacade}]]),
      ]
      
      pid = :global.whereis_name MyFacade
      cmd1 = {:do_something, %{"lat" => "21", "long" => "21"}}
      cmd2 = {:do_something_else, %{"lat" => "21", "long" => "21"}, [req_id: "1231231"]}
      GenServer.call pid, cmd1
      GenServer.call pid, cmd2

  `cmd` is tuple of 2 or 3 elements. First one is route, second one are params that will be proxied to controller,
  and optional 3rd is Logger metadata that will be set for that task.

  Result of MyController.do_something/1 will be sent in reply to GenServer.call. GenFacade handles that. If format of message
  is different, manual handle_call/3 handler can be set.
  """

  defmacro route(cmd, {controller, action}) do
    quote do
	  def handle_call({unquote(cmd), params}, from, request_sup) do
        execute(request_sup, from, fn ->
	      unquote(controller).unquote(action)(params)
        end)
      end
	  def handle_call({unquote(cmd), params, metadata}, from, request_sup) do
        execute(request_sup, from, fn ->
          Logger.metadata metadata
	      unquote(controller).unquote(action)(params)
        end)
	    {:noreply, request_sup}
	  end
    end
  end
  defmacro route(cmd, controller) do
    quote do
	  def handle_call({unquote(cmd), params}, from, request_sup) do
        execute(request_sup, from, fn ->
	      unquote(controller).unquote(cmd)(params)
        end)
      end
	  def handle_call({unquote(cmd), params, metadata}, from, request_sup) do
        execute(request_sup, from, fn ->
          Logger.metadata metadata
	      unquote(controller).unquote(cmd)(params)
        end)
	    {:noreply, request_sup}
	  end
    end
  end

  defmacro __using__(_) do
    quote do
      use     GenServer
      require Extreme.System.Facade
      import  Extreme.System.Facade
      require Logger

      def start_link(request_sup, opts \\ []), 
        do: GenServer.start_link(__MODULE__, request_sup, opts)
      
      def init(request_sup) do 
        on_init()
        {:ok, request_sup}
      end

      defp on_init, do: :ok

      defp execute(request_sup, from, fun) do
        Task.Supervisor.start_child(request_sup, fn ->
          response = fun.()
          GenServer.reply from, response
        end)
        {:noreply, request_sup}
      end

      defoverridable [on_init: 0]
    end
  end
end
