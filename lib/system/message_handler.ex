defmodule Extreme.System.MessageHandler do
  defmacro proxy_to_new_aggregate(cmd, opts \\ []) do
    quote do
      def unquote(cmd)(params) do
        id_field = Keyword.get(unquote(opts), :id)
        id       = Map.get(params, id_field)
        execute_on_new(unquote(cmd), params, id)
        |> (@pipe_resp_thru || &__respond_on/1).()
      end
    end
  end

  defmacro proxy_to_maybe_new_aggregate(cmd, opts \\ []) do
    quote do
      def unquote(cmd)(params) do
        id_field = Keyword.get(unquote(opts), :id, "id")
        id       = Map.fetch!(params, id_field)
        case get_pid(id) do
          {:ok, _} ->
            execute_on(id, unquote(cmd), params)
          _        ->
            execute_on_new(unquote(cmd), params, id)
        end
        |> (@pipe_resp_thru || &__respond_on/1).()
      end
    end
  end

  defmacro proxy_to_aggregate(cmd, opts \\ []) do
    quote do
      def unquote(cmd)(params) do
        id_field=Keyword.get(unquote(opts), :id)
        case id_field do
          nil ->
            params
            |> Map.fetch!("id")
            |> execute_on(unquote(cmd), params)
          :param -> 
            params
            |> execute_on(unquote(cmd))
          _ ->
            params
            |> Map.fetch!(id_field)
            |> execute_on(unquote(cmd), params)
        end
        |> (@pipe_resp_thru || &__respond_on/1).()
      end
    end
  end

  defmacro __using__(opts) do
    quote do
      require Logger
      alias   Extreme.System.EventStore
      alias   Extreme.System.AggregatePidFacade, as: PidFacade
      require Extreme.System.MessageHandler
      import  Extreme.System.MessageHandler

      @aggregate_mod   Keyword.fetch!(unquote(opts), :aggregate_mod)
      @prefix          Keyword.fetch!(unquote(opts), :prefix)
      @pipe_resp_thru  Keyword.get(unquote(opts), :pipe_response_thru)
      @es              Extreme.System.EventStore.name(@prefix)
      @pid_facade      Extreme.System.AggregatePidFacade.name(@aggregate_mod)

      defp aggregate_mod,  do: @aggregate_mod
      defp prefix,         do: @prefix

      defp __respond_on(response), do: response

      defp with_new_aggregate(log_msg, cmd, id \\ nil, fun) do
        if log_msg, do: Logger.info fn -> log_msg end
        key = id || UUID.uuid1
        with {:ok, pid}                             <- spawn_new(key),
             {:ok, transaction, events, version, _} <- fun.({:ok, pid, key}),
             {:ok, last_event}                      <- apply_changes(pid, key, transaction, events, version)
             do
               {:created, key, last_event}
             else 
               any -> 
                 Logger.warn fn -> "New aggregate creation failed: #{inspect any}" end
                 PidFacade.exit_process @pid_facade, key, {:creation_failed, any}
                 any
             end
      end

      defp with_aggregate(log_msg, id, fun) do
        if log_msg, do: Logger.info fn -> log_msg end
        with {:ok, pid}                                     <- get_pid(id),
             {:ok, transaction, events, version, aggr_resp} <- fun.({:ok, pid})
             do 
               _respond pid, id, transaction, events, version, aggr_resp
             else 
               any -> 
                 Logger.info fn -> "Nothing to commit: #{inspect any}" end
                 any
             end
      end

      defp with_aggregate(:no_commit, log_msg, id, fun) do
        if log_msg, do: Logger.info fn -> log_msg end
        result = case get_pid(id) do
          {:ok, pid} ->
            case fun.({:ok, pid}) do
              {:ok, transaction, events, version, aggr_resp} ->
                {:ok, fn -> _respond(pid, id, transaction, events, version, aggr_resp) end}
              any ->
                Logger.info fn -> "Nothing to commit: #{inspect any}" end
                any
            end
          other -> other
        end
      end

      defp _respond(pid, id, transaction, events, version, aggr_resp) do
        case apply_changes(pid, id, transaction, events, version) do
          {:ok, _} = response ->
            if aggr_resp == :default,
              do:   response,
              else: aggr_resp
          response ->
            response
        end
      end


      defp execute_on_new(cmd, params, id \\ nil) do
        with_new_aggregate nil, cmd, id, fn {:ok, pid, id} ->
          apply aggregate_mod(), cmd, [pid, {id, params}, Logger.metadata ++ [aggr: id]]
        end
      end

      defp execute_on(id, cmd) do
        with_aggregate nil, id, fn {:ok, pid} ->
          apply aggregate_mod(), cmd, [pid]
        end
      end

      defp execute_on(id, cmd, params) do
        with_aggregate nil, id, fn {:ok, pid} ->
          apply aggregate_mod(), cmd, [pid, params, Logger.metadata ++ [aggr: id]]
        end
      end

      defp get_pid(id),
        do: PidFacade.get_pid(@pid_facade, id, when_pid_is_not_registered(), &aggregate_start_params/1)

      defp exit_process(id, reason \\ :normal),
        do: PidFacade.exit_process(@pid_facade, id, reason)

      defp delete_stream(key, soft_or_hard, expected_version \\ -2) when soft_or_hard in ~w(soft hard)a do
        hard_delete? = soft_or_hard == :hard
        EventStore.delete_stream(@es, {aggregate_mod(), key}, hard_delete?, expected_version)
      end

      @doc false
      # Should return {:ok, last_event_number} on success, otherwise aggregate will be terminated and
      # that result will be returned to the caller
      def save_events(key, events, expected_version \\ -2)
      def save_events(key, events, expected_version),
        do: EventStore.save_events(@es, {aggregate_mod(), key}, events, Logger.metadata, expected_version)

      @doc false
      def save_state(id, state),
        do: :ok

      @doc false
      # Should return function that takes `aggregate_mod`, `id`, `spawn_new_fun` and returns {:ok, pid} or `anything`.
      # If `anything` is returned, `with_aggregate` will return that value and won't run command on aggregate
      def when_pid_is_not_registered, do: fn aggregate_mod, key, spawn_new_fun -> get_from_es(aggregate_mod, key, spawn_new_fun) end

      defp spawn_new(key), do: PidFacade.spawn_new(@pid_facade, key, aggregate_start_params(key))

      @doc false
      def  aggregate_start_params(_key), do: []

      defp get_from_es(aggregate_mod, key, spawn_new_fun) do
        case EventStore.has?(@es, aggregate_mod, key) do
          true ->
            {:ok, pid} = spawn_new_fun.()
            events     = EventStore.stream_events @es, {aggregate_mod, key}
            Logger.debug fn -> "Applying events for existing aggregate #{key}" end
            :ok        = aggregate_mod.apply pid, events
            {:ok, pid}
          false ->
            Logger.warn fn -> "No events found for aggregate: #{key}" end
            {:error, :not_found}
        end
      end

      defp apply_changes(aggregate, _, transaction, [], expected_version) do
        {:ok, _} = aggregate_mod().commit aggregate, transaction, expected_version, expected_version
        Logger.info fn -> "No events to commit" end
        {:ok, expected_version}
      end
      defp apply_changes(aggregate, key, transaction, events, expected_version) do
        case save_events(key, events, expected_version) do
          {:ok, last_event_number} ->
            {:ok, new_state} = aggregate_mod().commit aggregate, transaction, expected_version, last_event_number
            Logger.info fn ->  "Successfull commit of events. New aggregate version: #{last_event_number}" end
            :ok = save_state key, new_state
            {:ok, last_event_number}
          error ->
            Logger.error fn -> "Error saving events #{inspect error}" end
            Process.exit aggregate, :kill
            error
        end
      end

      defoverridable [save_events: 3, save_state: 2, when_pid_is_not_registered: 0, aggregate_start_params: 1]
    end
  end
end
