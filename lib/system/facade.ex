defmodule Extreme.System.Facade do
  @moduledoc """
      defmodule MyFacade do
        use     Extreme.System.Facade

        route :do_something,      MyController          # calls MyController.do_something(params)
        route :do_something_else, {MyController, :else} # calls MyController.else(params)

        on_alarm {:expire!, id}, fn ->
          with {:ok, _} <- Offer.expire!(id),
               do:         :ok
        end

        def handle_call({:get_timezone, :point, lat, long, metadata}=payload, from, state) do
          hash = hash(:get_timezone, payload)
          execute(state, hash, from, fn ->
            Logger.metadata metadata
            Timezone.get_timezone(:point, lat, long)
          end)
          {:noreply, state}
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
	  def handle_call({unquote(cmd), params}, from, state) do
        Logger.info fn -> "Routing #{inspect unquote(cmd)} to #{inspect unquote(controller)}#{inspect unquote(action)}" end
        req_id = hash(unquote(cmd), params)
        execute(state, req_id, from, fn ->
	      unquote(controller).unquote(action)(params)
        end)
	    {:noreply, state}
      end
	  def handle_call({unquote(cmd), params, metadata}, from, state) do
        Logger.metadata metadata
        Logger.info fn -> "Routing #{inspect unquote(cmd)} to #{inspect unquote(controller)}#{inspect unquote(action)}" end
        req_id = hash(unquote(cmd), params)
        execute(state, req_id, from, fn ->
          Logger.metadata metadata
	      unquote(controller).unquote(action)(params)
        end)
	    {:noreply, state}
	  end
    end
  end
  defmacro route(cmd, controller) do
    quote do
	  def handle_call({unquote(cmd), params}, from, state) do
        Logger.info fn -> "Routing #{inspect unquote(cmd)} to #{inspect unquote(controller)}" end
        req_id = hash(unquote(cmd), params)
        execute(state, req_id, from, fn ->
	      unquote(controller).unquote(cmd)(params)
        end)
	    {:noreply, state}
      end
	  def handle_call({unquote(cmd), params, metadata}, from, state) do
        Logger.metadata metadata
        Logger.info fn -> "Routing #{inspect unquote(cmd)} to #{inspect unquote(controller)}" end
        req_id = hash(unquote(cmd), params)
        execute(state, req_id, from, fn ->
          Logger.metadata metadata
	      unquote(controller).unquote(cmd)(params)
        end)
	    {:noreply, state}
	  end
    end
  end

  defmacro on_alarm(msg, fun) do
    quote do
      def handle_call({:alarm, on_time?, unquote(msg)}, from, state) do
        Logger.info fn -> "Received #{inspect on_time?} alarm message #{inspect unquote(msg)}" end
        req_id = hash(:alarm, unquote(msg))
        handler = unquote(fun)
        execute(state, req_id, from, fn -> handler.(on_time?) end)
        {:noreply, state}
      end
    end
  end

  defmacro __using__(opts \\ []) do
    quote do
      use     GenServer
      require Extreme.System.Facade
      import  Extreme.System.Facade
      require Logger

      @default_cache   unquote(opts[:default_cache]   || :no_cache)
      @cache_overrides unquote(opts[:cache_overrides] || [])

      defp cache_ttl(cmd),
        do: _cache_ttl(cmd, @cache_overrides)

      defp _cache_ttl(cmd, nil),
        do: @default_cache
      defp _cache_ttl(cmd, overrides),
        do: overrides[cmd] || @default_cache

      @doc false
      def start_link(request_sup, cache, opts \\ []),
        do: GenServer.start_link(__MODULE__, {request_sup, cache}, opts)

      @doc false
      def init({request_sup, cache}) do
        on_init()
        {:ok, %{request_sup: request_sup, cache: cache}}
      end

      def handle_cast({:response, hash, response, ttl}, state) do
        Cachex.transaction!(state.cache, [hash], fn(cache_state) ->
          case Cachex.get(cache_state, hash) do
            {:missing, nil} -> #no request in cache
              Logger.warn "We don't have cached callers for this request anymore"
            {:ok, %{callers: callers, response: :pending}} ->
              respond_to callers, response
              #Logger.debug "Setting expiration time to #{inspect ttl}"
              Cachex.set! cache_state, hash, %{callers: [], response: response}
              Cachex.expire cache_state, hash, ttl
            other ->
              Logger.warn "WTF is #{inspect other} ?!"
          end
        end)
        {:noreply, state}
      end

      defp respond_to([], response),
        do: :ok
      defp respond_to([caller | others], response) do
        #Logger.debug "Responding to caller #{inspect caller} with #{inspect response}"
        :ok = GenServer.reply caller, response
        respond_to others, response
      end

      defp on_init, do: :ok

      defp execute(state, {:hash, hash, ttl}, from, fun) do
        facade = self()
        Cachex.transaction!(state.cache, [hash], fn(cache_state) ->
          case Cachex.get(cache_state, hash) do
            {:ok, nil} -> #no request in cache
              #Logger.debug "We don't have cached result. Create queue of callers"
              Cachex.put! cache_state, hash, %{callers: [from], response: :pending}, [ttl: ttl]
              in_task(state, from, fn ->
                response = fun.()
                #Logger.debug "Sending response: #{inspect response}"
                GenServer.cast facade, {:response, hash, response, ttl}
                response
              end)
              {:noreply, state}
            {:ok, %{callers: callers, response: :pending}} ->
              #Logger.debug "Command is processing ... appending caller to queue"
              Cachex.put! cache_state, hash, %{callers: [from | callers], response: :pending}, [ttl: ttl]
              {:noreply, state}
            {:ok, %{response: response}} ->
              #Logger.debug "We have response #{inspect response}"
              GenServer.reply from, response
          end
        end)
      end
      defp execute(state, _, from, fun),
        do: in_task state, from, fun

      defp in_task(state, from, fun) do
        Task.Supervisor.start_child(state.request_sup, fn ->
          response = fun.()
          GenServer.reply from, response
        end)
      end


      defp hash(cmd, params), do: _hash(cmd, params, cache_ttl(cmd))

      defp _hash(cmd, params, :no_cache), do: :no_cache
      defp _hash(cmd, params, ttl),       do: {:hash, :crypto.hash(:sha256, inspect({cmd, params})), ttl}

      defoverridable [on_init: 0]
    end
  end
end
