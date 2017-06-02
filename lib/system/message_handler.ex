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


      defp with_new_aggregate(log_msg, cmd, fun) do
        Logger.info log_msg
        {:ok, pid, key} = PidFacade.spawn_new @pid_facade
        case fun.({:ok, pid, key}) do
          {:ok, transaction, events, version} ->
            {:ok, last_event} = apply_changes(pid, key, transaction, events, version)
            {:created, key, last_event}
          other -> other
        end
      end

      defp with_aggregate(log_msg, id, fun) do
        Logger.info log_msg
        case PidFacade.get_pid(@pid_facade, id) do
          {:ok, pid} ->
            case fun.({:ok, pid}) do
              {:ok, transaction, events, version} ->
                {:ok, last_event} = apply_changes(pid, id, transaction, events, version)
              other -> 
                Logger.info "No events to commit: #{inspect other}"
                other
            end
          error -> error
        end
      end

      defp apply_changes(aggregate, _, transaction, [], expected_version) do
        :ok = aggregate_mod().commit aggregate, transaction, expected_version
        Logger.info "Successfull commit of events"
        {:ok, expected_version}
      end
      defp apply_changes(aggregate, key, transaction, events, expected_version) do
        case EventStore.save_events(@es, {aggregate_mod(), key}, events, Logger.metadata, expected_version) do
          {:ok, last_event_number} ->
            :ok = aggregate_mod().commit aggregate, transaction, expected_version, last_event_number
            Logger.info "Successfull commit of events. New aggregate version: #{last_event_number}"
            {:ok, last_event_number}
          error ->
            Logger.error "Error saving events #{inspect error}"
            Process.exit aggregate, :kill
        end
      end
    end
  end
end
