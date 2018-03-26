defmodule Extreme.System.GenAggregate do
  @moduledoc """
  Generic Aggregate module.

  ## Example

      defmodule MyAggregate do
        use Extreme.System.GenAggregate
      
        defmodule State, do: defstruct GenAggregate.state_params ++ [:msg]
      
        ## Client API
      
        def start_link(ttl \\ 2_000), do: GenAggregate.start_link __MODULE__, ttl
      
        def do_something(pid, val), do: exec pid, {:do_something, val}
      
        def message(pid), do: exec pid, :get_message
      
        ## Server Callbacks
      
        def init(ttl) do
          state = initial_state(ttl)
                    |> Map.put(:msg, "")
          {:ok, struct(State, state)}
        end

        def handle_exec({:do_something, val}, from, state) do
          events = [%{val: val}]
          result = {:ok, state.transaction, events}
      
          {:block, from, result, %{state | events: events}}
        end
        def handle_exec(:get_message, from, state) do
          {:noblock, from, state.msg, state}
        end
      
        defp apply_events([%{val: val} | tail], state) do
          state = %{ state | msg: state.msg <> val }
          apply_events tail, state
        end
      end

    Use it then as:
    {:ok, a}                                           = MyAggregate.start_link
    {:ok, transaction_id, _events, version, _response} = MyAggregate.do_something(a, "something")
    {:ok, _new_state}                                  = MyAggregate.commit a, transaction_id
    MyAggregate.message(a)
    #=> "something"
  """

  def start_link(module, init_values, options \\ []) do 
    GenServer.start_link module, init_values, options
  end

  def  state_params,
    do: [:transaction, :ttl, :events, :buffer, :version]

  defmacro handle_cmd(cmd, params, metadata, fun, timeout \\ 5_000) do
    quote do
      def unquote(cmd)(server, unquote(params), unquote(metadata) \\ []),
        do: exec server, {unquote(cmd), unquote(params), unquote(metadata)}, unquote(timeout)
    
      def handle_exec({unquote(cmd), unquote(params), unquote(metadata)}, from, state) do
        Logger.metadata unquote(metadata)
        Logger.info  fn -> "Executing #{inspect unquote(cmd)} on #{inspect Map.get(state, :id) || __MODULE__} with params" end
        Logger.debug fn -> inspect unquote(params) end
        result = unquote(fun).(from, unquote(params), state)
        Logger.metadata []
        result
      end
    end
  end
  defmacro handle_cmd(cmd, fun, timeout \\ 5_000) do
    quote do
      def unquote(cmd)(server),
        do: exec server, unquote(cmd), unquote(timeout)
    
      def handle_exec(unquote(cmd), from, state) do
        Logger.metadata []
        Logger.info fn -> "Executing #{inspect unquote(cmd)} on #{inspect Map.get(state, :id) || __MODULE__} without params" end
        unquote(fun).(from, state)
      end
    end
  end


  defmacro __using__(_) do
    quote do
      use     GenServer
      alias   Extreme.System.GenAggregate
      import  Extreme.System.GenAggregate
      require Extreme.System.GenAggregate
      require Logger

      defp initial_state(ttl \\ 2_000),
        do: %{buffer: [], ttl: ttl, events: [], version: -1}

      def commit(pid, transaction, expected_version, new_version), 
        do: GenServer.call(pid, {:commit, transaction, expected_version, new_version})

      def exec(pid, cmd, timeout \\ 5_000), 
        do: GenServer.call(pid, {:cmd, cmd}, timeout)

      def reply(to, payload), 
        do: GenServer.reply to, payload

      def apply(pid, events), 
        do: GenServer.call(pid, {:apply_stream_events, events})

      def state_after_mutation(events, state) do
        events
        |> apply_events(:whatever_version, state)
      end


      def handle_call({:cmd, cmd}, from, %{buffer: [], transaction: nil}=state) do
        lock = make_ref()
        GenServer.cast self(), {:execute, {cmd, from}}
        {:noreply, %{state | transaction: lock}}
      end
      def handle_call({:cmd, cmd}, from, %{}=state) do
        #Logger.debug fn -> "Buffering: #{inspect cmd}" end
        #Logger.debug fn -> "State is: #{inspect state}" end
        buffer = [{cmd, from} | state.buffer]
        {:noreply, %{state | buffer: buffer}}
      end

      def handle_call({:commit, nil, _, _}, _from, state),
        do: {:reply, {:error, :nil_transaction}, state}
      def handle_call({:commit, _, version, _}, _from, %{version: current_version}=state) when version != current_version,
        do: {:reply, {:error, :wrong_version, current_version, version}, state}
      def handle_call({:commit, transaction, _, new_version}, _from, %{transaction: transaction}=state) do
        #Logger.debug fn -> "Commiting: #{inspect transaction}" end
        state     = apply_events state.events, new_version, state
        new_state = Map.drop state, [:transaction, :ttl, :events, :buffer]
        GenServer.cast self(), :process_buffer
        {:reply, {:ok, new_state}, %{state | transaction: nil, events: []}}
      end
      def handle_call({:commit, t1, _, _}, _from, %{transaction: transaction}=state) when t1 != transaction do 
        {:reply, {:error, :wrong_transaction}, state}
      end

      def handle_call({:apply_stream_events, events_stream}, _from, state) do
        state = Enum.reduce(events_stream, state, fn({event, event_number}, acc) -> apply_events([event], event_number, acc) end)
        {:reply, :ok, state}
      end

      def handle_cast(:process_buffer, %{buffer: []}=state), do: {:noreply, state}
      def handle_cast(:process_buffer, %{buffer: buffer, transaction: nil}=state) do
        lock = make_ref()
        {cmd, from} = List.last buffer
        #Logger.debug fn -> "Processing buffered cmd: #{inspect cmd}" end
        buffer = List.delete_at buffer, -1
        GenServer.cast self(), {:execute, {cmd, from}}
        {:noreply, %{state | buffer: buffer, transaction: lock}}
      end
      def handle_cast(:process_buffer, state), do: {:noreply, state}

      def handle_cast({:execute, {cmd, from}}, state) do
        cmd
        |> handle_exec(from, state)
        |> _respond(_dry_run_option(cmd))
      end

      defp _dry_run_option({_, {_id, %{"dry_run" => option}}, _}),
        do: option
      defp _dry_run_option({_, %{"dry_run" => option}, _}),
        do: option
      defp _dry_run_option(_),
        do: false

      defp _respond(response, dry_run_option)
      defp _respond({:block, from, {:events, events}, state}, :verbose) 
        when is_list(events) do
          GenServer.cast self(), :process_buffer
          GenServer.reply from, {:ok, events}
          {:noreply, %{state | transaction: nil}}
      end
      defp _respond({:block, from, {:events, events}, state}, true) 
        when is_list(events) do
          GenServer.cast self(), :process_buffer
          GenServer.reply from, {:ok, state.version}
          {:noreply, %{state | transaction: nil}}
      end
      defp _respond({:block, from, {:events, events}, state}, _) 
        when is_list(events) do
          schedule_rollback state.transaction, state.ttl
          GenServer.reply from, {:ok, state.transaction, events, state.version, :default}
          {:noreply, %{state | events: events}}
      end

      defp _respond({:block, from, {:events, events, _}, state}, :verbose) 
        when is_list(events) do
          GenServer.cast self(), :process_buffer
          GenServer.reply from, {:ok, events}
          {:noreply, %{state | transaction: nil}}
      end
      defp _respond({:block, from, {:events, events, _}, state}, true) 
        when is_list(events) do
          GenServer.cast self(), :process_buffer
          GenServer.reply from, {:ok, state.version}
          {:noreply, %{state | transaction: nil}}
      end
      defp _respond({:block, from, {:events, events, response}, state}, _) 
        when is_list(events) do
          schedule_rollback state.transaction, state.ttl
          GenServer.reply from, {:ok, state.transaction, events, state.version, response}
          {:noreply, %{state | events: events}}
      end

      defp _respond({:block, from, response, state}, _) do
        schedule_rollback state.transaction, state.ttl
        Logger.debug fn -> "WTH is response: #{inspect response}" end
        GenServer.reply from, response
        {:noreply, state}
      end

      defp _respond({:noblock, from, response, state}, _) do
        GenServer.cast self(), :process_buffer
        GenServer.reply from, response
        {:noreply, %{state | transaction: nil}}
      end


      def handle_info({:rollback, transaction}, %{transaction: transaction}=state),
        do: {:stop, {:commit_timeout, state}, state}
      def handle_info(_, state), 
        do: {:noreply, state}

      defp schedule_rollback(transaction, ttl),
        do: {:ok, _ref} = :timer.send_after ttl, self(), {:rollback, transaction}

      defp _ok(from, state),
        do: {:noblock, from, {:ok, state.version}, state}
        
      defp _log(msg, metadata \\ [], level \\ :info),
        do: Logger.log level, fn -> msg end, metadata

      defp apply_events([], _, state), do: state
      defp apply_events([event | tail], version, state) do
        state = state |> Map.put(:version, version)
        state = apply_event(event, state)
        apply_events tail, version, state
      end

      defoverridable [handle_info: 2]
    end
  end
end
