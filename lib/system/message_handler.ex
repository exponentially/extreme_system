defmodule Extreme.System.MessageHandler do
  defmacro __using__(opts) do
    quote do
      require Logger
      alias   Extreme.System.EventStore
      alias   Extreme.System.AggregatePidFacade, as: PidFacade

      @aggregate_mod   Keyword.fetch!(unquote(opts), :aggregate_mod)
      @prefix          Keyword.fetch!(unquote(opts), :prefix)
      @es              Extreme.System.EventStore.name(@prefix)
      @pid_facade      Extreme.System.AggregatePidFacade.name(@aggregate_mod)

      defp aggregate_mod,  do: @aggregate_mod
      defp prefix,         do: @prefix


      defp with_new_aggregate(log_msg, cmd, id \\ nil, fun) do
        Logger.info fn -> log_msg end
        key = id || UUID.uuid1
        with {:ok, pid}                          <- PidFacade.spawn_new(@pid_facade, key),
             {:ok, transaction, events, version} <- fun.({:ok, pid, key}),
             {:ok, last_event}                   <- apply_changes(pid, key, transaction, events, version)
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
        Logger.info fn -> log_msg end
        with {:ok, pid}                          <- get_pid(id),
             {:ok, transaction, events, version} <- fun.({:ok, pid})
             do 
               apply_changes(pid, id, transaction, events, version)
             else 
               any -> 
                 Logger.info fn -> "Nothing to commit: #{inspect any}" end
                 any
             end
      end

      defp with_aggregate(:no_commit, log_msg, id, fun) do
        Logger.info fn -> log_msg end
        result = case get_pid(id) do
          {:ok, pid} ->
            case fun.({:ok, pid}) do
              {:ok, transaction, events, version} ->
                {:ok, fn -> apply_changes(pid, id, transaction, events, version) end}
              any ->
                Logger.info fn -> "Nothing to commit: #{inspect any}" end
                any
            end
          other -> other
        end
      end

      defp get_pid(id),
        do: PidFacade.get_pid(@pid_facade, id)

      defp apply_changes(aggregate, _, transaction, [], expected_version) do
        :ok = aggregate_mod().commit aggregate, transaction, expected_version, expected_version
        Logger.info fn -> "No events to commit" end
        {:ok, expected_version}
      end
      defp apply_changes(aggregate, key, transaction, events, expected_version) do
        case EventStore.save_events(@es, {aggregate_mod(), key}, events, Logger.metadata, expected_version) do
          {:ok, last_event_number} ->
            :ok = aggregate_mod().commit aggregate, transaction, expected_version, last_event_number
            Logger.info fn ->  "Successfull commit of events. New aggregate version: #{last_event_number}" end
            {:ok, last_event_number}
          error ->
            Logger.error fn -> "Error saving events #{inspect error}" end
            Process.exit aggregate, :kill
            error
        end
      end
    end
  end
end
