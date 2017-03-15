defmodule Extreme.System.CommandHandler do
  defmacro __using__(opts) do
    quote do
      require Logger
      alias   Extreme.System.AggregateGroup

      defp group_name,       do: Keyword.fetch! unquote(opts), :group
      defp aggregate_module, do: Keyword.fetch! unquote(opts), :aggregate
      defp event_store,      do: Keyword.fetch! unquote(opts), :event_store
      defp stream_category,  do: Keyword.fetch! unquote(opts), :category

      defp spawn_new(id),
        do: AggregateGroup.spawn_new group_name, id

      defp exists?(key),
        do: event_store.has? {Keyword.fetch!(unquote(opts), :category), key}

      defp exec_on_aggregate(id, fun) do
        case get_pid(id) do
          {:ok, pid} -> case fun.(pid) do
                          {:ok, transaction, events} 
                            -> {:ok, _last_event} = apply_changes(pid, id, transaction, events)
                          other 
                            -> other
                        end
          error      -> error
        end
      end

      ## get aggregate pid
      defp get_pid(key) do
        case AggregateGroup.get_registered(group_name, key) do
          :error     -> get_from_db(key)
          {:ok, pid} -> {:ok, pid}
        end
      end

      defp get_from_db(key) do
        case event_store.has?({stream_category, key}) do
          true ->
            events = event_store.stream_events {Keyword.fetch!(unquote(opts), :category), key}
            Logger.debug "Applying events for existing tractor #{key}"
            {:ok, pid} = AggregateGroup.spawn_new group_name, key
            :ok        = aggregate_module.apply pid, events
            {:ok, pid}
          false ->
            Logger.warn "No events found for tractor: #{key}"
            {:error, :not_found}
        end
      end


      #apply_changes
      defp apply_changes(aggregate, key, transaction, events) do
        case event_store.save_events({Keyword.fetch!(unquote(opts), :category), key}, events, Logger.metadata) do
          {:ok, last_event_number} ->
            :ok = aggregate_module.commit aggregate, transaction
            Logger.info "Successfull commit of events"
            {:ok, last_event_number}
          error ->
            Logger.error "Error saving events #{inspect error}"
            Process.exit aggregate, :kill
        end
      end
    end
  end
end
